library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- APB-like simplified single-master interconnect for memory-mapped peripherals.
-- Address map (byte addresses):
--  - 0x0000_0000 .. 0x0000_03FF : Data RAM, excluding explicit MMIO locations
--  - 0x0000_0010 : GPIO_OUT (RW)
--  - 0x0000_0014 : GPIO_IN  (RO)
--  - 0x0000_0020 : TIMER_COUNT (RO)
--  - 0x0000_0024 : TIMER_CMP   (RW)
--  - 0x0000_0028 : TIMER_CTRL  (RW)
--  - 0x0000_0040 : UART_TXDATA (WO)
--  - 0x0000_0044 : UART_STATUS (RO)
--  - 0x0000_0048 : UART_CTRL   (RW)
--  - 0x0000_004C : UART_BAUDDIV(RW)
--  - 0x0000_0080 : DMA_SRC_ADDR
--  - 0x0000_0084 : DMA_DST_ADDR
--  - 0x0000_0088 : DMA_LENGTH
--  - 0x0000_008C : DMA_CTRL
--  - 0x0000_0090 : DMA_STATUS
entity bus_interconnect is
    Port (
        -- Master side
        m_addr       : in  std_logic_vector(31 downto 0);
        m_wdata      : in  std_logic_vector(31 downto 0);
        m_wstrb      : in  std_logic_vector(3 downto 0);
        m_write      : in  std_logic;
        m_read       : in  std_logic;
        m_valid      : in  std_logic;
        m_rdata      : out std_logic_vector(31 downto 0);
        m_ready      : out std_logic;
        m_error      : out std_logic;

        -- Data RAM slave side
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

        -- GPIO slave side
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

        -- TIMER slave side
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

        -- UART slave side
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

        -- DMA slave-register side
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
    -- Decode. Slave select depends on m_valid so idle accesses do not select anything.
    dec_gpio   <= '1' when (m_valid = '1' and (m_addr = x"00000010" or m_addr = x"00000014")) else '0';
    dec_timer  <= '1' when (m_valid = '1' and (m_addr = x"00000020" or m_addr = x"00000024" or m_addr = x"00000028")) else '0';
    dec_uart   <= '1' when (m_valid = '1' and (m_addr = x"00000040" or m_addr = x"00000044" or m_addr = x"00000048" or m_addr = x"0000004C")) else '0';
    dec_dma    <= '1' when (m_valid = '1' and (m_addr = x"00000080" or m_addr = x"00000084" or m_addr = x"00000088" or m_addr = x"0000008C" or m_addr = x"00000090")) else '0';
    ram_region <= '1' when unsigned(m_addr) <= to_unsigned(16#3FF#, 32) else '0';
    dec_ram    <= '1' when (m_valid = '1' and ram_region = '1' and dec_gpio = '0' and dec_timer = '0' and dec_uart = '0' and dec_dma = '0') else '0';
    dec_invalid<= '1' when (m_valid = '1' and dec_ram = '0' and dec_gpio = '0' and dec_timer = '0' and dec_uart = '0' and dec_dma = '0') else '0';

    -- Common fanout.
    ram_addr    <= m_addr;
    ram_wdata   <= m_wdata;
    ram_wstrb   <= m_wstrb;
    ram_write   <= m_write;
    ram_read    <= m_read;
    ram_valid   <= m_valid;
    ram_sel     <= dec_ram;

    gpio_addr   <= m_addr;
    gpio_wdata  <= m_wdata;
    gpio_wstrb  <= m_wstrb;
    gpio_write  <= m_write;
    gpio_read   <= m_read;
    gpio_valid  <= m_valid;
    gpio_sel    <= dec_gpio;

    timer_addr  <= m_addr;
    timer_wdata <= m_wdata;
    timer_wstrb <= m_wstrb;
    timer_write <= m_write;
    timer_read  <= m_read;
    timer_valid <= m_valid;
    timer_sel   <= dec_timer;

    uart_addr   <= m_addr;
    uart_wdata  <= m_wdata;
    uart_wstrb  <= m_wstrb;
    uart_write  <= m_write;
    uart_read   <= m_read;
    uart_valid  <= m_valid;
    uart_sel    <= dec_uart;

    dma_addr    <= m_addr;
    dma_wdata   <= m_wdata;
    dma_wstrb   <= m_wstrb;
    dma_write   <= m_write;
    dma_read    <= m_read;
    dma_valid   <= m_valid;
    dma_sel     <= dec_dma;

    -- Master response mux.
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
