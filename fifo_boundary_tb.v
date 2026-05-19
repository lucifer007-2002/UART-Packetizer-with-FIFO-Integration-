`define SIM_MODE
`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// tb_fifo_boundary.v
// Exhaustive FIFO boundary condition tests
// Tests exact fill levels where flags transition
//------------------------------------------------------------
module tb_fifo_boundary;

    reg wr_clk = 0, rd_clk = 0;
    always #5.0  wr_clk = ~wr_clk;   // 100MHz
    always #6.85 rd_clk = ~rd_clk;   // ~73MHz async

    reg        wr_rst = 1, rd_rst = 1;
    reg        wr_en  = 0, rd_en  = 0;
    reg  [7:0] wr_data = 0;
    wire [7:0] rd_data;
    wire       full, empty;

    integer pass_cnt = 0, fail_cnt = 0;

    async_fifo #(
        .DATA_W (FIFO_WIDTH),
        .DEPTH  (FIFO_DEPTH),
        .ADDR_W (FIFO_ADDR_W),
        .PTR_W  (FIFO_PTR_W)
    ) dut (
        .wr_clk(wr_clk), .wr_rst(wr_rst),
        .wr_en(wr_en),   .wr_data(wr_data), .full(full),
        .rd_clk(rd_clk), .rd_rst(rd_rst),
        .rd_en(rd_en),   .rd_data(rd_data), .empty(empty)
    );

    task do_reset;
        begin
            wr_rst=1; rd_rst=1; wr_en=0; rd_en=0;
            repeat(8) @(posedge wr_clk);
            repeat(8) @(posedge rd_clk);
            wr_rst=0; rd_rst=0;
            repeat(4) @(posedge wr_clk);
            repeat(4) @(posedge rd_clk);
        end
    endtask

    task sync_wait;
        // Wait for CDC propagation (4 cycles each domain)
        begin
            repeat(4) @(posedge wr_clk);
            repeat(4) @(posedge rd_clk);
        end
    endtask

    task assert_check;
        input        cond;
        input [127:0] msg;
        begin
            if (cond) pass_cnt = pass_cnt + 1;
            else begin
                $display("FAIL: %s at t=%0t", msg, $time);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST A: Empty flag exact transition
    // FIFO starts empty, write 1 byte → empty deasserts
    // Read 1 byte → empty reasserts
    //──────────────────────────────────────────────────────────
    task test_empty_transition;
        begin
            do_reset;
            assert_check(empty === 1'b1, "A1:empty after reset");
            assert_check(full  === 1'b0, "A2:not full after reset");

            // Write 1 byte
            @(posedge wr_clk);
            wr_en=1; wr_data=8'hAB;
            @(posedge wr_clk);
            wr_en=0;
            sync_wait;

            assert_check(empty === 1'b0, "A3:not empty after 1 write");

            // Read 1 byte
            @(posedge rd_clk);
            rd_en=1;
            @(posedge rd_clk);
            rd_en=0;
            sync_wait;

            assert_check(empty === 1'b1, "A4:empty after 1 read");
            $display("TEST A (empty transition): done");
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST B: Full flag exact transition
    // Fill FIFO to DEPTH-1 bytes — not full yet
    // Write 1 more — full asserts
    // Read 1 — full deasserts
    //──────────────────────────────────────────────────────────
    task test_full_transition;
        integer i;
        begin
            do_reset;

            // Write DEPTH-1 bytes
            for (i=0; i < FIFO_DEPTH-1; i=i+1) begin
                @(posedge wr_clk);
                wr_en=1; wr_data=i[7:0];
            end
            @(posedge wr_clk); wr_en=0;
            sync_wait;

            assert_check(full  === 1'b0, "B1:not full at DEPTH-1");
            assert_check(empty === 1'b0, "B2:not empty at DEPTH-1");

            // Write 1 more — FULL
            @(posedge wr_clk);
            wr_en=1; wr_data=8'hFF;
            @(posedge wr_clk); wr_en=0;
            sync_wait;

            assert_check(full === 1'b1, "B3:full at DEPTH");

            // Read 1 — NOT FULL
            @(posedge rd_clk);
            rd_en=1;
            @(posedge rd_clk); rd_en=0;
            sync_wait;

            assert_check(full === 1'b0, "B4:not full after 1 read");
            $display("TEST B (full transition): done");
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST C: Write-when-full guard
    // Attempt write when FIFO full → pointer must not move
    //──────────────────────────────────────────────────────────
    task test_full_guard;
        integer i;
        reg [FIFO_PTR_W-1:0] ptr_snap;
        begin
            do_reset;

            // Fill completely
            for (i=0; i < FIFO_DEPTH; i=i+1) begin
                @(posedge wr_clk);
                wr_en=1; wr_data=i[7:0];
            end
            @(posedge wr_clk); wr_en=0;
            sync_wait;

            // Snap write pointer
            ptr_snap = dut.wr_bin;

            // Try 3 writes when full
            repeat(3) begin
                @(posedge wr_clk);
                wr_en=1; wr_data=8'hDE;
            end
            @(posedge wr_clk); wr_en=0;

            assert_check(dut.wr_bin === ptr_snap,
                         "C1:wr_ptr unchanged when full");
            assert_check(full === 1'b1, "C2:still full");
            $display("TEST C (full guard): ptr_before=%0d ptr_after=%0d",
                     ptr_snap, dut.wr_bin);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST D: Read-when-empty guard
    // Attempt read when FIFO empty → pointer must not move
    //──────────────────────────────────────────────────────────
    task test_empty_guard;
        reg [FIFO_PTR_W-1:0] ptr_snap;
        begin
            do_reset;
            ptr_snap = dut.rd_bin;

            // Try 3 reads when empty
            repeat(3) begin
                @(posedge rd_clk);
                rd_en=1;
            end
            @(posedge rd_clk); rd_en=0;

            assert_check(dut.rd_bin === ptr_snap,
                         "D1:rd_ptr unchanged when empty");
            assert_check(empty === 1'b1, "D2:still empty");
            $display("TEST D (empty guard): ptr_before=%0d ptr_after=%0d",
                     ptr_snap, dut.rd_bin);
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST E: Wrap-around pointer integrity
    // Fill, drain, fill again — verify wrap is clean
    //──────────────────────────────────────────────────────────
    task test_wrap_around;
        integer i;
        reg [7:0] expected, got;
        integer mismatch;
        begin
            do_reset;
            mismatch = 0;

            // First fill + drain cycle
            for (i=0; i < FIFO_DEPTH; i=i+1) begin
                @(posedge wr_clk);
                wr_en=1; wr_data=i[7:0];
            end
            @(posedge wr_clk); wr_en=0;
            sync_wait;

            for (i=0; i < FIFO_DEPTH; i=i+1) begin
                @(posedge rd_clk); rd_en=1;
                @(posedge rd_clk); rd_en=0;
            end
            sync_wait;
            assert_check(empty===1'b1, "E1:empty after drain 1");

            // Second fill + drain (tests wrap-around)
            for (i=0; i < FIFO_DEPTH; i=i+1) begin
                @(posedge wr_clk);
                wr_en=1; wr_data=8'hE0+i[7:0];
            end
            @(posedge wr_clk); wr_en=0;
            sync_wait;

            for (i=0; i < FIFO_DEPTH; i=i+1) begin
                @(posedge rd_clk); rd_en=1;
                @(posedge rd_clk);
                got = rd_data;
                rd_en=0;
                expected = 8'hE0+i[7:0];
                if (got !== expected) begin
                    $display("FAIL E2: data[%0d]=0x%02X expect=0x%02X",
                             i, got, expected);
                    mismatch=mismatch+1;
                end
            end
            sync_wait;

            if (mismatch==0) begin
                pass_cnt=pass_cnt+1;
                $display("PASS E2: wrap-around data integrity");
            end else fail_cnt=fail_cnt+1;

            assert_check(empty===1'b1, "E3:empty after drain 2");
            $display("TEST E (wrap-around): done");
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST F: Gray-code pointer verify
    // At each fill level, gray pointer must differ from binary
    // by at most 1 bit (property of gray code)
    //──────────────────────────────────────────────────────────
    task test_gray_code_property;
        integer i;
        reg [FIFO_PTR_W-1:0] bin_val, gray_val, xor_val;
        integer bit_diff;
        integer bad;
        begin
            do_reset;
            bad = 0;

            for (i=0; i <= FIFO_DEPTH; i=i+1) begin
                bin_val  = dut.wr_bin;
                gray_val = dut.wr_gray_reg;
                // Expected gray = bin XOR (bin>>1)
                xor_val  = bin_val ^ (bin_val >> 1);

                if (gray_val !== xor_val) begin
                    $display("FAIL F: gray mismatch at bin=%0d: gray=0x%X expect=0x%X",
                             bin_val, gray_val, xor_val);
                    bad=bad+1;
                end

                if (i < FIFO_DEPTH) begin
                    @(posedge wr_clk);
                    wr_en=1; wr_data=i[7:0];
                    @(posedge wr_clk); wr_en=0;
                    repeat(2) @(posedge wr_clk);
                end
            end

            if (bad==0) begin
                pass_cnt=pass_cnt+1;
                $display("PASS F: gray code correct at all fill levels");
            end else fail_cnt=fail_cnt+1;
            $display("TEST F (gray code property): done");
        end
    endtask

    //──────────────────────────────────────────────────────────
    // Main sequence
    //──────────────────────────────────────────────────────────
    initial begin
        test_empty_transition;
        test_full_transition;
        test_full_guard;
        test_empty_guard;
        test_wrap_around;
        test_gray_code_property;

        #10000;
        $display("=========================================");
        $display("FIFO BOUNDARY TESTS: %0d PASS / %0d FAIL",
                 pass_cnt, fail_cnt);
        $display("=========================================");
        $finish;
    end

    initial begin #50_000_000; $display("TIMEOUT"); $finish; end
    initial begin $dumpfile("tb_fifo_boundary.vcd"); $dumpvars(0,tb_fifo_boundary); end

endmodule
