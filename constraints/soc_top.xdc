###############################################################################
# soc_top.xdc  –  Basys3 (xc7a35tcpg236-1)
# Mini-SoC RV32I
#
# Clock architecture:
#   clk        : 100 MHz onboard oscillator (W5)
#   periph_clk : 28.8 MHz, generated internally by MMCM
#                M=36, D=5, O=25  →  VCO=720 MHz
#
# UART bauddiv reference values (periph_clk = 28.8 MHz):
#     9600 bps  →  bauddiv = 2999
#   115200 bps  →  bauddiv =  249
#   230400 bps  →  bauddiv =  124
###############################################################################


###############################################################################
# Primary clock
###############################################################################

set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name clk_100 -period 10.000 [get_ports clk]


###############################################################################
# MMCM-derived clock (periph_clk, 28.8 MHz)
# Generated internally – no external pin.
# Vivado auto-derives this clock from the MMCM output net.
# The create_generated_clock below makes the constraint explicit so that
# timing reports show a named clock instead of an anonymous derived clock.
###############################################################################

create_generated_clock \
    -name periph_clk_28m8 \
    -source [get_pins mmcm_inst/CLKIN1] \
    -multiply_by 36 \
    -divide_by 125 \
    [get_pins mmcm_inst/CLKOUT0]

# clk_100 and periph_clk_28m8 are synchronous (same source, integer ratio),
# so cross-domain paths are analysable by the timing engine.
# The UART CDC uses a toggle-handshake; the false-path declarations below
# cover the two synchroniser chains so the engine does not flag them as
# violations.  All other cross-domain paths are intentionally left
# analysable.

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
# UART TX  (Basys3 USB-UART bridge → pin A18 = JA[2] on schematic)
###############################################################################

set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_false_path -to [get_ports uart_tx]


###############################################################################
# Bitstream / configuration
###############################################################################

set_property CFGBVS         VCCO  [current_design]
set_property CONFIG_VOLTAGE  3.3  [current_design]
