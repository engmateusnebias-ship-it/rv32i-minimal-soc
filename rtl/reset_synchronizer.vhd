library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Two-flip-flop reset synchronizer.
--
-- Asynchronous assert, synchronous de-assert: rst_out goes high immediately
-- when rst_in asserts, and is released synchronously two clk edges after
-- rst_in de-asserts. This removes reset recovery/removal timing hazards on
-- the destination domain.
--
-- The ASYNC_REG attribute keeps ff1/ff2 placed together so the metastability
-- settling window is maximised (addresses Vivado TIMING-10). Both flops use
-- their dedicated asynchronous preset, so no LUT drives the async control pin
-- (addresses Vivado LUTAR-1).
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

    -- Keep the synchroniser flip-flops grouped and flag them as
    -- clock-domain-crossing registers for the placer.
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of ff1 : signal is "TRUE";
    attribute ASYNC_REG of ff2 : signal is "TRUE";
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
