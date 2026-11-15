#!/usr/bin/env python3
"""synth/summarize.py (M3): turn the yosys `stat -json` reports into tables.

Reads  synth/reports/<target>_c<CACHE>_b<BLOCK>[_ws1].json  (from run_synth.sh)
Writes synth/reports/summary.csv  (one row per config, all targets side by side)
       synth/reports/summary.md   (the same numbers as markdown tables)

Every area number comes straight from the yosys report. The only computed
columns are the storage bit counts (lines x width), marked "calc".
Usage: python3 synth/summarize.py
"""
import csv
import glob
import json
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REPORTS = os.path.join(HERE, "reports")
ADDR_W = 32

# LUTs occupied by one primitive (a 6-input LUT holds 64 bits; RAM32M/RAM64M use 4 LUTs)
LUTRAM_LUTS = {"RAM32X1S": 1, "RAM64X1S": 1, "RAM128X1S": 2, "RAM256X1S": 4,
               "RAM32X1D": 2, "RAM64X1D": 2, "RAM128X1D": 4,
               "RAM32M": 4, "RAM64M": 4}


def load(path):
    with open(path) as f:
        return json.load(f)


def count(cells, pattern):
    return sum(n for name, n in cells.items() if re.fullmatch(pattern, name))


def real_cells(cells):
    """Cell count without yosys' $scopeinfo bookkeeping cells."""
    return sum(n for name, n in cells.items() if name != "$scopeinfo")


def geometry(cache, block):
    lines = cache // block
    index_w = int(math.log2(lines))
    off_w = int(math.log2(block))
    tag_w = ADDR_W - index_w - off_w
    return {
        "lines": lines, "index_w": index_w, "tag_w": tag_w,
        "data_bits": lines * block * 8,
        "tag_bits": lines * tag_w,
        "valid_bits": lines,
    }


def generic_row(d):
    cells = d["design"]["num_cells_by_type"]
    row = {
        "gen_cells": real_cells(cells),
        "gen_ff": count(cells, r"\$_S?DFFS?R?E?_.*"),
    }
    row["gen_comb"] = row["gen_cells"] - row["gen_ff"]
    for mod, m in d["modules"].items():
        short = mod.split("\\")[-1] if "\\cache_top" in mod else None
        for name in ("data_ram", "tag_ram", "valid_ram", "tag_comparator",
                     "cache_controller", "addr_decoder", "cache_top"):
            if re.search(r"\\" + name + r"(\\|$)", mod):
                short = name
        row["gen_" + short] = real_cells(m.get("num_cells_by_type", {}))
    return row


def xilinx_row(d):
    cells = d["design"]["num_cells_by_type"]
    unknown = [c for c in cells if c.startswith("RAM") and c not in LUTRAM_LUTS
               and not c.startswith("RAMB")]
    if unknown:
        raise SystemExit("summarize.py: unknown RAM primitive(s) %s" % unknown)
    return {
        "xil_lut_logic": count(cells, r"LUT[1-6]"),
        "xil_lutram_cells": sum(n for c, n in cells.items() if c in LUTRAM_LUTS),
        "xil_lutram_luts": sum(n * LUTRAM_LUTS[c] for c, n in cells.items() if c in LUTRAM_LUTS),
        "xil_ff": count(cells, r"FD[RSCP]E(_1)?"),
        "xil_carry4": cells.get("CARRY4", 0),
        "xil_muxf": count(cells, r"MUXF[789]"),
        "xil_bram": count(cells, r"RAMB.*"),
        "xil_lutram_types": " ".join("%s:%d" % (c, cells[c]) for c in sorted(cells) if c in LUTRAM_LUTS),
    }


def ice40_row(d):
    cells = d["design"]["num_cells_by_type"]
    return {
        "ice_lut4": cells.get("SB_LUT4", 0),
        "ice_ff": count(cells, r"SB_DFF.*"),
        "ice_carry": cells.get("SB_CARRY", 0),
        "ice_bram": count(cells, r"SB_RAM.*"),
    }


