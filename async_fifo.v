`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// async_fifo.v
// Asynchronous FIFO with gray-code pointers
// Safe for wr_clk and rd_clk with no phase/frequency relation
//
// Pointer scheme:
//   Both pointers are PTR_W = ADDR_W+1 bits wide
//   Extra MSB distinguishes full from empty when addresses match
//   Binary pointers index the RAM (lower ADDR_W bits used)
//   Gray pointers cross clock domains through 2-FF synchronizers
//
// FULL detection (in write domain):
//   Full when wr has wrapped one more time than rd:
//   full = (wr_gray[PTR_W-1]   != rd_gray_sync[PTR_W-1])
//       && (wr_gray[PTR_W-2]   != rd_gray_sync[PTR_W-2])
//       && (wr_gray[PTR_W-3:0] == rd_gray_sync[PTR_W-3:0])
//
// EMPTY detection (in read domain):
//   Empty when rd has caught up with wr:
//   empty = (rd_gray == wr_gray_sync)
//
// Reset:
//   wr_rst and rd_rst are SYNCHRONIZED resets — each must come
//   from a reset_sync instance clocked by wr_clk and rd_clk
//   respectively. Do NOT share one reset between both domains.
//------------------------------------------------------------
module async_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 16,
    parameter ADDR_W = 4,   // log2(DEPTH)
    parameter PTR_W  = 5    // ADDR_W + 1
)(
    // Write domain
    input  wire              wr_clk,
    input  wire              wr_rst,   // sync reset for write domain
    input  wire              wr_en,    // write enable
    input  wire [DATA_W-1:0] wr_data,  // data to write
    output wire              full,     // FIFO full flag (write domain)

    // Read domain
    input  wire              rd_clk,
    input  wire              rd_rst,   // sync reset for read domain
    input  wire              rd_en,    // read enable
    output wire [DATA_W-1:0] rd_data,  // data read
    output wire              empty     // FIFO empty flag (read domain)
);

    //==========================================================
    // WRITE DOMAIN — binary + gray pointers
    //==========================================================
    reg [PTR_W-1:0] wr_bin;    // binary write pointer
    wire[PTR_W-1:0] wr_bin_next = wr_bin + (wr_en & ~full);
    wire[PTR_W-1:0] wr_gray;   // gray write pointer

    // Binary to gray conversion: gray = bin XOR (bin >> 1)
    assign wr_gray = wr_bin_next ^ (wr_bin_next >> 1);

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_bin <= {PTR_W{1'b0}};
        end else begin
            wr_bin <= wr_bin_next;
        end
    end

    // Registered gray pointer for CDC (stable for synchronizer)
    reg [PTR_W-1:0] wr_gray_reg;
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst)
            wr_gray_reg <= {PTR_W{1'b0}};
        else
            wr_gray_reg <= wr_gray;
    end

    //==========================================================
    // READ DOMAIN — binary + gray pointers
    //==========================================================
    reg [PTR_W-1:0] rd_bin;    // binary read pointer
    wire[PTR_W-1:0] rd_bin_next = rd_bin + (rd_en & ~empty);
    wire[PTR_W-1:0] rd_gray;   // gray read pointer

    // Binary to gray conversion
    assign rd_gray = rd_bin_next ^ (rd_bin_next >> 1);

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_bin <= {PTR_W{1'b0}};
        end else begin
            rd_bin <= rd_bin_next;
        end
    end

    // Registered gray pointer for CDC
    reg [PTR_W-1:0] rd_gray_reg;
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_gray_reg <= {PTR_W{1'b0}};
        else
            rd_gray_reg <= rd_gray;
    end

    //==========================================================
    // CDC — 2-FF synchronizers
    // wr_gray → rd_clk domain (for EMPTY detection)
    // rd_gray → wr_clk domain (for FULL detection)
    //==========================================================

    // Write gray pointer synchronized into read domain
    wire [PTR_W-1:0] wr_gray_sync;  // stable in rd_clk domain
    fifo_sync #(.WIDTH(PTR_W)) u_sync_wr2rd (
        .clk (rd_clk),
        .rst (rd_rst),
        .d   (wr_gray_reg),
        .q   (wr_gray_sync)
    );

    // Read gray pointer synchronized into write domain
    wire [PTR_W-1:0] rd_gray_sync;  // stable in wr_clk domain
    fifo_sync #(.WIDTH(PTR_W)) u_sync_rd2wr (
        .clk (wr_clk),
        .rst (wr_rst),
        .d   (rd_gray_reg),
        .q   (rd_gray_sync)
    );

    //==========================================================
    // FULL flag — computed in WRITE domain
    // Uses rd_gray_sync (rd pointer synchronized to wr_clk)
    //
    // FULL when write has lapped read by exactly DEPTH entries:
    //   Top 2 bits of wr_gray and rd_gray_sync differ (wrap bits)
    //   Remaining lower bits are equal (same address)
    //
    // Why top TWO bits: in binary-reflected gray code for
    // power-of-2 sizes, a full wrap inverts both the MSB and
    // the second MSB. This is the standard Cummings comparison.
    //==========================================================
    assign full = (wr_gray_reg[PTR_W-1]   != rd_gray_sync[PTR_W-1])
               && (wr_gray_reg[PTR_W-2]   != rd_gray_sync[PTR_W-2])
               && (wr_gray_reg[PTR_W-3:0] == rd_gray_sync[PTR_W-3:0]);

    //==========================================================
    // EMPTY flag — computed in READ domain
    // Uses wr_gray_sync (wr pointer synchronized to rd_clk)
    //
    // EMPTY when read pointer equals write pointer:
    //   All PTR_W bits match → no unread data
    //==========================================================
    assign empty = (rd_gray_reg == wr_gray_sync);

    //==========================================================
    // Dual-port memory
    // Write address = lower ADDR_W bits of binary write pointer
    // Read address  = lower ADDR_W bits of binary read pointer
    // Binary pointers used for addresses (not gray) — correct
    // because addresses are only used within their own domain
    //==========================================================
    fifo_mem #(
        .DATA_W (DATA_W),
        .DEPTH  (DEPTH),
        .ADDR_W (ADDR_W)
    ) u_mem (
        .wr_clk  (wr_clk),
        .wr_en   (wr_en & ~full),
        .wr_addr (wr_bin[ADDR_W-1:0]),
        .wr_data (wr_data),
        .rd_clk  (rd_clk),
        .rd_en   (rd_en & ~empty),
        .rd_addr (rd_bin[ADDR_W-1:0]),
        .rd_data (rd_data)
    );

endmodule
