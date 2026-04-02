library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Memory-mapped GPIO peripheral.
-- Address map:
--  - 0x0000_0010 GPIO_OUT (RW) : bits[3:0] drive gpio_out
--  - 0x0000_0014 GPIO_IN  (RO) : bit0 reflects gpio_toggle
entity gpio is
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

        gpio_out    : out std_logic_vector(3 downto 0);
        gpio_toggle : in  std_logic
    );
end gpio;

architecture rtl of gpio is
    signal out_reg  : std_logic_vector(3 downto 0) := (others => '0');
    signal bus_hit  : std_logic;
    signal addr_hit : std_logic;
begin
    bus_hit  <= sel and valid;
    addr_hit <= '1' when (addr = x"00000010" or addr = x"00000014") else '0';

    process(clk, rst)
    begin
        if rst = '1' then
            out_reg <= (others => '0');
        elsif rising_edge(clk) then
            if bus_hit = '1' and write_en = '1' and addr = x"00000010" then
                if wstrb(0) = '1' then
                    out_reg <= wdata(3 downto 0);
                end if;
            end if;
        end if;
    end process;

    process(bus_hit, read_en, addr, out_reg, gpio_toggle)
    begin
        rdata <= (others => '0');
        if bus_hit = '1' and read_en = '1' then
            if addr = x"00000010" then
                rdata <= (31 downto 4 => '0') & out_reg;
            elsif addr = x"00000014" then
                rdata <= (31 downto 1 => '0') & gpio_toggle;
            end if;
        end if;
    end process;

    ready    <= bus_hit;
    error    <= bus_hit and (not addr_hit);
    gpio_out <= out_reg;
end rtl;