def main():
    configs = {}
    for path in sorted(glob.glob(os.path.join(REPORTS, "*.json"))):
        m = re.fullmatch(r"(generic|xilinx|ice40)_c(\d+)_b(\d+)(_ws1)?\.json", os.path.basename(path))
        if not m:
            continue
        target, cache, block, ws = m.group(1), int(m.group(2)), int(m.group(3)), 1 if m.group(4) else 0
        row = configs.setdefault((ws, cache, block),
                                 dict(cache_bytes=cache, block_bytes=block, write_support=ws,
                                      **geometry(cache, block)))
        row.update({"generic": generic_row, "xilinx": xilinx_row, "ice40": ice40_row}[target](load(path)))
    if not configs:
        raise SystemExit("summarize.py: no reports found in %s (run synth/sweep.sh first)" % REPORTS)

    rows = [configs[k] for k in sorted(configs)]
    for r in rows:
        r["overhead_pct"] = round(100.0 * (r["tag_bits"] + r["valid_bits"]) / r["data_bits"], 1)
        if "gen_cells" in r:
            r["gen_data_ram_pct"] = round(100.0 * r["gen_data_ram"] / r["gen_cells"], 1)

    cols = ["cache_bytes", "block_bytes", "write_support", "lines", "index_w", "tag_w",
            "data_bits", "tag_bits", "valid_bits", "overhead_pct",
            "gen_cells", "gen_ff", "gen_comb", "gen_data_ram", "gen_tag_ram", "gen_valid_ram",
            "gen_tag_comparator", "gen_cache_controller", "gen_addr_decoder", "gen_cache_top",
            "gen_data_ram_pct",
            "xil_lut_logic", "xil_lutram_cells", "xil_lutram_luts", "xil_ff",
            "xil_carry4", "xil_muxf", "xil_bram", "xil_lutram_types",
            "ice_lut4", "ice_ff", "ice_carry", "ice_bram"]
    with open(os.path.join(REPORTS, "summary.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, restval="")
        w.writeheader()
        w.writerows(rows)

    def table(title, header, keys, select):
        out = ["### " + title, "", "| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
        for r in rows:
            if select(r):
                out.append("| " + " | ".join(str(r.get(k, "")) for k in keys) + " |")
        return out + [""]

    cfg_h, cfg_k = ["Cache (B)", "Block (B)"], ["cache_bytes", "block_bytes"]
    sweeps = [("cache-size sweep, block = 16 B", lambda r: r["block_bytes"] == 16 and not r["write_support"]),
              ("block-size sweep, cache = 1 KB", lambda r: r["cache_bytes"] == 1024 and not r["write_support"]),
              ("base config, WRITE_SUPPORT = 0 vs 1", lambda r: r["cache_bytes"] == 1024 and r["block_bytes"] == 16)]
    md = ["# Synthesis summary (generated by synth/summarize.py, do not edit)", ""]
    for name, sel in sweeps:
        ws_h, ws_k = (["WS"], ["write_support"]) if "WRITE_SUPPORT" in name else ([], [])
        if not ws_h:
            md += table("Storage bits (calc): " + name,
                        cfg_h + ["Lines", "Index bits", "Tag bits/line", "Data bits", "Tag bits", "Valid bits", "Overhead %"],
                        cfg_k + ["lines", "index_w", "tag_w", "data_bits", "tag_bits", "valid_bits", "overhead_pct"], sel)
        md += table("Yosys generic `synth` (gate-level cells): " + name,
                    cfg_h + ws_h + ["Cells", "FFs", "Comb. cells", "data_ram", "tag_ram", "valid_ram", "comparator",
                                    "controller", "top (counters, muxes)", "data_ram %"],
                    cfg_k + ws_k + ["gen_cells", "gen_ff", "gen_comb", "gen_data_ram", "gen_tag_ram", "gen_valid_ram",
                                    "gen_tag_comparator", "gen_cache_controller", "gen_cache_top", "gen_data_ram_pct"], sel)
        md += table("Yosys `synth_xilinx` (7-series): " + name,
                    cfg_h + ws_h + ["Logic LUTs", "LUTRAM cells", "LUTs used as RAM", "FFs", "CARRY4",
                                    "MUXF7/8", "BRAM", "LUTRAM primitives"],
                    cfg_k + ws_k + ["xil_lut_logic", "xil_lutram_cells", "xil_lutram_luts", "xil_ff",
                                    "xil_carry4", "xil_muxf", "xil_bram", "xil_lutram_types"], sel)
        md += table("Yosys `synth_ice40`: " + name,
                    cfg_h + ws_h + ["SB_LUT4", "FFs (SB_DFF*)", "SB_CARRY", "BRAM (SB_RAM40_4K)"],
                    cfg_k + ws_k + ["ice_lut4", "ice_ff", "ice_carry", "ice_bram"], sel)
    with open(os.path.join(REPORTS, "summary.md"), "w") as f:
        f.write("\n".join(md))
    print("wrote synth/reports/summary.csv and summary.md (%d configs)" % len(rows))


if __name__ == "__main__":
    main()
