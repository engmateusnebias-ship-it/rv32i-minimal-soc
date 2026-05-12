##############################################################################
# Makefile -- Mini-SoC RV32I unit test runner (GHDL)
#
# Usage:
#   make ci           -- run all unit tests (used by GitHub Actions)
#   make sim TB=tb_alu  -- run a single testbench interactively
#   make clean        -- remove build artefacts
#
# Excluded from CI (requires Xilinx UNISIM / MMCM primitive):
#   tb_soc_top
#
# Note: instruction_memory.vhd opens "program.mem" with a relative path.
# Either run make from the repo root after creating the symlink below,
# or let the CI workflow create it:
#   ln -s programs/program.mem program.mem
##############################################################################

GHDL    := ghdl
STD     := --std=08
WORKDIR := build

RTL_SRCS := \
	rtl/alu.vhd \
	rtl/alu_control.vhd \
	rtl/branch_compare.vhd \
	rtl/control_unit.vhd \
	rtl/immediate_generator.vhd \
	rtl/program_counter.vhd \
	rtl/register_file.vhd \
	rtl/trap_unit.vhd \
	rtl/load_store_unit.vhd \
	rtl/instruction_memory.vhd \
	rtl/data_memory.vhd \
	rtl/gpio.vhd \
	rtl/timer.vhd \
	rtl/reset_synchronizer.vhd \
	rtl/bus_interconnect.vhd \
	rtl/uart.vhd \
	rtl/dma.vhd \
	rtl/rv32i_core.vhd

TB_SRCS := \
	tb/tb_alu.vhd \
	tb/tb_alu_control.vhd \
	tb/tb_branch_compare.vhd \
	tb/tb_control_unit.vhd \
	tb/tb_immediate_generator.vhd \
	tb/tb_program_counter.vhd \
	tb/tb_register_file.vhd \
	tb/tb_trap_unit.vhd \
	tb/tb_load_store_unit.vhd \
	tb/tb_instruction_memory.vhd \
	tb/tb_data_memory.vhd \
	tb/tb_gpio.vhd \
	tb/tb_timer.vhd \
	tb/tb_reset_synchronizer.vhd \
	tb/tb_bus_interconnect.vhd \
	tb/tb_uart.vhd \
	tb/tb_dma.vhd \
	tb/tb_rv32i_core.vhd

TB_TOPS := \
	tb_alu \
	tb_alu_control \
	tb_branch_compare \
	tb_control_unit \
	tb_immediate_generator \
	tb_program_counter \
	tb_register_file \
	tb_trap_unit \
	tb_load_store_unit \
	tb_instruction_memory \
	tb_data_memory \
	tb_gpio \
	tb_timer \
	tb_reset_synchronizer \
	tb_bus_interconnect \
	tb_uart \
	tb_dma \
	tb_rv32i_core

.PHONY: all ci sim clean

all: ci

# ----------------------------------------------------------------------
# ci: analyse all sources then run every testbench
# ----------------------------------------------------------------------
ci: $(WORKDIR)/.analysed
	@echo ""
	@echo "======================================================"
	@echo " Running unit tests"
	@echo "======================================================"
	@PASS=0; FAIL=0; \
	for top in $(TB_TOPS); do \
		printf "  %-40s" "$$top ..."; \
		LOG=$$($(GHDL) -r $(STD) --workdir=$(WORKDIR) $$top \
			--assert-level=failure 2>&1); \
		if echo "$$LOG" | grep -qiE "failure|error|FAILED"; then \
			echo "FAIL"; \
			echo "$$LOG" | sed 's/^/    /'; \
			FAIL=$$((FAIL+1)); \
		else \
			echo "pass"; \
			PASS=$$((PASS+1)); \
		fi; \
	done; \
	echo ""; \
	echo "  Results: $$PASS passed, $$FAIL failed"; \
	echo "======================================================"; \
	test $$FAIL -eq 0

# ----------------------------------------------------------------------
# analyse: compile RTL then TBs into the work library
# ----------------------------------------------------------------------
$(WORKDIR)/.analysed: $(RTL_SRCS) $(TB_SRCS) | $(WORKDIR)
	@echo "Analysing RTL sources..."
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(RTL_SRCS)
	@echo "Analysing testbench sources..."
	$(GHDL) -a $(STD) --workdir=$(WORKDIR) $(TB_SRCS)
	@touch $(WORKDIR)/.analysed

# ----------------------------------------------------------------------
# sim: run a single testbench  (make sim TB=tb_uart)
# ----------------------------------------------------------------------
sim: $(WORKDIR)/.analysed
ifndef TB
	$(error Specify a testbench with TB=<name>, e.g.: make sim TB=tb_uart)
endif
	$(GHDL) -r $(STD) --workdir=$(WORKDIR) $(TB) --assert-level=failure

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
$(WORKDIR):
	mkdir -p $(WORKDIR)

clean:
	rm -rf $(WORKDIR)
