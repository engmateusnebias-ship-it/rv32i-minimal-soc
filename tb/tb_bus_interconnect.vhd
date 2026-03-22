library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_bus_interconnect is
end tb_bus_interconnect;

architecture tb of tb_bus_interconnect is
    signal m_addr    : std_logic_vector(31 downto 0) := (others => '0');
    signal m_wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal m_wstrb   : std_logic_vector(3 downto 0)  := (others => '0');
    signal m_write   : std_logic := '0';
    signal m_read    : std_logic := '0';
    signal m_valid   : std_logic := '0';
    signal m_rdata   : std_logic_vector(31 downto 0);
    signal m_ready   : std_logic;
    signal m_error   : std_logic;

    signal ram_sel, gpio_sel, timer_sel, uart_sel, dma_sel : std_logic;
    signal ram_addr, gpio_addr, timer_addr, uart_addr, dma_addr : std_logic_vector(31 downto 0);
    signal ram_wdata, gpio_wdata, timer_wdata, uart_wdata, dma_wdata : std_logic_vector(31 downto 0);
    signal ram_wstrb, gpio_wstrb, timer_wstrb, uart_wstrb, dma_wstrb : std_logic_vector(3 downto 0);
    signal ram_write, gpio_write, timer_write, uart_write, dma_write : std_logic;
    signal ram_read, gpio_read, timer_read, uart_read, dma_read : std_logic;
    signal ram_valid, gpio_valid, timer_valid, uart_valid, dma_valid : std_logic;

    signal ram_rdata   : std_logic_vector(31 downto 0) := x"AAAAAAAA";
    signal ram_ready   : std_logic := '1';
    signal ram_error   : std_logic := '0';

    signal gpio_rdata  : std_logic_vector(31 downto 0) := x"BBBBBBBB";
    signal gpio_ready  : std_logic := '1';
    signal gpio_error  : std_logic := '0';

    signal timer_rdata : std_logic_vector(31 downto 0) := x"CCCCCCCC";
    signal timer_ready : std_logic := '1';
    signal timer_error : std_logic := '0';

    signal uart_rdata  : std_logic_vector(31 downto 0) := x"DDDDDDDD";
    signal uart_ready  : std_logic := '1';
    signal uart_error  : std_logic := '0';

    signal dma_rdata   : std_logic_vector(31 downto 0) := x"EEEEEEEE";
    signal dma_ready   : std_logic := '1';
    signal dma_error   : std_logic := '0';

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report msg severity failure;
    end procedure;
begin
    dut: entity work.bus_interconnect
        port map (
            m_addr      => m_addr,
            m_wdata     => m_wdata,
            m_wstrb     => m_wstrb,
            m_write     => m_write,
            m_read      => m_read,
            m_valid     => m_valid,
            m_rdata     => m_rdata,
            m_ready     => m_ready,
            m_error     => m_error,

            ram_sel     => ram_sel,
            ram_addr    => ram_addr,
            ram_wdata   => ram_wdata,
            ram_wstrb   => ram_wstrb,
            ram_write   => ram_write,
            ram_read    => ram_read,
            ram_valid   => ram_valid,
            ram_rdata   => ram_rdata,
            ram_ready   => ram_ready,
            ram_error   => ram_error,

            gpio_sel    => gpio_sel,
            gpio_addr   => gpio_addr,
            gpio_wdata  => gpio_wdata,
            gpio_wstrb  => gpio_wstrb,
            gpio_write  => gpio_write,
            gpio_read   => gpio_read,
            gpio_valid  => gpio_valid,
            gpio_rdata  => gpio_rdata,
            gpio_ready  => gpio_ready,
            gpio_error  => gpio_error,

            timer_sel   => timer_sel,
            timer_addr  => timer_addr,
            timer_wdata => timer_wdata,
            timer_wstrb => timer_wstrb,
            timer_write => timer_write,
            timer_read  => timer_read,
            timer_valid => timer_valid,
            timer_rdata => timer_rdata,
            timer_ready => timer_ready,
            timer_error => timer_error,

            uart_sel    => uart_sel,
            uart_addr   => uart_addr,
            uart_wdata  => uart_wdata,
            uart_wstrb  => uart_wstrb,
            uart_write  => uart_write,
            uart_read   => uart_read,
            uart_valid  => uart_valid,
            uart_rdata  => uart_rdata,
            uart_ready  => uart_ready,
            uart_error  => uart_error,

            dma_sel     => dma_sel,
            dma_addr    => dma_addr,
            dma_wdata   => dma_wdata,
            dma_wstrb   => dma_wstrb,
            dma_write   => dma_write,
            dma_read    => dma_read,
            dma_valid   => dma_valid,
            dma_rdata   => dma_rdata,
            dma_ready   => dma_ready,
            dma_error   => dma_error
        );

    stim: process
    begin
        wait for 1 ns;
        check(m_ready = '0' and m_error = '0', "Idle response should be inactive");
        check(ram_sel = '0' and gpio_sel = '0' and timer_sel = '0' and uart_sel = '0' and dma_sel = '0', "Idle decode should select no slave");

        m_addr  <= x"00000100";
        m_read  <= '1';
        m_valid <= '1';
        wait for 1 ns;
        check(ram_sel = '1', "RAM read decode failed");
        check(m_rdata = x"AAAAAAAA" and m_ready = '1' and m_error = '0', "RAM read response mux failed");

        m_addr <= x"00000014";
        wait for 1 ns;
        check(gpio_sel = '1' and ram_sel = '0', "GPIO read decode failed");
        check(m_rdata = x"BBBBBBBB", "GPIO read response mux failed");

        m_addr <= x"00000020";
        wait for 1 ns;
        check(timer_sel = '1', "TIMER read decode failed");
        check(m_rdata = x"CCCCCCCC", "TIMER read response mux failed");

        m_addr <= x"00000044";
        wait for 1 ns;
        check(uart_sel = '1', "UART read decode failed");
        check(m_rdata = x"DDDDDDDD", "UART read response mux failed");

        m_addr <= x"00000090";
        wait for 1 ns;
        check(dma_sel = '1', "DMA read decode failed");
        check(m_rdata = x"EEEEEEEE", "DMA read response mux failed");

        m_addr  <= x"10000000";
        wait for 1 ns;
        check(ram_sel = '0' and gpio_sel = '0' and timer_sel = '0' and uart_sel = '0' and dma_sel = '0', "Invalid address should select no slave");
        check(m_ready = '1' and m_error = '1', "Invalid address should return ready and error");

        m_valid <= '0';
        m_read  <= '0';
        wait for 1 ns;
        check(m_ready = '0' and m_error = '0', "Idle response should clear after access");

        report "tb_bus_interconnect PASSED" severity warning;
        wait;
    end process;
end tb;
