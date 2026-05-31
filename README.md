# Mini-SoC RV32I in VHDL

**Author:** Mateus Telles Nebias

![CI](https://github.com/engmateusnebias-ship-it/risc-v-cpu/actions/workflows/ci.yml/badge.svg)

A complete RISC-V RV32I single-cycle processor and mini-SoC implemented from scratch in synthesizable VHDL, verified on the Digilent Basys3 FPGA board.

---

## Overview

The project is a fully integrated mini-SoC built around an RV32I single-cycle core. Every module was written in pure RTL VHDL from scratch, with no third-party IP cores — the only exception is the Artix-7 MMCM primitive used for internal peripheral clock generation.

The SoC includes an APB-like internal bus, instruction and data memories, GPIO, a Timer with IRQ, a UART with clock-domain crossing, a single-channel DMA with bus takeover, and reset synchronizers for each clock domain.

---

## Architecture

```
                   +----------------------------------------------+
       clk ------->|                                              |
  (100 MHz, W5)    |  soc_top                                     |
       rst ------->|   MMCM ---> core_clk   (48.0 MHz)            |
gpio_toggle ------>|        \--> periph_clk (28.8 MHz)            |
   gpio_out <------|   rv32i_core                                 |
    uart_tx <------|   instruction_memory                         |
                   |   bus_interconnect                           |
                   |   data_memory                                |
                   |   gpio                                       |
                   |   timer                                      |
                   |   uart  (dual-clock domain)                  |
                   |   dma                                        |
                   |   reset_synchronizer x2                      |
                   +----------------------------------------------+
```

### Clock Domains

A single MMCM (VCO = 720 MHz) derives both working clocks from the 100 MHz
input. The core runs at 48 MHz, **not** at 100 MHz: the single-cycle datapath
has a ~19 ns combinational critical path (fmax ~52 MHz on this Artix-7 -1
part), so 100 MHz cannot close timing. 48 MHz is the highest core frequency
obtainable from the same VCO that also yields the exact 28.8 MHz peripheral
clock, so one MMCM cleanly serves both synchronous domains.

| Domain       | Frequency | Source            | Modules                                        |
|--------------|-----------|-------------------|------------------------------------------------|
| `clk`        | 100 MHz   | W5 oscillator     | MMCM input only                                |
| `core_clk`   | 48.0 MHz  | MMCM CLKOUT0      | rv32i_core, data_memory, gpio, timer, dma, bus |
| `periph_clk` | 28.8 MHz  | MMCM CLKOUT1      | UART TX engine                                 |

Both derived clocks come from the `MMCME2_BASE` primitive
(CLKFBOUT_MULT_F=36, DIVCLK_DIVIDE=5 -> VCO=720 MHz; CLKOUT0_DIVIDE_F=15.0
-> 48 MHz; CLKOUT1_DIVIDE=25 -> 28.8 MHz). Both domains are held in reset
until the MMCM `LOCKED` signal asserts. The UART crosses between `core_clk`
and `periph_clk` using a toggle handshake with two-FF synchronizers (marked
`ASYNC_REG`) in each direction — no FIFO.

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

RAM and peripherals occupy fully separated, non-overlapping regions: RAM is
0x000-0x3FF (all 256 words usable), peripherals start at 0x400.

| Module            | Base  | Registers                                                             |
|-------------------|-------|-----------------------------------------------------------------------|
| `data_memory.vhd` | 0x000 | 256-word RAM (1 KiB), byte strobes                                    |
| `gpio.vhd`        | 0x400 | GPIO_OUT (RW), GPIO_IN (RO)                                           |
| `timer.vhd`       | 0x410 | TIMER_COUNT (RO), TIMER_CMP (RW), TIMER_CTRL (RW)                    |
| `uart.vhd`        | 0x420 | UART_TXDATA (WO), UART_STATUS (RO), UART_CTRL (RW), UART_BAUDDIV (RW)|
| `dma.vhd`         | 0x430 | DMA_SRC_ADDR, DMA_DST_ADDR, DMA_LENGTH, DMA_CTRL, DMA_STATUS         |

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
0x0000_0000   Data RAM      RW       1 KiB, 256 words (fully usable)
0x0000_0400   GPIO_OUT      RW       bits [3:0] drive gpio_out
0x0000_0404   GPIO_IN       RO       bit [0] reflects gpio_toggle
0x0000_0410   TIMER_COUNT   RO       current counter value
0x0000_0414   TIMER_CMP     RW       compare value
0x0000_0418   TIMER_CTRL    RW       [0]=enable [1]=irq_en [2]=clear
0x0000_0420   UART_TXDATA   WO       byte to transmit
0x0000_0424   UART_STATUS   RO       [0]=tx_ready [1]=tx_busy
0x0000_0428   UART_CTRL     RW       [0]=enable
0x0000_042C   UART_BAUDDIV  RW       baud rate divisor
0x0000_0430   DMA_SRC_ADDR  RW       transfer source address
0x0000_0434   DMA_DST_ADDR  RW       transfer destination address
0x0000_0438   DMA_LENGTH    RW       transfer length in words
0x0000_043C   DMA_CTRL      RW       [0]=start [1]=irq_enable
0x0000_0440   DMA_STATUS    RO       [0]=busy [1]=done [2]=error
```

> RAM (0x000-0x3FF) and peripherals (0x400+) occupy non-overlapping
> regions, so all 256 RAM words are usable with no shadowed addresses.

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

### Continuous Integration

Unit testbenches run automatically on every push via GitHub Actions using the
open-source GHDL simulator. Each self-checking bench fails the build (non-zero
exit) if any assertion fires, so regressions are caught immediately. The
top-level `tb_soc_top` is excluded from CI because it instantiates the Xilinx
MMCM primitive, which GHDL does not model natively; it is verified in Vivado
XSim instead.

---

## Implementation Results

The design was synthesised, placed, routed, and run on hardware.

| Metric              | Value                                   |
|---------------------|-----------------------------------------|
| Timing (WNS)        | +0.543 ns (all constraints met)         |
| Core clock          | 48.0 MHz                                |
| Peripheral clock    | 28.8 MHz                                |
| LUTs                | ~2000                                   |
| Flip-flops          | ~500                                    |
| BRAM                | 0                                       |
| On-chip power       | ~0.18 W                                 |
| Status              | Verified on Basys3 hardware             |

The demo firmware: on a button press (BTNL), the CPU programs the DMA to copy
a data block in RAM, the UART reports completion, and the GPIO drives the LEDs
through a progress sequence ending at 0xA on success — confirmed on the board.

---

## Repository Structure

```
mini-soc-rv32i/
├── rtl/             # Synthesizable VHDL sources
├── tb/              # VHDL testbenches
├── programs/        # Firmware image (program.mem)
├── constraints/     # soc_top.xdc (Basys3 / Artix-7)
├── docs/            # Technical documentation
├── .github/         # CI workflow (GHDL)
└── Makefile         # GHDL build/test runner
```

---

## Synthesis Target

| Parameter      | Value                            |
|----------------|----------------------------------|
| FPGA           | Xilinx Artix-7 XC7A35T           |
| Board          | Digilent Basys3                  |
| Speed grade    | -1 (cpg236)                      |
| Tool           | Vivado 2025.2                    |
| External clock | 100 MHz (pin W5)                 |
| Core clock     | 48.0 MHz (MMCM CLKOUT0)          |
| Peripheral clk | 28.8 MHz (MMCM CLKOUT1)          |

The program image path is passed to synthesis via the `INIT_FILE` top-level
generic (default `program.mem` for GHDL/CI; absolute path set in Vivado
Settings -> General -> Generics/Parameters).

---

## Tools

- **VHDL** (VHDL-2008, synthesizable)
- **Vivado 2025.2** - synthesis, implementation, simulation
- **XSim** - Vivado simulator (UNISIM required for MMCM primitive)
- **GHDL** - open-source simulator used in CI
- **RISC-V GCC Toolchain** - firmware compilation (planned migration from hand-assembled)

---

## Motivation

Developed as a personal project to deepen knowledge in computer architecture, RTL digital design,
and hardware/software co-design. Covers the full design cycle: microarchitecture specification,
RTL implementation, functional verification by simulation, and FPGA synthesis.

---

## License

MIT License
