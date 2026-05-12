Mini-SoC RV32I em VHDL
Desenvolvido por Mateus Telles Nébias
Implementação de um processador RISC-V RV32I single-cycle e um mini-SoC completo em VHDL sintetizável, desenvolvido do zero como projeto pessoal de arquitetura de computadores e design digital.

Visão geral
O projeto é um mini-SoC completo centrado em um núcleo RV32I single-cycle. Todos os módulos foram escritos em VHDL RTL puro a partir do zero, sem IP cores de terceiros, exceto pelo primitivo MMCM da Artix-7 usado para geração interna do clock periférico.
O SoC inclui um barramento interno APB-like, memórias de instrução e dados, GPIO, Timer com IRQ, UART com CDC entre domínios de clock, DMA single-channel com takeover de barramento, e sincronizadores de reset para cada domínio de clock.

Arquitetura
                        +---------------------------+
            clk ------->|                           |
   (100 MHz, W5)        |  soc_top                  |
            rst ------->|                           |
   gpio_toggle -------->|   MMCM (interno)          |---> periph_clk (28.8 MHz)
      gpio_out <--------|   rv32i_core              |
       uart_tx <--------|   instruction_memory      |
                        |   bus_interconnect        |
                        |   data_memory             |
                        |   gpio                    |
                        |   timer                   |
                        |   uart  (dual-clock)      |
                        |   dma                     |
                        |   reset_synchronizer x2   |
                        +---------------------------+
Domínios de clock
DomínioFrequênciaFonteMódulosclk100 MHzOscilador W5rv32i_core, data_memory, gpio, timer, dma, bus_interconnectperiph_clk28.8 MHzMMCM internoUART TX engine
O periph_clk é gerado internamente pelo primitivo MMCME2_BASE (M=36, D=5, O=25, VCO=720 MHz). O domínio periférico é mantido em reset até que o sinal LOCKED do MMCM seja asserted. A UART usa um toggle handshake para cruzar dados entre os dois domínios de forma segura, sem FIFO.
Referência de bauddiv para 28.8 MHz:
Baud ratebauddiv96002999115200249230400124

Núcleo RV32I
Implementação single-cycle do ISA RV32I base. O datapath é inteiramente combinacional entre o Program Counter e o Register File — os cinco "phases" (Fetch, Decode, Execute, Memory, Writeback) são divisões conceituais de um único caminho combinacional, não estágios de pipeline.
MóduloFunçãoprogram_counter.vhdPC com reset síncronoinstruction_memory.vhdROM inicializada via program.memcontrol_unit.vhdDecodificador completo: R/I/S/B/U/J, FENCE, ECALL, EBREAKalu_control.vhdTraduz opcode/funct3/funct7 para operação ALU de 4 bitsalu.vhd11 operações: ADD, SUB, LUI, SLL, SLT, SLTU, XOR, SRL, SRA, OR, ANDregister_file.vhd32 registradores, x0 hardwired zero, leitura combinacionalimmediate_generator.vhdSign-extension para todos os formatos de imediatobranch_compare.vhdBEQ/BNE/BLT/BGE/BLTU/BGEUload_store_unit.vhdByte enables, alinhamento, sign/zero-extend (LB/LH/LBU/LHU/LW)trap_unit.vhdExceções com prioridade: misaligned fetch > misaligned LS > illegal > ECALL > EBREAK

