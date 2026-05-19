`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// tb_baud_gen.v
// Verifies baud_tick period is exactly BAUD_DIV cycles
// and oversample_tick period is exactly OVERSAMPLE_DIV cycles
//------------------------------------------------------------
module tb_baud_gen;

    reg  clk = 0, rst = 1;
    wire baud_tick, oversample_tick;

    // 200MHz clock = 5ns period
    always #2.5 clk = ~clk;

    baud_gen dut (
        .clk            (clk),
        .rst            (rst),
        .baud_tick      (baud_tick),
        .oversample_tick(oversample_tick)
    );

    // Release reset after 3 cycles
    initial begin
        repeat(3) @(posedge clk);
        rst = 0;
    end

    // ── Verify baud_tick period ───────────────────────────────
    integer baud_tick_count;
    time    last_baud_tick_time;
    integer baud_period_cycles;

    initial begin
        baud_tick_count = 0;
        last_baud_tick_time = 0;

        // Wait for first tick after reset
        @(posedge baud_tick);
        last_baud_tick_time = $time;

        // Measure next 5 periods for consistency
        repeat(5) begin
            @(posedge baud_tick);
            baud_period_cycles = ($time - last_baud_tick_time) / 5; // /5 = ns to cycles at 200MHz
            last_baud_tick_time = $time;

            if (baud_period_cycles == BAUD_DIV) begin
                $display("PASS baud_tick period = %0d cycles (expect %0d)",
                         baud_period_cycles, BAUD_DIV);
            end else begin
                $display("FAIL baud_tick period = %0d cycles (expect %0d) ERROR!",
                         baud_period_cycles, BAUD_DIV);
            end
        end

        // ── Verify oversample_tick period ─────────────────────
        @(posedge oversample_tick);
        last_baud_tick_time = $time;
        @(posedge oversample_tick);
        baud_period_cycles = ($time - last_baud_tick_time) / 5;

        if (baud_period_cycles == OVERSAMPLE_DIV) begin
            $display("PASS oversample_tick period = %0d cycles (expect %0d)",
                     baud_period_cycles, OVERSAMPLE_DIV);
        end else begin
            $display("FAIL oversample_tick period = %0d cycles (expect %0d)",
                     baud_period_cycles, OVERSAMPLE_DIV);
        end

        $finish;
    end

    // Timeout
    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
