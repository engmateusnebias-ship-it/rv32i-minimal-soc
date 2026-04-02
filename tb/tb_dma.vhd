library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_dma is
end tb_dma;

architecture tb of tb_dma is
    constant CLK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';

    -- CPU-style master controlled by the testbench
    signal cpu_addr    : std_logic_vector(31 downto 0) := (others => '0');
    signal cpu_wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal cpu_wstrb   : std_logic_vector(3 downto 0)  := (others => '0');
    signal cpu_write   : std_logic := '0';
    signal cpu_read    : std_logic := '0';
    signal cpu_valid   : std_logic := '0';
    signal cpu_rdata   : std_logic_vector(31 downto 0);
    signal cpu_ready   : std_logic;
    signal cpu_error   : std_logic;

    -- DMA master bus
    signal dma_m_addr  : std_logic_vector(31 downto 0);
    signal dma_m_wdata : std_logic_vector(31 downto 0);
    signal dma_m_wstrb : std_logic_vector(3 downto 0);
    signal dma_m_write : std_logic;
    signal dma_m_read  : std_logic;
    signal dma_m_valid : std_logic;
    signal dma_m_rdata : std_logic_vector(31 downto 0);
    signal dma_m_ready : std_logic;
    signal dma_m_error : std_logic;
    signal dma_active  : std_logic;
    signal dma_irq     : std_logic;

    -- Selected master bus
    signal bus_addr    : std_logic_vector(31 downto 0);
    signal bus_wdata   : std_logic_vector(31 downto 0);
    signal bus_wstrb   : std_logic_vector(3 downto 0);
    signal bus_write   : std_logic;
    signal bus_read    : std_logic;
    signal bus_valid   : std_logic;
    signal bus_rdata   : std_logic_vector(31 downto 0);
    signal bus_ready   : std_logic;
    signal bus_error   : std_logic;

    -- Interconnect slave signals
    signal ram_sel     : std_logic;
    signal ram_addr    : std_logic_vector(31 downto 0);
    signal ram_wdata   : std_logic_vector(31 downto 0);
    signal ram_wstrb   : std_logic_vector(3 downto 0);
    signal ram_write   : std_logic;
    signal ram_read    : std_logic;
    signal ram_valid   : std_logic;
    signal ram_rdata   : std_logic_vector(31 downto 0);
    signal ram_ready   : std_logic;
    signal ram_error   : std_logic;

    signal gpio_sel    : std_logic;
    signal gpio_addr   : std_logic_vector(31 downto 0);
    signal gpio_wdata  : std_logic_vector(31 downto 0);
    signal gpio_wstrb  : std_logic_vector(3 downto 0);
    signal gpio_write  : std_logic;
    signal gpio_read   : std_logic;
    signal gpio_valid  : std_logic;
    signal gpio_rdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal gpio_ready  : std_logic := '1';
    signal gpio_error  : std_logic := '0';

    signal timer_sel   : std_logic;
    signal timer_addr  : std_logic_vector(31 downto 0);
    signal timer_wdata : std_logic_vector(31 downto 0);
    signal timer_wstrb : std_logic_vector(3 downto 0);
    signal timer_write : std_logic;
    signal timer_read  : std_logic;
    signal timer_valid : std_logic;
    signal timer_rdata : std_logic_vector(31 downto 0) := (others => '0');
    signal timer_ready : std_logic := '1';
    signal timer_error : std_logic := '0';

    signal uart_sel    : std_logic;
    signal uart_addr   : std_logic_vector(31 downto 0);
    signal uart_wdata  : std_logic_vector(31 downto 0);
    signal uart_wstrb  : std_logic_vector(3 downto 0);
    signal uart_write  : std_logic;
    signal uart_read   : std_logic;
    signal uart_valid  : std_logic;
    signal uart_rdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal uart_ready  : std_logic := '1';
    signal uart_error  : std_logic := '0';

    signal dma_sel     : std_logic;
    signal dma_addr    : std_logic_vector(31 downto 0);
    signal dma_wdata   : std_logic_vector(31 downto 0);
    signal dma_wstrb   : std_logic_vector(3 downto 0);
    signal dma_write_s : std_logic;
    signal dma_read_s  : std_logic;
    signal dma_valid_s : std_logic;
    signal dma_rdata   : std_logic_vector(31 downto 0);
    signal dma_ready_s : std_logic;
    signal dma_error_s : std_logic;

    signal irq_seen    : std_logic := '0';

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
    clk_gen: process
    begin
        while true loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
    end process;

    irq_mon: process(clk)
    begin
        if rising_edge(clk) then
            if dma_irq = '1' then
                irq_seen <= '1';
            end if;
        end if;
    end process;

    -- Master mux identical to soc_top policy.
    bus_addr  <= dma_m_addr  when dma_active = '1' else cpu_addr;
    bus_wdata <= dma_m_wdata when dma_active = '1' else cpu_wdata;
    bus_wstrb <= dma_m_wstrb when dma_active = '1' else cpu_wstrb;
    bus_write <= dma_m_write when dma_active = '1' else cpu_write;
    bus_read  <= dma_m_read  when dma_active = '1' else cpu_read;
    bus_valid <= dma_m_valid when dma_active = '1' else cpu_valid;

    cpu_rdata   <= bus_rdata;
    cpu_ready   <= bus_ready;
    cpu_error   <= bus_error;
    dma_m_rdata <= bus_rdata;
    dma_m_ready <= bus_ready;
    dma_m_error <= bus_error;

    bus_i: entity work.bus_interconnect
        port map (
            m_addr      => bus_addr,
            m_wdata     => bus_wdata,
            m_wstrb     => bus_wstrb,
            m_write     => bus_write,
            m_read      => bus_read,
            m_valid     => bus_valid,
            m_rdata     => bus_rdata,
            m_ready     => bus_ready,
            m_error     => bus_error,

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
            dma_write   => dma_write_s,
            dma_read    => dma_read_s,
            dma_valid   => dma_valid_s,
            dma_rdata   => dma_rdata,
            dma_ready   => dma_ready_s,
            dma_error   => dma_error_s
        );

    ram_i: entity work.data_memory
        port map (
            clk      => clk,
            rst      => rst,
            sel      => ram_sel,
            addr     => ram_addr,
            wdata    => ram_wdata,
            wstrb    => ram_wstrb,
            write_en => ram_write,
            read_en  => ram_read,
            valid    => ram_valid,
            rdata    => ram_rdata,
            ready    => ram_ready,
            error    => ram_error
        );

    dma_i: entity work.dma
        port map (
            clk      => clk,
            rst      => rst,
            sel      => dma_sel,
            addr     => dma_addr,
            wdata    => dma_wdata,
            wstrb    => dma_wstrb,
            write_en => dma_write_s,
            read_en  => dma_read_s,
            valid    => dma_valid_s,
            rdata    => dma_rdata,
            ready    => dma_ready_s,
            error    => dma_error_s,
            m_addr   => dma_m_addr,
            m_wdata  => dma_m_wdata,
            m_wstrb  => dma_m_wstrb,
            m_write  => dma_m_write,
            m_read   => dma_m_read,
            m_valid  => dma_m_valid,
            m_rdata  => dma_m_rdata,
            m_ready  => dma_m_ready,
            m_error  => dma_m_error,
            active_o => dma_active,
            irq      => dma_irq
        );

    stim: process
        variable tmp : std_logic_vector(31 downto 0);
    begin
        tick(2);
        rst <= '0';
        tick(1);

        -- Preload source RAM and clear destination RAM.
        cpu_addr  <= x"00000100"; cpu_wdata <= x"11223344"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_read <= '0'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"00000104"; cpu_wdata <= x"55667788"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"00000140"; cpu_wdata <= x"00000000"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"00000144"; cpu_wdata <= x"00000000"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        -- Program DMA registers.
        cpu_addr  <= x"00000080"; cpu_wdata <= x"00000100"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"00000084"; cpu_wdata <= x"00000140"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"00000088"; cpu_wdata <= x"00000002"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"0000008C"; cpu_wdata <= x"00000002"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        -- Start DMA.
        cpu_addr  <= x"0000008C"; cpu_wdata <= x"00000003"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        -- Wait for DMA takeover to finish.
        while dma_active = '1' loop
            tick(1);
        end loop;
        tick(1);

        -- Status after completion.
        cpu_addr  <= x"00000090"; cpu_write <= '0'; cpu_read <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU read returned error");
        tmp := cpu_rdata;
        cpu_read <= '0'; cpu_valid <= '0';

        check(tmp(0) = '0', "DMA busy should be 0 after completion");
        check(tmp(1) = '1', "DMA done should be 1 after completion");
        check(tmp(2) = '0', "DMA error should be 0 after successful completion");
        check(irq_seen = '1', "DMA IRQ pulse was not observed");

        -- Verify destination RAM content.
        cpu_addr  <= x"00000140"; cpu_write <= '0'; cpu_read <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU read returned error");
        tmp := cpu_rdata;
        cpu_read <= '0'; cpu_valid <= '0';
        check(tmp = x"11223344", "DMA first destination word mismatch");

        cpu_addr  <= x"00000144"; cpu_write <= '0'; cpu_read <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU read returned error");
        tmp := cpu_rdata;
        cpu_read <= '0'; cpu_valid <= '0';
        check(tmp = x"55667788", "DMA second destination word mismatch");

        -- Invalid configuration: length=0 must set error and not start.
        cpu_addr  <= x"00000088"; cpu_wdata <= x"00000000"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"0000008C"; cpu_wdata <= x"00000003"; cpu_wstrb <= "1111"; cpu_write <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU write returned error");
        cpu_write <= '0'; cpu_wstrb <= (others => '0'); cpu_valid <= '0';

        cpu_addr  <= x"00000090"; cpu_write <= '0'; cpu_read <= '1'; cpu_valid <= '1';
        loop
            tick(1);
            exit when cpu_ready = '1';
        end loop;
        wait for 1 ns;
        check(cpu_error = '0', "CPU read returned error");
        tmp := cpu_rdata;
        cpu_read <= '0'; cpu_valid <= '0';

        check(tmp(0) = '0', "DMA should not become busy for length=0");
        check(tmp(2) = '1', "DMA should set error for length=0");

        report "tb_dma PASSED" severity warning;
        wait;
    end process;
end tb;
