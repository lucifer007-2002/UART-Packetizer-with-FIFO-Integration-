`timescale 1ns / 1ps
`include "uart_params.vh"
//============================================================
// uart_top.v
// UART Packetizer with Async FIFO — top-level wrapper
// Target: AC701 (xc7a200tfbg676-2)
// Clock:  200MHz LVDS via IBUFDS + BUFG
//
// Architecture:
//   Data source (clk domain) → Async FIFO → Packet FSM
//   → UART TX → uart_tx pin
//
// Two clock domains:
//   clk  : 200MHz system clock — data source, FIFO write side
//   clk  : same 200MHz — this design uses ONE clock domain
//          with baud_tick enable pulses for UART timing.
//          The async FIFO is included architecturally to
//          demonstrate CDC design — in this implementation
//          both sides use clk with baud_tick as the
//          rate-limiting signal for the TX side.
//          To test true async: drive wr_clk from a PLL
//          output at a different frequency (Part 6 option).
//============================================================
module uart_top (
    // Clock — differential LVDS 200MHz from AC701 oscillator
    input  wire        sysclk_p,
    input  wire        sysclk_n,

    // Reset — active-high, asynchronous (CPU_RESET button U4)
    input  wire        rst,

    // UART serial interface
    output wire        uart_tx,    // to USB-UART bridge T19
    input  wire        uart_rx,    // from USB-UART bridge U19

    // Status LEDs
    output wire [3:0]  led,

    // DIP switches
    input  wire [3:0]  sw
);

    //==========================================================
    // SECTION 1 — Clock generation (IBUFDS + BUFG)
    // LVDS input mandatory for AC701 200MHz oscillator
    //==========================================================
    wire clk_unbuf;
    wire clk;

    IBUFDS #(
        .DIFF_TERM    ("FALSE"),
        .IBUF_LOW_PWR ("FALSE")
    ) u_ibufds (
        .I  (sysclk_p),
        .IB (sysclk_n),
        .O  (clk_unbuf)
    );

    BUFG u_bufg (
        .I (clk_unbuf),
        .O (clk)
    );

    //==========================================================
    // SECTION 2 — Reset synchronizer
    // Async assert (immediate), sync deassert (2-FF chain)
    // Prevents metastability on rst release
    // Instantiated once here; drives all downstream modules
    //==========================================================
    wire rst_sync;    // synchronized reset output (active-high)

    // reset_sync instantiated in Part 4
    // reset_sync u_rst_sync (
    //     .clk     (clk),
    //     .rst_in  (rst),
    //     .rst_out (rst_sync)
    // );

    // Temporary passthrough until Part 4
    assign rst_sync = rst;

    //==========================================================
    // SECTION 3 — Baud tick generator
    // Generates a single-cycle pulse every BAUD_DIV cycles
    // All UART timing derives from this pulse
    //==========================================================
    wire baud_tick;    // 1-cycle pulse at 115,207 Hz

    // baud_gen instantiated in Part 3
    // baud_gen u_baud (
    //     .clk       (clk),
    //     .rst       (rst_sync),
    //     .baud_tick (baud_tick)
    // );

    assign baud_tick = 1'b0;   // stub until Part 3

    //==========================================================
    // SECTION 4 — Data source (test pattern generator)
    // Generates bytes to push into FIFO
    // sw[0]=1: continuous injection mode
    // sw[1]:   selects packet size
    //==========================================================
    wire [7:0]  src_data;     // byte from data source
    wire        src_valid;    // data source has a byte ready
    wire        src_ready;    // FIFO can accept (not full)

    // data_source instantiated in Part 5
    // data_source u_src (
    //     .clk       (clk),
    //     .rst       (rst_sync),
    //     .sw        (sw),
    //     .data      (src_data),
    //     .valid     (src_valid),
    //     .ready     (src_ready)
    // );

    assign src_data  = 8'hAB;   // stub
    assign src_valid = 1'b0;    // stub

    //==========================================================
    // SECTION 5 — Asynchronous FIFO
    // Write side: clk (system clock, data source)
    // Read side:  clk (same in this impl — different in CDC test)
    //==========================================================
    wire [7:0]  fifo_rdata;    // data out of FIFO to packet FSM
    wire        fifo_wr_en;    // write enable from data source
    wire        fifo_rd_en;    // read enable from packet FSM
    wire        fifo_full;     // back-pressure to data source
    wire        fifo_empty;    // FSM waits when asserted

    assign fifo_wr_en = src_valid & ~fifo_full;
    assign src_ready  = ~fifo_full;

    // async_fifo instantiated in Part 4
    // async_fifo #(
    //     .DATA_W (FIFO_WIDTH),
    //     .DEPTH  (FIFO_DEPTH),
    //     .ADDR_W (FIFO_ADDR_W),
    //     .PTR_W  (FIFO_PTR_W)
    // ) u_fifo (
    //     .wr_clk   (clk),
    //     .rd_clk   (clk),
    //     .wr_rst   (rst_sync),
    //     .rd_rst   (rst_sync),
    //     .wr_en    (fifo_wr_en),
    //     .wr_data  (src_data),
    //     .rd_en    (fifo_rd_en),
    //     .rd_data  (fifo_rdata),
    //     .full     (fifo_full),
    //     .empty    (fifo_empty)
    // );

    // Stubs until Part 4
    assign fifo_rdata = 8'h00;
    assign fifo_full  = 1'b0;
    assign fifo_empty = 1'b1;

    //==========================================================
    // SECTION 6 — Packet FSM
    // Reads bytes from FIFO, forms packet, feeds UART TX
    //==========================================================
    wire [7:0]  pkt_byte;      // byte to transmit (from FSM)
    wire        pkt_valid;     // FSM has a byte ready for TX
    wire        pkt_ready;     // UART TX ready for next byte
    wire        pkt_done;      // pulse: full packet transmitted

    // packet_fsm instantiated in Part 5
    // packet_fsm #(
    //     .PKT_MAX_DATA (PKT_MAX_DATA)
    // ) u_fsm (
    //     .clk        (clk),
    //     .rst        (rst_sync),
    //     .baud_tick  (baud_tick),
    //     .fifo_data  (fifo_rdata),
    //     .fifo_empty (fifo_empty),
    //     .fifo_rd_en (fifo_rd_en),
    //     .tx_data    (pkt_byte),
    //     .tx_valid   (pkt_valid),
    //     .tx_ready   (pkt_ready),
    //     .pkt_done   (pkt_done)
    // );

    // Stubs until Part 5
    assign pkt_byte    = 8'h00;
    assign pkt_valid   = 1'b0;
    assign fifo_rd_en  = 1'b0;
    assign pkt_done    = 1'b0;

    //==========================================================
    // SECTION 7 — UART Transmitter
    //==========================================================

    // uart_tx instantiated in Part 3
    // uart_tx u_uart_tx (
    //     .clk       (clk),
    //     .rst       (rst_sync),
    //     .baud_tick (baud_tick),
    //     .data      (pkt_byte),
    //     .valid     (pkt_valid),
    //     .ready     (pkt_ready),
    //     .tx        (uart_tx)
    // );

    assign uart_tx  = 1'b1;    // UART idle = high
    assign pkt_ready = 1'b0;   // stub

    //==========================================================
    // SECTION 8 — LED status outputs
    //==========================================================
    // Registered to avoid glitches on output pins
    reg [3:0] led_r;
    always @(posedge clk) begin
        if (rst_sync) begin
            led_r <= 4'b0000;
        end else begin
            led_r[0] <= ~fifo_empty;   // data waiting in FIFO
            led_r[1] <=  fifo_full;    // FIFO full — back-pressure
            led_r[2] <=  pkt_valid;    // TX currently active
            led_r[3] <=  pkt_done;     // packet completed (brief pulse)
        end
    end
    assign led = led_r;

endmodule
