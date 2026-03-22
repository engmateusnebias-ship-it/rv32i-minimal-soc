-- tb_soc_top.vhd
-- Self-checking SoC top-level testbench (Vivado/XSim, VHDL-2002 compatible)
-- This TB validates:
--  * After START button press, the program updates GPIO_OUT with a counter 0..10 (wraps to 0).
--  * The sequence increments by +1 (mod 11) without skipping.
--  * STOP button press freezes the output (no further updates while stopped).
--  * START again resumes updates.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_soc_top is
end entity;

architecture sim of tb_soc_top is

  constant CLK_PERIOD : time := 10 ns;

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

  function gpio_nibble_to_int(v : std_logic_vector(3 downto 0)) return integer is
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
    signal g       : in std_logic_vector(3 downto 0);
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

  uut : entity work.soc_top
    port map (
      clk         => clk,
      rst         => rst,
      gpio_toggle => gpio_toggle,
      gpio_out    => gpio_out,
      uart_tx     => uart_tx
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

    report "tb_soc_top STARTED" severity warning;

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

    report "tb_soc_top PASSED" severity warning;
    wait;
  end process;

end architecture;
