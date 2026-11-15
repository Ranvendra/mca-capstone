# =============================================================================
# MCA Capstone — M4 verification + M5 workload analysis + M3 synthesis
# M4 targets and CSV contracts are preserved; M5 adds trace/analysis targets.
# =============================================================================
IVERILOG     ?= iverilog
VVP          ?= vvp
PYTHON       ?= python3
GTKWAVE      ?= gtkwave
RTL_DIR      := rtl
TB_DIR       := tb
TRACES_DIR   := traces
ANALYSIS_DIR := analysis
RESULTS_DIR  := $(ANALYSIS_DIR)/results
BUILD_DIR    := build
RTL_SRCS     := $(wildcard $(RTL_DIR)/*.v)
TRACES       := $(wildcard $(TRACES_DIR)/*.trace)
export T

.PHONY: all sim trace test unit wave clean help traces analysis analysis-base analysis-rtl synth
all: test

help:
	@echo "Available targets:"
	@echo "  make sim                 Run M4 directed self-checking testbench"
	@echo "  make trace T=<name>      Run RTL, golden model and per-access comparison"
	@echo "  make test                Run M2/M3 unit tests, directed tests and every trace"
	@echo "  make unit                Run M2 and M3 unit test suites"
	@echo "  make wave                Run directed simulation and open GTKWave"
	@echo "  make traces              Regenerate seven deterministic M5 traces"
	@echo "  make analysis            Run M5 Python reference analysis and parameter sweep"
	@echo "  make analysis-base       Run reference analysis at 1 KiB / 16 B only"
	@echo "  make analysis-rtl T=<name>  Validate and summarize one RTL trace CSV"
	@echo "  make synth               Run the M3 synthesis sweep"
	@echo "  make clean               Remove build and generated analysis outputs"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(RESULTS_DIR):
	mkdir -p $(RESULTS_DIR)

# M2 and M3 unit tests (M4)
unit:
	@echo "=== Running M2 Unit Tests ==="
	@sh $(TB_DIR)/run_m2_tests.sh
	@echo "\n=== Running M3 Unit Tests ==="
	@sh $(TB_DIR)/run_m3_tests.sh

# Directed self-checking testbench (M4)
sim: $(BUILD_DIR)
	@echo "=== Compiling Directed Testbench ==="
	$(IVERILOG) -g2012 -Wall -Wno-timescale -o $(BUILD_DIR)/tb_cache_directed $(RTL_SRCS) $(TB_DIR)/tb_cache_directed.v
	@echo "=== Running Directed Testbench ==="
	$(VVP) $(BUILD_DIR)/tb_cache_directed

# Trace-driven RTL simulation + golden-model comparison (M4)
.NOTPARALLEL: trace test analysis-rtl

trace: $(BUILD_DIR) $(RESULTS_DIR)
ifndef T
	$(error Please specify trace name using T=<name>, e.g., make trace T=seq)
endif
	@case "$T" in ""|*[!A-Za-z0-9_-]*) echo "ERROR: T must contain only letters, digits, underscore or hyphen"; exit 2;; esac
	@if [ ! -f "$(TRACES_DIR)/$T.trace" ]; then echo "ERROR: missing $(TRACES_DIR)/$T.trace"; exit 1; fi
	@echo "=== Compiling Trace Testbench for $T ==="
	$(IVERILOG) -g2012 -Wall -Wno-timescale -o $(BUILD_DIR)/tb_cache_trace $(RTL_SRCS) $(TB_DIR)/tb_cache_trace.v
	@echo "=== Running RTL Simulation on $T.trace ==="
	$(VVP) $(BUILD_DIR)/tb_cache_trace +TRACE="$(TRACES_DIR)/$T.trace" +OUT="$(RESULTS_DIR)/$T_sim.csv"
	@echo "=== Running Python Golden Model on $T.trace ==="
	$(PYTHON) $(ANALYSIS_DIR)/golden_model.py "$(TRACES_DIR)/$T.trace" --out "$(RESULTS_DIR)/$T_golden.csv"
	@echo "=== Verifying RTL Output vs Golden Model ==="
	$(PYTHON) $(ANALYSIS_DIR)/compare.py "$(RESULTS_DIR)/$T_sim.csv" "$(RESULTS_DIR)/$T_golden.csv" --check-latency

# Comprehensive verification suite (M4); committed M5 traces are included automatically.
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

wave: sim
	@which $(GTKWAVE) >/dev/null 2>&1 && $(GTKWAVE) tb_cache_directed.vcd || \
		echo "NOTE: gtkwave command not found. VCD generated at tb_cache_directed.vcd"

# M5 deterministic workload generation and reference-model analysis.
traces:
	$(PYTHON) traces/gen_traces.py --count 4096 --seed 20261116

analysis: traces
	$(PYTHON) analysis/analyze.py

analysis-base: traces
	$(PYTHON) analysis/analyze.py --no-sweep --cache 1024 --block 16 --latency 4

# Run M4 RTL simulation/comparison first, then independently validate and summarize its CSV.
analysis-rtl: trace
	$(PYTHON) analysis/analyze.py --rtl-csv "$(RESULTS_DIR)/$T_sim.csv" --trace "$(TRACES_DIR)/$T.trace" --cache 1024 --block 16 --latency 4

# M3 synthesis workflow; preserve synth/Makefile ownership and implementation.
synth:
	$(MAKE) -C synth sweep

clean:
	rm -rf $(BUILD_DIR) *.vcd /tmp/tb_* /tmp/m2_tests /tmp/m3_tests
	rm -f $(RESULTS_DIR)/*_reference.csv $(RESULTS_DIR)/*_sim.csv $(RESULTS_DIR)/*_golden.csv
	rm -f $(RESULTS_DIR)/parameter_sweep.csv $(RESULTS_DIR)/rtl_summary.csv
	rm -f $(RESULTS_DIR)/*.png
