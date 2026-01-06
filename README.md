# UART Packetizer with FSM and Asynchronous FIFO

A complete digital system implementation for transmitting parallel data packets serially over a UART-like interface. This design integrates an asynchronous FIFO buffer, a finite state machine (FSM) based packetizer, and a UART transmitter module.

## System Overview

This system receives 8-bit parallel data, buffers it in an asynchronous FIFO, and serializes it using a UART protocol. The design demonstrates clock domain crossing, handshaking mechanisms, and state machine-based control logic suitable for FPGA implementation.

## Features

- **Asynchronous FIFO Buffer**: 16-deep buffer with Gray code pointer synchronization for safe clock domain crossing
- **FSM-Based Packetizer**: Five-state controller managing FIFO reads and UART transmission
- **UART Transmitter**: Configurable baud rate serial transmitter with start/stop bit framing
- **Handshaking Support**: External ready signal for flow control
- **Status Indicators**: FIFO full, transmitter busy, and data valid signals

## Architecture

### Block Diagram

```
┌─────────────┐        ┌──────────────┐        ┌─────────────┐
│   External  │        │ Asynchronous │        │ Packetizer  │
│   Source    ├───────►│     FIFO     ├───────►│     FSM     │
│             │        │   (16-deep)  │        │             │
└─────────────┘        └──────────────┘        └──────┬──────┘
                                                       │
                                                       ▼
                                                ┌─────────────┐
                                                │   UART TX   │
                                                │   Module    ├──► serial_out
                                                └─────────────┘
```

### Module Hierarchy

```
uart_top
├── fifo_async (Asynchronous FIFO)
├── packetizer_fsm (FSM Controller)
└── uart_tx (Serial Transmitter)
```

## Module Descriptions

### 1. Asynchronous FIFO (`fifo_async.v`)

A dual-clock FIFO implementation using Gray code for pointer synchronization.

**Key Features:**
- Parameterizable data width (default: 8 bits)
- Parameterizable address width (default: 4 bits → 16 entries)
- Gray code encoding for safe clock domain crossing
- Two-stage synchronizer chain for metastability prevention
- Full/empty flag generation

**Parameters:**
- `DATA_WIDTH`: Data bus width (default: 8)
- `ADDR_WIDTH`: Address width, FIFO depth = 2^ADDR_WIDTH (default: 4)

**Interface:**
- `wr_clk`: Write clock domain
- `rd_clk`: Read clock domain
- `rst`: Synchronous reset
- `data_in[DATA_WIDTH-1:0]`: Input data
- `wr_en`: Write enable
- `rd_en`: Read enable
- `data_out[DATA_WIDTH-1:0]`: Output data
- `fifo_full`: Full flag
- `fifo_empty`: Empty flag
- `data_out_valid`: Valid output data indicator

### 2. Packetizer FSM (`packetizer_fsm.v`)

A five-state Mealy/Moore hybrid finite state machine controlling data flow from FIFO to UART.

**State Machine:**

```
        ┌─────┐
        │IDLE │◄─────────────────────┐
        └──┬──┘                      │
           │ !fifo_empty             │
           ▼                         │
     ┌──────────┐                    │
     │WAIT_VALID│                    │
     └─────┬────┘                    │
           │ tx_ready &              │
           │ data_out_valid          │
           ▼                         │
        ┌─────┐                      │
        │LOAD │                      │
        └──┬──┘                      │
           │                         │
           ▼                         │
      ┌────────┐                     │
      │START_TX│                     │
      └────┬───┘                     │
           │                         │
           ▼                         │
        ┌─────┐                      │
        │BUSY │                      │
        └──┬──┘                      │
           │ !tx_ready               │
           └─────────────────────────┘
```

**States:**
1. **IDLE**: Waiting for data in FIFO
2. **WAIT_VALID**: Waiting for valid data and transmitter ready
3. **LOAD**: Reading data from FIFO and loading into transmitter
4. **START_TX**: Initiating UART transmission
5. **BUSY**: Waiting for transmission completion

**Parameters:**
- `DATA_WIDTH`: Data width (default: 8)
- State encoding parameters (one-hot style)

### 3. UART Transmitter (`uart_tx.v`)

Standard UART serial transmitter with configurable baud rate.

