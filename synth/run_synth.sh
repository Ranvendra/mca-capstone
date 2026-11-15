#!/bin/sh
# synth/run_synth.sh  (M3)  synthesise cache_top for one configuration.
#
# Usage (from anywhere):
#   sh synth/run_synth.sh [CACHE_BYTES] [BLOCK_BYTES] [TARGET] [WRITE_SUPPORT]
#     CACHE_BYTES    default 1024
#     BLOCK_BYTES    default 16
#     TARGET         generic (default) | xilinx | ice40
#     WRITE_SUPPORT  default 0
#
# Output:
#   synth/reports/<target>_c<CACHE>_b<BLOCK>[_ws1].rpt    yosys `stat` (text)
#   synth/reports/<target>_c<CACHE>_b<BLOCK>[_ws1].json   yosys `stat -json`
#   synth/build/<same name>.log                           full yosys log (not in git)
# Exit code != 0 if yosys fails or the log has a latch / a real warning.
set -u
cd "$(dirname "$0")/.." || exit 1

CACHE=${1:-1024}
BLOCK=${2:-16}
TARGET=${3:-generic}
WS=${4:-0}

RTL="rtl/addr_decoder.v rtl/tag_ram.v rtl/valid_ram.v rtl/data_ram.v rtl/tag_comparator.v rtl/cache_controller.v rtl/cache_top.v"

case "$TARGET" in
    generic) SYNTH="synth -top cache_top" ;;                     # hierarchy kept: per-module area
    xilinx)  SYNTH="synth_xilinx -top cache_top -flatten" ;;     # 7-series: LUT6, FDRE, RAM64X1S, RAMB*
    ice40)   SYNTH="synth_ice40 -top cache_top" ;;               # LUT4, SB_DFF*, SB_RAM40_4K
    *) echo "unknown target '$TARGET' (generic | xilinx | ice40)"; exit 2 ;;
esac

NAME="${TARGET}_c${CACHE}_b${BLOCK}"
[ "$WS" != 0 ] && NAME="${NAME}_ws1"
mkdir -p synth/reports synth/build
LOG="synth/build/$NAME.log"
RPT="synth/reports/$NAME.rpt"

yosys -q -l "$LOG" -p "
    read_verilog -sv $RTL
    hierarchy -check -top cache_top -chparam CACHE_BYTES $CACHE -chparam BLOCK_BYTES $BLOCK -chparam WRITE_SUPPORT $WS
    $SYNTH
    check -assert
    tee -o $RPT stat -top cache_top
    tee -o synth/reports/$NAME.json stat -json -top cache_top
" > /dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "FAIL $NAME: yosys exit code $rc, see $LOG"; tail -5 "$LOG"; exit 1
fi

# Latches and warnings. Two warnings come from the tools themselves, not from
# our RTL, and are ignored: ABC's 'network is combinational' note and a lexer
# warning inside Yosys' own abc9_map.v.
latch=$(grep -c "Latch inferred for signal" "$LOG")
dlatch=$(grep -cE '\$_DLATCH|\$dlatch' "$RPT")
warn=$(grep -i "warning" "$LOG" | grep -v "ABC: Warning: The network is combinational" \
                                 | grep -v "share/yosys/abc9_map.v" | sort -u)
nwarn=$(printf '%s' "$warn" | grep -c .)

echo "OK   $NAME: latches=$((latch + dlatch)) warnings=$nwarn  -> $RPT"
if [ $((latch + dlatch)) -ne 0 ] || [ "$nwarn" -ne 0 ]; then
    grep -n "Latch inferred for signal" "$LOG"
    printf '%s\n' "$warn"
    exit 1
fi
exit 0
