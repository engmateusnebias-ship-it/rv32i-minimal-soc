library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bus_interconnect is
    Port (
        m_addr       : in  std_logic_vector(31 downto 0);
        m_wdata      : in  std_logic_vector(31 downto 0);
        m_wstrb      : in  std_logic_vector(3 downto 0);
        m_write      : in  std_logic;
        m_read       : in  std_logic;
        m_valid      : in  std_logic;
        m_rdata      : out std_logic_vector(31 downto 0);
        m_ready      : out std_logic;
        m_error      : out std_logic;

        ram_sel      : out std_logic;
        ram_addr     : out std_logic_vector(31 downto 0);
        ram_wdata    : out std_logic_vector(31 downto 0);
        ram_wstrb    : out std_logic_vector(3 downto 0);
        ram_write    : out std_logic;
        ram_read     : out std_logic;
        ram_valid    : out std_logic;
        ram_rdata    : in  std_logic_vector(31 downto 0);
        ram_ready    : in  std_logic;
        ram_error    : in  std_logic;

        gpio_sel     : out std_logic;
        gpio_addr    : out std_logic_vector(31 downto 0);
        gpio_wdata   : out std_logic_vector(31 downto 0);
        gpio_wstrb   : out std_logic_vector(3 downto 0);
        gpio_write   : out std_logic;
        gpio_read    : out std_logic;
        gpio_valid   : out std_logic;
        gpio_rdata   : in  std_logic_vector(31 downto 0);
        gpio_ready   : in  std_logic;
        gpio_error   : in  std_logic;

        timer_sel    : out std_logic;
        timer_addr   : out std_logic_vector(31 downto 0);
        timer_wdata  : out std_logic_vector(31 downto 0);
        timer_wstrb  : out std_logic_vector(3 downto 0);
        timer_write  : out std_logic;
        timer_read   : out std_logic;
        timer_valid  : out std_logic;
        timer_rdata  : in  std_logic_vector(31 downto 0);
        timer_ready  : in  std_logic;
        timer_error  : in  std_logic;

        uart_sel     : out std_logic;
        uart_addr    : out std_logic_vector(31 downto 0);
        uart_wdata   : out std_logic_vector(31 downto 0);
        uart_wstrb   : out std_logic_vector(3 downto 0);
        uart_write   : out std_logic;
        uart_read    : out std_logic;
        uart_valid   : out std_logic;
        uart_rdata   : in  std_logic_vector(31 downto 0);
        uart_ready   : in  std_logic;
        uart_error   : in  std_logic;

        dma_sel      : out std_logic;
        dma_addr     : out std_logic_vector(31 downto 0);
        dma_wdata    : out std_logic_vector(31 downto 0);
        dma_wstrb    : out std_logic_vector(3 downto 0);
        dma_write    : out std_logic;
        dma_read     : out std_logic;
        dma_valid    : out std_logic;
        dma_rdata    : in  std_logic_vector(31 downto 0);
        dma_ready    : in  std_logic;
        dma_error    : in  std_logic
    );
end bus_interconnect;

architecture rtl of bus_interconnect is
    signal dec_ram      : std_logic;
    signal dec_gpio     : std_logic;
    signal dec_timer    : std_logic;
    signal dec_uart     : std_logic;
    signal dec_dma      : std_logic;
    signal dec_invalid  : std_logic;
    signal ram_region   : std_logic;
