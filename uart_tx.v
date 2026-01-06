module uart_tx #(
    parameter DATA_WIDTH = 8,
    parameter CLK_FREQ = 50000000,
    parameter BAUD_RATE = 115200
) (
    input                   clk,
    input                   rst,
    input                   tx_start,
    input  [DATA_WIDTH-1:0] tx_data,
    input                   tx_ready,      // ✅ Changed from output to input
    output reg              serial_out
);

    localparam BIT_CNT = 10;
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

    reg [DATA_WIDTH+1:0] tx_shift_reg;     // Adjust width for start + stop + data
    reg [3:0] bit_index = 0;
    reg [15:0] baud_cnt = 0;
    reg transmitting = 0;

    always @(posedge clk) begin
        if (rst) begin
            serial_out <= 1;
            transmitting <= 0;
            bit_index <= 0;
            baud_cnt <= 0;
        end else begin
            if (tx_start && tx_ready && !transmitting) begin
                tx_shift_reg <= {1'b1, tx_data, 1'b0}; // {stop, data[7:0], start}
                transmitting <= 1;
                bit_index <= 0;
                baud_cnt <= 0;
            end else if (transmitting) begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    serial_out <= tx_shift_reg[bit_index];
                    bit_index <= bit_index + 1;
                    if (bit_index == BIT_CNT - 1) begin
                        transmitting <= 0;
                        serial_out <= 1;
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end
        end
    end

endmodule
