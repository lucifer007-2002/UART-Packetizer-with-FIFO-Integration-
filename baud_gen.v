`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// baud_gen.v
// Generates a single-cycle baud_tick pulse every BAUD_DIV
// clock cycles. All UART TX timing derives from this pulse.
//
// Counter: 0 → BAUD_DIV-1 → 0 → ...
// baud_tick asserts for exactly 1 cycle when counter == 0
// AFTER the first rollover (not at reset).
//
// OFF-BY-ONE RULE:
//   Counter terminal count = BAUD_DIV - 1 = 1735
//   Next cycle: counter resets to 0, baud_tick pulses
//   Period = BAUD_DIV cycles = 1736 cycles ✓
//   If you use BAUD_DIV (1736) as terminal count:
//   Period = BAUD_DIV + 1 = 1737 cycles → wrong baud rate
//
// Also generates oversample_tick at 8× baud rate for RX.
//------------------------------------------------------------
module baud_gen (
    input  wire clk,
    input  wire rst,
    output wire baud_tick,        // 1-cycle pulse at 115,207 Hz
    output wire oversample_tick   // 1-cycle pulse at 8× baud (921,659 Hz)
);
    // ── Baud counter ─────────────────────────────────────────
    reg [BAUD_CTR_W-1:0] baud_cnt;  // 11-bit counter (0..1735)

    always @(posedge clk) begin
        if (rst) begin
            baud_cnt <= {BAUD_CTR_W{1'b0}};
        end else begin
            if (baud_cnt == BAUD_DIV - 1)
                baud_cnt <= {BAUD_CTR_W{1'b0}};
            else
                baud_cnt <= baud_cnt + 1'b1;
        end
    end

    // Tick fires the cycle AFTER counter reaches BAUD_DIV-1
    // (i.e., when counter == 0 post-rollover)
    // Using == 0 here means tick fires one cycle after rollover.
    // Equivalent: use == BAUD_DIV-1 for tick at end of period.
    // We use rollover detection for cleaner timing:
    assign baud_tick = (baud_cnt == {BAUD_CTR_W{1'b0}}) && !rst;

    // ── Oversample counter (8× baud) ─────────────────────────
    reg [OVERSAMPLE_CTR_W-1:0] os_cnt;   // 8-bit (0..216)

    always @(posedge clk) begin
        if (rst) begin
            os_cnt <= {OVERSAMPLE_CTR_W{1'b0}};
        end else begin
            if (os_cnt == OVERSAMPLE_DIV - 1)
                os_cnt <= {OVERSAMPLE_CTR_W{1'b0}};
            else
                os_cnt <= os_cnt + 1'b1;
        end
    end

    assign oversample_tick = (os_cnt == {OVERSAMPLE_CTR_W{1'b0}}) && !rst;

endmodule
