`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// tb_uart_tx.v
// Self-checking UART TX testbench
// Sends known bytes and verifies bit-level timing on tx line
//------------------------------------------------------------
module tb_uart_tx;

    reg        clk = 0, rst = 1;
    reg  [7:0] data;
    reg        valid;
    wire       ready, tx, baud_tick;

    always #2.5 clk = ~clk;

    // Instantiate baud generator
    baud_gen u_baud (
        .clk            (clk),
        .rst            (rst),
        .baud_tick      (baud_tick),
        .oversample_tick()
    );

    // Instantiate UART TX
    uart_tx u_tx (
        .clk       (clk),
        .rst       (rst),
        .baud_tick (baud_tick),
        .data      (data),
        .valid     (valid),
        .ready     (ready),
        .tx        (tx)
    );

    // ── Task: transmit one byte and capture serial output ─────
    reg [9:0] captured_bits; // start + 8 data + stop
    integer   bit_idx;

    task send_byte;
        input [7:0] byte_val;
        input [7:0] expect_val;
        integer i;
        begin
            // Present data
            @(posedge clk);
            data  = byte_val;
            valid = 1'b1;

            // Wait for TX to accept
            @(posedge clk);
            while (!ready) @(posedge clk);
            valid = 1'b0;

            // Capture bits: start + 8 data + stop
            // Wait for falling edge (start bit)
            @(negedge tx);

            // Sample each bit at center of bit period
            // Center = BAUD_DIV/2 = 868 cycles after bit edge
            for (i = 0; i < 10; i = i + 1) begin
                repeat(BAUD_DIV/2) @(posedge clk);
                captured_bits[i] = tx;
                repeat(BAUD_DIV - BAUD_DIV/2) @(posedge clk);
            end

            // Verify start bit = 0
            if (captured_bits[0] !== 1'b0)
                $display("FAIL byte=0x%02X: start bit = %b (expect 0)",
                         byte_val, captured_bits[0]);

            // Verify data bits (LSB first)
            if (captured_bits[8:1] !== byte_val)
                $display("FAIL byte=0x%02X: data = 0x%02X (expect 0x%02X)",
                         byte_val, captured_bits[8:1], expect_val);
            else
                $display("PASS byte=0x%02X: data = 0x%02X",
                         byte_val, captured_bits[8:1]);

            // Verify stop bit = 1
            if (captured_bits[9] !== 1'b1)
                $display("FAIL byte=0x%02X: stop bit = %b (expect 1)",
                         byte_val, captured_bits[9]);
        end
    endtask

    // ── Test sequence ─────────────────────────────────────────
    initial begin
        // Reset
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        // Verify idle line is HIGH
        if (tx !== 1'b1)
            $display("FAIL: tx not HIGH in idle state");
        else
            $display("PASS: tx idle = HIGH");

        // Test 1: transmit 0x55 (alternating 0101_0101)
        send_byte(8'h55, 8'h55);

        // Test 2: transmit 0xAA (alternating 1010_1010)
        send_byte(8'hAA, 8'hAA);

        // Test 3: transmit 0x00 (all zeros)
        send_byte(8'h00, 8'h00);

        // Test 4: transmit 0xFF (all ones)
        send_byte(8'hFF, 8'hFF);

        // Test 5: transmit 0xA5 (known pattern)
        send_byte(8'hA5, 8'hA5);

        // Test 6: back-to-back bytes (no gap)
        fork
            begin
                data = 8'h12; valid = 1'b1;
                @(posedge ready); valid = 1'b0;
                data = 8'h34; valid = 1'b1;
                @(posedge ready); valid = 1'b0;
            end
        join
        $display("Back-to-back bytes sent");

        #100000;
        $display("All UART TX tests complete");
        $finish;
    end

    // Timeout safety
    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

endmodule
