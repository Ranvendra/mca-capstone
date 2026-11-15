#!/bin/sh
# Runs all M3 tests. Exit code != 0 if any fails.
#   1. tb_main_memory at MEM_LATENCY = 1, 4, 10
#   2. tb_m3_cache_mem: cache_top + real main_memory, several latencies and sizes
#   3. M1's tb_m1_smoke with the real rtl/*.v (WRITE_SUPPORT 0 and 1)
# Usage: sh tb/run_m3_tests.sh   (from the repo root, needs Icarus Verilog)
set -u
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/m3_tests
mkdir -p "$OUT"
fail=0

# run <name> <expected PASS prefix> <iverilog args...>
run() {
    name=$1; want=$2; shift 2
    if ! iverilog -g2012 -Wall -Wno-timescale -o "$OUT/$name" "$@"; then
        echo "FAIL $name: compile error"; fail=1; return
    fi
    res=$(cd "$OUT" && vvp -n "$name")
    echo "$res" | grep -E '^(PASS|FAIL)'
    echo "$res" | grep -q "^$want" || fail=1
}

for L in 1 4 10; do
    run "tb_main_memory_L$L" "PASS tb_main_memory" -Ptb_main_memory.LATENCY=$L \
        rtl/main_memory.v tb/tb_main_memory.v
done

for cfg in "1 1024 16" "4 1024 16" "10 1024 16" "4 512 8" "4 4096 64" "4 2048 32"; do
    set -- $cfg
    run "tb_m3_cache_mem_L$1_$2_$3" "PASS tb_m3_cache_mem" \
        -Ptb_m3_cache_mem.LATENCY=$1 -Ptb_m3_cache_mem.CACHE_BYTES=$2 -Ptb_m3_cache_mem.BLOCK_BYTES=$3 \
        rtl/*.v tb/tb_m3_cache_mem.v
done

for ws in 0 1; do
    for L in 1 4 10; do
        run "tb_m1_smoke_WS${ws}_L$L" "PASS (WS=$ws, MEM_LATENCY=$L)" \
            -Ptb_m1_smoke.WS=$ws -Ptb_m1_smoke.LATENCY=$L rtl/*.v tb/tb_m1_smoke.v
    done
done

if [ $fail -eq 0 ]; then echo "ALL M3 TESTS PASSED"; else echo "SOME M3 TESTS FAILED"; fi
exit $fail
