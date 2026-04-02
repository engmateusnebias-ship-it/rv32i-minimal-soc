library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_reset_synchronizer is
end tb_reset_synchronizer;

architecture tb of tb_reset_synchronizer is
    constant CLK_PERIOD : time := 10 ns;

    signal clk     : std_logic := '0';
    signal rst_in  : std_logic := '1';
    signal rst_out : std_logic;

    procedure tick(n : natural := 1) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report msg severity failure;
    end procedure;
begin
    dut: entity work.reset_synchronizer
        port map (
            clk     => clk,
            rst_in  => rst_in,
            rst_out => rst_out
        );

    clk_gen: process
    begin
        while true loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
    end process;

    stim: process
    begin
        -- While reset is asserted, output must be asserted.
        tick(2);
        wait for 1 ns;
        check(rst_out = '1', "rst_out should be high while rst_in is asserted");

        -- Deassert rst_in well away from the next clock edge.
        wait for CLK_PERIOD/2;
        rst_in <= '0';
        wait for 1 ns;
        check(rst_out = '1', "rst_out must not deassert asynchronously");

        tick(1);
        wait for 1 ns;
        check(rst_out = '1', "rst_out should still be high after one clock");

        tick(1);
        wait for 1 ns;
        check(rst_out = '0', "rst_out should deassert after two clocks");

        -- Assert again asynchronously.
        rst_in <= '1';
        wait for 1 ns;
        check(rst_out = '1', "rst_out should assert asynchronously");

        report "tb_reset_synchronizer PASSED" severity warning;
        wait;
    end process;
end tb;
