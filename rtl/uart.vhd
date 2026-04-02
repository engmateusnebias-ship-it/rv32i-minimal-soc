library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- UART v2 with two clock domains:
--   * core_clk/core_rst    : register interface and bus-facing logic
--   * periph_clk/periph_rst: TX engine
--
-- CDC method:
--   * tx request crosses core->periph using a toggle handshake
--   * ack crosses periph->core using a toggle handshake
--   * tx data and bauddiv shadow are staged in core domain and held stable
--     until the request is accepted in the peripheral domain
--
-- Memory map:
--   0x0000_0040 UART_TXDATA  (WO)
--   0x0000_0044 UART_STATUS  (RO) bit0=tx_ready, bit1=tx_busy
--   0x0000_0048 UART_CTRL    (RW) bit0=enable
--   0x0000_004C UART_BAUDDIV (RW)
entity uart is
    Port (
        core_clk    : in  std_logic;
        core_rst    : in  std_logic;
        periph_clk  : in  std_logic;
        periph_rst  : in  std_logic;

        -- Slave bus interface (core clock domain)
        sel         : in  std_logic;
        addr        : in  std_logic_vector(31 downto 0);
        wdata       : in  std_logic_vector(31 downto 0);
        wstrb       : in  std_logic_vector(3 downto 0);
        write_en    : in  std_logic;
        read_en     : in  std_logic;
        valid       : in  std_logic;
        rdata       : out std_logic_vector(31 downto 0);
        ready       : out std_logic;
        error       : out std_logic;

        uart_tx     : out std_logic
    );
end uart;

architecture rtl of uart is
    constant UART_TXDATA_ADDR_C  : std_logic_vector(31 downto 0) := x"00000040";
    constant UART_STATUS_ADDR_C  : std_logic_vector(31 downto 0) := x"00000044";
    constant UART_CTRL_ADDR_C    : std_logic_vector(31 downto 0) := x"00000048";
    constant UART_BAUDDIV_ADDR_C : std_logic_vector(31 downto 0) := x"0000004C";

    signal bus_hit          : std_logic;
    signal access_req       : std_logic;
    signal addr_hit         : std_logic;

    -- Core-domain registers
    signal enable_reg         : std_logic := '0';
    signal bauddiv_reg        : std_logic_vector(31 downto 0) := (others => '0');

    signal tx_data_stage      : std_logic_vector(7 downto 0)  := (others => '0');
    signal bauddiv_stage      : std_logic_vector(31 downto 0) := (others => '0');

    signal tx_req_toggle_core : std_logic := '0';
    signal tx_ack_meta_core   : std_logic := '0';
    signal tx_ack_sync_core   : std_logic := '0';
    signal tx_ack_seen_core   : std_logic := '0';

    signal tx_busy_meta_core  : std_logic := '0';
    signal tx_busy_sync_core  : std_logic := '0';

    signal req_pending_core   : std_logic := '0';
    signal tx_busy_core       : std_logic;
    signal tx_ready_core      : std_logic;

    signal illegal_access     : std_logic;

    -- Peripheral-domain CDC and TX engine
    signal tx_req_meta_periph   : std_logic := '0';
    signal tx_req_sync_periph   : std_logic := '0';
    signal tx_req_seen_periph   : std_logic := '0';
    signal tx_ack_toggle_periph : std_logic := '0';

    signal tx_busy_periph     : std_logic := '0';
    signal uart_tx_reg        : std_logic := '1';

    signal bit_index          : integer range 0 to 9 := 0;
    signal baud_counter       : unsigned(31 downto 0) := (others => '0');
    signal bauddiv_latched    : unsigned(31 downto 0) := (others => '0');
    signal tx_shift_data      : std_logic_vector(7 downto 0) := (others => '0');
