# Mini-SoC RV32I in VHDL

**Author:** Mateus Telles Nebias

A complete RISC-V RV32I single-cycle processor and mini-SoC implemented from scratch in synthesizable VHDL, targeting the Digilent Basys3 FPGA board.

---

## Overview

The project is a fully integrated mini-SoC built around an RV32I single-cycle core. Every module was written in pure RTL VHDL from scratch, with no third-party IP cores — the only exception is the Artix-7 MMCM primitive used for internal peripheral clock generation.

The SoC includes an APB-like internal bus, instruction and data memories, GPIO, a Timer with IRQ, a UART with clock-domain crossing, a single-channel DMA with bus takeover, and reset synchronizers for each clock domain.

---

## Architecture

```
                   +--------------------------------------------+
       clk ------->|                                            |
  (100 MHz, W5)    |  soc_top                                   |
       rst ------->|                                            |
gpio_toggle ------>|   MMCM (internal) --> periph_clk (28.8 MHz)|
   gpio_out <------|   rv32i_core                               |
    uart_tx <------|   instruction_memory                       |
                   |   bus_interconnect                         |
                   |   data_memory                              |
                   |   gpio                                     |
                   |   timer                                    |
                   |   uart  (dual-clock domain)                |
                   |   dma                                      |
                   |   reset_synchronizer x2                    |
                   +--------------------------------------------+
```

### Clock Domains

| Domain       | Frequency | Source          | Modules                                      |
|--------------|-----------|-----------------|----------------------------------------------|
| `clk`        | 100 MHz   | W5 oscillator   | rv32i_core, data_memory, gpio, timer, dma, bus |
| `periph_clk` | 28.8 MHz  | MMCM (internal) | UART TX engine                               |

`periph_clk` is generated internally by the `MMCME2_BASE` primitive (M=36, D=5, O=25, VCO=720 MHz).
The peripheral domain is held in reset until the MMCM `LOCKED` signal is asserted.
The UART uses a toggle handshake with two-FF synchronizers in each direction for safe cross-domain data transfer without a FIFO.

**UART bauddiv reference (periph_clk = 28.8 MHz):**

| Baud rate | bauddiv register |
|-----------|-----------------|
| 9600      | 2999            |
| 115200    | 249             |
| 230400    | 124             |

---

## RV32I Core

Single-cycle implementation of the base RV32I ISA. The datapath is entirely combinational between the Program Counter and the Register File. The five phases (Fetch, Decode, Execute, Memory, Writeback) are conceptual divisions of a single combinational path, not pipeline stages.

| Module                    | Function                                                                    |
|---------------------------|-----------------------------------------------------------------------------|
| `program_counter.vhd`     | PC with synchronous reset                                                   |
| `instruction_memory.vhd`  | ROM initialized from `program.mem` at elaboration                           |
| `control_unit.vhd`        | Full RV32I decoder: R/I/S/B/U/J, FENCE, ECALL, EBREAK                      |
| `alu_control.vhd`         | Translates opcode/funct3/funct7 to 4-bit ALU operation                      |
| `alu.vhd`                 | 11 operations: ADD, SUB, LUI, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND      |
| `register_file.vhd`       | 32 registers, x0 hardwired zero, combinational read                         |
| `immediate_generator.vhd` | Sign-extension for all immediate formats                                    |
| `branch_compare.vhd`      | BEQ / BNE / BLT / BGE / BLTU / BGEU                                        |
| `load_store_unit.vhd`     | Byte enables, alignment, sign/zero-extend (LB/LH/LBU/LHU/LW)              |
| `trap_unit.vhd`           | Prioritized exceptions: misaligned fetch > misaligned LS > illegal > ECALL |

---

## Peripherals and Bus

The internal bus is APB-like: `addr`, `wdata`, `wstrb`, `write`, `read`, `valid`, `rdata`, `ready`, `error`.
The `bus_interconnect` routes by address and aggregates responses.

| Module            | Base  | Registers                                                             |
|-------------------|-------|-----------------------------------------------------------------------|
| `data_memory.vhd` | 0x000 | 256-word RAM (1 KiB), byte strobes                                    |
| `gpio.vhd`        | 0x010 | GPIO_OUT (RW), GPIO_IN (RO)                                           |
| `timer.vhd`       | 0x020 | TIMER_COUNT (RO), TIMER_CMP (RW), TIMER_CTRL (RW)                    |
| `uart.vhd`        | 0x040 | UART_TXDATA (WO), UART_STATUS (RO), UART_CTRL (RW), UART_BAUDDIV (RW)|
| `dma.vhd`         | 0x080 | DMA_SRC_ADDR, DMA_DST_ADDR, DMA_LENGTH, DMA_CTRL, DMA_STATUS         |

