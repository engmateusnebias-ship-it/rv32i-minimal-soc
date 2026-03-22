library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_data_memory is
end tb_data_memory;

architecture tb of tb_data_memory is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '0';
    signal sel      : std_logic := '0';
    signal addr     : std_logic_vector(31 downto 0) := (others => '0');
    signal wdata    : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb    : std_logic_vector(3 downto 0) := (others => '0');
    signal write_en : std_logic := '0';
    signal read_en  : std_logic := '0';
    signal valid    : std_logic := '0';
    signal rdata    : std_logic_vector(31 downto 0);
    signal ready    : std_logic;
    signal error    : std_logic;

    procedure tick(signal c : in std_logic) is
    begin
        wait until rising_edge(c);
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report msg severity failure;
    end procedure;
begin
    clk_gen: process
    begin
        clk <= '0'; wait for 5 ns;
        clk <= '1'; wait for 5 ns;
    end process;

    dut: entity work.data_memory
        port map (
            clk      => clk,
            rst      => rst,
            sel      => sel,
            addr     => addr,
            wdata    => wdata,
            wstrb    => wstrb,
            write_en => write_en,
            read_en  => read_en,
            valid    => valid,
            rdata    => rdata,
            ready    => ready,
            error    => error
        );

    stim: process
    begin
        wait for 1 ns;
        check(ready = '0' and error = '0' and rdata = x"00000000", "Idle slave response incorrect");

        sel      <= '1';
        valid    <= '1';
        addr     <= x"00000000";
        wdata    <= x"11223344";
        wstrb    <= "1111";
        write_en <= '1';
        tick(clk);
        write_en <= '0';
        wstrb    <= "0000";

        read_en <= '1';
        wait for 1 ns;
        check(ready = '1' and error = '0', "Readback response flags incorrect");
        check(rdata = x"11223344", "Word readback failed");
        read_en <= '0';

        addr     <= x"00000002";
        wdata    <= x"00AA0000";
        wstrb    <= "0100";
        write_en <= '1';
        tick(clk);
        write_en <= '0';
        wstrb    <= "0000";

        addr    <= x"00000000";
        read_en <= '1';
        wait for 1 ns;
        check(rdata = x"11AA3344", "Byte write (lane2) failed");
        read_en <= '0';

        addr     <= x"00000002";
        wdata    <= x"BEEF0000";
        wstrb    <= "1100";
        write_en <= '1';
        tick(clk);
        write_en <= '0';
        wstrb    <= "0000";

        addr    <= x"00000000";
        read_en <= '1';
        wait for 1 ns;
        check(rdata = x"BEEF3344", "Halfword write failed");
        read_en <= '0';

        addr     <= x"00000000";
        wdata    <= x"FFFFFFFF";
        wstrb    <= "0000";
        write_en <= '1';
        tick(clk);
        write_en <= '0';

        read_en <= '1';
        wait for 1 ns;
        check(rdata = x"BEEF3344", "Write with wstrb=0000 should not modify memory");
        read_en <= '0';

        sel   <= '0';
        valid <= '0';
        wait for 1 ns;
        check(ready = '0' and error = '0' and rdata = x"00000000", "Deselected slave response incorrect");

        report "tb_data_memory PASSED" severity warning;
        wait;
    end process;
end tb;