begin
    bus_hit    <= sel and valid;
    access_req <= bus_hit and (read_en or write_en);
    addr_hit   <= '1' when (addr = UART_TXDATA_ADDR_C or addr = UART_STATUS_ADDR_C or
                            addr = UART_CTRL_ADDR_C   or addr = UART_BAUDDIV_ADDR_C) else '0';

    -- Make the core-visible status deterministic while either domain is in reset.
    tx_busy_core  <= '0' when (core_rst = '1' or periph_rst = '1') else (req_pending_core or tx_busy_sync_core);
    tx_ready_core <= not tx_busy_core;

    -- Local access error semantics are only meaningful for a real access.
    illegal_access <= '1' when (
                          (access_req = '1' and addr_hit = '0') or
                          (access_req = '1' and read_en  = '1' and addr = UART_TXDATA_ADDR_C) or
                          (access_req = '1' and write_en = '1' and addr = UART_STATUS_ADDR_C) or
                          (access_req = '1' and write_en = '1' and addr = UART_TXDATA_ADDR_C and
                               (enable_reg = '0' or tx_busy_core = '1'))
                      ) else '0';

    -- Core-domain logic
    process(core_clk, core_rst)
    begin
        if core_rst = '1' then
            enable_reg         <= '0';
            bauddiv_reg        <= (others => '0');
            tx_data_stage      <= (others => '0');
            bauddiv_stage      <= (others => '0');
            tx_req_toggle_core <= '0';
            tx_ack_meta_core   <= '0';
            tx_ack_sync_core   <= '0';
            tx_ack_seen_core   <= '0';
            tx_busy_meta_core  <= '0';
            tx_busy_sync_core  <= '0';
            req_pending_core   <= '0';
        elsif rising_edge(core_clk) then
            -- Synchronize ack toggle from periph domain
            tx_ack_meta_core <= tx_ack_toggle_periph;
            tx_ack_sync_core <= tx_ack_meta_core;

            -- Synchronize tx_busy level from periph domain
            tx_busy_meta_core <= tx_busy_periph;
            tx_busy_sync_core <= tx_busy_meta_core;

            -- Clear pending flag when ack toggle changes
            if tx_ack_sync_core /= tx_ack_seen_core then
                tx_ack_seen_core <= tx_ack_sync_core;
                req_pending_core <= '0';
            end if;

            -- Register writes are only acted upon for real, legal accesses
            if access_req = '1' and write_en = '1' and illegal_access = '0' then
                if addr = UART_CTRL_ADDR_C and wstrb(0) = '1' then
                    enable_reg <= wdata(0);
                elsif addr = UART_BAUDDIV_ADDR_C and wstrb = "1111" then
                    bauddiv_reg <= wdata;
                elsif addr = UART_TXDATA_ADDR_C and wstrb(0) = '1' then
                    tx_data_stage      <= wdata(7 downto 0);
                    bauddiv_stage      <= bauddiv_reg;
                    tx_req_toggle_core <= not tx_req_toggle_core;
                    req_pending_core   <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Peripheral-domain TX engine with request/ack CDC
    process(periph_clk, periph_rst)
        variable baud_limit : unsigned(31 downto 0);
    begin
        if periph_rst = '1' then
            tx_req_meta_periph   <= '0';
            tx_req_sync_periph   <= '0';
            tx_req_seen_periph   <= '0';
            tx_ack_toggle_periph <= '0';
            tx_busy_periph       <= '0';
            uart_tx_reg          <= '1';
            bit_index            <= 0;
            baud_counter         <= (others => '0');
            bauddiv_latched      <= (others => '0');
            tx_shift_data        <= (others => '0');
        elsif rising_edge(periph_clk) then
            tx_req_meta_periph <= tx_req_toggle_core;
            tx_req_sync_periph <= tx_req_meta_periph;

            -- Accept a new request only when idle
            if tx_busy_periph = '0' then
                uart_tx_reg <= '1';
                if tx_req_sync_periph /= tx_req_seen_periph then
                    tx_req_seen_periph   <= tx_req_sync_periph;
                    tx_ack_toggle_periph <= not tx_ack_toggle_periph;

                    -- Data and bauddiv stage are held stable by core until ack is seen
                    tx_shift_data   <= tx_data_stage;
                    bauddiv_latched <= unsigned(bauddiv_stage);
                    baud_counter    <= (others => '0');
                    bit_index       <= 0;
                    tx_busy_periph  <= '1';

                    -- Start bit
                    uart_tx_reg <= '0';
                end if;
            else
                baud_limit := bauddiv_latched;

                if baud_counter = baud_limit then
                    baud_counter <= (others => '0');

                    if bit_index < 8 then
                        uart_tx_reg <= tx_shift_data(bit_index);
                        bit_index   <= bit_index + 1;
                    elsif bit_index = 8 then
                        uart_tx_reg <= '1';  -- stop bit
                        bit_index   <= 9;
                    else
                        uart_tx_reg    <= '1';
                        tx_busy_periph <= '0';
                        bit_index      <= 0;
                    end if;
                else
                    baud_counter <= baud_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- Readback
    process(bus_hit, access_req, read_en, addr, enable_reg, bauddiv_reg, tx_ready_core, tx_busy_core)
        variable status_v : std_logic_vector(31 downto 0);
        variable ctrl_v   : std_logic_vector(31 downto 0);
    begin
        rdata    <= (others => '0');
        status_v := (others => '0');
        ctrl_v   := (others => '0');

        status_v(0) := tx_ready_core;
        status_v(1) := tx_busy_core;
        ctrl_v(0)   := enable_reg;

        if access_req = '1' and read_en = '1' and addr_hit = '1' then
            if addr = UART_STATUS_ADDR_C then
                rdata <= status_v;
            elsif addr = UART_CTRL_ADDR_C then
                rdata <= ctrl_v;
            elsif addr = UART_BAUDDIV_ADDR_C then
                rdata <= bauddiv_reg;
            else
                rdata <= (others => '0');
            end if;
        end if;
    end process;

    ready   <= access_req;
    error   <= access_req and illegal_access;
    uart_tx <= uart_tx_reg;
end rtl;