**DMA:** Single-channel, word-based (32-bit) controller. Four-state FSM: IDLE -> READ_REQ -> WRITE_REQ -> DONE.
During a transfer the DMA asserts `active_o` and takes ownership of the bus; the CPU is stalled.
Generates a 1-cycle IRQ pulse on completion when `irq_enable = '1'`.

**UART:** TX-only, 8N1, programmable bauddiv. The TX engine runs in the `periph_clk` domain.
Bus interface and configuration registers reside in the `clk` domain.
The data byte remains stable in a staging register until the toggle handshake completes.

---

## Memory Map

```
Address       Name          Access   Notes
-----------   -----------   ------   ----------------------------------
0x0000_0000   Data RAM      RW       1 KiB, 256 words
0x0000_0010   GPIO_OUT      RW       bits [3:0] drive gpio_out
0x0000_0014   GPIO_IN       RO       bit [0] reflects gpio_toggle
0x0000_0020   TIMER_COUNT   RO       current counter value
0x0000_0024   TIMER_CMP     RW       compare value
0x0000_0028   TIMER_CTRL    RW       [0]=enable [1]=irq_en [2]=clear
0x0000_0040   UART_TXDATA   WO       byte to transmit
0x0000_0044   UART_STATUS   RO       [0]=tx_ready [1]=tx_busy
0x0000_0048   UART_CTRL     RW       [0]=enable
0x0000_004C   UART_BAUDDIV  RW       baud rate divisor
0x0000_0080   DMA_SRC_ADDR  RW       transfer source address
0x0000_0084   DMA_DST_ADDR  RW       transfer destination address
0x0000_0088   DMA_LENGTH    RW       transfer length in words
0x0000_008C   DMA_CTRL      RW       [0]=start [1]=irq_enable
0x0000_0090   DMA_STATUS    RO       [0]=busy [1]=done [2]=error
```

> MMIO addresses 0x010-0x028 fall within the RAM address window but are
> intercepted by the bus interconnect decoder before reaching data_memory.

---

## Verification

Each RTL module has a dedicated self-checking unit testbench.
The top-level testbench (`tb_soc_top.vhd`) validates the full SoC with a firmware demo:
DMA moves data in RAM, UART reports the result, GPIO signals progress via LEDs.

| Testbench                | Covers                                             |
|--------------------------|----------------------------------------------------|
| `tb_alu.vhd`             | All 11 ALU operations                              |
| `tb_alu_control.vhd`     | opcode/funct3/funct7 decode                        |
| `tb_control_unit.vhd`    | All RV32I opcodes                                  |
| `tb_load_store_unit.vhd` | LB/LH/LBU/LHU/LW/SB/SH/SW + alignment             |
| `tb_uart.vhd`            | Serial transmission + CDC handshake                |
| `tb_dma.vhd`             | RAM-to-RAM transfer, IRQ, error cases              |
| `tb_rv32i_core.vhd`      | Full firmware execution on the core                |
| `tb_soc_top.vhd`         | Full SoC integration with demo firmware            |

> Simulation requires the Vivado UNISIM libraries (for `MMCME2_BASE`).
> Use Vivado XSim: Flow Navigator -> Run Simulation -> Run Behavioral Simulation.

---

## Repository Structure

```
mini-soc-rv32i/
├── rtl/           # Synthesizable VHDL sources
├── tb/            # VHDL testbenches
├── programs/      # Compiled firmware (program.mem)
├── constraints/   # soc_top.xdc (Basys3 / Artix-7)
└── docs/          # Technical documentation
```

---

## Synthesis Target

| Parameter      | Value                  |
|----------------|------------------------|
| FPGA           | Xilinx Artix-7 XC7A35T |
| Board          | Digilent Basys3        |
| Speed grade    | -1 (cpg236)            |
| Tool           | Vivado 2025.2          |
| External clock | 100 MHz (pin W5)       |
| Internal clock | 28.8 MHz via MMCM      |

---

## Tools

- **VHDL** (VHDL-93/2002, synthesizable)
- **Vivado 2025.2** - synthesis, implementation, simulation
- **XSim** - integrated simulator (UNISIM required for MMCM primitive)
- **RISC-V GCC Toolchain** - firmware compilation

---

## Motivation

Developed as a personal project to deepen knowledge in computer architecture, RTL digital design,
and hardware/software co-design. Covers the full design cycle: microarchitecture specification,
RTL implementation, functional verification by simulation, and FPGA synthesis.

---

## License

MIT License
