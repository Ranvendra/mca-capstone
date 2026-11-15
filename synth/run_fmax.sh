#!/bin/sh
# synth/run_fmax.sh  (M3)  place-and-route timing (Fmax) on a Lattice iCE40 HX8K.
# Needs yosys + nextpnr-ice40. Yosys alone cannot give Fmax; this number comes
# from nextpnr's static timing analysis after routing.
#
# Usage: sh synth/run_fmax.sh [CACHE_BYTES] [BLOCK_BYTES] [bram|nobram] [SEED]
#   nobram (default): the design as it is. iCE40 has no LUT-RAM, so the
#                     async-read arrays are built from flip-flops.
#   bram            : lets Yosys use block RAM. Only possible here because the
#                     timing wrapper drives cpu_addr from a flip-flop, which
#                     Yosys merges into the RAM as a registered read address.
#                     It shows what a registered-address cache would cost; it
#                     is not the timing of cache_top on its own.
# The top is synth/fmax_wrap.v (flip-flops on every input and output).
# Output: synth/reports/fmax_ice40_c<CACHE>_b<BLOCK>_<mode>.rpt
set -u
cd "$(dirname "$0")/.." || exit 1
CACHE=${1:-512}
BLOCK=${2:-16}
MODE=${3:-nobram}
SEED=${4:-1}
RTL="rtl/addr_decoder.v rtl/tag_ram.v rtl/valid_ram.v rtl/data_ram.v rtl/tag_comparator.v rtl/cache_controller.v rtl/cache_top.v synth/fmax_wrap.v"
OPT=""; [ "$MODE" = nobram ] && OPT="-nobram"
NAME="fmax_ice40_c${CACHE}_b${BLOCK}_${MODE}"
mkdir -p synth/reports synth/build

if ! yosys -q -l "synth/build/$NAME.log" -p "
    read_verilog -sv $RTL
    hierarchy -check -top fmax_wrap -chparam CACHE_BYTES $CACHE -chparam BLOCK_BYTES $BLOCK
    synth_ice40 -top fmax_wrap $OPT -json synth/build/$NAME.json
" > /dev/null 2>&1; then
    echo "FAIL $NAME: yosys error, see synth/build/$NAME.log"; exit 1
fi

nextpnr-ice40 --hx8k --package ct256 --json "synth/build/$NAME.json" --seed "$SEED" --freq 50 \
    -q -l "synth/build/${NAME}_pnr.log" > /dev/null 2>&1
rc=$?

RPT="synth/reports/$NAME.rpt"
{
    echo "# $NAME : nextpnr-ice40 --hx8k --package ct256 --seed $SEED (top = fmax_wrap)"
    echo "# $(nextpnr-ice40 --version 2>&1 | head -1)"
    grep -E "ICESTORM_LC:|ICESTORM_RAM:|SB_IO:|SB_GB:" "synth/build/${NAME}_pnr.log" | tail -4
    grep -E "^ERROR" "synth/build/${NAME}_pnr.log"
    grep -E "Max frequency for clock" "synth/build/${NAME}_pnr.log" | tail -1
    echo "# critical path (after routing):"
    awk '/Critical path report for clock/{buf=""; on=1} on{buf=buf $0 "\n"} /Info: +[0-9.]+ ns logic, +[0-9.]+ ns routing/{if(on){last=buf; on=0}} END{printf "%s", last}' \
        "synth/build/${NAME}_pnr.log" | grep -vE "Defined in:|cells_map.v|\.v:[0-9]"
} > "$RPT"

if [ $rc -ne 0 ]; then
    echo "NOFIT $NAME: $(grep -E '^ERROR' "synth/build/${NAME}_pnr.log" | head -1)  -> $RPT"
    exit 1
fi
echo "OK   $NAME: $(grep -E 'Max frequency for clock' "synth/build/${NAME}_pnr.log" | tail -1 | sed 's/^Info: //')  -> $RPT"
