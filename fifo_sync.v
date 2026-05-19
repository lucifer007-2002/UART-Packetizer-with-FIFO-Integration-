`timescale 1ns / 1ps
//------------------------------------------------------------
// fifo_sync.v
// 2-FF synchronizer for gray-code FIFO pointer crossing
//
// Parameterized width — instantiated twice:
//   1. wr_gray  synchronized into rd_clk domain (for EMPTY)
//   2. rd_gray  synchronized into wr_clk domain (for FULL)
//
// (* ASYNC_REG = "TRUE" *) on BOTH FFs — mandatory.
// Vivado must see these as a synchronizer pair and place them
// in adjacent flip-flops within the same slice to minimize
// the MTBF (mean time between failures) due to metastability.
//
// Only gray-coded pointers may be synchronized this way —
// binary pointers MUST NOT use this module (see Part 1 for why).
//------------------------------------------------------------
module fifo_sync #(
    parameter WIDTH = 5     // pointer width (FIFO_ADDR_W + 1)
)(
    input  wire             clk,      // destination clock domain
    input  wire             rst,      // destination domain reset
    input  wire [WIDTH-1:0] d,        // gray pointer from source domain
    output reg  [WIDTH-1:0] q         // synchronized gray pointer
);
    // Two-stage synchronizer chain
    (* ASYNC_REG = "TRUE" *)
    reg [WIDTH-1:0] stage1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            stage1 <= {WIDTH{1'b0}};
            q      <= {WIDTH{1'b0}};
        end else begin
            stage1 <= d;    // first FF — may be metastable briefly
            q      <= stage1; // second FF — resolved
        end
    end

endmodule
