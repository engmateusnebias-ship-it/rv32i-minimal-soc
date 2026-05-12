library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
 
-- Xilinx primitives (MMCME2_BASE, BUFG)
library UNISIM;
use UNISIM.VComponents.all;
 
entity soc_top is
    Port (
        clk         : in  std_logic;   -- 100 MHz onboard oscillator (W5)
        rst         : in  std_logic;   -- active-high, async (BTNC)
        gpio_toggle : in  std_logic;
        gpio_out    : out std_logic_vector(3 downto 0);
        uart_tx     : out std_logic
    );
end soc_top;
 
architecture rtl of soc_top is
 
    ---------------------------------------------------------------------------
    -- Clock signals
    ---------------------------------------------------------------------------
    signal periph_clk_mmcm : std_logic;  -- raw output from MMCM
    signal periph_clk       : std_logic;  -- after BUFG
    signal mmcm_locked      : std_logic;
 
    ---------------------------------------------------------------------------
    -- Resets
    ---------------------------------------------------------------------------
    signal rst_core   : std_logic;
    signal rst_periph : std_logic;
 
    -- Periph reset is the union of the external request and MMCM not yet locked
    signal rst_periph_req : std_logic;
 
    ---------------------------------------------------------------------------
    -- Instruction bus
    ---------------------------------------------------------------------------
    signal instr_addr  : std_logic_vector(31 downto 0);
    signal instr_rdata : std_logic_vector(31 downto 0);
 
    ---------------------------------------------------------------------------
    -- CPU master bus
    ---------------------------------------------------------------------------
    signal cpu_bus_addr   : std_logic_vector(31 downto 0);
    signal cpu_bus_wdata  : std_logic_vector(31 downto 0);
    signal cpu_bus_wstrb  : std_logic_vector(3 downto 0);
    signal cpu_bus_write  : std_logic;
    signal cpu_bus_read   : std_logic;
    signal cpu_bus_valid  : std_logic;
    signal cpu_bus_rdata  : std_logic_vector(31 downto 0);
    signal cpu_bus_ready  : std_logic;
    signal cpu_bus_error  : std_logic;
 
    ---------------------------------------------------------------------------
    -- DMA master bus
    ---------------------------------------------------------------------------
    signal dma_m_addr     : std_logic_vector(31 downto 0);
    signal dma_m_wdata    : std_logic_vector(31 downto 0);
    signal dma_m_wstrb    : std_logic_vector(3 downto 0);
    signal dma_m_write    : std_logic;
    signal dma_m_read     : std_logic;
    signal dma_m_valid    : std_logic;
    signal dma_m_rdata    : std_logic_vector(31 downto 0);
    signal dma_m_ready    : std_logic;
    signal dma_m_error    : std_logic;
    signal dma_active     : std_logic;
 
    ---------------------------------------------------------------------------
    -- Arbitrated bus (after CPU/DMA mux)
    ---------------------------------------------------------------------------
    signal bus_addr       : std_logic_vector(31 downto 0);
    signal bus_wdata      : std_logic_vector(31 downto 0);
    signal bus_wstrb      : std_logic_vector(3 downto 0);
    signal bus_write      : std_logic;
    signal bus_read       : std_logic;
    signal bus_valid      : std_logic;
 
    -- Shared fabric response
    signal fabric_rdata   : std_logic_vector(31 downto 0);
    signal fabric_ready   : std_logic;
    signal fabric_error   : std_logic;
 
    ---------------------------------------------------------------------------
    -- Peripheral selects
    ---------------------------------------------------------------------------
    signal ram_sel        : std_logic;
    signal gpio_sel       : std_logic;
    signal timer_sel      : std_logic;
    signal uart_sel       : std_logic;
    signal dma_sel        : std_logic;
 
    signal ram_addr       : std_logic_vector(31 downto 0);
    signal gpio_addr      : std_logic_vector(31 downto 0);
    signal timer_addr     : std_logic_vector(31 downto 0);
    signal uart_addr      : std_logic_vector(31 downto 0);
    signal dma_addr       : std_logic_vector(31 downto 0);
 
    signal ram_wdata      : std_logic_vector(31 downto 0);
    signal gpio_wdata     : std_logic_vector(31 downto 0);
    signal timer_wdata    : std_logic_vector(31 downto 0);
    signal uart_wdata     : std_logic_vector(31 downto 0);
    signal dma_wdata      : std_logic_vector(31 downto 0);
 
    signal ram_wstrb      : std_logic_vector(3 downto 0);
    signal gpio_wstrb     : std_logic_vector(3 downto 0);
    signal timer_wstrb    : std_logic_vector(3 downto 0);
    signal uart_wstrb     : std_logic_vector(3 downto 0);
    signal dma_wstrb      : std_logic_vector(3 downto 0);
 
    signal ram_write      : std_logic;
    signal gpio_write     : std_logic;
    signal timer_write    : std_logic;
    signal uart_write     : std_logic;
    signal dma_write_s    : std_logic;
 
    signal ram_read       : std_logic;
    signal gpio_read      : std_logic;
    signal timer_read     : std_logic;
    signal uart_read      : std_logic;
    signal dma_read_s     : std_logic;
 
    signal ram_valid      : std_logic;
    signal gpio_valid     : std_logic;
    signal timer_valid    : std_logic;
    signal uart_valid     : std_logic;
    signal dma_valid_s    : std_logic;
 
    signal ram_rdata      : std_logic_vector(31 downto 0);
    signal gpio_rdata     : std_logic_vector(31 downto 0);
    signal timer_rdata    : std_logic_vector(31 downto 0);
    signal uart_rdata     : std_logic_vector(31 downto 0);
    signal dma_rdata      : std_logic_vector(31 downto 0);
 
    signal ram_ready      : std_logic;
    signal gpio_ready     : std_logic;
    signal timer_ready    : std_logic;
    signal uart_ready     : std_logic;
    signal dma_ready_s    : std_logic;
 
    signal ram_error      : std_logic;
    signal gpio_error     : std_logic;
    signal timer_error    : std_logic;
    signal uart_error     : std_logic;
    signal dma_error_s    : std_logic;
 
    signal timer_irq      : std_logic;
    signal dma_irq        : std_logic;
    signal irq_combined   : std_logic;
 
