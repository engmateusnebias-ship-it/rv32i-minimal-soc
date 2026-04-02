library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Simple memory-mapped timer.
-- Registers (byte addresses):
--  - 0x0000_0020 TIMER_COUNT (RO): increments every clock when enabled
--  - 0x0000_0024 TIMER_CMP   (RW): compare value
--  - 0x0000_0028 TIMER_CTRL  (RW): bit0=enable, bit1=irq_enable, bit2=clear (write pulse)
--
-- Official semantics:
--  - TIMER_COUNT increments only when enable=1
--  - TIMER_CMP is a normal RW compare register
--  - TIMER_CTRL.clear is write-only pulse semantics; it always reads back as 0
--  - irq is a one-cycle pulse generated when the updated count reaches cmp
--  - reaching cmp does not stop or clear the timer automatically
entity timer is
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

        irq         : out std_logic
    );
end timer;

architecture rtl of timer is
    signal count_reg : unsigned(31 downto 0) := (others => '0');
    signal cmp_reg   : unsigned(31 downto 0) := (others => '0');
    signal enable    : std_logic := '0';
    signal irq_en    : std_logic := '0';
    signal irq_pulse : std_logic := '0';
    signal bus_hit   : std_logic;
    signal addr_hit  : std_logic;
begin
    bus_hit  <= sel and valid;
    addr_hit <= '1' when (addr = x"00000020" or addr = x"00000024" or addr = x"00000028") else '0';

    process(clk, rst)
        variable next_count  : unsigned(31 downto 0);
        variable next_cmp    : unsigned(31 downto 0);
        variable next_enable : std_logic;
        variable next_irq_en : std_logic;
    begin
        if rst = '1' then
            count_reg <= (others => '0');
            cmp_reg   <= (others => '0');
            enable    <= '0';
            irq_en    <= '0';
            irq_pulse <= '0';
        elsif rising_edge(clk) then
            -- Default: IRQ is a one-cycle pulse.
            irq_pulse <= '0';

            -- Start from current state.
            next_count  := count_reg;
            next_cmp    := cmp_reg;
            next_enable := enable;
            next_irq_en := irq_en;

            -- TIMER_CTRL write.
            -- clear has write-pulse semantics and is not stored.
            if bus_hit = '1' and write_en = '1' and addr = x"00000028" and wstrb(0) = '1' then
                next_enable := wdata(0);
                next_irq_en := wdata(1);

                if wdata(2) = '1' then
                    next_count := (others => '0');
                end if;
            end if;

            -- TIMER_CMP write.
            if bus_hit = '1' and write_en = '1' and addr = x"00000024" and wstrb = "1111" then
                next_cmp := unsigned(wdata);
            end if;

            -- Increment when enabled, using the updated enable value.
            if next_enable = '1' then
                next_count := next_count + 1;
            end if;

            -- Generate one-cycle pulse when the updated count reaches the updated compare value.
            if next_enable = '1' and next_irq_en = '1' and next_count = next_cmp then
                irq_pulse <= '1';
            end if;

            -- Commit state.
            count_reg <= next_count;
            cmp_reg   <= next_cmp;
            enable    <= next_enable;
            irq_en    <= next_irq_en;
        end if;
    end process;

    process(bus_hit, read_en, addr, count_reg, cmp_reg, enable, irq_en)
        variable ctrl : std_logic_vector(31 downto 0);
    begin
        rdata <= (others => '0');
        ctrl := (others => '0');
        ctrl(0) := enable;
        ctrl(1) := irq_en;
        -- ctrl(2) always reads back as 0 because clear is write-pulse only.

        if bus_hit = '1' and read_en = '1' then
            if addr = x"00000020" then
                rdata <= std_logic_vector(count_reg);
            elsif addr = x"00000024" then
                rdata <= std_logic_vector(cmp_reg);
            elsif addr = x"00000028" then
                rdata <= ctrl;
            end if;
        end if;
    end process;

    ready <= bus_hit;
    error <= bus_hit and (not addr_hit);
    irq   <= irq_pulse;
end rtl;
