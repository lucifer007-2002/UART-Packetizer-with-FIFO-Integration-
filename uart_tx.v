`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// uart_tx.v
// UART transmitter — 8N1 format (8 data, no parity, 1 stop)
//
// Interface:
//   valid + data → present a byte to transmit
//   ready → 1 when TX can accept a new byte (not busy)
//   tx    → serial output line (idle = 1)
//
// Handshake: transfer occurs when valid & ready in same cycle
//
// CRITICAL — valid must stay high until ready is seen:
//   If valid deasserts before ready, the byte is lost.
//   Packet FSM (Part 5) must hold valid until ready asserts.
//
// Shift register: LSB first (UART standard)
//   bit 0 transmitted first, bit 7 last
//   Reversed order = protocol violation, receiver gets garbage
//
// State machine:
//   IDLE       → wait for valid, output tx=1 (idle high)
//   START_BIT  → output tx=0 for exactly 1 bit period
//   DATA_BITS  → shift out 8 bits LSB first, 1 per baud_tick
//   STOP_BIT   → output tx=1 for exactly 1 bit period
//   → back to IDLE, assert ready
//------------------------------------------------------------

// TX FSM state encoding
`define TX_IDLE      2'd0
`define TX_START     2'd1
`define TX_DATA      2'd2
`define TX_STOP      2'd3

module uart_tx (
    input  wire       clk,
    input  wire       rst,
    input  wire       baud_tick,   // 1-cycle pulse from baud_gen
    input  wire [7:0] data,        // byte to transmit
    input  wire       valid,       // data is valid, request TX
    output reg        ready,       // 1 = can accept new byte
    output reg        tx           // UART serial output
);

    // ── FSM state and datapath registers ─────────────────────
    reg [1:0]  state;
    reg [7:0]  shift_reg;           // data shift register
    reg [2:0]  bit_cnt;             // counts 0..7 for data bits

    // ── FSM — next state and output logic ────────────────────
    always @(posedge clk) begin
        if (rst) begin
            state     <= `TX_IDLE;
            shift_reg <= 8'h00;
            bit_cnt   <= 3'd0;
            tx        <= 1'b1;      // idle high — mandatory
            ready     <= 1'b1;      // ready at reset
        end else begin
            case (state)

                //──────────────────────────────────────────────
                `TX_IDLE: begin
                    tx    <= 1'b1;  // keep idle high
                    ready <= 1'b1;

                    if (valid) begin
                        // Capture byte, move to start bit
                        shift_reg <= data;
                        ready     <= 1'b0;   // busy now
                        state     <= `TX_START;
                    end
                end

                //──────────────────────────────────────────────
                `TX_START: begin
                    // Start bit: drive tx LOW for exactly one
                    // bit period (one baud_tick to next)
                    tx    <= 1'b0;
                    ready <= 1'b0;

                    if (baud_tick) begin
                        bit_cnt <= 3'd0;
                        state   <= `TX_DATA;
                    end
                end

                //──────────────────────────────────────────────
                `TX_DATA: begin
                    // Output LSB of shift register
                    // Shift right on each baud_tick
                    tx    <= shift_reg[0];
                    ready <= 1'b0;

                    if (baud_tick) begin
                        shift_reg <= {1'b0, shift_reg[7:1]};  // SRL

                        if (bit_cnt == 3'd7) begin
                            // All 8 bits sent — go to stop bit
                            state <= `TX_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                //──────────────────────────────────────────────
                `TX_STOP: begin
                    // Stop bit: drive tx HIGH for one bit period
                    tx    <= 1'b1;
                    ready <= 1'b0;

                    if (baud_tick) begin
                        // Done — return to IDLE
                        // If another byte is waiting (valid=1),
                        // the IDLE state catches it next cycle
                        state <= `TX_IDLE;
                        ready <= 1'b1;
                    end
                end

                //──────────────────────────────────────────────
                default: begin
                    state <= `TX_IDLE;
                    tx    <= 1'b1;
                    ready <= 1'b1;
                end

            endcase
        end
    end

endmodule
