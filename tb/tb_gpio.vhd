library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_gpio is
end tb_gpio;

architecture sim of tb_gpio is
    constant CLK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '0';
    signal sel         : std_logic := '0';
    signal addr        : std_logic_vector(31 downto 0) := (others => '0');
    signal wdata       : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb       : std_logic_vector(3 downto 0)  := (others => '0');
    signal write_en    : std_logic := '0';
    signal read_en     : std_logic := '0';
    signal valid       : std_logic := '0';
    signal rdata       : std_logic_vector(31 downto 0);
    signal ready       : std_logic;
    signal error       : std_logic;
    signal gpio_out    : std_logic_vector(3 downto 0);
    signal gpio_toggle : std_logic := '0';

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report msg severity failure;
    end procedure;
begin
    uut: entity work.gpio
        port map (
            clk         => clk,
            rst         => rst,
            sel         => sel,
            addr        => addr,
            wdata       => wdata,
            wstrb       => wstrb,
            write_en    => write_en,
            read_en     => read_en,
            valid       => valid,
            rdata       => rdata,
            ready       => ready,
            error       => error,
            gpio_out    => gpio_out,
            gpio_toggle => gpio_toggle
        );

    clk_gen: process
    begin
        while now < 500 ns loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    stim: process
    begin
        rst <= '1';
        wait for 2*CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        sel   <= '1';
        valid <= '1';

        check(gpio_out = "0000", "GPIO reset value incorrect");

        addr     <= x"00000010";
        wdata    <= x"0000000A";
        wstrb    <= "0001";
        write_en <= '1';
        wait until rising_edge(clk);
        write_en <= '0';
        wstrb    <= (others => '0');
        wait for 1 ns;
        check(gpio_out = "1010", "GPIO write failed");
        check(ready = '1' and error = '0', "GPIO access flags incorrect after write");

        read_en <= '1';
        wait for 1 ns;
        check(rdata(3 downto 0) = "1010", "GPIO readback of OUT failed");
        read_en <= '0';

        gpio_toggle <= '1';
        addr    <= x"00000014";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '1', "GPIO IN read failed (toggle=1)");
        read_en <= '0';

        gpio_toggle <= '0';
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '0', "GPIO IN read failed (toggle=0)");
        read_en <= '0';

        addr    <= x"00000018";
        read_en <= '1';
        wait for 1 ns;
        check(rdata = x"00000000", "GPIO invalid local address should return zero");
        check(ready = '1' and error = '1', "GPIO invalid local address flags incorrect");
        read_en <= '0';

        sel   <= '0';
        valid <= '0';
        wait for 1 ns;
        check(ready = '0' and error = '0', "GPIO idle flags incorrect");

        report "tb_gpio PASSED" severity warning;
        wait;
    end process;
end sim;
