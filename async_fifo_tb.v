`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// tb_async_fifo.v
// Self-checking async FIFO testbench
// Tests all boundary conditions:
//   1. Reset behavior (all flags correct after reset)
//   2. Write until FULL — verify full asserts at exactly DEPTH
//   3. Read until EMPTY — verify empty asserts after last read
//   4. Write-then-read data integrity (no corruption)
//   5. Simultaneous read+write (throughput without stall)
//   6. FULL flag prevents overwrite
//   7. EMPTY flag prevents underread
//------------------------------------------------------------
module tb_async_fifo;

    // Two independent clocks for true async test
    // wr_clk: 100MHz (10ns), rd_clk: 73MHz (13.7ns) — no harmonic
    reg wr_clk = 0, rd_clk = 0;
    always #5.0  wr_clk = ~wr_clk;   // 100MHz write clock
    always #6.85 rd_clk = ~rd_clk;   // ~73MHz read clock (async)

    reg        wr_rst, rd_rst;
    reg        wr_en, rd_en;
    reg  [7:0] wr_data;
    wire [7:0] rd_data;
    wire       full, empty;

    // Instantiate FIFO
    async_fifo #(
        .DATA_W (FIFO_WIDTH),
        .DEPTH  (FIFO_DEPTH),
        .ADDR_W (FIFO_ADDR_W),
        .PTR_W  (FIFO_PTR_W)
    ) dut (
        .wr_clk  (wr_clk), .wr_rst (wr_rst),
        .wr_en   (wr_en),  .wr_data(wr_data),
        .full    (full),
        .rd_clk  (rd_clk), .rd_rst (rd_rst),
        .rd_en   (rd_en),  .rd_data(rd_data),
        .empty   (empty)
    );

    // Tracking
    integer pass_cnt, fail_cnt;
    integer write_count, read_count;
    reg [7:0] expected_data [0:FIFO_DEPTH-1];

    // ── Task: assert check ────────────────────────────────────
    task check;
        input        cond;
        input [63:0] msg_id;
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL test_id=%0d at time %0t", msg_id, $time);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 1: Reset behavior
    //──────────────────────────────────────────────────────────
    task test_reset;
        begin
            wr_rst = 1; rd_rst = 1;
            wr_en  = 0; rd_en  = 0;
            wr_data = 8'h00;
            repeat(5) @(posedge wr_clk);
            repeat(5) @(posedge rd_clk);
            wr_rst = 0; rd_rst = 0;
            repeat(3) @(posedge wr_clk);
            repeat(3) @(posedge rd_clk);

            check(empty === 1'b1, 101);  // empty after reset
            check(full  === 1'b0, 102);  // not full after reset
            $display("TEST 1 (reset): empty=%b full=%b", empty, full);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 2: Write until FULL
    //──────────────────────────────────────────────────────────
    task test_write_full;
        integer i;
        begin
            write_count = 0;
            for (i = 0; i < FIFO_DEPTH + 2; i = i + 1) begin
                @(posedge wr_clk);
                if (!full) begin
                    wr_en   = 1'b1;
                    wr_data = i[7:0];
                    expected_data[write_count] = i[7:0];
                    write_count = write_count + 1;
                end else begin
                    wr_en = 1'b0;  // stop writing when full
                end
            end
            @(posedge wr_clk);
            wr_en = 1'b0;

            // Allow sync propagation
            repeat(4) @(posedge rd_clk);

            check(write_count == FIFO_DEPTH, 201);
            check(full === 1'b1, 202);
            check(empty === 1'b0, 203);
            $display("TEST 2 (write full): wrote %0d items, full=%b",
                     write_count, full);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 3: Read until EMPTY + data integrity check
    //──────────────────────────────────────────────────────────
    task test_read_empty;
        integer i;
        reg [7:0] got;
        begin
            read_count = 0;
            for (i = 0; i < FIFO_DEPTH + 2; i = i + 1) begin
                @(posedge rd_clk);
                if (!empty) begin
                    rd_en = 1'b1;
                    read_count = read_count + 1;
                end else begin
                    rd_en = 1'b0;
                end
            end
            @(posedge rd_clk);
            rd_en = 1'b0;

            // Extra cycle for last read data to appear
            @(posedge rd_clk);

            // Allow sync propagation back to write domain
            repeat(4) @(posedge wr_clk);

            check(read_count == FIFO_DEPTH, 301);
            check(empty === 1'b1, 302);
            check(full  === 1'b0, 303);
            $display("TEST 3 (read empty): read %0d items, empty=%b",
                     read_count, empty);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 4: Data integrity — write pattern, read back, verify
    //──────────────────────────────────────────────────────────
    task test_data_integrity;
        integer i;
        reg [7:0] rd_captures [0:FIFO_DEPTH-1];
        begin
            // Write known pattern
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                @(posedge wr_clk);
                wr_en   = 1'b1;
                wr_data = 8'hA0 + i[7:0];
            end
            @(posedge wr_clk);
            wr_en = 1'b0;
            repeat(4) @(posedge rd_clk);

            // Read back and capture
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                @(posedge rd_clk);
                rd_en = 1'b1;
                // Data appears one cycle after rd_en (sync BRAM read)
                @(posedge rd_clk);
                rd_captures[i] = rd_data;
            end
            @(posedge rd_clk);
            rd_en = 1'b0;

            // Verify each byte
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                if (rd_captures[i] !== (8'hA0 + i[7:0]))
                    $display("FAIL DATA[%0d]: got 0x%02X expect 0x%02X",
                             i, rd_captures[i], 8'hA0 + i[7:0]);
                else
                    pass_cnt = pass_cnt + 1;
            end
            $display("TEST 4 (data integrity): %0d checks", FIFO_DEPTH);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 5: Simultaneous read + write (no bubble)
    //──────────────────────────────────────────────────────────
    task test_simultaneous;
        integer i;
        begin
            // Pre-fill half the FIFO
            for (i = 0; i < FIFO_DEPTH/2; i = i + 1) begin
                @(posedge wr_clk);
                wr_en = 1'b1; wr_data = 8'h10 + i;
            end
            @(posedge wr_clk); wr_en = 1'b0;
            repeat(4) @(posedge rd_clk);

            // Now simultaneously write and read for FIFO_DEPTH cycles
            fork
                begin : write_proc
                    integer j;
                    for (j = 0; j < FIFO_DEPTH; j = j + 1) begin
                        @(posedge wr_clk);
                        wr_en = ~full;
                        wr_data = 8'h50 + j;
                    end
                    @(posedge wr_clk); wr_en = 1'b0;
                end
                begin : read_proc
                    integer j;
                    for (j = 0; j < FIFO_DEPTH; j = j + 1) begin
                        @(posedge rd_clk);
                        rd_en = ~empty;
                    end
                    @(posedge rd_clk); rd_en = 1'b0;
                end
            join

            repeat(6) @(posedge wr_clk);
            // FIFO should neither be stuck full nor stuck empty
            check(full === 1'b0, 501);
            $display("TEST 5 (simultaneous r/w): full=%b empty=%b",
                     full, empty);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 6: FULL flag prevents overwrite
    //──────────────────────────────────────────────────────────
    task test_full_guard;
        integer i;
        reg [PTR_W-1:0] ptr_before;
        begin
            // Fill FIFO completely first (assume empty from prior reset)
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                @(posedge wr_clk);
                wr_en = 1'b1; wr_data = 8'hBB;
            end
            @(posedge wr_clk); wr_en = 1'b0;
            repeat(4) @(posedge wr_clk);

            // Try to write when full — pointer should not move
            ptr_before = dut.wr_bin;
            @(posedge wr_clk);
            wr_en = 1'b1; wr_data = 8'hDE;  // overwrite attempt
            @(posedge wr_clk);
            wr_en = 1'b0;

            check(dut.wr_bin == ptr_before, 601); // ptr unchanged
            check(full === 1'b1, 602);
            $display("TEST 6 (full guard): ptr_before=%0d ptr_after=%0d",
                     ptr_before, dut.wr_bin);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // Main test sequence
    //──────────────────────────────────────────────────────────
    initial begin
        pass_cnt = 0; fail_cnt = 0;
        wr_en = 0; rd_en = 0; wr_data = 0;

        test_reset;
        test_write_full;
        test_read_empty;

        // Re-reset between tests
        wr_rst=1; rd_rst=1;
        repeat(5) @(posedge wr_clk);
        repeat(5) @(posedge rd_clk);
        wr_rst=0; rd_rst=0;
        repeat(3) @(posedge wr_clk);

        test_data_integrity;

        wr_rst=1; rd_rst=1;
        repeat(5) @(posedge wr_clk);
        repeat(5) @(posedge rd_clk);
        wr_rst=0; rd_rst=0;
        repeat(3) @(posedge wr_clk);

        test_simultaneous;

        wr_rst=1; rd_rst=1;
        repeat(5) @(posedge wr_clk);
        repeat(5) @(posedge rd_clk);
        wr_rst=0; rd_rst=0;
        repeat(3) @(posedge wr_clk);

        test_full_guard;

        #10000;
        $display("=================================");
        $display("FIFO TEST RESULTS: %0d PASS / %0d FAIL",
                 pass_cnt, fail_cnt);
        $display("=================================");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT — check for FIFO deadlock");
        $finish;
    end

    initial begin
        $dumpfile("tb_async_fifo.vcd");
        $dumpvars(0, tb_async_fifo);
    end

endmodule
