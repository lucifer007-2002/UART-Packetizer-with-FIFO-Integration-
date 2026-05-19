`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// data_source.v
// Test pattern generator — fills FIFO with controllable data
//
// Modes (controlled by sw[1:0]):
//   sw[1:0]=00: counting pattern (0x00, 0x01, 0x02, ...)
//   sw[1:0]=01: alternating 0x55/0xAA
//   sw[1:0]=10: pseudo-random (LFSR-based)
//   sw[1:0]=11: fixed byte 0xA5
//
// sw[2]=1: enable continuous injection (hold valid high)
// sw[2]=0: inject one packet worth of bytes, then stop
//
// Throttle: injects one byte every INJECT_INTERVAL cycles
// This prevents flooding the FIFO faster than TX drains it
//------------------------------------------------------------
module data_source (
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] sw,         // DIP switches

    // FIFO write interface
    output reg  [7:0] data,       // byte to inject
    output reg        valid,      // data is ready to write
    input  wire       ready       // FIFO can accept (not full)
);

    // Injection interval — one byte every N cycles
    // At 200MHz, 1736 cycles = one UART bit period
    // 17360 cycles = one UART byte = natural drain rate
    localparam INJECT_INTERVAL = 17360;  // match UART byte period
    localparam INTERVAL_W      = 15;     // ceil(log2(17360))

    // Throttle counter
    reg [INTERVAL_W-1:0] throttle_cnt;
    wire inject_tick = (throttle_cnt == INTERVAL_W'(0));

    always @(posedge clk) begin
        if (rst)
            throttle_cnt <= INTERVAL_W'(0);
        else if (throttle_cnt == INJECT_INTERVAL - 1)
            throttle_cnt <= INTERVAL_W'(0);
        else
            throttle_cnt <= throttle_cnt + 1'b1;
    end

    // Counting pattern counter
    reg [7:0] count_val;
    always @(posedge clk) begin
        if (rst)
            count_val <= 8'h00;
        else if (valid && ready)
            count_val <= count_val + 1'b1;
    end

    // LFSR for pseudo-random pattern (19-bit, same as SignalCrypt)
    reg [7:0] lfsr;
    always @(posedge clk) begin
        if (rst)
            lfsr <= 8'hA5;   // non-zero seed
        else if (valid && ready)
            // 8-bit maximal LFSR: x^8+x^6+x^5+x^4+1
            lfsr <= {lfsr[6:0],
                     lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
    end

    // Alternating toggle
    reg alt_toggle;
    always @(posedge clk) begin
        if (rst)
            alt_toggle <= 1'b0;
        else if (valid && ready)
            alt_toggle <= ~alt_toggle;
    end

    // Bytes sent counter (for one-packet mode)
    reg [7:0] bytes_sent;
    wire packet_complete = (bytes_sent >= PKT_MAX_DATA);

    always @(posedge clk) begin
        if (rst)
            bytes_sent <= 8'd0;
        else if (valid && ready)
            bytes_sent <= packet_complete ? 8'd0 : bytes_sent + 1'b1;
    end

    // Data mux based on sw[1:0]
    wire [7:0] data_mux =
        (sw[1:0] == 2'b00) ? count_val    :
        (sw[1:0] == 2'b01) ? (alt_toggle ? 8'hAA : 8'h55) :
        (sw[1:0] == 2'b10) ? lfsr         :
                              8'hA5;

    // Valid generation
    wire continuous_mode = sw[2];
    wire inject_en       = inject_tick &&
                           (continuous_mode || !packet_complete);

    always @(posedge clk) begin
        if (rst) begin
            valid <= 1'b0;
            data  <= 8'h00;
        end else begin
            if (inject_en && ready) begin
                valid <= 1'b1;
                data  <= data_mux;
            end else if (ready) begin
                valid <= 1'b0;
            end
        end
    end

endmodule
