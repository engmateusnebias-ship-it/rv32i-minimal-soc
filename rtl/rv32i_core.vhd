library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- RV32I single-cycle core.
-- This module contains only the architectural CPU core:
--  - PC / fetch interface
--  - decode / control
--  - register file
--  - execute / branch logic
--  - load/store generation
--  - trap detection
--
-- The core does not instantiate instruction memory, data memory, interconnect,
-- or peripherals. Those belong to the SoC top level.
entity rv32i_core is
    Port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Instruction fetch interface
        instr_addr  : out std_logic_vector(31 downto 0);
        instr_rdata : in  std_logic_vector(31 downto 0);

        -- System bus master interface (APB-like simplified)
        bus_addr    : out std_logic_vector(31 downto 0);
        bus_wdata   : out std_logic_vector(31 downto 0);
        bus_wstrb   : out std_logic_vector(3 downto 0);
        bus_write   : out std_logic;
        bus_read    : out std_logic;
        bus_valid   : out std_logic;
        bus_rdata   : in  std_logic_vector(31 downto 0);
        bus_ready   : in  std_logic;
        bus_error   : in  std_logic;

        -- Reserved external interrupt input for future SoC integration
        irq_in      : in  std_logic
    );
end rv32i_core;

architecture rtl of rv32i_core is

    -- JALR requires clearing bit 0 of the computed target address.
    -- Use a numeric_std constant to avoid ambiguous type conversions in VHDL-93/2002.
    constant JALR_ALIGN_MASK : unsigned(31 downto 0) := unsigned'(x"FFFFFFFE");

    -- PC / Instruction
    signal pc, next_pc, pc_plus4 : std_logic_vector(31 downto 0);
    signal instruction           : std_logic_vector(31 downto 0);

    -- Decode fields
    signal opcode : std_logic_vector(6 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);
    signal rs1_addr, rs2_addr, rd_addr : std_logic_vector(4 downto 0);

    -- Control
    signal reg_write      : std_logic;
    signal alu_src_a_pc   : std_logic;
    signal alu_src_b_imm  : std_logic;
    signal alu_op_ctrl    : std_logic_vector(1 downto 0);
    signal is_branch      : std_logic;
    signal is_jal         : std_logic;
    signal is_jalr        : std_logic;
    signal wb_sel         : std_logic_vector(1 downto 0);
    signal mem_re, mem_we : std_logic;
    signal mem_size       : std_logic_vector(1 downto 0);
    signal mem_unsigned   : std_logic;
    signal fence_nop      : std_logic;
    signal ecall, ebreak  : std_logic;
    signal illegal_insn   : std_logic;

    -- Register file
    signal rs1_data, rs2_data : std_logic_vector(31 downto 0);
    signal wb_data            : std_logic_vector(31 downto 0);

    -- Immediate
    signal imm : std_logic_vector(31 downto 0);

    -- ALU
    signal alu_a, alu_b     : std_logic_vector(31 downto 0);
    signal alu_result       : std_logic_vector(31 downto 0);
    signal alu_zero         : std_logic;
    signal alu_ctrl_sig     : std_logic_vector(3 downto 0);

    -- Branch compare
    signal branch_taken : std_logic;

    -- LSU
    signal lsu_wdata     : std_logic_vector(31 downto 0);
    signal lsu_wstrb     : std_logic_vector(3 downto 0);
    signal load_result   : std_logic_vector(31 downto 0);
    signal ls_misaligned : std_logic;

    -- Trap
    signal misaligned_fetch : std_logic;
    signal trap_taken       : std_logic;
    signal trap_target      : std_logic_vector(31 downto 0);
    signal trap_cause       : std_logic_vector(3 downto 0);

    -- Next PC candidates
    signal pc_branch_target : std_logic_vector(31 downto 0);
    signal pc_jal_target    : std_logic_vector(31 downto 0);
    signal pc_jalr_target   : std_logic_vector(31 downto 0);

    -- Gated side effects
    signal reg_write_g      : std_logic;
    signal mem_re_g         : std_logic;
    signal mem_we_g         : std_logic;