begin
    dec_gpio <= '1' when (
        m_valid = '1' and
        unsigned(m_addr) >= to_unsigned(16#10#, 32) and
        unsigned(m_addr) <= to_unsigned(16#1F#, 32)
    ) else '0';

    dec_timer <= '1' when (
        m_valid = '1' and
        unsigned(m_addr) >= to_unsigned(16#20#, 32) and
        unsigned(m_addr) <= to_unsigned(16#2F#, 32)
    ) else '0';

    dec_uart <= '1' when (
        m_valid = '1' and
        unsigned(m_addr) >= to_unsigned(16#40#, 32) and
        unsigned(m_addr) <= to_unsigned(16#4F#, 32)
    ) else '0';

    dec_dma <= '1' when (
        m_valid = '1' and
        unsigned(m_addr) >= to_unsigned(16#80#, 32) and
        unsigned(m_addr) <= to_unsigned(16#9F#, 32)
    ) else '0';

    ram_region <= '1' when unsigned(m_addr) <= to_unsigned(16#3FF#, 32) else '0';

    dec_ram <= '1' when (
        m_valid = '1' and
        ram_region = '1' and
        dec_gpio = '0' and
        dec_timer = '0' and
        dec_uart = '0' and
        dec_dma = '0'
    ) else '0';

    dec_invalid <= '1' when (
        m_valid = '1' and
        dec_ram = '0' and
        dec_gpio = '0' and
        dec_timer = '0' and
        dec_uart = '0' and
        dec_dma = '0'
    ) else '0';

    ram_addr   <= m_addr;
    ram_wdata  <= m_wdata;
    ram_wstrb  <= m_wstrb;
    ram_write  <= m_write and dec_ram;
    ram_read   <= m_read  and dec_ram;
    ram_valid  <= m_valid and dec_ram;
    ram_sel    <= dec_ram;

    gpio_addr  <= m_addr;
    gpio_wdata <= m_wdata;
    gpio_wstrb <= m_wstrb;
    gpio_write <= m_write and dec_gpio;
    gpio_read  <= m_read  and dec_gpio;
    gpio_valid <= m_valid and dec_gpio;
    gpio_sel   <= dec_gpio;

    timer_addr  <= m_addr;
    timer_wdata <= m_wdata;
    timer_wstrb <= m_wstrb;
    timer_write <= m_write and dec_timer;
    timer_read  <= m_read  and dec_timer;
    timer_valid <= m_valid and dec_timer;
    timer_sel   <= dec_timer;

    uart_addr  <= m_addr;
    uart_wdata <= m_wdata;
    uart_wstrb <= m_wstrb;
    uart_write <= m_write and dec_uart;
    uart_read  <= m_read  and dec_uart;
    uart_valid <= m_valid and dec_uart;
    uart_sel   <= dec_uart;

    dma_addr   <= m_addr;
    dma_wdata  <= m_wdata;
    dma_wstrb  <= m_wstrb;
    dma_write  <= m_write and dec_dma;
    dma_read   <= m_read  and dec_dma;
    dma_valid  <= m_valid and dec_dma;
    dma_sel    <= dec_dma;

    process(
        m_valid, dec_ram, dec_gpio, dec_timer, dec_uart, dec_dma, dec_invalid,
        ram_rdata, ram_ready, ram_error,
        gpio_rdata, gpio_ready, gpio_error,
        timer_rdata, timer_ready, timer_error,
        uart_rdata, uart_ready, uart_error,
        dma_rdata, dma_ready, dma_error
    )
    begin
        m_rdata <= (others => '0');
        m_ready <= '0';
        m_error <= '0';

        if m_valid = '1' then
            if dec_ram = '1' then
                m_rdata <= ram_rdata;
                m_ready <= ram_ready;
                m_error <= ram_error;
            elsif dec_gpio = '1' then
                m_rdata <= gpio_rdata;
                m_ready <= gpio_ready;
                m_error <= gpio_error;
            elsif dec_timer = '1' then
                m_rdata <= timer_rdata;
                m_ready <= timer_ready;
                m_error <= timer_error;
            elsif dec_uart = '1' then
                m_rdata <= uart_rdata;
                m_ready <= uart_ready;
                m_error <= uart_error;
            elsif dec_dma = '1' then
                m_rdata <= dma_rdata;
                m_ready <= dma_ready;
                m_error <= dma_error;
            elsif dec_invalid = '1' then
                m_rdata <= (others => '0');
                m_ready <= '1';
                m_error <= '1';
            end if;
        end if;
    end process;
end rtl;