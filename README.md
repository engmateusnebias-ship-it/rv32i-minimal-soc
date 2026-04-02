# RV32I Minimal SoC in VHDL

A custom **RV32I-based minimal System-on-Chip (SoC)** written in **VHDL**, evolving from a single-cycle CPU into a modular SoC architecture with **memory-mapped peripherals**, **DMA**, **multi-clock domains**, and explicit **clock domain crossing (CDC)** handling.

This project emphasizes **clean RTL architecture**, **modular design**, and **verification-driven development**, targeting **FPGA**, **RTL**, and **SoC design** roles.

## Stable Milestone

**Latest stable integration milestone:** `soc_v1_integration_pass`

This tag marks the first fully validated SoC integration including:
- RV32I core execution from instruction memory
- memory-mapped GPIO signaling
- UART transmission
- DMA RAM-to-RAM transfer
- SoC-level integration testbench passing successfully

---

## Key Features

### RV32I Single-Cycle Core
- Clean datapath/control separation
- Modular components:
  - ALU
  - ALU Control
  - Control Unit
  - Register File
  - Immediate Generator
  - Branch Comparator
  - Load/Store Unit
  - Program Counter
  - Trap Unit

### Memory-Mapped SoC Architecture
- Dedicated instruction memory
- Data memory integrated as a bus slave
- Memory-mapped peripheral space
- Structured top-level integration through `soc_top`

### Custom APB-Like System Bus
- Address-decoded interconnect
- Byte-enable support (`wstrb`)
- Ready/valid handshake
- Error signaling
- Designed for extensibility

### Multi-Clock Domain Design
- `core_clk` domain:
  - CPU
  - bus/interconnect
  - data memory
  - GPIO
  - timer
  - DMA
  - UART register interface
- `periph_clk` domain:
  - UART transmit engine

### Clock Domain Crossing (CDC)
- Explicit UART CDC implementation
- Handshake-based synchronization between clock domains
- Data stability preserved during transfers
- Reset synchronization per domain via reset synchronizers

### Peripherals
- **GPIO**
- **Timer**
  - programmable compare register
  - single-cycle IRQ pulse generation
- **UART**
  - split architecture:
    - register/bus interface in `core_clk`
    - TX engine in `periph_clk`
- **DMA Engine**
  - autonomous RAM-to-RAM transfer
  - word-based transfer model
  - memory-mapped control registers
  - status reporting (`busy`, `done`, `error`)
  - completion IRQ

### SoC Integration
- Unified `soc_top`
- CPU / DMA master multiplexing
- Shared bus fabric with address decoding
- Integration validated with a full SoC-level testbench

---

## Architecture Overview

The system is composed of the following main blocks:

- `rv32i_core`
- `instruction_memory`
- `bus_interconnect`
- `data_memory`
- `gpio`
- `timer`
- `uart`
- `dma`
- `soc_top`

### UART Partitioning
The UART is architecturally split into:
- **register interface** in `core_clk`
- **transmit engine** in `periph_clk`

This creates a real and explicit CDC use case within the SoC.

---

## Verification Strategy

The project follows a **verification-oriented development flow** with dedicated testbenches and assertion-based validation.

### Module-Level Verification
Dedicated testbenches exist for major blocks, including:
- bus interconnect
- data memory
- GPIO
- timer
- UART
- DMA
- reset synchronizer
- RV32I core

### SoC-Level Verification
The `tb_soc_top` testbench validates end-to-end integration using `program.mem`.

The integrated demo covers:
- program execution from instruction memory
- GPIO state progression
- UART transmission activity
- DMA configuration and RAM-to-RAM copy
- final success/failure signaling through memory-mapped I/O

**Current validated outcome:** `tb_soc_top PASSED`

---

## Design Goals

- Build a realistic **SoC architecture**, not just a CPU
- Demonstrate **multi-clock domain** design
- Implement explicit **CDC handling**
- Apply **clean RTL modularity**
- Maintain strong **verification coverage**
- Build a solid portfolio project for **FPGA / RTL / SoC** roles

---

## Current Scope

- RV32I single-cycle core
- Memory-mapped SoC integration
- DMA engine with simplified bus takeover
- Two real clock domains:
  - `core_clk`
  - `periph_clk`
- UART TX CDC implementation
- Assertion-based verification
- Full SoC integration test passing

---

## Planned Extensions

- Interrupt controller with pending/ack logic
- Additional peripherals such as SPI
- UART RX path
- More advanced DMA capabilities
- Full multi-master arbitration
- Expanded CDC use across additional subsystems

---

## Tools

- VHDL (IEEE 1076)
- Xilinx Vivado
- XSim
- Assertion-based verification

---

## Repository Structure

```text
rtl/        RTL modules
tb/         Testbenches
programs/   Program images / memory initialization files
docs/       Project documentation
