-- tb_rv32i_core.vhd
-- Self-checking RV32I core integration testbench (Vivado/XSim, VHDL-2002 compatible)
-- This TB validates the split rv32i_core against the original software behavior
-- using the same instruction memory, interconnect, RAM, GPIO and TIMER environment.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rv32i_core is
end entity;

architecture sim of tb_rv32i_core is

  constant CLK_PERIOD : time := 10 ns;

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal gpio_toggle : std_logic := '0';
  signal gpio_out    : std_logic_vector(31 downto 0);

  signal instr_addr  : std_logic_vector(31 downto 0);
  signal instr_rdata : std_logic_vector(31 downto 0);

  signal bus_addr    : std_logic_vector(31 downto 0);
  signal bus_wdata   : std_logic_vector(31 downto 0);
  signal bus_wstrb   : std_logic_vector(3 downto 0);
  signal bus_write   : std_logic;
  signal bus_read    : std_logic;
  signal bus_valid   : std_logic;
  signal bus_rdata   : std_logic_vector(31 downto 0);
  signal bus_ready   : std_logic;
  signal bus_error   : std_logic;

  signal ram_sel     : std_logic;
  signal ram_addr    : std_logic_vector(31 downto 0);
  signal ram_wdata   : std_logic_vector(31 downto 0);
  signal ram_wstrb   : std_logic_vector(3 downto 0);
  signal ram_write   : std_logic;
  signal ram_read    : std_logic;
  signal ram_valid   : std_logic;
  signal ram_rdata   : std_logic_vector(31 downto 0);
  signal ram_ready   : std_logic;
  signal ram_error   : std_logic;

  signal gpio_sel    : std_logic;
  signal gpio_addr   : std_logic_vector(31 downto 0);
  signal gpio_wdata  : std_logic_vector(31 downto 0);
  signal gpio_wstrb  : std_logic_vector(3 downto 0);
  signal gpio_write  : std_logic;
  signal gpio_read   : std_logic;
  signal gpio_valid  : std_logic;
  signal gpio_rdata  : std_logic_vector(31 downto 0);
  signal gpio_ready  : std_logic;
  signal gpio_error  : std_logic;

  signal timer_sel   : std_logic;
  signal timer_addr  : std_logic_vector(31 downto 0);
  signal timer_wdata : std_logic_vector(31 downto 0);
  signal timer_wstrb : std_logic_vector(3 downto 0);
  signal timer_write : std_logic;
  signal timer_read  : std_logic;
  signal timer_valid : std_logic;
  signal timer_rdata : std_logic_vector(31 downto 0);
  signal timer_ready : std_logic;
  signal timer_error : std_logic;
  signal timer_irq   : std_logic;

  signal uart_sel    : std_logic;
  signal uart_addr   : std_logic_vector(31 downto 0);
  signal uart_wdata  : std_logic_vector(31 downto 0);
  signal uart_wstrb  : std_logic_vector(3 downto 0);
  signal uart_write  : std_logic;
  signal uart_read   : std_logic;
  signal uart_valid  : std_logic;
  signal uart_rdata  : std_logic_vector(31 downto 0);
  signal uart_ready  : std_logic;
  signal uart_error  : std_logic;
  signal uart_tx     : std_logic;

  procedure tick(signal c : in std_logic; n : natural) is
  begin
    for i in 1 to n loop
      wait until rising_edge(c);
    end loop;
  end procedure;

  procedure press_button(signal btn : inout std_logic; signal c : in std_logic) is
  begin
    btn <= '1';
    tick(c, 100);
    btn <= '0';
    tick(c, 20);
  end procedure;

  function is_01_only(v : std_logic_vector) return boolean is
  begin
    for i in v'range loop
      if not (v(i) = '0' or v(i) = '1') then
        return false;
      end if;
    end loop;
    return true;
  end function;

  function gpio_nibble_to_int(v : std_logic_vector(31 downto 0)) return integer is
  begin
    return to_integer(unsigned(v(3 downto 0)));
  end function;

  function mod11_plus(val : integer; inc : integer) return integer is
    variable tmp : integer;
  begin
    tmp := val + inc;
    while tmp >= 11 loop
      tmp := tmp - 11;
    end loop;
    while tmp < 0 loop
      tmp := tmp + 11;
    end loop;
    return tmp;
  end function;

  procedure wait_for_gpio_change(
    signal c       : in std_logic;
    signal g       : in std_logic_vector(31 downto 0);
    prev_val       : in integer;
    timeout_cycles : in natural;
    new_val        : out integer
  ) is
    variable v : integer;
  begin
    for i in 1 to timeout_cycles loop
      tick(c, 1);
      v := gpio_nibble_to_int(g);
      if v /= prev_val then
        new_val := v;
        return;
      end if;
    end loop;

    assert false
      report "Timeout waiting for GPIO_OUT to change"
      severity failure;

    new_val := prev_val;
  end procedure;

