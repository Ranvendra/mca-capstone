#!/bin/sh
# Runs all M2 (storage datapath) unit tests. Exit code != 0 if any fails.
# Usage: sh tb/run_m2_tests.sh   (from the repo root)
set -u
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/m2_tests
mkdir -p "$OUT"
fail=0

for m in addr_decoder tag_comparator tag_ram valid_ram data_ram; do
    if ! iverilog -g2012 -Wall -Wno-timescale -o "$OUT/tb_$m" "rtl/$m.v" "tb/tb_$m.v"; then
        echo "FAIL tb_$m: compile error"; fail=1; continue
    fi
    res=$(vvp -n "$OUT/tb_$m")
    echo "$res" | grep -E '^(PASS|FAIL)'
    echo "$res" | grep -q "^PASS tb_$m" || fail=1
done

if [ $fail -eq 0 ]; then echo "ALL M2 TESTS PASSED"; else echo "SOME M2 TESTS FAILED"; fi
exit $fail
