library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- DMA v1:
-- - Single channel
-- - Word-based transfers only
-- - RAM-to-RAM transfers
-- - Start is a write pulse
-- - done/error are sticky until next valid start
-- - irq is a one-cycle pulse on successful completion when irq_enable=1
entity dma is
    Port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Slave bus interface (CPU programs the DMA registers)
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

        -- Master bus interface (DMA becomes the active master while busy)
        m_addr      : out std_logic_vector(31 downto 0);
        m_wdata     : out std_logic_vector(31 downto 0);
        m_wstrb     : out std_logic_vector(3 downto 0);
        m_write     : out std_logic;
        m_read      : out std_logic;
        m_valid     : out std_logic;
        m_rdata     : in  std_logic_vector(31 downto 0);
        m_ready     : in  std_logic;
        m_error     : in  std_logic;

        active_o    : out std_logic;
        irq         : out std_logic
    );
end dma;

architecture rtl of dma is
    type dma_state_t is (IDLE, READ_REQ, WRITE_REQ);
    signal state            : dma_state_t := IDLE;

    signal src_reg          : std_logic_vector(31 downto 0) := (others => '0');
    signal dst_reg          : std_logic_vector(31 downto 0) := (others => '0');
    signal len_reg          : unsigned(31 downto 0) := (others => '0');
    signal irq_enable_reg   : std_logic := '0';

    signal cur_src          : std_logic_vector(31 downto 0) := (others => '0');
    signal cur_dst          : std_logic_vector(31 downto 0) := (others => '0');
    signal remaining_words  : unsigned(31 downto 0) := (others => '0');
    signal data_latch       : std_logic_vector(31 downto 0) := (others => '0');

    signal done_reg         : std_logic := '0';
    signal error_reg        : std_logic := '0';
    signal irq_pulse        : std_logic := '0';

    signal bus_hit          : std_logic;
    signal addr_hit         : std_logic;
    signal start_pulse      : std_logic;

    signal master_addr      : std_logic_vector(31 downto 0);
    signal master_wdata     : std_logic_vector(31 downto 0);
    signal master_wstrb     : std_logic_vector(3 downto 0);
    signal master_write     : std_logic;
    signal master_read      : std_logic;
    signal master_valid     : std_logic;
    signal status_busy      : std_logic;

    constant DMA_SRC_ADDR_C    : std_logic_vector(31 downto 0) := x"00000080";
    constant DMA_DST_ADDR_C    : std_logic_vector(31 downto 0) := x"00000084";
    constant DMA_LENGTH_ADDR_C : std_logic_vector(31 downto 0) := x"00000088";
    constant DMA_CTRL_ADDR_C   : std_logic_vector(31 downto 0) := x"0000008C";
    constant DMA_STATUS_ADDR_C : std_logic_vector(31 downto 0) := x"00000090";