begin
    -- The current core does not yet consume external interrupts.
    -- Keep the reserved input connected at the boundary for future integration.
    unused_irq: process(irq_in)
    begin
        null;
    end process;

    -- The current system bus is still single-cycle / always-ready.
    -- Keep these inputs in the interface so the protocol can evolve later
    -- without changing the core boundary again.
    unused_bus_ctrl: process(bus_ready, bus_error)
    begin
        null;
    end process;

    instruction <= instr_rdata;
    instr_addr  <= pc;

    -- Decode fields
    opcode   <= instruction(6 downto 0);
    funct3   <= instruction(14 downto 12);
    funct7   <= instruction(31 downto 25);
    rs1_addr <= instruction(19 downto 15);
    rs2_addr <= instruction(24 downto 20);
    rd_addr  <= instruction(11 downto 7);

    -- PC register
    pc_reg: entity work.program_counter
        port map (
            clk     => clk,
            rst     => rst,
            enable  => '1',
            next_pc => next_pc,
            pc      => pc
        );

    pc_plus4 <= std_logic_vector(unsigned(pc) + 4);

    -- Control unit
    ctrl: entity work.control_unit
        port map (
            instr         => instruction,
            reg_write     => reg_write,
            alu_src_a_pc  => alu_src_a_pc,
            alu_src_b_imm => alu_src_b_imm,
            alu_op_ctrl   => alu_op_ctrl,
            is_branch     => is_branch,
            is_jal        => is_jal,
            is_jalr       => is_jalr,
            wb_sel        => wb_sel,
            mem_re        => mem_re,
            mem_we        => mem_we,
            mem_size      => mem_size,
            mem_unsigned  => mem_unsigned,
            fence_nop     => fence_nop,
            ecall         => ecall,
            ebreak        => ebreak,
            illegal_insn  => illegal_insn
        );

    -- Register file
    reg_file: entity work.register_file
        port map (
            clk          => clk,
            we           => reg_write_g,
            rs1_addr     => rs1_addr,
            rs2_addr     => rs2_addr,
            rd_addr      => rd_addr,
            rd_data_in   => wb_data,
            rs1_data_out => rs1_data,
            rs2_data_out => rs2_data
        );

    -- Immediate generator
    imm_gen: entity work.immediate_generator
        port map (
            instr   => instruction,
            imm_out => imm
        );

    -- ALU control
    alu_ctrl: entity work.alu_control
        port map (
            opcode             => opcode,
            alu_op_ctrl        => alu_op_ctrl,
            funct3             => funct3,
            funct7             => funct7,
            alu_control_signal => alu_ctrl_sig
        );

    -- ALU operand muxes
    alu_a <= pc when alu_src_a_pc = '1' else rs1_data;
    alu_b <= imm when alu_src_b_imm = '1' else rs2_data;

    -- ALU
    alu_inst: entity work.alu
        port map (
            A      => alu_a,
            B      => alu_b,
            alu_op => alu_ctrl_sig,
            result => alu_result,
            zero   => alu_zero
        );

    -- Branch comparator
    brcmp: entity work.branch_compare
        port map (
            funct3       => funct3,
            rs1          => rs1_data,
            rs2          => rs2_data,
            branch_taken => branch_taken
        );

    -- LSU
    lsu: entity work.load_store_unit
        port map (
            addr           => alu_result,
            funct3         => funct3,
            is_load        => mem_re,
            is_store       => mem_we,
            rs2_store_data => rs2_data,
            mem_rdata_raw  => bus_rdata,
            mem_wdata      => lsu_wdata,
            mem_wstrb      => lsu_wstrb,
            load_result    => load_result,
            misaligned     => ls_misaligned
        );

    -- Trap detection
    misaligned_fetch <= '1' when pc(1 downto 0) /= "00" else '0';

    traps: entity work.trap_unit
        port map (
            pc               => pc,
            illegal_insn     => illegal_insn,
            ecall            => ecall,
            ebreak           => ebreak,
            misaligned_ls    => ls_misaligned,
            misaligned_fetch => misaligned_fetch,
            trap_taken       => trap_taken,
            trap_target      => trap_target,
            trap_cause       => trap_cause
        );

    -- Gate side effects on traps
    reg_write_g <= reg_write and (not trap_taken);
    mem_re_g    <= mem_re and (not trap_taken) and (not ls_misaligned);
    mem_we_g    <= mem_we and (not trap_taken) and (not ls_misaligned);

    -- System bus master interface
    bus_addr  <= alu_result;
    bus_wdata <= lsu_wdata;
    bus_wstrb <= lsu_wstrb when mem_we_g = '1' else "0000";
    bus_write <= mem_we_g;
    bus_read  <= mem_re_g;
    bus_valid <= mem_re_g or mem_we_g;

    -- Writeback mux
    -- VHDL-93/VHDL-2002 compatible combinational process (no process(all)).
    process(wb_sel, alu_result, load_result, pc_plus4)
    begin
        case wb_sel is
            when "00" => wb_data <= alu_result;
            when "01" => wb_data <= load_result;
            when "10" => wb_data <= pc_plus4;
            when others => wb_data <= alu_result;
        end case;
    end process;

    -- Next PC targets
    pc_branch_target <= std_logic_vector(unsigned(pc) + unsigned(imm));
    pc_jal_target    <= std_logic_vector(unsigned(pc) + unsigned(imm));

    -- JALR target: (rs1 + imm) & ~1
    pc_jalr_target <= std_logic_vector((unsigned(rs1_data) + unsigned(imm)) and JALR_ALIGN_MASK);

    -- Next PC selection (priority: trap -> jalr -> jal -> branch -> pc+4)
    -- VHDL-93/VHDL-2002 compatible combinational process (no process(all)).
    process(pc_plus4, trap_taken, trap_target, is_jalr, pc_jalr_target, is_jal, pc_jal_target, is_branch, branch_taken, pc_branch_target)
    begin
        next_pc <= pc_plus4;

        if trap_taken = '1' then
            next_pc <= trap_target;
        elsif is_jalr = '1' then
            next_pc <= pc_jalr_target;
        elsif is_jal = '1' then
            next_pc <= pc_jal_target;
        elsif is_branch = '1' and branch_taken = '1' then
            next_pc <= pc_branch_target;
        else
            next_pc <= pc_plus4;
        end if;
    end process;

end rtl;