begin
 
    ---------------------------------------------------------------------------
    -- MMCM: generates periph_clk = 28.8 MHz from clk = 100 MHz
    --
    --   VCO  = 100 MHz * CLKFBOUT_MULT_F / DIVCLK_DIVIDE
    --        = 100 * 36 / 5 = 720 MHz  (within 600-1200 MHz for Artix-7)
    --   CLKOUT0 = VCO / CLKOUT0_DIVIDE_F = 720 / 25 = 28.8 MHz
    --
    -- UART bauddiv reference values:
    --     9600 bps  ->  bauddiv = 2999
    --   115200 bps  ->  bauddiv =  249
    --   230400 bps  ->  bauddiv =  124
    ---------------------------------------------------------------------------
    mmcm_inst : MMCME2_BASE
        generic map (
            CLKIN1_PERIOD      => 10.0,    -- 100 MHz input
            CLKFBOUT_MULT_F    => 36.0,    -- VCO multiply
            DIVCLK_DIVIDE      => 5,       -- VCO pre-divider
            CLKOUT0_DIVIDE_F   => 25.0,    -- periph_clk divider
            CLKOUT0_DUTY_CYCLE => 0.5,
            CLKOUT0_PHASE      => 0.0,
            BANDWIDTH          => "OPTIMIZED",
            CLKFBOUT_PHASE     => 0.0,
            REF_JITTER1        => 0.01,
            STARTUP_WAIT       => FALSE
        )
        port map (
            CLKIN1   => clk,
            CLKFBIN  => periph_clk,        -- feedback loop closed through BUFG
            CLKOUT0  => periph_clk_mmcm,
            CLKFBOUT => open,              -- feedback not used (self-contained)
            LOCKED   => mmcm_locked,
            PWRDWN   => '0',
            RST      => '0'
        );
 
    -- Route MMCM output through a global clock buffer
    bufg_periph : BUFG
        port map (
            I => periph_clk_mmcm,
            O => periph_clk
        );
 
    ---------------------------------------------------------------------------
    -- Resets
    --
    -- rst_core   : synchronised to clk (100 MHz domain)
    -- rst_periph : synchronised to periph_clk (28.8 MHz domain)
    --              held asserted until MMCM is locked
    ---------------------------------------------------------------------------
    rst_core_sync_i : entity work.reset_synchronizer
        port map (
            clk     => clk,
            rst_in  => rst,
            rst_out => rst_core
        );
 
    -- Keep periph domain in reset while MMCM is not yet locked
    rst_periph_req <= rst or (not mmcm_locked);
 
    rst_periph_sync_i : entity work.reset_synchronizer
        port map (
            clk     => periph_clk,
            rst_in  => rst_periph_req,
            rst_out => rst_periph
        );
 
    ---------------------------------------------------------------------------
    -- Bus arbitration: DMA takes priority over CPU
    ---------------------------------------------------------------------------
    bus_addr  <= dma_m_addr  when dma_active = '1' else cpu_bus_addr;
    bus_wdata <= dma_m_wdata when dma_active = '1' else cpu_bus_wdata;
    bus_wstrb <= dma_m_wstrb when dma_active = '1' else cpu_bus_wstrb;
    bus_write <= dma_m_write when dma_active = '1' else cpu_bus_write;
    bus_read  <= dma_m_read  when dma_active = '1' else cpu_bus_read;
    bus_valid <= dma_m_valid when dma_active = '1' else cpu_bus_valid;
 
    -- CPU must not observe fabric responses while DMA owns the bus
    cpu_bus_rdata <= fabric_rdata when dma_active = '0' else (others => '0');
    cpu_bus_ready <= fabric_ready when dma_active = '0' else '0';
    cpu_bus_error <= fabric_error when dma_active = '0' else '0';
 
    -- DMA always sees the real fabric response
    dma_m_rdata <= fabric_rdata;
    dma_m_ready <= fabric_ready;
    dma_m_error <= fabric_error;
 
    irq_combined <= timer_irq or dma_irq;
 
    ---------------------------------------------------------------------------
    -- Component instantiations
    ---------------------------------------------------------------------------
    core_i : entity work.rv32i_core
        port map (
            clk         => clk,
            rst         => rst_core,
            instr_addr  => instr_addr,
            instr_rdata => instr_rdata,
            bus_addr    => cpu_bus_addr,
            bus_wdata   => cpu_bus_wdata,
            bus_wstrb   => cpu_bus_wstrb,
            bus_write   => cpu_bus_write,
            bus_read    => cpu_bus_read,
            bus_valid   => cpu_bus_valid,
            bus_rdata   => cpu_bus_rdata,
            bus_ready   => cpu_bus_ready,
            bus_error   => cpu_bus_error,
            irq_in      => irq_combined
        );
 
    instr_mem_i : entity work.instruction_memory
        port map (
            addr        => instr_addr,
            instruction => instr_rdata
        );
 
    bus_i : entity work.bus_interconnect
        port map (
            m_addr      => bus_addr,
            m_wdata     => bus_wdata,
            m_wstrb     => bus_wstrb,
            m_write     => bus_write,
            m_read      => bus_read,
            m_valid     => bus_valid,
            m_rdata     => fabric_rdata,
            m_ready     => fabric_ready,
            m_error     => fabric_error,
 
            ram_sel     => ram_sel,
            ram_addr    => ram_addr,
            ram_wdata   => ram_wdata,
            ram_wstrb   => ram_wstrb,
            ram_write   => ram_write,
            ram_read    => ram_read,
            ram_valid   => ram_valid,
            ram_rdata   => ram_rdata,
            ram_ready   => ram_ready,
            ram_error   => ram_error,
 
            gpio_sel    => gpio_sel,
            gpio_addr   => gpio_addr,
            gpio_wdata  => gpio_wdata,
            gpio_wstrb  => gpio_wstrb,
            gpio_write  => gpio_write,
            gpio_read   => gpio_read,
            gpio_valid  => gpio_valid,
            gpio_rdata  => gpio_rdata,
            gpio_ready  => gpio_ready,
            gpio_error  => gpio_error,
 
            timer_sel   => timer_sel,
            timer_addr  => timer_addr,
            timer_wdata => timer_wdata,
            timer_wstrb => timer_wstrb,
            timer_write => timer_write,
            timer_read  => timer_read,
            timer_valid => timer_valid,
            timer_rdata => timer_rdata,
            timer_ready => timer_ready,
            timer_error => timer_error,
 
            uart_sel    => uart_sel,
            uart_addr   => uart_addr,
            uart_wdata  => uart_wdata,
            uart_wstrb  => uart_wstrb,
            uart_write  => uart_write,
            uart_read   => uart_read,
            uart_valid  => uart_valid,
            uart_rdata  => uart_rdata,
            uart_ready  => uart_ready,
            uart_error  => uart_error,
 
            dma_sel     => dma_sel,
            dma_addr    => dma_addr,
            dma_wdata   => dma_wdata,
            dma_wstrb   => dma_wstrb,
            dma_write   => dma_write_s,
            dma_read    => dma_read_s,
            dma_valid   => dma_valid_s,
            dma_rdata   => dma_rdata,
            dma_ready   => dma_ready_s,
            dma_error   => dma_error_s
        );
 
    ram_i : entity work.data_memory
        port map (
            clk      => clk,
            rst      => rst_core,
            sel      => ram_sel,
            addr     => ram_addr,
            wdata    => ram_wdata,
            wstrb    => ram_wstrb,
            write_en => ram_write,
            read_en  => ram_read,
            valid    => ram_valid,
            rdata    => ram_rdata,
            ready    => ram_ready,
            error    => ram_error
        );
 
    gpio_i : entity work.gpio
        port map (
            clk         => clk,
            rst         => rst_core,
            sel         => gpio_sel,
            addr        => gpio_addr,
            wdata       => gpio_wdata,
            wstrb       => gpio_wstrb,
            write_en    => gpio_write,
            read_en     => gpio_read,
            valid       => gpio_valid,
            rdata       => gpio_rdata,
            ready       => gpio_ready,
            error       => gpio_error,
            gpio_out    => gpio_out,
            gpio_toggle => gpio_toggle
        );
 
    timer_i : entity work.timer
        port map (
            clk      => clk,
            rst      => rst_core,
            sel      => timer_sel,
            addr     => timer_addr,
            wdata    => timer_wdata,
            wstrb    => timer_wstrb,
            write_en => timer_write,
            read_en  => timer_read,
            valid    => timer_valid,
            rdata    => timer_rdata,
            ready    => timer_ready,
            error    => timer_error,
            irq      => timer_irq
        );
 
    uart_i : entity work.uart
        port map (
            core_clk   => clk,
            core_rst   => rst_core,
            periph_clk => periph_clk,
            periph_rst => rst_periph,
            sel        => uart_sel,
            addr       => uart_addr,
            wdata      => uart_wdata,
            wstrb      => uart_wstrb,
            write_en   => uart_write,
            read_en    => uart_read,
            valid      => uart_valid,
            rdata      => uart_rdata,
            ready      => uart_ready,
            error      => uart_error,
            uart_tx    => uart_tx
        );
 
    dma_i : entity work.dma
        port map (
            clk      => clk,
            rst      => rst_core,
            sel      => dma_sel,
            addr     => dma_addr,
            wdata    => dma_wdata,
            wstrb    => dma_wstrb,
            write_en => dma_write_s,
            read_en  => dma_read_s,
            valid    => dma_valid_s,
            rdata    => dma_rdata,
            ready    => dma_ready_s,
            error    => dma_error_s,
            m_addr   => dma_m_addr,
            m_wdata  => dma_m_wdata,
            m_wstrb  => dma_m_wstrb,
            m_write  => dma_m_write,
            m_read   => dma_m_read,
            m_valid  => dma_m_valid,
            m_rdata  => dma_m_rdata,
            m_ready  => dma_m_ready,
            m_error  => dma_m_error,
            active_o => dma_active,
            irq      => dma_irq
        );
 
end rtl;