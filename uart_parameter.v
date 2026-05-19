→ Add: src/rtl/
This lets every .v file use `include "uart_params.vh" without a full path.

Step 4 — Parameters File (uart_params.vh)
All constants in one place. Change any of these and the change propagates everywhere.

verilog
//============================================================
// uart_params.vh
// All design parameters for UART Packetizer with Async FIFO
// Target: AC701 — xc7a200tfbg676-2
// System clock: 200 MHz
//============================================================
`ifndef UART_PARAMS_VH
`define UART_PARAMS_VH

//------------------------------------------------------------
// Clock and baud rate
//------------------------------------------------------------
// System clock frequency in Hz
localparam CLK_FREQ_HZ   = 200_000_000;

// Target baud rate
localparam BAUD_RATE     = 115_200;

// Baud tick divisor: CLK_FREQ / BAUD_RATE = 1736
// Actual baud: 200MHz/1736 = 115,207 Hz → 0.006% error (safe)
// Counter counts 0..BAUD_DIV-1, generates 1-cycle tick at rollover
localparam BAUD_DIV      = 1736;

// Baud counter width: ceil(log2(1736)) = 11 bits
localparam BAUD_CTR_W    = 11;

// RX oversampling: 8x → divisor = CLK_FREQ / (BAUD × 8) = 217
// Sample point = OVERSAMPLE_DIV/2 = 108 (center of bit)
localparam OVERSAMPLE_DIV = 217;
localparam OVERSAMPLE_CTR_W = 8;  // ceil(log2(217)) = 8 bits
localparam SAMPLE_POINT   = 108;  // center sample: 217/2 rounded

//------------------------------------------------------------
// UART protocol constants
//------------------------------------------------------------
// Data bits (always 8 for standard UART)
localparam UART_DATA_BITS = 8;

// Bit counter width: ceil(log2(8)) = 3 bits
localparam BIT_CTR_W     = 3;

//------------------------------------------------------------
// Async FIFO parameters
//------------------------------------------------------------
// FIFO data width (matches UART byte width)
localparam FIFO_WIDTH    = 8;

// FIFO depth — must be a power of 2 for gray-code arithmetic
// 16 entries: enough to buffer one max-length packet
// Change to 64 for longer packets (uses more BRAM)
localparam FIFO_DEPTH    = 16;

// Address width: log2(FIFO_DEPTH) = 4
// Pointer width: FIFO_ADDR_W + 1 (extra MSB for wrap detection)
localparam FIFO_ADDR_W   = 4;
localparam FIFO_PTR_W    = 5;   // FIFO_ADDR_W + 1

//------------------------------------------------------------
// Packet format constants
//------------------------------------------------------------
// Header byte — fixed preamble, receiver syncs on this
localparam PKT_HEADER    = 8'hAA;

// Maximum data bytes per packet
// Must fit in FIFO: PKT_MAX_DATA <= FIFO_DEPTH
localparam PKT_MAX_DATA  = 8;

// Packet length field width
localparam PKT_LEN_W     = 8;   // 1-byte length field → max 255

//------------------------------------------------------------
// Reset synchronizer stages
// 2 FF stages minimum for metastability resolution on Artix-7
//------------------------------------------------------------
localparam RESET_SYNC_STAGES = 2;

//------------------------------------------------------------
// FSM state encoding (one-hot for speed, binary for area)
// Using binary encoding — 3 bits covers 6 states
//------------------------------------------------------------
localparam FSM_IDLE        = 3'd0;
localparam FSM_SEND_HEADER = 3'd1;
localparam FSM_SEND_LENGTH = 3'd2;
localparam FSM_SEND_DATA   = 3'd3;
localparam FSM_SEND_CHKSUM = 3'd4;
localparam FSM_WAIT_TX     = 3'd5;

`endif // UART_PARAMS_VH
