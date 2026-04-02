-- tb_rv32i_core.vhd
-- RV32I core integration TB aligned with the current SoC architecture.
--
-- This TB instantiates:
--   * rv32i_core
--   * instruction_memory
--   * bus_interconnect
--   * data_memory
--   * gpio
--   * timer
--   * uart (with core/peripheral clock domains)
--   * dma
--
-- The checked behavior matches the current DMA + UART demo firmware:
--   GPIO_OUT: 0 -> 1 -> 2 -> final result
--   final result must be 0xA for success
--
-- If the demo currently fails in the SoC, this TB will fail the same way,
-- but it compiles against the current interfaces and is useful for debug.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rv32i_core is
end entity;

architecture sim of tb_rv32i_core is
  constant CORE_CLK_PERIOD   : time := 10 ns;
  constant PERIPH_CLK_PERIOD : time := 14 ns;

  signal clk         : std_logic := '0';
  signal periph_clk  : std_logic := '0';
  signal rst         : std_logic := '1';
  signal gpio_toggle : std_logic := '0';
  signal gpio_out    : std_logic_vector(3 downto 0);
  signal uart_tx     : std_logic;

  signal instr_addr  : std_logic_vector(31 downto 0);
  signal instr_rdata : std_logic_vector(31 downto 0);

  signal cpu_bus_addr   : std_logic_vector(31 downto 0);
  signal cpu_bus_wdata  : std_logic_vector(31 downto 0);
  signal cpu_bus_wstrb  : std_logic_vector(3 downto 0);
  signal cpu_bus_write  : std_logic;
  signal cpu_bus_read   : std_logic;
  signal cpu_bus_valid  : std_logic;
  signal cpu_bus_rdata  : std_logic_vector(31 downto 0);
  signal cpu_bus_ready  : std_logic;
  signal cpu_bus_error  : std_logic;

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

  signal bus_addr       : std_logic_vector(31 downto 0);
  signal bus_wdata      : std_logic_vector(31 downto 0);
  signal bus_wstrb      : std_logic_vector(3 downto 0);
  signal bus_write      : std_logic;
  signal bus_read       : std_logic;
  signal bus_valid      : std_logic;
  signal bus_rdata      : std_logic_vector(31 downto 0);
  signal bus_ready      : std_logic;
  signal bus_error      : std_logic;

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

  procedure tick(signal c : in std_logic; n : natural) is
  begin
    for i in 1 to n loop
      wait until rising_edge(c);
    end loop;
  end procedure;

  function gpio_to_int(v : std_logic_vector(3 downto 0)) return integer is
  begin
    return to_integer(unsigned(v));
  end function;

  function is_01_only(v : std_logic_vector) return boolean is
  begin
    for i in v'range loop
      if not (v(i) = '0' or v(i) = '1') then
        return false;
      end if;
    end loop;
    return true;
  end function;

  procedure wait_for_gpio_value(
    signal c       : in std_logic;
    signal g       : in std_logic_vector(3 downto 0);
    expected_val   : in integer;
    timeout_cycles : in natural
  ) is
    variable v : integer;
  begin
    for i in 1 to timeout_cycles loop
      tick(c, 1);
      v := gpio_to_int(g);
      if v = expected_val then
        return;
      end if;
    end loop;

    assert false
      report "Timeout waiting for GPIO_OUT = " & integer'image(expected_val)
      severity failure;
  end procedure;

  procedure wait_for_gpio_result(
    signal c          : in std_logic;
    signal g          : in std_logic_vector(3 downto 0);
    timeout_cycles    : in natural;
    result_val        : out integer
  ) is
    variable v : integer;
  begin
    for i in 1 to timeout_cycles loop
      tick(c, 1);
      v := gpio_to_int(g);
      if (v = 10) or (v = 14) then
        result_val := v;
        return;
      end if;
    end loop;

    assert false
      report "Timeout waiting for GPIO_OUT final result (0xA or 0xE)"
      severity failure;

    result_val := -1;
  end procedure;

begin
  core_clk_gen : process
  begin
    while true loop
      clk <= '0'; wait for CORE_CLK_PERIOD/2;
      clk <= '1'; wait for CORE_CLK_PERIOD/2;
    end loop;
  end process;

  periph_clk_gen : process
  begin
    while true loop
      periph_clk <= '0'; wait for PERIPH_CLK_PERIOD/2;
      periph_clk <= '1'; wait for PERIPH_CLK_PERIOD/2;
    end loop;
  end process;

  -- Shared-bus arbitration identical to soc_top.
  bus_addr  <= dma_m_addr  when dma_active = '1' else cpu_bus_addr;
  bus_wdata <= dma_m_wdata when dma_active = '1' else cpu_bus_wdata;
  bus_wstrb <= dma_m_wstrb when dma_active = '1' else cpu_bus_wstrb;
  bus_write <= dma_m_write when dma_active = '1' else cpu_bus_write;
  bus_read  <= dma_m_read  when dma_active = '1' else cpu_bus_read;
  bus_valid <= dma_m_valid when dma_active = '1' else cpu_bus_valid;

  cpu_bus_rdata <= bus_rdata;
  cpu_bus_ready <= bus_ready;
  cpu_bus_error <= bus_error;

  dma_m_rdata <= bus_rdata;
  dma_m_ready <= bus_ready;
  dma_m_error <= bus_error;

  core0 : entity work.rv32i_core
    port map (
      clk         => clk,
      rst         => rst,
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
      irq_in      => timer_irq or dma_irq
    );

  instr_mem : entity work.instruction_memory
    port map (
      addr        => instr_addr,
      instruction => instr_rdata
    );

  intercon : entity work.bus_interconnect
    port map (
      m_addr      => bus_addr,
      m_wdata     => bus_wdata,
      m_wstrb     => bus_wstrb,
      m_write     => bus_write,
      m_read      => bus_read,
      m_valid     => bus_valid,
      m_rdata     => bus_rdata,
      m_ready     => bus_ready,
      m_error     => bus_error,

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

  ram0 : entity work.data_memory
    port map (
      clk      => clk,
      rst      => rst,
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

  gpio0 : entity work.gpio
    port map (
      clk         => clk,
      rst         => rst,
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

  timer0 : entity work.timer
    port map (
      clk      => clk,
      rst      => rst,
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

  uart0 : entity work.uart
    port map (
      core_clk   => clk,
      core_rst   => rst,
      periph_clk => periph_clk,
      periph_rst => rst,
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

  dma0 : entity work.dma
    port map (
      clk      => clk,
      rst      => rst,
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

  stim : process
    variable result_val : integer;
  begin
    rst <= '1';
    gpio_toggle <= '0';
    tick(clk, 5);
    rst <= '0';
    tick(clk, 5);

    report "tb_rv32i_core STARTED" severity warning;

    assert is_01_only(gpio_out)
      report "GPIO_OUT contains unresolved values after reset"
      severity failure;

    assert gpio_to_int(gpio_out) = 0
      report "GPIO_OUT should be 0 after reset"
      severity failure;

    gpio_toggle <= '1';

    wait_for_gpio_value(clk, gpio_out, 1, 4000);
    wait_for_gpio_value(clk, gpio_out, 2, 4000);
    wait_for_gpio_result(clk, gpio_out, 12000, result_val);

    assert result_val = 10
      report "DMA/UART demo failed in tb_rv32i_core: GPIO_OUT reached 0xE instead of 0xA"
      severity failure;

    gpio_toggle <= '0';
    wait_for_gpio_value(clk, gpio_out, 0, 12000);

    report "tb_rv32i_core PASSED" severity warning;
    wait;
  end process;
end architecture;