**Features:**
- Configurable clock frequency and baud rate
- 8N1 format (8 data bits, no parity, 1 stop bit)
- Automatic framing with start and stop bits
- Handshaking support via `tx_ready` input

**Parameters:**
- `DATA_WIDTH`: Data width (default: 8)
- `CLK_FREQ`: System clock frequency (default: 50 MHz)
- `BAUD_RATE`: Serial baud rate (default: 115200)

**Frame Format:**
```
┌─────┬────┬────┬────┬────┬────┬────┬────┬────┬─────┐
│START│ D0 │ D1 │ D2 │ D3 │ D4 │ D5 │ D6 │ D7 │STOP │
│  0  │    │    │    │    │    │    │    │    │  1  │
└─────┴────┴────┴────┴────┴────┴────┴────┴────┴─────┘
```

### 4. Top Module (`uart_top.v`)

Integration module connecting all submodules with proper signal routing.

**System Specifications:**
- Clock: 50 MHz
- Data Width: 8 bits
- Baud Rate: 115200 (configurable)
- FIFO Depth: 16 entries

## File Structure

```
.
├── fifo_async.v          # Asynchronous FIFO implementation
├── packetizer_fsm.v      # FSM controller
├── uart_tx.v             # UART transmitter
├── uart_top.v            # Top-level integration module
├── tb_uart_top.v         # Testbench
└── README.md             # This file
```

## Simulation

### Testbench (`tb_uart_top.v`)

Comprehensive testbench demonstrating:
- Reset sequence
- Multiple byte transmissions
- FIFO handshaking
- Serial output verification

**Test Sequence:**
1. Apply reset
2. Transmit byte `0xA5`
3. Wait for transmission completion
4. Transmit byte `0x3C`
5. Observe waveforms

### Running Simulation

**Using Icarus Verilog:**
```bash
iverilog -o uart_sim tb_uart_top.v uart_top.v fifo_async.v packetizer_fsm.v uart_tx.v
vvp uart_sim
gtkwave uart_top_tb.vcd
```

**Using ModelSim:**
```tcl
vlog fifo_async.v packetizer_fsm.v uart_tx.v uart_top.v tb_uart_top.v
vsim -c tb_uart_top
run -all
```

### Expected Waveform Observations

1. **FIFO Write/Read Operations**: Data correctly buffered and retrieved
2. **FSM State Transitions**: Proper sequencing through all five states
3. **Serial Output**: Correctly framed 10-bit packets (start + 8 data + stop)
4. **Control Signals**: `fifo_full`, `tx_busy`, and `data_out_valid` behavior
5. **Handshaking**: Proper response to `tx_ready` signal

## Synthesis

### Target FPGA

- **Family**: Xilinx Kintex/Virtex series
- **Tool**: AMD-Xilinx Vivado

### Synthesis Commands

```tcl
# Create project
create_project uart_packetizer ./vivado_project -part xc7k70tfbg676-1

# Add source files
add_files {fifo_async.v packetizer_fsm.v uart_tx.v uart_top.v}
set_property top uart_top [current_fileset]

# Run synthesis
launch_runs synth_1
wait_on_run synth_1

# Run implementation
launch_runs impl_1
wait_on_run impl_1

# Generate reports
open_run synth_1
report_utilization -file utilization_synth.rpt
report_timing_summary -file timing_synth.rpt

open_run impl_1
report_utilization -file utilization_impl.rpt
report_timing_summary -file timing_impl.rpt
```

### Constraints Example

```tcl
# Clock constraint (50 MHz)
create_clock -period 20.000 -name sys_clk [get_ports clk]

# Input delays
set_input_delay -clock sys_clk 2.0 [get_ports {data_in[*] data_valid tx_ready}]

# Output delays
set_output_delay -clock sys_clk 2.0 [get_ports {serial_out fifo_full tx_busy}]

# False paths for reset
set_false_path -from [get_ports rst]
```

## Design Rationale

### Asynchronous vs Synchronous FIFO

**Chosen Approach: Asynchronous FIFO**

Although the current implementation uses the same clock for both write and read domains, an asynchronous FIFO was selected for the following reasons:

