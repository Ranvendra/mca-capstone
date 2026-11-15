.PHONY: traces analysis analysis-base test clean

PYTHON ?= python3

# Rebuild all deterministic trace inputs.
traces:
	$(PYTHON) traces/gen_traces.py --count 3000 --seed 20261116

# Run the Python reference-model baseline and all parameter sweeps.
analysis: traces
	$(PYTHON) analysis/analyze.py

# Run only the base 1 KiB / 16 B configuration.
analysis-base: traces
	$(PYTHON) analysis/analyze.py --no-sweep --cache 1024 --block 16 --latency 4

# M4 owns the integrated test target. Keep this target useful once their
# Makefile/testbench arrives, without silently claiming tests passed today.
test:
	@if [ -f tb/run_m4_tests.sh ]; then sh tb/run_m4_tests.sh; \
	elif [ -f tb/run_m2_tests.sh ] && [ -f tb/run_m3_tests.sh ]; then \
	  sh tb/run_m2_tests.sh && sh tb/run_m3_tests.sh; \
	else echo "No complete test runner found; run the available tb/run_*.sh scripts."; exit 1; fi

clean:
	rm -f analysis/results/*_reference.csv analysis/results/summary.csv
	rm -f analysis/results/summary.md analysis/results/parameter_sweep.csv
	rm -f analysis/results/*.png
