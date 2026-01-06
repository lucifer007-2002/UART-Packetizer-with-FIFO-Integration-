// fifo_async.v

module fifo_async #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4 // 2^4 = 16-depth FIFO
) (
    input                   wr_clk,
    input                   rd_clk,
    input                   rst,
    input  [DATA_WIDTH-1:0] data_in,
    input                   wr_en,
    input                   rd_en,
    output [DATA_WIDTH-1:0] data_out,
    output                  fifo_full,
    output                  fifo_empty,
    output                  data_out_valid
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr_bin = 0, rd_ptr_bin = 0;
    reg [ADDR_WIDTH:0] wr_ptr_gray = 0, rd_ptr_gray = 0;
    reg [ADDR_WIDTH:0] wr_ptr_gray_rdclk = 0, rd_ptr_gray_wrclk = 0;

    reg data_out_valid_reg = 0;
    assign data_out_valid = data_out_valid_reg;

    // Synchronization registers
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1 = 0, rd_ptr_gray_sync2 = 0;
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1 = 0, wr_ptr_gray_sync2 = 0;

    // Memory Read
    reg [DATA_WIDTH-1:0] data_out_reg;
    assign data_out = data_out_reg;

    // Write pointer logic
    always @(posedge wr_clk) begin
        if (rst) begin
            wr_ptr_bin <= 0;
            wr_ptr_gray <= 0;
        end else if (wr_en && !fifo_full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= data_in;
            wr_ptr_bin <= wr_ptr_bin + 1;
            wr_ptr_gray <= (wr_ptr_bin + 1) ^ ((wr_ptr_bin + 1) >> 1);
        end
    end

    // Read pointer logic
    always @(posedge rd_clk) begin
        if (rst) begin
            rd_ptr_bin <= 0;
            rd_ptr_gray <= 0;
            data_out_valid_reg <= 0;
        end else if (rd_en && !fifo_empty) begin
            data_out_reg <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
            rd_ptr_bin <= rd_ptr_bin + 1;
            rd_ptr_gray <= (rd_ptr_bin + 1) ^ ((rd_ptr_bin + 1) >> 1);
            data_out_valid_reg <= 1;
        end else begin
            data_out_valid_reg <= 0;
        end
    end

    // Sync write pointer into read clock domain
    always @(posedge rd_clk) begin
        wr_ptr_gray_sync1 <= wr_ptr_gray;
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end

    // Sync read pointer into write clock domain
    always @(posedge wr_clk) begin
        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end

    // Full and empty logic
    assign fifo_full = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign fifo_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

endmodule