begin

  clk_gen : process
  begin
    while true loop
      clk <= '0';
      wait for CLK_PERIOD/2;
      clk <= '1';
      wait for CLK_PERIOD/2;
    end loop;
  end process;

  core0 : entity work.rv32i_core
    port map (
      clk         => clk,
      rst         => rst,
      instr_addr  => instr_addr,
      instr_rdata => instr_rdata,
      bus_addr    => bus_addr,
      bus_wdata   => bus_wdata,
      bus_wstrb   => bus_wstrb,
      bus_write   => bus_write,
      bus_read    => bus_read,
      bus_valid   => bus_valid,
      bus_rdata   => bus_rdata,
      bus_ready   => bus_ready,
      bus_error   => bus_error,
      irq_in      => timer_irq
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
      uart_error  => uart_error
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
      gpio_out    => gpio_out(3 downto 0),
      gpio_toggle => gpio_toggle
    );

  gpio_out(31 downto 4) <= (others => '0');

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
      clk      => clk,
      rst      => rst,
      sel      => uart_sel,
      addr     => uart_addr,
      wdata    => uart_wdata,
      wstrb    => uart_wstrb,
      write_en => uart_write,
      read_en  => uart_read,
      valid    => uart_valid,
      rdata    => uart_rdata,
      ready    => uart_ready,
      error    => uart_error,
      uart_tx  => uart_tx
    );

  stim : process
    variable v0            : integer;
    variable v1            : integer;
    variable expected_next : integer;
    variable expected_alt  : integer;
    variable saw_ten       : boolean;
    variable saw_wrap      : boolean;
    variable last          : integer;
    variable changes       : integer;
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

    v0 := gpio_nibble_to_int(gpio_out);
    press_button(gpio_toggle, clk);
    wait_for_gpio_change(clk, gpio_out, v0, 2000, v1);

    last := v1;
    saw_ten := (last = 10);
    saw_wrap := false;
    changes := 0;

    while (changes < 40) and (not (saw_ten and saw_wrap)) loop
      v0 := last;
      wait_for_gpio_change(clk, gpio_out, v0, 4000, v1);
      expected_next := mod11_plus(last, 1);

      assert v1 = expected_next
        report "Unexpected GPIO_OUT sequence: expected " & integer'image(expected_next) &
               " got " & integer'image(v1)
        severity failure;

      if v1 = 10 then
        saw_ten := true;
      end if;
      if (last = 10) and (v1 = 0) then
        saw_wrap := true;
      end if;

      last := v1;
      changes := changes + 1;
    end loop;

    assert saw_ten
      report "Did not observe GPIO_OUT reaching 10 while running"
      severity failure;

    assert saw_wrap
      report "Did not observe GPIO_OUT wrapping from 10 back to 0 while running"
      severity failure;

    v0 := last;
    while (last /= 5) loop
      wait_for_gpio_change(clk, gpio_out, v0, 4000, v1);
      last := v1;
      v0 := last;
      exit when changes > 80;
      changes := changes + 1;
    end loop;

    v0 := gpio_nibble_to_int(gpio_out);
    press_button(gpio_toggle, clk);

    tick(clk, 6000);
    v1 := gpio_nibble_to_int(gpio_out);

    assert v1 = v0
      report "GPIO_OUT changed while STOPPED (expected stable)"
      severity failure;

    press_button(gpio_toggle, clk);
    wait_for_gpio_change(clk, gpio_out, v0, 8000, v1);

    expected_next := mod11_plus(v0, 1);
    expected_alt  := mod11_plus(v0, 2);

    assert (v1 = expected_next) or (v1 = expected_alt)
      report "After RESUME, unexpected first change: expected " &
             integer'image(expected_next) & " or " & integer'image(expected_alt) &
             " got " & integer'image(v1)
      severity failure;

    last := v1;
    for k in 1 to 6 loop
      v0 := last;
      wait_for_gpio_change(clk, gpio_out, v0, 8000, v1);
      expected_next := mod11_plus(last, 1);

      assert v1 = expected_next
        report "After RESUME, sequence error: expected " & integer'image(expected_next) &
               " got " & integer'image(v1)
        severity failure;

      last := v1;
    end loop;

    report "tb_rv32i_core PASSED" severity warning;
    wait;
  end process;

end architecture;
