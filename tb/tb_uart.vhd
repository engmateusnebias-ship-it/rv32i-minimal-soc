library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_uart is
end tb_uart;

architecture tb of tb_uart is
    constant CORE_CLK_PERIOD   : time := 10 ns;
    constant PERIPH_CLK_PERIOD : time := 14 ns;

    signal core_clk   : std_logic := '0';
    signal core_rst   : std_logic := '1';
    signal periph_clk : std_logic := '0';
    signal periph_rst : std_logic := '1';

    signal sel      : std_logic := '0';
    signal addr     : std_logic_vector(31 downto 0) := (others => '0');
    signal wdata    : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb    : std_logic_vector(3 downto 0)  := (others => '0');
    signal write_en : std_logic := '0';
    signal read_en  : std_logic := '0';
    signal valid    : std_logic := '0';
    signal rdata    : std_logic_vector(31 downto 0);
    signal ready    : std_logic;
    signal error    : std_logic;
    signal uart_tx  : std_logic;

    procedure tick_core(n : natural := 1) is
    begin
        for i in 1 to n loop
            wait until rising_edge(core_clk);
        end loop;
    end procedure;

    procedure tick_periph(n : natural := 1) is
    begin
        for i in 1 to n loop
            wait until rising_edge(periph_clk);
        end loop;
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report msg severity failure;
    end procedure;
begin
    dut: entity work.uart
        port map (
            core_clk   => core_clk,
            core_rst   => core_rst,
            periph_clk => periph_clk,
            periph_rst => periph_rst,
            sel        => sel,
            addr       => addr,
            wdata      => wdata,
            wstrb      => wstrb,
            write_en   => write_en,
            read_en    => read_en,
            valid      => valid,
            rdata      => rdata,
            ready      => ready,
            error      => error,
            uart_tx    => uart_tx
        );

    core_clk_gen: process
    begin
        while true loop
            core_clk <= '0'; wait for CORE_CLK_PERIOD/2;
            core_clk <= '1'; wait for CORE_CLK_PERIOD/2;
        end loop;
    end process;

    periph_clk_gen: process
    begin
        while true loop
            periph_clk <= '0'; wait for PERIPH_CLK_PERIOD/2;
            periph_clk <= '1'; wait for PERIPH_CLK_PERIOD/2;
        end loop;
    end process;

    stim: process
        variable saw_start : boolean;
    begin
        sel   <= '1';
        valid <= '1';

        tick_core(3);
        tick_periph(3);

        core_rst   <= '0';
        periph_rst <= '0';

        tick_core(4);
        tick_periph(4);
        wait for 1 ns;

        -- After reset: disabled, idle line high, ready=1, busy=0
        addr    <= x"00000044";
        read_en <= '1';
        wait for 1 ns;
        check(uart_tx = '1', "UART TX line should idle high after reset");
        check(rdata(0) = '1' and rdata(1) = '0', "UART status after reset is incorrect");
        check(ready = '1' and error = '0', "UART status read flags incorrect after reset");
        read_en <= '0';

        -- Writing TXDATA while disabled must error
        addr     <= x"00000040";
        wdata    <= x"00000055";
        wstrb    <= "0001";
        write_en <= '1';
        tick_core(1);
        wait for 1 ns;
        check(ready = '1' and error = '1', "UART TXDATA write while disabled should error");
        write_en <= '0';
        wstrb    <= (others => '0');

        -- Enable UART
        addr     <= x"00000048";
        wdata    <= x"00000001";
        wstrb    <= "0001";
        write_en <= '1';
        tick_core(1);
        wait for 1 ns;
        check(error = '0', "UART CTRL write should not error");
        write_en <= '0';
        wstrb    <= (others => '0');

        -- Program bauddiv = 1 (two periph clocks per bit)
        addr     <= x"0000004C";
        wdata    <= x"00000001";
        wstrb    <= "1111";
        write_en <= '1';
        tick_core(1);
        wait for 1 ns;
        check(error = '0', "UART BAUDDIV write should not error");
        write_en <= '0';
        wstrb    <= (others => '0');

        -- STATUS should show ready before TX
        addr    <= x"00000044";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '1' and rdata(1) = '0', "UART should be ready before TX");
        read_en <= '0';

        -- Start TX of 0xA5.
        -- Important: sample acceptance during the access cycle, then deassert write.
        addr     <= x"00000040";
        wdata    <= x"000000A5";
        wstrb    <= "0001";
        write_en <= '1';
        wait for 1 ns;
        check(ready = '1' and error = '0', "UART TXDATA write should be accepted");
        tick_core(1);
        write_en <= '0';
        wstrb    <= (others => '0');

        -- Second write while busy: must error
        write_en <= '1';
        wait for 1 ns;
        check(error = '1', "Second write while UART busy should error");
        tick_core(1);
        write_en <= '0';

        -- STATUS should indicate busy from core side
        addr    <= x"00000044";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(1) = '1', "UART should report busy after TX start");
        read_en <= '0';

        saw_start := false;
        for i in 1 to 20 loop
            tick_periph(1);
            if uart_tx = '0' then
                saw_start := true;
                exit;
            end if;
        end loop;
        check(saw_start, "UART start bit was not observed");

        tick_periph(2); wait for 1 ns; check(uart_tx = '1', "UART data bit 0 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '0', "UART data bit 1 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '1', "UART data bit 2 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '0', "UART data bit 3 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '0', "UART data bit 4 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '1', "UART data bit 5 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '0', "UART data bit 6 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '1', "UART data bit 7 incorrect");
        tick_periph(2); wait for 1 ns; check(uart_tx = '1', "UART stop bit incorrect");

        tick_core(8);
        addr    <= x"00000044";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '1' and rdata(1) = '0', "UART should return to ready after TX");
        read_en <= '0';

        addr    <= x"00000050";
        read_en <= '1';
        wait for 1 ns;
        check(ready = '1' and error = '1', "UART invalid local address flags incorrect");
        check(rdata = x"00000000", "UART invalid local address should return zero");
        read_en <= '0';

        sel   <= '0';
        valid <= '0';
        wait for 1 ns;
        check(ready = '0' and error = '0', "UART idle flags incorrect");

        report "tb_uart PASSED" severity warning;
        wait;
    end process;
end tb;
