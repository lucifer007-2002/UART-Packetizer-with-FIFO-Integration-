// tb_uart_top.v

`timescale 1ns / 1ps

module tb_uart_top;

    reg clk = 0;
    reg rst = 0;
    reg [7:0] data_in = 0;
    reg data_valid = 0;
    reg tx_ready = 1;

    wire serial_out;
    wire fifo_full;
    wire tx_busy;

    // Clock generation
    always #10 clk = ~clk; // 50 MHz

    uart_top uut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .data_valid(data_valid),
        .tx_ready(tx_ready),
        .serial_out(serial_out),
        .fifo_full(fifo_full),
        .tx_busy(tx_busy)
    );

    initial begin
        $dumpfile("uart_top_tb.vcd");
        $dumpvars(0, tb_uart_top);

        rst = 1;
        #40;
        rst = 0;

        // Send first packet
        send_byte(8'hA5);
        #200; // Wait for first packet transmission

        // Send second packet
        send_byte(8'h3C);
        #200;

        $finish;
    end

    task send_byte(input [7:0] byte);
        begin
            wait(!fifo_full);
            data_in = byte;
            data_valid = 1;
            #20;
            data_valid = 0;
        end
    endtask

endmodule
