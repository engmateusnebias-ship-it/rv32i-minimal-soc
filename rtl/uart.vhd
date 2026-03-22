library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Memory-mapped UART transmitter (TX-only), 8N1, LSB-first.
-- Registers:
--  - 0x0000_0040 UART_TXDATA  (WO)
--  - 0x0000_0044 UART_STATUS  (RO) bit0=tx_ready, bit1=tx_busy
--  - 0x0000_0048 UART_CTRL    (RW) bit0=enable
--  - 0x0000_004C UART_BAUDDIV (RW) baud tick every bauddiv+1 clocks
entity uart is
    Port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Slave bus interface
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
    signal enable_reg    : std_logic := '0';
    signal bauddiv_reg   : unsigned(31 downto 0) := (others => '0');
    signal baud_cnt      : unsigned(31 downto 0) := (others => '0');
    signal shift_reg     : std_logic_vector(9 downto 0) := (others => '1');
    signal bits_left     : integer range 0 to 10 := 0;
    signal tx_busy_reg   : std_logic := '0';
    signal tx_line_reg   : std_logic := '1';
    signal bus_hit       : std_logic;
    signal addr_hit      : std_logic;
    signal tx_write_req  : std_logic;
    signal tx_write_ok   : std_logic;
    signal invalid_access: std_logic;
begin
    bus_hit      <= sel and valid;
    addr_hit     <= '1' when (addr = x"00000040" or addr = x"00000044" or addr = x"00000048" or addr = x"0000004C") else '0';
    tx_write_req <= '1' when (bus_hit = '1' and write_en = '1' and addr = x"00000040") else '0';
    tx_write_ok  <= '1' when (tx_write_req = '1' and enable_reg = '1' and tx_busy_reg = '0' and wstrb(0) = '1') else '0';

    invalid_access <= '1' when (
                        bus_hit = '1' and (
                            addr_hit = '0' or
                            (addr = x"00000040" and read_en = '1') or
                            (addr = x"00000044" and write_en = '1') or
                            (addr = x"00000040" and write_en = '1' and tx_write_ok = '0')
                        )
                      ) else '0';

    process(clk, rst)
    begin
        if rst = '1' then
            enable_reg  <= '0';
            bauddiv_reg <= (others => '0');
            baud_cnt    <= (others => '0');
            shift_reg   <= (others => '1');
            bits_left   <= 0;
            tx_busy_reg <= '0';
            tx_line_reg <= '1';
        elsif rising_edge(clk) then
            -- Register writes
            if bus_hit = '1' and write_en = '1' then
                if addr = x"00000048" and wstrb(0) = '1' then
                    enable_reg <= wdata(0);
                elsif addr = x"0000004C" and wstrb = "1111" then
                    bauddiv_reg <= unsigned(wdata);
                elsif tx_write_ok = '1' then
                    shift_reg   <= '1' & wdata(7 downto 0) & '0';
                    bits_left   <= 10;
                    tx_busy_reg <= '1';
                    tx_line_reg <= '0';
                    baud_cnt    <= bauddiv_reg;
                end if;
            end if;

            -- TX engine
            if tx_busy_reg = '1' then
                if baud_cnt = 0 then
                    if bits_left = 1 then
                        tx_busy_reg <= '0';
                        bits_left   <= 0;
                        tx_line_reg <= '1';
                    else
                        tx_line_reg <= shift_reg(1);
                        shift_reg   <= '1' & shift_reg(9 downto 1);
                        bits_left   <= bits_left - 1;
                        baud_cnt    <= bauddiv_reg;
                    end if;
                else
                    baud_cnt <= baud_cnt - 1;
                end if;
            end if;
        end if;
    end process;

    process(bus_hit, read_en, addr, enable_reg, tx_busy_reg, bauddiv_reg)
        variable status_reg : std_logic_vector(31 downto 0);
        variable ctrl_reg   : std_logic_vector(31 downto 0);
    begin
        rdata <= (others => '0');

        status_reg := (others => '0');
        status_reg(0) := not tx_busy_reg;
        status_reg(1) := tx_busy_reg;

        ctrl_reg := (others => '0');
        ctrl_reg(0) := enable_reg;

        if bus_hit = '1' and read_en = '1' then
            if addr = x"00000044" then
                rdata <= status_reg;
            elsif addr = x"00000048" then
                rdata <= ctrl_reg;
            elsif addr = x"0000004C" then
                rdata <= std_logic_vector(bauddiv_reg);
            end if;
        end if;
    end process;

    ready   <= bus_hit;
    error   <= invalid_access;
    uart_tx <= tx_line_reg;
end rtl;
