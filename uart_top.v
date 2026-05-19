`timescale 1ns / 1ps
`include "uart_params.vh"
//============================================================
// uart_top.v  —  UART Packetizer complete integration
// Target: AC701 (xc7a200tfbg676-2)
// All modules from Parts 2-5 instantiated and connected.
//============================================================
module uart_top (
    input  wire        sysclk_p,
    input  wire        sysclk_n,
    input  wire        rst,
    output wire        uart_tx,
    input  wire        uart_rx,
    output wire [3:0]  led,
    input  wire [3:0]  sw
);

    //==========================================================
    // SECTION 1 — Clock: IBUFDS + BUFG
    //==========================================================
    wire clk_unbuf, clk;

    IBUFDS #(
        .DIFF_TERM    ("FALSE"),
        .IBUF_LOW_PWR ("FALSE")
    ) u_ibufds (
        .I  (sysclk_p),
        .IB (sysclk_n),
        .O  (clk_unbuf)
    );

    BUFG u_bufg (.I(clk_unbuf), .O(clk));

    //==========================================================
    // SECTION 2 — Reset synchronizers (one per domain)
    //==========================================================
    wire rst_sync_wr, rst_sync_rd;

    reset_sync #(.STAGES(RESET_SYNC_STAGES)) u_rst_wr (
        .clk     (clk),
        .rst_in  (rst),
        .rst_out (rst_sync_wr)
    );

    reset_sync #(.STAGES(RESET_SYNC_STAGES)) u_rst_rd (
        .clk     (clk),
        .rst_in  (rst),
        .rst_out (rst_sync_rd)
    );

    // Shared alias for single-clock modules
    wire rst_sync = rst_sync_wr;

    //==========================================================
    // SECTION 3 — Baud generator
    //==========================================================
    wire baud_tick;
    wire oversample_tick;

    baud_gen u_baud (
        .clk            (clk),
        .rst            (rst_sync),
        .baud_tick      (baud_tick),
        .oversample_tick(oversample_tick)
    );

    //==========================================================
    // SECTION 4 — Data source
    //==========================================================
    wire [7:0] src_data;
    wire       src_valid;
    wire       src_ready;

    data_source u_src (
        .clk   (clk),
        .rst   (rst_sync),
        .sw    (sw),
        .data  (src_data),
        .valid (src_valid),
        .ready (src_ready)
    );

    //==========================================================
    // SECTION 5 — Asynchronous FIFO
    //==========================================================
    wire [7:0] fifo_rdata;
    wire       fifo_wr_en;
    wire       fifo_rd_en;
    wire       fifo_full;
    wire       fifo_empty;

    // Write enable: source valid AND FIFO not full
    assign fifo_wr_en = src_valid & ~fifo_full;
    // Back-pressure: source ready when FIFO can accept
    assign src_ready  = ~fifo_full;

    async_fifo #(
        .DATA_W (FIFO_WIDTH),
        .DEPTH  (FIFO_DEPTH),
        .ADDR_W (FIFO_ADDR_W),
        .PTR_W  (FIFO_PTR_W)
    ) u_fifo (
        .wr_clk  (clk),
        .wr_rst  (rst_sync_wr),
        .wr_en   (fifo_wr_en),
        .wr_data (src_data),
        .full    (fifo_full),
        .rd_clk  (clk),
        .rd_rst  (rst_sync_rd),
        .rd_en   (fifo_rd_en),
        .rd_data (fifo_rdata),
        .empty   (fifo_empty)
    );

    //==========================================================
    // SECTION 6 — Packet FSM
    //==========================================================
    wire [7:0] pkt_tx_data;
    wire       pkt_tx_valid;
    wire       pkt_tx_ready;
    wire       pkt_done;

    packet_fsm #(
        .MAX_DATA (PKT_MAX_DATA)
    ) u_fsm (
        .clk        (clk),
        .rst        (rst_sync),
        .fifo_data  (fifo_rdata),
        .fifo_empty (fifo_empty),
        .fifo_rd_en (fifo_rd_en),
        .tx_data    (pkt_tx_data),
        .tx_valid   (pkt_tx_valid),
        .tx_ready   (pkt_tx_ready),
        .len_sel    (sw[1]),
        .pkt_done   (pkt_done)
    );

    //==========================================================
    // SECTION 7 — UART Transmitter
    //==========================================================
    uart_tx u_uart_tx (
        .clk       (clk),
        .rst       (rst_sync),
        .baud_tick (baud_tick),
        .data      (pkt_tx_data),
        .valid     (pkt_tx_valid),
        .ready     (pkt_tx_ready),
        .tx        (uart_tx)
    );

    //==========================================================
    // SECTION 8 — UART Receiver (loopback verification)
    //==========================================================
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_frame_err;

    uart_rx u_uart_rx (
        .clk            (clk),
        .rst            (rst_sync),
        .oversample_tick(oversample_tick),
        .rx             (uart_rx),
        .data           (rx_data),
        .valid          (rx_valid),
        .frame_error    (rx_frame_err)
    );

    //==========================================================
    // SECTION 9 — LED outputs (registered)
    //==========================================================
    reg [3:0] led_r;

    always @(posedge clk) begin
        if (rst_sync) begin
            led_r <= 4'b0000;
        end else begin
            led_r[0] <= ~fifo_empty;   // data in FIFO
            led_r[1] <=  fifo_full;    // FIFO full / back-pressure
            led_r[2] <=  pkt_tx_valid; // TX active
            led_r[3] <=  pkt_done;     // packet complete pulse
        end
    end

    assign led = led_r;

endmodule
