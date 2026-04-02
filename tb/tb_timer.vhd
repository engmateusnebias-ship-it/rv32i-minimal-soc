library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_timer is
end tb_timer;

architecture tb of tb_timer is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
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
    signal irq      : std_logic;

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
    clk_gen : process
    begin
        while true loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
    end process;

    dut: entity work.timer
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
            error    => error,
            irq      => irq
        );

    stim : process
    begin
        sel   <= '1';
        valid <= '1';

        tick(2);
        rst <= '0';
        tick(1);

        -- After reset, COUNT must be zero.
        addr    <= x"00000020";
        read_en <= '1';
        wait for 1 ns;
        check(rdata = x"00000000", "COUNT should reset to zero");
        check(ready = '1' and error = '0', "COUNT read flags incorrect after reset");
        read_en <= '0';

        -- Program CMP = 3.
        addr     <= x"00000024";
        wdata    <= x"00000003";
        wstrb    <= "1111";
        write_en <= '1';
        tick(1);
        write_en <= '0';
        wstrb    <= (others => '0');

        -- Read back CMP.
        read_en <= '1';
        wait for 1 ns;
        check(rdata = x"00000003", "CMP readback failed");
        read_en <= '0';

        -- Program CTRL = enable + irq_enable.
        addr     <= x"00000028";
        wdata    <= x"00000003";
        wstrb    <= "0001";
        write_en <= '1';
        tick(1);
        write_en <= '0';
        wstrb    <= (others => '0');

        -- CTRL bit2 must read back as 0 (clear is pulse only).
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '1' and rdata(1) = '1' and rdata(2) = '0', "CTRL readback semantics incorrect");
        read_en <= '0';

        -- Starting from COUNT=0, after enabling the timer:
        -- tick 1 -> COUNT becomes 1
        -- tick 2 -> COUNT becomes 2
        -- tick 3 -> COUNT becomes 3 and IRQ must pulse
        tick(2);
        check(irq = '0', "IRQ asserted too early");
        tick(1);
        check(irq = '1', "IRQ pulse missing when count reaches cmp");
        tick(1);
        check(irq = '0', "IRQ must be a one-cycle pulse");

        -- Timer must keep counting after compare.
        addr    <= x"00000020";
        read_en <= '1';
        wait for 1 ns;
        check(unsigned(rdata) >= 4, "COUNT should continue after compare");
        read_en <= '0';

        -- Clear the counter with CTRL.clear pulse only.
        addr     <= x"00000028";
        wdata    <= x"00000004";
        wstrb    <= "0001";
        write_en <= '1';
        tick(1);
        write_en <= '0';
        wstrb    <= (others => '0');

        addr    <= x"00000020";
        read_en <= '1';
        wait for 1 ns;
        check(rdata = x"00000000", "COUNT should clear to zero");
        read_en <= '0';

        -- Read CTRL after clear pulse: clear bit must still read as 0.
        addr    <= x"00000028";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(2) = '0', "CTRL.clear must read as zero");
        read_en <= '0';

        -- Invalid local address must respond with ready=1, error=1, rdata=0.
        addr    <= x"0000002C";
        read_en <= '1';
        wait for 1 ns;
        check(ready = '1' and error = '1', "Timer invalid local address flags incorrect");
        check(rdata = x"00000000", "Timer invalid local address should return zero");
        read_en <= '0';

        -- Idle behavior.
        sel   <= '0';
        valid <= '0';
        wait for 1 ns;
        check(ready = '0' and error = '0', "Timer idle flags incorrect");

        report "tb_timer PASSED" severity warning;
        wait;
    end process;
end tb;
