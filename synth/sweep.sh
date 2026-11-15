#!/bin/sh
# synth/sweep.sh  (M3)  run every configuration of docs/synthesis.md on every
# target, then build the summary tables.
#   cache-size sweep : 512 B, 1 KB, 2 KB, 4 KB   (block 16 B)
#   block-size sweep : 8, 16, 32, 64 B            (cache 1 KB)
#   base config with WRITE_SUPPORT=1 (stretch goal), to see what writes cost
# Usage: sh synth/sweep.sh     (about a minute)
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
for target in generic xilinx ice40; do
    for cfg in "512 16" "1024 16" "2048 16" "4096 16" "1024 8" "1024 32" "1024 64"; do
        set -- $cfg
        sh synth/run_synth.sh "$1" "$2" "$target" 0 || fail=1
    done
    sh synth/run_synth.sh 1024 16 "$target" 1 || fail=1
done
python3 synth/summarize.py || fail=1
[ $fail -eq 0 ] && echo "SYNTHESIS SWEEP DONE" || echo "SYNTHESIS SWEEP HAD ERRORS"
exit $fail
