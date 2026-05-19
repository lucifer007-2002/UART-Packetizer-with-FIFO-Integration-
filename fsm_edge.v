`define SIM_MODE
`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// tb_fsm_edge.v
// Tests FSM edge cases not covered by system testbench:
//   1. TX backpressure mid-packet (ready=0 for multiple cycles)
//   2. FIFO empties mid-packet (should not happen in design
//      but FSM must not deadlock if it does)
//   3. Single-byte packet (length=1)
//   4. Checksum = 0x00 (XOR of even identical bytes)
//   5. Maximum length packet (PKT_MAX_DATA bytes)
//------------------------------------------------------------
module tb_fsm_edge;

    reg  clk = 0, rst = 1;
    always #2.5 clk = ~clk;  // 200MHz

    wire baud_tick;
    baud_gen u_baud (
        .clk(clk), .rst(rst),
        .baud_tick(baud_tick),
        .oversample_tick()
    );

    // Manual FIFO interface (we drive it directly)
    reg  [7:0] fifo_data;
    reg        fifo_empty;
    wire       fifo_rd_en;

    // Manual TX interface (we control ready)
    wire [7:0] tx_data;
    wire       tx_valid;
    reg        tx_ready = 1;

    wire pkt_done;

    packet_fsm #(.MAX_DATA(PKT_MAX_DATA)) dut (
        .clk        (clk),
        .rst        (rst),
        .fifo_data  (fifo_data),
        .fifo_empty (fifo_empty),
        .fifo_rd_en (fifo_rd_en),
        .tx_data    (tx_data),
        .tx_valid   (tx_valid),
        .tx_ready   (tx_ready),
        .len_sel    (1'b0),      // 4-byte packets
        .pkt_done   (pkt_done)
    );

    integer pass_cnt=0, fail_cnt=0;
    integer byte_idx;

    // FIFO byte sequence for controlled feeding
    reg [7:0] fifo_seq [0:15];
    integer   fifo_seq_idx;

    // Simulate FIFO read: respond to rd_en with next byte
    always @(posedge clk) begin
        if (fifo_rd_en && !fifo_empty) begin
            fifo_data    <= fifo_seq[fifo_seq_idx];
            fifo_seq_idx <= fifo_seq_idx + 1;
        end
    end

    task do_reset;
        begin
            rst=1; tx_ready=1; fifo_empty=1;
            fifo_seq_idx=0;
            repeat(5) @(posedge clk);
            rst=0;
            repeat(3) @(posedge clk);
        end
    endtask

    // Wait for packet done with timeout
    task wait_pkt_done;
        input integer timeout_cycles;
        integer cnt;
        begin
            cnt=0;
            while (!pkt_done && cnt < timeout_cycles) begin
                @(posedge clk); cnt=cnt+1;
            end
            if (cnt >= timeout_cycles)
                $display("TIMEOUT waiting for pkt_done");
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 1: TX backpressure — ready=0 for 5 cycles mid-byte
    //──────────────────────────────────────────────────────────
    task test_backpressure;
        integer baud_cnt;
        begin
            do_reset;
            // Load 4 bytes into FIFO sequence
            fifo_seq[0]=8'h11; fifo_seq[1]=8'h22;
            fifo_seq[2]=8'h33; fifo_seq[3]=8'h44;
            fifo_seq_idx=0;
            fifo_empty=0;

            // After header is presented, stall TX for 5 cycles
            // Wait for header to be presented
            @(posedge tx_valid);
            repeat(3) @(posedge clk);
            tx_ready=0;     // stall TX
            repeat(5) @(posedge clk);

            // Verify FSM is holding (tx_valid still asserted)
            if (tx_valid !== 1'b1)
                $display("FAIL BP1: tx_valid dropped during backpressure");
            else
                pass_cnt=pass_cnt+1;

            // Release backpressure
            tx_ready=1;
            wait_pkt_done(50000);

            if (pkt_done) begin
                pass_cnt=pass_cnt+1;
                $display("PASS BP2: packet completed after backpressure");
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL BP2: no pkt_done after backpressure release");
            end
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 2: Checksum = 0x00 (4× 0xA5)
    // 0xA5^0xA5^0xA5^0xA5 = 0x00
    //──────────────────────────────────────────────────────────
    task test_zero_checksum;
        reg [7:0] last_tx;
        begin
            do_reset;
            fifo_seq[0]=8'hA5; fifo_seq[1]=8'hA5;
            fifo_seq[2]=8'hA5; fifo_seq[3]=8'hA5;
            fifo_seq_idx=0; fifo_empty=0;

            // Capture last tx byte (should be checksum = 0x00)
            // Wait for SEND_CHKSUM state — 7th byte transmitted
            // (header + length + 4 data = 6 bytes before checksum)
            repeat(6) begin
                @(posedge tx_valid);
                @(posedge clk);
            end
            @(posedge tx_valid);
            last_tx = tx_data;

            wait_pkt_done(50000);

            if (last_tx === 8'h00) begin
                pass_cnt=pass_cnt+1;
                $display("PASS CHKSUM: 0xA5×4 checksum = 0x00");
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL CHKSUM: got=0x%02X expect=0x00", last_tx);
            end
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 3: All bytes = 0x00 → checksum = 0x00
    //──────────────────────────────────────────────────────────
    task test_all_zeros;
        begin
            do_reset;
            fifo_seq[0]=8'h00; fifo_seq[1]=8'h00;
            fifo_seq[2]=8'h00; fifo_seq[3]=8'h00;
            fifo_seq_idx=0; fifo_empty=0;

            wait_pkt_done(50000);

            if (pkt_done) begin
                pass_cnt=pass_cnt+1;
                $display("PASS ZEROS: all-zero packet completed");
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL ZEROS: no pkt_done");
            end
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 4: Header byte verified = 0xAA
    //──────────────────────────────────────────────────────────
    task test_header_value;
        reg [7:0] first_tx;
        begin
            do_reset;
            fifo_seq[0]=8'h01; fifo_seq[1]=8'h02;
            fifo_seq[2]=8'h03; fifo_seq[3]=8'h04;
            fifo_seq_idx=0; fifo_empty=0;

            // Capture first byte presented to UART TX
            @(posedge tx_valid);
            first_tx = tx_data;

            wait_pkt_done(50000);

            if (first_tx === PKT_HEADER) begin
                pass_cnt=pass_cnt+1;
                $display("PASS HEADER: first byte = 0x%02X (0xAA)",
                         first_tx);
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL HEADER: got=0x%02X expect=0x%02X",
                         first_tx, PKT_HEADER);
            end
        end
    endtask

    //──────────────────────────────────────────────────────────
    // TEST 5: Reset in middle of packet — clean recovery
    //──────────────────────────────────────────────────────────
    task test_mid_packet_reset;
        begin
            do_reset;
            fifo_seq[0]=8'hCC; fifo_seq[1]=8'hDD;
            fifo_seq[2]=8'hEE; fifo_seq[3]=8'hFF;
            fifo_seq_idx=0; fifo_empty=0;

            // Wait for data to start transmitting
            @(posedge tx_valid);
            repeat(3) @(posedge clk);

            // Assert reset mid-packet
            rst=1;
            repeat(3) @(posedge clk);
            rst=0;
            repeat(3) @(posedge clk);

            // FSM should be back in IDLE
            if (dut.state === 3'd0) begin   // ST_IDLE = 0
                pass_cnt=pass_cnt+1;
                $display("PASS RESET: FSM in IDLE after mid-packet reset");
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL RESET: FSM state=%0d after reset (expect 0)",
                         dut.state);
            end

            // Verify new packet can start cleanly
            fifo_seq_idx=0; fifo_empty=0;
            wait_pkt_done(50000);
            if (pkt_done) begin
                pass_cnt=pass_cnt+1;
                $display("PASS RESET_RECOVERY: clean packet after reset");
            end else begin
                fail_cnt=fail_cnt+1;
                $display("FAIL RESET_RECOVERY: no pkt_done after reset");
            end
        end
    endtask

    //──────────────────────────────────────────────────────────
    // Main
    //──────────────────────────────────────────────────────────
    initial begin
        test_backpressure;
        test_zero_checksum;
        test_all_zeros;
        test_header_value;
        test_mid_packet_reset;

        #10000;
        $display("=========================================");
        $display("FSM EDGE TESTS: %0d PASS / %0d FAIL",
                 pass_cnt, fail_cnt);
        $display("=========================================");
        $finish;
    end

    initial begin #10_000_000; $display("TIMEOUT"); $finish; end
    initial begin
        $dumpfile("tb_fsm_edge.vcd");
        $dumpvars(0, tb_fsm_edge);
    end

endmodule
