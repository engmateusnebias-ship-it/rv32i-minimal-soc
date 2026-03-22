library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_uart is
end tb_uart;

architecture tb of tb_uart is
    constant CLK_PERIOD : time := 10 ns;

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
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
    dut: entity work.uart
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
            uart_tx  => uart_tx
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
        sel   <= '1';
        valid <= '1';

        -- Reset
        tick(2);
        rst <= '0';
        tick(1);

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
        tick(1);
        wait for 1 ns;
        check(ready = '1' and error = '1', "UART TXDATA write while disabled should error");
        write_en <= '0';
        wstrb    <= (others => '0');

        -- Enable UART
        addr     <= x"00000048";
        wdata    <= x"00000001";
        wstrb    <= "0001";
        write_en <= '1';
        tick(1);
        write_en <= '0';
        wstrb    <= (others => '0');

        -- Program bauddiv = 0 (advance every clock)
        addr     <= x"0000004C";
        wdata    <= x"00000000";
        wstrb    <= "1111";
        write_en <= '1';
        tick(1);
        write_en <= '0';
        wstrb    <= (others => '0');

        -- STATUS should show ready before TX
        addr    <= x"00000044";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '1' and rdata(1) = '0', "UART should be ready before TX");
        read_en <= '0';

        -- Start TX of 0xA5 = 1010_0101, LSB-first => 1,0,1,0,0,1,0,1
        addr     <= x"00000040";
        wdata    <= x"000000A5";
        wstrb    <= "0001";
        write_en <= '1';
        tick(1);
        write_en <= '0';
        wstrb    <= (others => '0');

        -- Busy should now be active
        addr    <= x"00000044";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '0' and rdata(1) = '1', "UART should be busy after TX start");
        read_en <= '0';

        -- Start bit
        wait for 1 ns;
        check(uart_tx = '0', "UART start bit incorrect");

        -- Data bits, one bit per clock because bauddiv=0
        tick(1); wait for 1 ns; check(uart_tx = '1', "UART data bit 0 incorrect");
        tick(1); wait for 1 ns; check(uart_tx = '0', "UART data bit 1 incorrect");
        tick(1); wait for 1 ns; check(uart_tx = '1', "UART data bit 2 incorrect");
        tick(1); wait for 1 ns; check(uart_tx = '0', "UART data bit 3 incorrect");
        tick(1); wait for 1 ns; check(uart_tx = '0', "UART data bit 4 incorrect");
        tick(1); wait for 1 ns; check(uart_tx = '1', "UART data bit 5 incorrect");
        tick(1); wait for 1 ns; check(uart_tx = '0', "UART data bit 6 incorrect");
        tick(1); wait for 1 ns; check(uart_tx = '1', "UART data bit 7 incorrect");

        -- Stop bit
        tick(1); wait for 1 ns; check(uart_tx = '1', "UART stop bit incorrect");

        -- Return to ready
        tick(1);
        addr    <= x"00000044";
        read_en <= '1';
        wait for 1 ns;
        check(rdata(0) = '1' and rdata(1) = '0', "UART should return to ready after TX");
        read_en <= '0';

        -- Invalid local address
        addr    <= x"00000050";
        read_en <= '1';
        wait for 1 ns;
        check(ready = '1' and error = '1', "UART invalid local address flags incorrect");
        check(rdata = x"00000000", "UART invalid local address should return zero");
        read_en <= '0';

        -- Idle bus
        sel   <= '0';
        valid <= '0';
        wait for 1 ns;
        check(ready = '0' and error = '0', "UART idle flags incorrect");

        report "tb_uart PASSED" severity warning;
        wait;
    end process;
end tb;
