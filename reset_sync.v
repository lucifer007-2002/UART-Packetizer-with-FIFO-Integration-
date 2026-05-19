`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// reset_sync.v
// Async assert, synchronous deassert reset synchronizer
//
// WHY THIS TOPOLOGY (async assert, sync deassert):
//   Async ASSERT: rst_out goes high immediately when rst_in
//   is asserted — no waiting for a clock edge. This ensures
//   reset takes effect even if the clock is stopped (power-on).
//
//   Sync DEASSERT: rst_out goes low only on a clock edge,
//   after 2 FF stages have resolved any metastability on the
//   rst_in release edge. This prevents the pipeline from
//   coming out of reset in a metastable state.
//
// One instance per clock domain — do NOT share one reset_sync
// between wr_clk and rd_clk domains. Each domain must release
// reset independently to avoid pointer divergence.
//
// Reset ordering: it is acceptable for one domain to release
// reset before the other. The FIFO flags (FULL/EMPTY) will
// naturally be in safe states (EMPTY=1, FULL=0) when both
// sides have released reset, regardless of order.
//------------------------------------------------------------
module reset_sync #(
    parameter STAGES = 2    // number of synchronizer FF stages
)(
    input  wire clk,
    input  wire rst_in,     // asynchronous reset input (active-high)
    output wire rst_out     // synchronized reset output (active-high)
);
    // Shift register of STAGES FFs, initialized to all-1 (in reset)
    // Use (* ASYNC_REG = "TRUE" *) to tell Vivado these FFs are
    // synchronizers — prevents optimization that breaks CDC behavior
    (* ASYNC_REG = "TRUE" *)
    reg [STAGES-1:0] sync_chain;

    always @(posedge clk or posedge rst_in) begin
        if (rst_in) begin
            // Async assert: immediately drive all stages high
            sync_chain <= {STAGES{1'b1}};
        end else begin
            // Sync deassert: shift in 0, propagates over STAGES cycles
            sync_chain <= {sync_chain[STAGES-2:0], 1'b0};
        end
    end

    // Reset output is the last stage
    assign rst_out = sync_chain[STAGES-1];

endmodule
