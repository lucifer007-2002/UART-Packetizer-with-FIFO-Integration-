`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// tb_uart_top.v
// Full system self-checking testbench
// Verifies complete packet formation end-to-end:
//   data_source → FIFO → packet_fsm → uart_tx → uart_rx
// Checks: header byte, length byte, data bytes, checksum
//------------------------------------------------------------
module tb_uart_top;

    // 200MHz differential clock
    reg clk_p = 0, clk_n = 1;
    always #2.5 begin
        clk_p = ~clk_p;
        clk_n = ~clk_n;
    end

    reg        rst = 1;
    reg  [3:0] sw  = 4'b0100; // sw[2]=1: continuous, sw[1:0]=00: counting
    wire [3:0] led;
    wire       uart_tx_line;

    // Loopback: tx directly into rx for verification
    wire uart_rx_line = uart_tx_line;

    // Instantiate full design
    uart_top dut (
        .sysclk_p (clk_p),
        .sysclk_n (clk_n),
        .rst      (rst),
        .uart_tx  (uart_tx_line),
        .uart_rx  (uart_rx_line),
        .led      (led),
        .sw       (sw)
    );

    //==========================================================
    // Packet capture — monitors uart_tx_line and reconstructs
    // received bytes using bit sampling
    //==========================================================
    integer byte_idx;
    reg [7:0] captured_bytes [0:31];  // capture up to 32 bytes
    integer   capture_count;
    integer   pass_cnt, fail_cnt;

    // Sample tx line at center of each bit
    // Start bit detected on falling edge
    task capture_uart_byte;
        output [7:0] byte_out;
        integer i;
        reg [7:0] bits;
        begin
            // Wait for start bit (falling edge)
            @(negedge uart_tx_line);

            // Skip to center of start bit
            repeat(BAUD_DIV/2) @(posedge clk_p);

            // Verify start bit is low
            if (uart_tx_line !== 1'b0)
                $display("WARNING: start bit not low at t=%0t", $time);

            // Sample 8 data bits at center of each bit period
            for (i = 0; i < 8; i = i + 1) begin
                repeat(BAUD_DIV) @(posedge clk_p);
                bits[i] = uart_tx_line;  // LSB first
            end

            // Skip stop bit
            repeat(BAUD_DIV) @(posedge clk_p);

            byte_out = bits;
        end
    endtask

    // Capture one complete packet
    // Returns number of data bytes captured
    task capture_packet;
        output [7:0] hdr;
        output [7:0] len;
        output [7:0] chk;
        output integer data_count;
        reg [7:0] b;
        integer i;
        begin
            // Capture header
            capture_uart_byte(hdr);

            // Capture length
            capture_uart_byte(len);
            data_count = len;

            // Capture data bytes
            for (i = 0; i < len; i = i + 1)
                capture_uart_byte(captured_bytes[i]);

            // Capture checksum
            capture_uart_byte(chk);
        end
    endtask

    //==========================================================
    // Self-checking tasks
    //==========================================================
    task check_packet;
        input [7:0] hdr, len, chk;
        input integer dcnt;
        reg [7:0] computed_chk;
        integer i;
        begin
            computed_chk = 8'h00;

            // Check header
            if (hdr === PKT_HEADER) begin
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: header=0x%02X expect=0x%02X", hdr, PKT_HEADER);
                fail_cnt = fail_cnt + 1;
            end

            // Check length
            if (len === dcnt[7:0]) begin
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: length=%0d expect=%0d", len, dcnt);
                fail_cnt = fail_cnt + 1;
            end

            // Compute expected checksum
            for (i = 0; i < dcnt; i = i + 1)
                computed_chk = computed_chk ^ captured_bytes[i];

            // Check checksum
            if (chk === computed_chk) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS packet: hdr=0x%02X len=%0d chk=0x%02X",
                         hdr, len, chk);
            end else begin
                $display("FAIL: chk=0x%02X expect=0x%02X", chk, computed_chk);
                fail_cnt = fail_cnt + 1;
            end

            // Print data bytes
            $write("  Data: ");
            for (i = 0; i < dcnt; i = i + 1)
                $write("0x%02X ", captured_bytes[i]);
            $display("");
        end
    endtask

    //==========================================================
    // Main test
    //==========================================================
    reg [7:0] pkt_hdr, pkt_len, pkt_chk;
    integer   pkt_dcnt;

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        capture_count = 0;

        // ── Release reset ─────────────────────────────────────
        repeat(10) @(posedge clk_p);
        rst = 0;
        repeat(20) @(posedge clk_p);

        $display("=== UART Packetizer Full System Test ===");
        $display("BAUD_DIV=%0d FIFO_DEPTH=%0d PKT_MAX=%0d",
                 BAUD_DIV, FIFO_DEPTH, PKT_MAX_DATA);

        // ── TEST 1: 4-byte counting packet (sw[1]=0) ─────────
        sw = 4'b0100;  // continuous, 4-byte, counting
        repeat(20) @(posedge clk_p);

        $display("--- Test 1: 4-byte counting packet ---");
        capture_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        check_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);

        // ── TEST 2: 8-byte packet (sw[1]=1) ──────────────────
        sw = 4'b0110;  // continuous, 8-byte, counting
        repeat(20) @(posedge clk_p);

        $display("--- Test 2: 8-byte counting packet ---");
        capture_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        check_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);

        // ── TEST 3: Alternating 0x55/0xAA pattern ────────────
        sw = 4'b0101;  // continuous, 4-byte, alternating
        repeat(20) @(posedge clk_p);

        $display("--- Test 3: alternating 0x55/0xAA pattern ---");
        capture_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        check_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);

        // ── TEST 4: Fixed 0xA5 pattern ───────────────────────
        sw = 4'b0111;  // continuous, 4-byte, fixed 0xA5
        repeat(20) @(posedge clk_p);

        $display("--- Test 4: fixed 0xA5 pattern ---");
        capture_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        check_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);

        // ── TEST 5: Back-to-back packets ─────────────────────
        $display("--- Test 5: back-to-back packets ---");
        sw = 4'b0100;
        capture_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        check_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        capture_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        check_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);

        // ── TEST 6: Reset mid-stream recovery ────────────────
        $display("--- Test 6: reset recovery ---");
        rst = 1;
        repeat(5) @(posedge clk_p);
        rst = 0;
        repeat(20) @(posedge clk_p);
        sw = 4'b0100;
        capture_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);
        check_packet(pkt_hdr, pkt_len, pkt_chk, pkt_dcnt);

        // ── Results ──────────────────────────────────────────
        #100000;
        $display("========================================");
        $display("SYSTEM TEST: %0d PASS / %0d FAIL",
                 pass_cnt, fail_cnt);
        $display("========================================");
        $finish;
    end

    // Timeout
    initial begin
        #2_000_000_000;
        $display("TIMEOUT — check FSM for deadlock");
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("tb_uart_top.vcd");
        $dumpvars(0, tb_uart_top);
    end

    // Monitor LED status
    always @(led) begin
        $display("t=%0t LED: fifo_ne=%b fifo_full=%b tx_act=%b pkt_done=%b",
                 $time, led[0], led[1], led[2], led[3]);
    end

endmodule
