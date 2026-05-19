`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// tb_uart_loopback.v
// Connects uart_tx.tx directly to uart_rx.rx
// Verifies received byte matches transmitted byte exactly
//------------------------------------------------------------
module tb_uart_loopback;

    reg  clk = 0, rst = 1;
    wire baud_tick, oversample_tick;

    // TX side
    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready, tx_line;

    // RX side
    wire [7:0] rx_data;
    wire       rx_valid, rx_frame_err;

    always #2.5 clk = ~clk;

    baud_gen u_baud (
        .clk            (clk),
        .rst            (rst),
        .baud_tick      (baud_tick),
        .oversample_tick(oversample_tick)
    );

    uart_tx u_tx (
        .clk       (clk), .rst(rst),
        .baud_tick (baud_tick),
        .data      (tx_data),
        .valid     (tx_valid),
        .ready     (tx_ready),
        .tx        (tx_line)
    );

    uart_rx u_rx (
        .clk            (clk), .rst(rst),
        .oversample_tick(oversample_tick),
        .rx             (tx_line),   // loopback
        .data           (rx_data),
        .valid          (rx_valid),
        .frame_error    (rx_frame_err)
    );

    // ── Self-checking loopback task ───────────────────────────
    integer pass_count, fail_count;

    task loopback_check;
        input [7:0] byte_val;
        begin
            // Send byte
            @(posedge clk);
            while (!tx_ready) @(posedge clk);
            tx_data = byte_val; tx_valid = 1'b1;
            @(posedge clk);
            tx_valid = 1'b0;

            // Wait for RX valid
            @(posedge rx_valid);

            if (rx_frame_err) begin
                $display("FAIL 0x%02X: frame error", byte_val);
                fail_count = fail_count + 1;
            end else if (rx_data !== byte_val) begin
                $display("FAIL 0x%02X: got 0x%02X", byte_val, rx_data);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS 0x%02X: loopback OK", byte_val);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(10) @(posedge clk);

        // Test all corner cases
        loopback_check(8'h00);   // all zeros
        loopback_check(8'hFF);   // all ones
        loopback_check(8'h55);   // alternating low
        loopback_check(8'hAA);   // alternating high
        loopback_check(8'hAA);   // packet header
        loopback_check(8'h01);   // min length
        loopback_check(8'hFF);   // max length
        loopback_check(8'hA5);   // known pattern

        #100000;
        $display("Loopback results: %0d PASS / %0d FAIL",
                 pass_count, fail_count);
        $finish;
    end

    initial begin #500_000_000; $display("TIMEOUT"); $finish; end

endmodule