Periféricos e barramento
O barramento interno é APB-like com sinais addr, wdata, wstrb, write, read, valid, rdata, ready, error. O bus_interconnect roteia por endereço e agrega as respostas.
MóduloBaseRegistradoresdata_memory.vhd0x000RAM de 256 words (1 KiB), byte strobesgpio.vhd0x010GPIO_OUT (RW), GPIO_IN (RO)timer.vhd0x020TIMER_COUNT (RO), TIMER_CMP (RW), TIMER_CTRL (RW)uart.vhd0x040UART_TXDATA (WO), UART_STATUS (RO), UART_CTRL (RW), UART_BAUDDIV (RW)dma.vhd0x080DMA_SRC_ADDR, DMA_DST_ADDR, DMA_LENGTH, DMA_CTRL, DMA_STATUS
DMA
Controlador single-channel word-based (32 bits). FSM com 4 estados: IDLE → READ_REQ → WRITE_REQ → DONE. Durante a transferência, o DMA toma posse do barramento via sinal active_o; a CPU fica suspensa. Gera IRQ ao término se irq_enable = '1'.
UART
TX-only, formato 8N1, bauddiv programável. Opera no domínio periph_clk (28.8 MHz). A interface de barramento e os registradores de configuração residem no domínio clk. O cruzamento de domínio é feito por toggle handshake com sincronizadores de 2 flip-flops em cada direção.

Mapa de memória
0x0000_0000 - 0x0000_03FF   Data RAM
0x0000_0010                 GPIO_OUT        RW
0x0000_0014                 GPIO_IN         RO
0x0000_0020                 TIMER_COUNT     RO
0x0000_0024                 TIMER_CMP       RW
0x0000_0028                 TIMER_CTRL      RW
0x0000_0040                 UART_TXDATA     WO
0x0000_0044                 UART_STATUS     RO
0x0000_0048                 UART_CTRL       RW
0x0000_004C                 UART_BAUDDIV    RW
0x0000_0080                 DMA_SRC_ADDR    RW
0x0000_0084                 DMA_DST_ADDR    RW
0x0000_0088                 DMA_LENGTH      RW
0x0000_008C                 DMA_CTRL        RW
0x0000_0090                 DMA_STATUS      RO
O interconnect tem prioridade sobre a RAM para endereços de MMIO — os endereços 0x10, 0x14, 0x20, 0x24, 0x28 estão dentro da janela de RAM fisicamente, mas são interceptados antes de chegar à data_memory.

Verificação
Cada módulo RTL tem um testbench unitário dedicado. O testbench de topo (tb_soc_top.vhd) é self-checking e valida o firmware de demonstração end-to-end: DMA move dados na RAM, UART reporta o resultado, GPIO sinaliza progresso via LEDs.
TestbenchCobretb_alu.vhdTodas as 11 operações da ALUtb_control_unit.vhdTodos os opcodes RV32Itb_load_store_unit.vhdLB/LH/LBU/LHU/LW/SB/SH/SW + alinhamentotb_uart.vhdTransmissão serial + CDC handshaketb_dma.vhdTransferência RAM→RAM, IRQ, casos de errotb_rv32i_core.vhdExecução de firmware completo no núcleotb_soc_top.vhdIntegração SoC completa com firmware de demo
A simulação usa as bibliotecas UNISIM do Vivado para instanciar corretamente o MMCME2_BASE. Rodar via Vivado XSim (Flow Navigator → Run Simulation → Run Behavioral Simulation).

Estrutura do repositório
mini-soc-rv32i/
├── rtl/           # Fontes VHDL sintetizáveis
├── tb/            # Testbenches VHDL
├── programs/      # Firmware compilado (program.mem)
├── constraints/   # soc_top.xdc (Artix-7 / Basys3)
└── docs/          # Documentacao tecnica

Alvo de síntese
ParâmetroValorFPGAXilinx Artix-7 XC7A35TBoardDigilent Basys3Speed grade-1 (cpg236)FerramentaVivado 2025.2Clock externo100 MHz (pino W5)Clock interno28.8 MHz via MMCM

Ferramentas

VHDL (VHDL-93/2002, sintetizavel)
Vivado 2025.2 — sintese, implementacao e simulacao
XSim — simulador integrado (UNISIM necessario para MMCM)
RISC-V GCC Toolchain — compilacao de firmware


Motivacao
Projeto desenvolvido como iniciativa pessoal para aprofundar conhecimento em arquitetura de computadores, design digital RTL e co-design hardware/software. Cobre o ciclo completo: especificacao de microarquitetura, implementacao RTL, verificacao funcional por simulacao e sintese para FPGA.

Licenca
MIT License
