-- tb_soc_top.vhd
-- Self-checking SoC top-level testbench for the DMA + UART demo
--
-- This TB validates:
--   * After button press, GPIO_OUT goes through:
--       0x0 -> 0x1 -> 0x2 -> final result
--   * Final result must be 0xA (success)
--   * UART_TX must show activity during the report phase
--   * After button release, GPIO_OUT returns to 0x0
--
-- Clocks:
--   * core clock   = 10 ns (100 MHz)
--   * periph_clk   = 28.8 MHz, generated internally by MMCM inside soc_top
--                    (not driven by this TB)
 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
 
entity tb_soc_top is
end entity;
 
architecture sim of tb_soc_top is
 
  constant CORE_CLK_PERIOD : time := 10 ns;
 
  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal gpio_toggle : std_logic := '0';
  signal gpio_out    : std_logic_vector(3 downto 0);
  signal uart_tx     : std_logic;
 
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
 
  -- =======================================================
  -- Core clock generator (100 MHz)
  -- periph_clk is generated inside soc_top by the MMCM
  -- =======================================================
  core_clk_gen : process
  begin
    while true loop
      clk <= '0';
      wait for CORE_CLK_PERIOD / 2;
      clk <= '1';
      wait for CORE_CLK_PERIOD / 2;
    end loop;
  end process;
 
  -- =======================================================
  -- DUT
  -- =======================================================
  uut : entity work.soc_top
    port map (
      clk         => clk,
      rst         => rst,
      gpio_toggle => gpio_toggle,
      gpio_out    => gpio_out,
      uart_tx     => uart_tx
    );
 
  -- =======================================================
  -- Stimulus and checks
  -- =======================================================
  stim : process
    variable result_val        : integer;
    variable uart_activity_cnt : integer;
    variable last_uart         : std_logic;
  begin
    -- Initial reset
    rst         <= '1';
    gpio_toggle <= '0';
    tick(clk, 5);
    rst <= '0';
    tick(clk, 5);
 
    report "tb_soc_top STARTED" severity warning;
 
    -- Basic sanity after reset
    assert is_01_only(gpio_out)
      report "GPIO_OUT contains unresolved values after reset"
      severity failure;
 
    assert gpio_to_int(gpio_out) = 0
      report "GPIO_OUT should be 0 after reset"
      severity failure;
 
    -- Press button to start demo
    gpio_toggle <= '1';
 
    -- Expect stage markers
    wait_for_gpio_value(clk, gpio_out, 1, 4000);
    wait_for_gpio_value(clk, gpio_out, 2, 4000);
 
    -- Wait for final result
    wait_for_gpio_result(clk, gpio_out, 12000, result_val);
 
    -- We want the demo to succeed
    assert result_val = 10
      report "DMA/UART demo failed: GPIO_OUT reached 0xE instead of 0xA"
      severity failure;
 
    -- Check UART activity during the report phase.
    -- Sampled on clk (core clock) since periph_clk is internal to the DUT.
    uart_activity_cnt := 0;
    last_uart         := uart_tx;
 
    for i in 1 to 3000 loop
      tick(clk, 1);
      if uart_tx /= last_uart then
        uart_activity_cnt := uart_activity_cnt + 1;
        last_uart         := uart_tx;
      end if;
    end loop;
 
    assert uart_activity_cnt > 0
      report "UART_TX showed no activity during the success-report window"
      severity failure;
 
    -- Release button and expect return to idle
    gpio_toggle <= '0';
    wait_for_gpio_value(clk, gpio_out, 0, 12000);
 
    report "tb_soc_top PASSED" severity warning;
    wait;
  end process;
 
end architecture;