begin
    bus_hit     <= sel and valid;
    addr_hit    <= '1' when (addr = DMA_SRC_ADDR_C or addr = DMA_DST_ADDR_C or addr = DMA_LENGTH_ADDR_C or
                              addr = DMA_CTRL_ADDR_C or addr = DMA_STATUS_ADDR_C) else '0';
    start_pulse <= '1' when (bus_hit = '1' and write_en = '1' and addr = DMA_CTRL_ADDR_C and wstrb(0) = '1' and wdata(0) = '1') else '0';

    status_busy <= '1' when state /= IDLE else '0';

    process(clk, rst)
        variable cfg_ok : boolean;
        variable next_rem : unsigned(31 downto 0);
    begin
        if rst = '1' then
            state           <= IDLE;
            src_reg         <= (others => '0');
            dst_reg         <= (others => '0');
            len_reg         <= (others => '0');
            irq_enable_reg  <= '0';
            cur_src         <= (others => '0');
            cur_dst         <= (others => '0');
            remaining_words <= (others => '0');
            data_latch      <= (others => '0');
            done_reg        <= '0';
            error_reg       <= '0';
            irq_pulse       <= '0';
        elsif rising_edge(clk) then
            irq_pulse <= '0';

            -- Register programming. These writes are accepted while idle.
            if bus_hit = '1' and write_en = '1' and state = IDLE then
                if addr = DMA_SRC_ADDR_C and wstrb = "1111" then
                    src_reg <= wdata;
                elsif addr = DMA_DST_ADDR_C and wstrb = "1111" then
                    dst_reg <= wdata;
                elsif addr = DMA_LENGTH_ADDR_C and wstrb = "1111" then
                    len_reg <= unsigned(wdata);
                elsif addr = DMA_CTRL_ADDR_C and wstrb(0) = '1' then
                    irq_enable_reg <= wdata(1);
                end if;
            elsif bus_hit = '1' and write_en = '1' and addr = DMA_CTRL_ADDR_C and wstrb(0) = '1' then
                -- While busy, allow irq_enable to be updated only.
                irq_enable_reg <= wdata(1);
            end if;

            -- Handle start pulse.
            if start_pulse = '1' then
                cfg_ok := (state = IDLE) and
                          (len_reg /= 0) and
                          (src_reg(1 downto 0) = "00") and
                          (dst_reg(1 downto 0) = "00");

                done_reg  <= '0';
                error_reg <= '0';

                if cfg_ok then
                    cur_src         <= src_reg;
                    cur_dst         <= dst_reg;
                    remaining_words <= len_reg;
                    state           <= READ_REQ;
                else
                    error_reg <= '1';
                end if;
            else
                case state is
                    when IDLE =>
                        null;

                    when READ_REQ =>
                        if master_valid = '1' and m_ready = '1' then
                            if m_error = '1' then
                                state     <= IDLE;
                                error_reg <= '1';
                            else
                                data_latch <= m_rdata;
                                state      <= WRITE_REQ;
                            end if;
                        end if;

                    when WRITE_REQ =>
                        if master_valid = '1' and m_ready = '1' then
                            if m_error = '1' then
                                state     <= IDLE;
                                error_reg <= '1';
                            else
                                if remaining_words = to_unsigned(1, remaining_words'length) then
                                    state    <= IDLE;
                                    done_reg <= '1';
                                    if irq_enable_reg = '1' then
                                        irq_pulse <= '1';
                                    end if;
                                else
                                    cur_src <= std_logic_vector(unsigned(cur_src) + to_unsigned(4, 32));
                                    cur_dst <= std_logic_vector(unsigned(cur_dst) + to_unsigned(4, 32));
                                    next_rem := remaining_words - to_unsigned(1, remaining_words'length);
                                    remaining_words <= next_rem;
                                    state   <= READ_REQ;
                                end if;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- Slave readback.
    process(bus_hit, read_en, addr, src_reg, dst_reg, len_reg, irq_enable_reg, status_busy, done_reg, error_reg)
        variable ctrl_v   : std_logic_vector(31 downto 0);
        variable status_v : std_logic_vector(31 downto 0);
    begin
        rdata    <= (others => '0');
        ctrl_v   := (others => '0');
        status_v := (others => '0');

        ctrl_v(1)   := irq_enable_reg;
        status_v(0) := status_busy;
        status_v(1) := done_reg;
        status_v(2) := error_reg;

        if bus_hit = '1' and read_en = '1' then
            if addr = DMA_SRC_ADDR_C then
                rdata <= src_reg;
            elsif addr = DMA_DST_ADDR_C then
                rdata <= dst_reg;
            elsif addr = DMA_LENGTH_ADDR_C then
                rdata <= std_logic_vector(len_reg);
            elsif addr = DMA_CTRL_ADDR_C then
                rdata <= ctrl_v;
            elsif addr = DMA_STATUS_ADDR_C then
                rdata <= status_v;
            end if;
        end if;
    end process;

    -- Slave response.
    ready <= bus_hit;
    error <= bus_hit and (not addr_hit);

    -- Master outputs.
    master_addr  <= cur_src when state = READ_REQ else cur_dst;
    master_wdata <= data_latch;
    master_wstrb <= "1111";
    master_write <= '1' when state = WRITE_REQ else '0';
    master_read  <= '1' when state = READ_REQ  else '0';
    master_valid <= '1' when (state = READ_REQ or state = WRITE_REQ) else '0';

    m_addr   <= master_addr;
    m_wdata  <= master_wdata;
    m_wstrb  <= master_wstrb;
    m_write  <= master_write;
    m_read   <= master_read;
    m_valid  <= master_valid;

    active_o <= status_busy;
    irq      <= irq_pulse;
end rtl;
