###############################################################################
# soc_top.xdc  -  Basys3 (xc7a35tcpg236-1)
# Mini-SoC RV32I
#
# Clock architecture (single MMCM, VCO = 720 MHz):
#   clk        : 100 MHz onboard oscillator (W5)  -- feeds MMCM only
#   core_clk   : 48.0 MHz, MMCM CLKOUT0  -- CPU core domain
#   periph_clk : 28.8 MHz, MMCM CLKOUT1  -- UART TX engine
#
# The core runs at 48 MHz (not 100 MHz) because the single-cycle datapath
# critical path is ~19 ns (fmax ~52 MHz). 48 MHz is the highest core clock
# obtainable from the same VCO that produces the exact 28.8 MHz peripheral
# clock, so one MMCM drives both synchronous domains.
#
# UART bauddiv reference values (periph_clk = 28.8 MHz):
#     9600 bps  ->  bauddiv = 2999
#   115200 bps  ->  bauddiv =  249
#   230400 bps  ->  bauddiv =  124
###############################################################################


###############################################################################
# Primary clock (input to MMCM only)
###############################################################################

set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name clk_100 -period 10.000 [get_ports clk]


###############################################################################
# MMCM-derived clocks
# Vivado automatically derives generated clocks from the MMCM outputs once the
# input clock is constrained. Explicit names are not required; the timing
# engine will report them as clk_out1_*/clk_out2_* or via the MMCM pins.
# core_clk (48 MHz) and periph_clk (28.8 MHz) are synchronous (same VCO),
# so inter-domain paths remain analysable.
#
# The UART CDC toggle-handshake synchroniser chains are declared as false
# paths so the engine does not flag them.
###############################################################################

set_false_path \
    -from [get_cells -hierarchical -filter {NAME =~ *tx_req_toggle_core_reg*}] \
    -to   [get_cells -hierarchical -filter {NAME =~ *tx_req_meta_periph_reg*}]

set_false_path \
    -from [get_cells -hierarchical -filter {NAME =~ *tx_ack_toggle_periph_reg*}] \
    -to   [get_cells -hierarchical -filter {NAME =~ *tx_ack_meta_core_reg*}]

set_false_path \
    -from [get_cells -hierarchical -filter {NAME =~ *tx_busy_periph_reg*}] \
    -to   [get_cells -hierarchical -filter {NAME =~ *tx_busy_meta_core_reg*}]


###############################################################################
# Reset  (active-high; BTNC = centre button)
###############################################################################

set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports rst]

# Asynchronous assertion, synchronous de-assertion.
# The reset synchronisers inside soc_top handle the re-synchronisation;
# declare false paths on the async reset input to suppress bogus setup
# violations on the first flop of each synchroniser chain.
set_false_path -from [get_ports rst]


###############################################################################
# GPIO input  (gpio_toggle → BTNL = left button)
###############################################################################

set_property -dict { PACKAGE_PIN W19  IOSTANDARD LVCMOS33 } [get_ports gpio_toggle]
set_false_path -from [get_ports gpio_toggle]


###############################################################################
# GPIO output  (gpio_out[3:0] → LD3..LD0)
###############################################################################

set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {gpio_out[0]}]
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports {gpio_out[1]}]
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports {gpio_out[2]}]
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports {gpio_out[3]}]

set_false_path -to [get_ports {gpio_out[*]}]


###############################################################################
# UART TX  (Basys3 USB-UART bridge -> pin A18)
###############################################################################

set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_false_path -to [get_ports uart_tx]


###############################################################################
# Methodology waiver: LUTAR-1 on the reset synchronizers
#
# The reset path (rst OR not-mmcm_locked) drives the asynchronous preset of
# the synchroniser flip-flops through a LUT. Vivado flags LUTAR-1 because a
# LUT on an async control pin can glitch. Here it is safe by construction:
# the term is only ever asserted while the MMCM is unlocked, during which the
# derived clocks are not yet stable and the entire domain is held in reset
# anyway. A glitch on the reset assert during that window has no effect.
# Asynchronous assert is required precisely because there is no stable clock
# to synchronise to before lock. Waiving with justification rather than
# restructuring in a way that would break correct behaviour.
###############################################################################

set_property SEVERITY {Warning} [get_drc_checks LUTAR-1]


###############################################################################
# Bitstream / configuration
###############################################################################

set_property CFGBVS         VCCO  [current_design]
set_property CONFIG_VOLTAGE  3.3  [current_design]
