# RV32I Minimal SoC in VHDL

This project implements a **custom RV32I-based mini System-on-Chip (SoC)** in VHDL, evolving from a single-cycle CPU into a modular and extensible SoC architecture with **multiple clock domains and explicit clock domain crossing (CDC)**.

The design emphasizes **clean architecture, modular RTL design, and verification-driven development**, targeting FPGA/RTL and SoC-oriented roles.

---

##  Key Features

- **RV32I Single-Cycle Core**
  - Clean datapath/control separation
  - Modular components (ALU, Control Unit, Register File, Branch Logic, etc.)

- **Custom APB-like System Bus**
  - Memory-mapped architecture
  - Byte-enable support (`wstrb`)
  - Ready/valid handshake
  - Error signaling
  - Designed for extensibility (DMA, wait states, CDC)

- **Multi-Clock Domain Architecture**
  - `core_clk`: CPU, bus, memory, DMA, peripherals
  - `periph_clk`: UART transmission engine
  - Explicit CDC design using handshake-based synchronization

- **Clock Domain Crossing (CDC)**
  - Toggle-based handshake (`req/ack`) between domains
  - Data stability guarantees during transfer
  - Per-domain synchronized resets via reset synchronizers

- **Memory Subsystems**
  - Dedicated instruction memory
  - Data memory integrated as a bus slave

- **Memory-Mapped Peripherals**
  - GPIO
  - Timer with programmable compare and IRQ pulse generation
  - UART with split architecture (register interface + TX engine)

- **Timer with Precise IRQ Semantics**
  - Compare-based trigger
  - Single-cycle IRQ pulse
  - Clean separation from future interrupt controller logic

- **DMA Engine (v1)**
  - Autonomous RAM-to-RAM transfers
  - Word-based transfer model (32-bit)
  - Memory-mapped control interface
  - Status reporting (`busy`, `done`, `error`)
  - IRQ on completion
  - Simplified bus takeover (no full arbiter yet)

- **SoC Integration**
  - Unified `soc_top` architecture
  - CPU/DMA master multiplexing
  - Structured interconnect with address decoding

- **Verification-Oriented Design**
  - Dedicated testbenches per module
  - Assertion-based validation
  - Full SoC-level simulation

---

##  Architecture Overview

The system is organized as a modular SoC composed of:

- `rv32i_core` (CPU)
- `instruction_memory`
- `system bus / interconnect`
- `data_memory`
- peripherals (GPIO, Timer, UART, DMA registers)
- `dma_engine`

The UART is architecturally split into:
- register interface in `core_clk`
- transmission engine in `periph_clk`
- CDC bridge using handshake synchronization

---

##  Design Goals

- Build a **realistic SoC architecture**, not just a CPU
- Demonstrate **multi-clock domain design and CDC handling**
- Apply **clean RTL design and modularity**
- Ensure **strong verification coverage**
- Provide a solid **portfolio project for FPGA/SoC roles**

---

##  Current Scope

- Single-cycle RV32I core
- Single-master bus with DMA takeover mechanism
- Two clock domains (`core_clk`, `periph_clk`)
- CDC implemented for UART TX path
- No full multi-master arbitration yet

---

##  Planned Extensions

- Interrupt controller with pending/ack logic
- Additional peripherals (SPI, enhanced UART RX)
- Full multi-master arbitration
- Expanded CDC usage across subsystems
- More advanced DMA features

---

##  Tools

- VHDL (IEEE 1076)
- Xilinx Vivado / XSim
- Assertion-based verification