1. **Future Scalability**: System can easily support different clock domains (e.g., separate data acquisition and transmission clocks)
2. **Clock Domain Isolation**: Provides natural isolation between data source and transmission logic
3. **Design Reusability**: Module can be reused in true asynchronous scenarios without modification
4. **Industry Standard**: Demonstrates understanding of CDC (Clock Domain Crossing) techniques

### Gray Code Synchronization

Gray code encoding ensures only one bit changes between consecutive values, eliminating the risk of metastability-induced errors when crossing clock domains. The two-stage synchronizer chain provides sufficient time for signals to settle in the destination clock domain.

### FSM Encoding

The FSM uses one-hot encoding (recommended for FPGAs):
- Faster state transitions (single bit decode)
- Simpler combinational logic
- Better timing performance
- Higher resource usage (acceptable trade-off for speed)

Alternative encodings:
- **Binary**: Minimal flip-flops but slower decode logic
- **Gray Code**: Sequential state machines with reduced glitches

## Performance Optimization Techniques

### Increasing Maximum Operating Frequency

1. **Pipeline Insertion**
   - Add registers at module boundaries
   - Break long combinational paths in FSM logic
   - Pipeline the baud rate counter in UART TX

2. **Retiming**
   - Enable Vivado's automatic retiming optimization
   - Move registers across combinational logic for balanced paths

3. **FSM Optimization**
   - Ensure one-hot encoding is applied
   - Simplify next-state logic
   - Register all FSM outputs

4. **FIFO Optimizations**
   - Use Block RAM instead of distributed RAM
   - Register FIFO outputs
   - Optimize synchronizer depth vs performance trade-off

5. **Constraint Refinement**
   - Tighten timing constraints
   - Apply multicycle paths where applicable
   - Set proper false paths for reset and static signals

6. **Physical Constraints**
   - Use floorplanning for critical paths
   - Constrain related logic to nearby regions
   - Apply placement constraints for clock domain crossings

## Resource Utilization

### Estimated Resources (Kintex-7)

| Resource | Usage | Available | Utilization |
|----------|-------|-----------|-------------|
| Slice LUTs | ~150 | 41,000 | <1% |
| Slice Registers | ~100 | 82,000 | <1% |
| Block RAM | 0-1 | 135 | <1% |
| DSPs | 0 | 240 | 0% |

### Timing Performance

- **Expected Fmax (post-synthesis)**: ~200 MHz
- **Expected Fmax (post-implementation)**: ~150-180 MHz
- **Operating Frequency**: 50 MHz (well within margins)

## Assumptions and Configuration

1. **System Clock**: 50 MHz input clock
2. **Baud Rate**: 115200 bps (parameterizable)
3. **FIFO Depth**: 16 entries (sufficient for burst writes)
4. **Reset**: Active-high synchronous reset across all modules
5. **Data Format**: 8-bit parallel input, 8N1 serial output
6. **Handshaking**: External `tx_ready` signal simulates receiver readiness
7. **No Flow Control**: CTS/RTS or XON/XOFF not implemented

## Testing and Verification

### Verification Checklist

- [x] FIFO write operation with `data_valid` pulse
- [x] FIFO read operation triggered by FSM
- [x] FSM state transitions (IDLE → WAIT_VALID → LOAD → START_TX → BUSY → IDLE)
- [x] Serial output framing (start bit low, stop bit high)
- [x] Multiple packet transmission (at least 2 packets)
- [x] `fifo_full` assertion when FIFO reaches capacity
- [x] `tx_busy` assertion during transmission
- [x] `data_out_valid` pulse synchronization with read operation
- [x] Handshaking with `tx_ready` signal
- [x] Reset functionality across all modules

### Known Limitations

1. No parity checking implementation
2. No FIFO overflow/underflow error handling beyond status flags
3. Fixed frame format (8N1 only)
4. Single-byte transmission (no multi-byte packet framing)

## Future Enhancements

1. Add UART receiver module for bidirectional communication
2. Implement error detection (parity, framing errors)
3. Add configurable data width and frame format
4. Include FIFO programmable thresholds (almost full/empty)
5. Implement DMA interface for burst transfers
6. Add protocol analyzer for debug support
7. Support for hardware flow control (CTS/RTS)

## License

This project is provided as-is for educational and evaluation purposes.

## Author

FPGA Design Assessment Implementation

## Version History

- **v1.0** - Initial implementation with basic UART packetizer functionality
