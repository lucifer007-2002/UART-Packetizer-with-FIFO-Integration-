`timescale 1ns / 1ps
`include "uart_params.vh"
//------------------------------------------------------------
// uart_rx.v
// UART receiver — 8N1 format, 8x oversampled
//
// Used for loopback verification — connects uart_rx pin
// back to verify transmitted data matches received data.
//
// Oversampling: samples at 8× baud rate
//   Each bit period = OVERSAMPLE_DIV × 8 = 217 × 8 = 1736 clk
//   Start bit detected on falling edge of rx input
//   After SAMPLE_POINT ticks (108) → at center of start bit
//   Verify start bit is still LOW (reject noise glitches)
//   Sample each data bit at center: every OVERSAMPLE_DIV ticks
//
// Double-FF synchronizer on rx input (metastability guard):
//   rx is an asynchronous external signal — must synchronize
//   before any edge detection or sampling
//------------------------------------------------------------

`define RX_IDLE      3'd0
`define RX_START     3'd1
`define RX_DATA      3'd2
`define RX_STOP      3'd3

module uart_rx (
    input  wire       clk,
    input  wire       rst,
    input  wire       oversample_tick, // 8× baud tick from baud_gen
    input  wire       rx,              // UART serial input (async)
    output reg  [7:0] data,            // received byte
    output reg        valid,           // pulses 1 cycle when byte ready
    output reg        frame_error      // 1 if stop bit not HIGH
);

    // ── 2-FF synchronizer for async rx input ─────────────────
    // rx comes from an external pin with no timing relationship
    // to clk. Must synchronize to prevent metastability.
    reg rx_meta, rx_sync;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;    // default idle = high
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;          // first FF — may be metastable
            rx_sync <= rx_meta;     // second FF — resolved
        end
    end

    // Edge detection on synchronized rx
    reg rx_prev;
    wire rx_falling = rx_prev & ~rx_sync;  // HIGH→LOW = start bit

    always @(posedge clk) begin
        if (rst) rx_prev <= 1'b1;
        else     rx_prev <= rx_sync;
    end

    // ── FSM state and datapath ────────────────────────────────
    reg [2:0]  state;
    reg [7:0]  shift_reg;
    reg [2:0]  bit_cnt;
    reg [7:0]  os_cnt;   // oversample counter (restartable)
    reg        os_cnt_en; // enable oversample counting

    always @(posedge clk) begin
        if (rst) begin
            state       <= `RX_IDLE;
            shift_reg   <= 8'h00;
            bit_cnt     <= 3'd0;
            os_cnt      <= 8'd0;
            os_cnt_en   <= 1'b0;
            data        <= 8'h00;
            valid       <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            // Default: clear single-cycle signals
            valid <= 1'b0;

            // Oversample counter — only runs when enabled
            if (os_cnt_en && oversample_tick) begin
                if (os_cnt == OVERSAMPLE_DIV - 1)
                    os_cnt <= 8'd0;
                else
                    os_cnt <= os_cnt + 1'b1;
            end

            case (state)

                //──────────────────────────────────────────────
                `RX_IDLE: begin
                    os_cnt_en <= 1'b0;
                    os_cnt    <= 8'd0;

                    if (rx_falling) begin
                        // Falling edge = potential start bit
                        // Begin counting to find bit center
                        os_cnt_en <= 1'b1;
                        state     <= `RX_START;
                    end
                end

                //──────────────────────────────────────────────
                `RX_START: begin
                    // Wait until we're at the center of start bit
                    // Center = SAMPLE_POINT (108) oversample ticks
                    if (os_cnt_en && oversample_tick &&
                        os_cnt == SAMPLE_POINT - 1) begin

                        if (rx_sync == 1'b0) begin
                            // Start bit confirmed LOW at center
                            // Reset counter for data bit sampling
                            bit_cnt <= 3'd0;
                            os_cnt  <= 8'd0;
                            state   <= `RX_DATA;
                        end else begin
                            // Noise glitch — not a real start bit
                            os_cnt_en <= 1'b0;
                            state     <= `RX_IDLE;
                        end
                    end
                end

                //──────────────────────────────────────────────
                `RX_DATA: begin
                    // Sample at center of each data bit
                    // Center = OVERSAMPLE_DIV (217) ticks after
                    // previous sample point
                    if (os_cnt_en && oversample_tick &&
                        os_cnt == OVERSAMPLE_DIV - 1) begin

                        // Shift in from MSB side (LSB received first)
                        // rx_sync[0] is current bit value
                        shift_reg <= {rx_sync, shift_reg[7:1]};

                        if (bit_cnt == 3'd7) begin
                            state <= `RX_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                //──────────────────────────────────────────────
                `RX_STOP: begin
                    // Wait for stop bit center, verify HIGH
                    if (os_cnt_en && oversample_tick &&
                        os_cnt == OVERSAMPLE_DIV - 1) begin

                        if (rx_sync == 1'b1) begin
                            // Valid stop bit — output data
                            data        <= shift_reg;
                            valid       <= 1'b1;
                            frame_error <= 1'b0;
                        end else begin
                            // Framing error — stop bit not HIGH
                            frame_error <= 1'b1;
                        end

                        os_cnt_en <= 1'b0;
                        state     <= `RX_IDLE;
                    end
                end

                default: state <= `RX_IDLE;

            endcase
        end
    end

endmodule
