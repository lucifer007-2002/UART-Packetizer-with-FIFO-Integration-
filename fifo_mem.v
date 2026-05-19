`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// fifo_mem.v
// True dual-port RAM for async FIFO storage
// Write port clocked by wr_clk, read port by rd_clk
//
// Vivado infers this as RAMB18E1 or RAMB36E1 depending on
// depth and width. For 16×8: fits in one RAMB18E1.
//
// (* ram_style = "block" *) forces BRAM inference.
// Without it, small RAMs may be inferred as distributed RAM
// (LUTs) which also works but uses more LUT resources.
//
// Read is synchronous (registered output) — this matches
// BRAM behavior. Read data is valid one cycle after rd_addr
// is presented. The packet FSM must account for this latency.
//
// IMPORTANT: No reset on read data output — BRAM does not
// support synchronous reset on read data path. Gate unused
// read data in the consumer, not here.
//------------------------------------------------------------
module fifo_mem #(
    parameter DATA_W = 8,
    parameter DEPTH  = 16,
    parameter ADDR_W = 4    // log2(DEPTH)
)(
    // Write port
    input  wire              wr_clk,
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [DATA_W-1:0] wr_data,

    // Read port
    input  wire              rd_clk,
    input  wire              rd_en,
    input  wire [ADDR_W-1:0] rd_addr,
    output reg  [DATA_W-1:0] rd_data
);
    (* ram_style = "block" *)
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // Synchronous write (wr_clk domain)
    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    // Synchronous read (rd_clk domain)
    // rd_data is valid one cycle after rd_addr + rd_en
    always @(posedge rd_clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

endmodule
