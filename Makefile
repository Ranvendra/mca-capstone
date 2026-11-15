# =============================================================================
# Makefile for Project 6: Direct-Mapped Cache Controller (MCA Capstone)
# M4 Verification and Automation
# =============================================================================

IVERILOG    ?= iverilog
VVP         ?= vvp
PYTHON      ?= python3
GTKWAVE     ?= gtkwave

RTL_DIR     := rtl
TB_DIR      := tb
TRACES_DIR  := traces
ANALYSIS_DIR:= analysis
RESULTS_DIR := $(ANALYSIS_DIR)/results
BUILD_DIR   := build

RTL_SRCS    := $(wildcard $(RTL_DIR)/*.v)
TRACES      := $(wildcard $(TRACES_DIR)/*.trace)

.PHONY: all sim trace test unit wave clean help

all: test

help:
	@echo "Available targets:"
	@echo "  make sim              Run directed self-checking testbench (tb_cache_directed.v)"
	@echo "  make trace T=<name>   Run RTL sim, golden model, and compare for traces/<name>.trace"
	@echo "  make test             Run full verification suite (unit + directed + all traces)"
	@echo "  make unit             Run M2 and M3 unit test suites"
	@echo "  make wave             Run directed simulation and open waveform with GTKWave"
	@echo "  make clean            Remove build artifacts and simulation outputs"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(RESULTS_DIR):
	mkdir -p $(RESULTS_DIR)

# -----------------------------------------------------------------------------
# Unit Tests (M2 and M3)
# -----------------------------------------------------------------------------
unit:
	@echo "=== Running M2 Unit Tests ==="
	@sh $(TB_DIR)/run_m2_tests.sh
	@echo "\n=== Running M3 Unit Tests ==="
	@sh $(TB_DIR)/run_m3_tests.sh

# -----------------------------------------------------------------------------
# Directed Self-Checking Testbench
# -----------------------------------------------------------------------------
sim: $(BUILD_DIR)
	@echo "=== Compiling Directed Testbench ==="
	$(IVERILOG) -g2012 -Wall -Wno-timescale -o $(BUILD_DIR)/tb_cache_directed $(RTL_SRCS) $(TB_DIR)/tb_cache_directed.v
	@echo "=== Running Directed Testbench ==="
	$(VVP) $(BUILD_DIR)/tb_cache_directed

# -----------------------------------------------------------------------------
# Trace-Driven Simulation and Golden Model Verification
# -----------------------------------------------------------------------------
trace: $(BUILD_DIR) $(RESULTS_DIR)
ifndef T
	$(error Please specify trace name using T=<name>, e.g., make trace T=sample)
endif
	@if [ ! -f $(TRACES_DIR)/$(T).trace ]; then \
		echo "ERROR: Trace file $(TRACES_DIR)/$(T).trace does not exist"; exit 1; \
	fi
	@echo "=== Compiling Trace Testbench for $(T) ==="
	$(IVERILOG) -g2012 -Wall -Wno-timescale -o $(BUILD_DIR)/tb_cache_trace $(RTL_SRCS) $(TB_DIR)/tb_cache_trace.v
	@echo "=== Running RTL Simulation on $(T).trace ==="
	$(VVP) $(BUILD_DIR)/tb_cache_trace +TRACE=$(TRACES_DIR)/$(T).trace +OUT=$(RESULTS_DIR)/$(T)_sim.csv
	@echo "=== Running Python Golden Model on $(T).trace ==="
	$(PYTHON) $(ANALYSIS_DIR)/golden_model.py $(TRACES_DIR)/$(T).trace --out $(RESULTS_DIR)/$(T)_golden.csv
	@echo "=== Verifying RTL Output vs Golden Model ==="
	$(PYTHON) $(ANALYSIS_DIR)/compare.py $(RESULTS_DIR)/$(T)_sim.csv $(RESULTS_DIR)/$(T)_golden.csv --check-latency

# -----------------------------------------------------------------------------
# Comprehensive Test Suite
# -----------------------------------------------------------------------------
test: unit sim
	@echo "\n=== Running Trace Verifications ==="
	@for tr in $(TRACES); do \
		tname=$$(basename $$tr .trace); \
		echo "\n--- Testing Trace: $$tname ---"; \
		$(MAKE) --no-print-directory trace T=$$tname || exit 1; \
	done
	@echo "\n=================================================="
	@echo ">>> ALL VERIFICATION SUITE TESTS PASSED <<<"
	@echo "=================================================="

# -----------------------------------------------------------------------------
# Waveform Inspection
# -----------------------------------------------------------------------------
wave: sim
	@which $(GTKWAVE) >/dev/null 2>&1 && $(GTKWAVE) tb_cache_directed.vcd || \
		echo "NOTE: gtkwave command not found. VCD generated at tb_cache_directed.vcd"

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR) *.vcd /tmp/tb_* /tmp/m2_tests /tmp/m3_tests
