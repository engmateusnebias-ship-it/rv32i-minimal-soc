library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity reset_synchronizer is
    Port (
        clk     : in  std_logic;
        rst_in  : in  std_logic;
        rst_out : out std_logic
    );
end reset_synchronizer;

architecture rtl of reset_synchronizer is
    signal ff1 : std_logic := '1';
    signal ff2 : std_logic := '1';
begin
    process(clk, rst_in)
    begin
        if rst_in = '1' then
            ff1 <= '1';
            ff2 <= '1';
        elsif rising_edge(clk) then
            ff1 <= '0';
            ff2 <= ff1;
        end if;
    end process;

    rst_out <= ff2;
end rtl;
