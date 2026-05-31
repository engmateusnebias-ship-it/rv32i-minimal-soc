library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity instruction_memory is
    generic (
        -- Path to the program image. Default works for GHDL/CI (file at the
        -- working directory). Vivado synthesis overrides this with an absolute
        -- path because its run directory differs (.runs/synth_1).
        INIT_FILE : string := "program.mem"
    );
    Port (
        addr        : in  std_logic_vector(31 downto 0);     -- Address from PC
        instruction : out std_logic_vector(31 downto 0)      -- Instruction at that address
    );
end instruction_memory;

architecture rtl of instruction_memory is

    type mem_array is array (0 to 255) of std_logic_vector(31 downto 0);
    signal rom : mem_array := (others => (others => '0'));

    signal word_addr : integer range 0 to 255;

    -- File loading
    impure function load_program return mem_array is
        file mem_file : text open read_mode is INIT_FILE;
        variable line_buf : line;
        variable mem      : mem_array := (others => (others => '0'));
        variable i        : integer := 0;
        variable data     : std_logic_vector(31 downto 0);
    begin
        while not endfile(mem_file) loop
            readline(mem_file, line_buf);
            hread(line_buf, data);
            if i <= 255 then
                mem(i) := data;
                i := i + 1;
            end if;
        end loop;
        return mem;
    end function;

begin

    -- Load program at elaboration time
    rom <= load_program;

    -- Convert byte address to word index (word-aligned)
    word_addr <= to_integer(unsigned(addr(9 downto 2)));

    -- Asynchronous read
    instruction <= rom(word_addr);

end rtl;
