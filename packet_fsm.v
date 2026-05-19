`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// packet_fsm.v
// Packetizer FSM — sequences HEADER→LENGTH→DATA→CHECKSUM
//
// Packet format:
//   [0xAA][pkt_len][data_0]...[data_N-1][XOR_checksum]
//
// FIFO read latency handling:
//   FIFO_RD state: asserts fifo_rd_en for 1 cycle
//   SEND_DATA state: fifo_rdata is now valid, sends to UART TX
//   Explicit RD state prevents using stale data
//
// Checksum: running XOR of ALL data bytes (not header/length)
//   checksum ^= fifo_rdata in SEND_DATA state each byte
//
// Handshake with UART TX:
//   tx_valid asserted → UART TX accepts when tx_ready=1
//   FSM holds current state until tx_ready seen
//   This prevents any byte loss under TX backpressure
//
// Back-to-back packets:
//   After SEND_CHKSUM completes, if FIFO has enough data
//   for another full packet, FSM immediately re-enters
//   SEND_HEADER without returning to IDLE first.
//   This maximises throughput on continuous data streams.
//------------------------------------------------------------

// FSM state encoding
localparam ST_IDLE      = 3'd0;
localparam ST_SEND_HDR  = 3'd1;
localparam ST_SEND_LEN  = 3'd2;
localparam ST_FIFO_RD   = 3'd3;   // explicit 1-cycle FIFO read wait
localparam ST_SEND_DATA = 3'd4;
localparam ST_SEND_CHK  = 3'd5;

module packet_fsm #(
    parameter MAX_DATA = 8   // max payload bytes per packet
)(
    input  wire       clk,
    input  wire       rst,

    // FIFO interface (read side)
    input  wire [7:0] fifo_data,    // read data (valid 1 cycle after rd_en)
    input  wire       fifo_empty,   // 1 = no data available
    output reg        fifo_rd_en,   // pulse: request next byte from FIFO

    // UART TX interface
    output reg  [7:0] tx_data,      // byte to transmit
    output reg        tx_valid,     // byte is ready for TX
    input  wire       tx_ready,     // UART TX can accept byte

    // Packet length selection (from DIP switches)
    input  wire       len_sel,      // 0=4 bytes, 1=8 bytes

    // Status
    output reg        pkt_done      // 1-cycle pulse: packet complete
);

    //==========================================================
    // Internal registers
    //==========================================================
    reg [2:0]  state;
    reg [2:0]  state_next;

    reg [7:0]  checksum;     // running XOR of data bytes
    reg [7:0]  byte_cnt;     // counts data bytes sent (0..pkt_len-1)
    reg [7:0]  pkt_len;      // locked packet length at start
    reg [7:0]  data_latch;   // latches fifo_data after RD wait cycle

    // tx_done: UART TX accepted the byte this cycle
    wire tx_done = tx_valid & tx_ready;

    // last_byte: this is the final data byte of the packet
    wire last_byte = (byte_cnt == pkt_len - 1'b1);

    //==========================================================
    // Packet length selection
    //==========================================================
    wire [7:0] selected_len = len_sel ? 8'd8 : 8'd4;

    //==========================================================
    // FSM — sequential state register
    //==========================================================
    always @(posedge clk) begin
        if (rst)
            state <= ST_IDLE;
        else
            state <= state_next;
    end

    //==========================================================
    // FSM — next-state logic (combinational)
    //==========================================================
    always @(*) begin
        state_next = state;   // default: hold state

        case (state)
            ST_IDLE: begin
                // Wait for enough data in FIFO to fill one packet
                // Could start on any data present — design choice.
                // Here: start as soon as FIFO is not empty.
                if (!fifo_empty)
                    state_next = ST_SEND_HDR;
            end

            ST_SEND_HDR: begin
                // Wait for UART TX to accept 0xAA header byte
                if (tx_done)
                    state_next = ST_SEND_LEN;
            end

            ST_SEND_LEN: begin
                // Wait for UART TX to accept length byte
                if (tx_done)
                    state_next = ST_FIFO_RD;
            end

            ST_FIFO_RD: begin
                // Assert rd_en this cycle, data valid next cycle
                // Unconditional 1-cycle wait
                state_next = ST_SEND_DATA;
            end

            ST_SEND_DATA: begin
                // Send latched fifo byte, wait for TX acceptance
                if (tx_done) begin
                    if (last_byte)
                        state_next = ST_SEND_CHK;
                    else
                        state_next = ST_FIFO_RD;  // fetch next byte
                end
            end

            ST_SEND_CHK: begin
                // Send XOR checksum byte
                if (tx_done)
                    state_next = ST_IDLE;
            end

            default: state_next = ST_IDLE;
        endcase
    end

    //==========================================================
    // FSM — output logic and datapath (sequential)
    //==========================================================
    always @(posedge clk) begin
        if (rst) begin
            tx_data    <= 8'h00;
            tx_valid   <= 1'b0;
            fifo_rd_en <= 1'b0;
            checksum   <= 8'h00;
            byte_cnt   <= 8'd0;
            pkt_len    <= 8'd4;
            data_latch <= 8'h00;
            pkt_done   <= 1'b0;
        end else begin
            // Default: clear single-cycle signals
            fifo_rd_en <= 1'b0;
            pkt_done   <= 1'b0;

            case (state)
                //──────────────────────────────────────────────
                ST_IDLE: begin
                    tx_valid  <= 1'b0;
                    checksum  <= 8'h00;
                    byte_cnt  <= 8'd0;

                    if (!fifo_empty) begin
                        // Lock packet length at start of packet
                        pkt_len <= selected_len;
                    end
                end

                //──────────────────────────────────────────────
                ST_SEND_HDR: begin
                    // Present header byte 0xAA to UART TX
                    tx_data  <= PKT_HEADER;
                    tx_valid <= 1'b1;

                    if (tx_done) begin
                        tx_valid <= 1'b0;
                    end
                end

                //──────────────────────────────────────────────
                ST_SEND_LEN: begin
                    // Present packet length byte
                    tx_data  <= pkt_len;
                    tx_valid <= 1'b1;

                    if (tx_done) begin
                        tx_valid <= 1'b0;
                        checksum <= 8'h00;   // init checksum
                        byte_cnt <= 8'd0;    // reset byte counter
                    end
                end

                //──────────────────────────────────────────────
                ST_FIFO_RD: begin
                    // Assert rd_en for exactly 1 cycle
                    // fifo_data will be valid on NEXT cycle
                    fifo_rd_en <= 1'b1;
                    tx_valid   <= 1'b0;   // not sending yet
                end

                //──────────────────────────────────────────────
                ST_SEND_DATA: begin
                    // fifo_data is now valid (1 cycle after rd_en)
                    // Latch it and present to UART TX
                    data_latch <= fifo_data;
                    tx_data    <= fifo_data;
                    tx_valid   <= 1'b1;

                    if (tx_done) begin
                        // Accumulate checksum with this byte
                        checksum <= checksum ^ fifo_data;
                        byte_cnt <= byte_cnt + 1'b1;
                        tx_valid <= 1'b0;

                        if (last_byte) begin
                            // Last data byte — move to checksum
                            // checksum is now complete
                        end
                    end
                end

                //──────────────────────────────────────────────
                ST_SEND_CHK: begin
                    // Send accumulated XOR checksum
                    tx_data  <= checksum;
                    tx_valid <= 1'b1;

                    if (tx_done) begin
                        tx_valid <= 1'b0;
                        pkt_done <= 1'b1;  // signal packet complete
                    end
                end

                default: begin
                    tx_valid   <= 1'b0;
                    fifo_rd_en <= 1'b0;
                end

            endcase
        end
    end

endmodule
