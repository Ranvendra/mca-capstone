#!/usr/bin/env python3
"""Reproducible cache-trace analysis and AMAT/parameter sweep."""
from __future__ import annotations
import argparse, csv
from collections import OrderedDict
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TRACES = ROOT / "traces"
DEFAULT_OUT = ROOT / "analysis" / "results"
WORD_BYTES, HASH = 4, 0x9E3779B1

def load_trace(path: Path):
    accesses = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"): continue
        fields = line.split()
        if len(fields) != 2: raise ValueError(f"{path}:{line_no}: expected '<op> <hex-address>'")
        op, addr = int(fields[0], 16), int(fields[1], 16)
        if op not in (0, 1): raise ValueError(f"{path}:{line_no}: op must be 0 or 1")
        if addr < 0 or addr >= 256*1024 or addr % 4: raise ValueError(f"{path}:{line_no}: invalid address")
        accesses.append((op, addr))
    return accesses

def word_value(address):
    return (((address >> 2) * HASH) & 0xFFFFFFFF)

def simulate(accesses: Iterable[tuple[int,int]], cache_bytes, block_bytes, mem_latency):
    if cache_bytes < block_bytes or cache_bytes % block_bytes: raise ValueError("cache must be a multiple of block size")
    if cache_bytes & (cache_bytes-1) or block_bytes & (block_bytes-1): raise ValueError("sizes must be powers of two")
    if block_bytes < 8 or block_bytes % 4: raise ValueError("block must be >= 8 and divisible by 4")
    lines, words = cache_bytes//block_bytes, block_bytes//4
    miss_latency = words*(mem_latency+1)+2
    tags, valid = [None]*lines, [False]*lines
    seen, shadow = set(), OrderedDict()
    rows, hits, misses, compulsory, conflict, capacity, total_latency = [], 0, 0, 0, 0, 0, 0
    for idx,(op,address) in enumerate(accesses):
        block = address//block_bytes
        line, tag, word = block%lines, block//lines, (address%block_bytes)//4
        hit = valid[line] and tags[line] == tag
        if hit:
            hits += 1; latency=1; kind="hit"
        else:
            misses += 1; latency=miss_latency
            if block not in seen: compulsory += 1; kind="compulsory"
            elif block in shadow: conflict += 1; kind="conflict"
            else: capacity += 1; kind="capacity"
            valid[line], tags[line] = True, tag
        seen.add(block)
        if block in shadow: shadow.move_to_end(block)
        else:
            shadow[block]=None
            if len(shadow)>lines: shadow.popitem(last=False)
        base=(address//block_bytes)*block_bytes
        rows.append({"idx":idx,"op":op,"addr":f"{address:08x}","hit":int(hit),
                     "rdata":f"{word_value(base+word*4):08x}","latency_cycles":latency,"miss_class":kind})
        total_latency += latency
    total=len(rows); miss_rate=misses/total if total else 0
    miss_penalty=miss_latency-1
    summary={"accesses":total,"hits":hits,"misses":misses,
      "hit_ratio":hits/total if total else 0,"miss_ratio":miss_rate,
      "compulsory_misses":compulsory,"conflict_misses":conflict,"capacity_misses":capacity,
      "hit_time_cycles":1,"miss_latency_cycles":miss_latency,"miss_penalty_cycles":miss_penalty,
      "avg_hit_latency_cycles":1.0 if hits else 0.0,
      "measured_amat_cycles":total_latency/total if total else 0,
      "formula_amat_cycles":1+miss_rate*miss_penalty,
      "amat_difference_cycles":(total_latency/total if total else 0)-(1+miss_rate*miss_penalty)}
    return rows,summary

def write_csv(path, rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    fields=list(rows[0]) if rows else ["idx","op","addr","hit","rdata","latency_cycles","miss_class"]
    with path.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)

def make_plots(records,out_dir):
    try: import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib unavailable; CSV/Markdown retained, plots skipped"); return
    base=[r for r in records if r["cache_bytes"]==1024 and r["block_bytes"]==16]
    if base:
        plt.figure(); plt.bar([r["trace"] for r in base],[100*r["hit_ratio"] for r in base])
        plt.ylabel("Hit ratio (%)"); plt.xlabel("Trace"); plt.title("Hit ratio by workload (1 KiB / 16 B)")
        plt.xticks(rotation=25,ha="right"); plt.tight_layout(); plt.savefig(out_dir/"hit_ratio_by_trace.png",dpi=160); plt.close()
    for metric,ylabel,file,title in [("hit_ratio","Hit ratio","hit_ratio_vs_block_size.png","Hit ratio vs block size"),
                                    ("measured_amat_cycles","AMAT (cycles)","amat_vs_block_size.png","AMAT vs block size")]:
        plt.figure()
        for size in (512,1024,2048,4096):
            ss=sorted([r for r in records if r["trace"]=="seq" and r["cache_bytes"]==size],key=lambda x:x["block_bytes"])
            if ss: plt.plot([r["block_bytes"] for r in ss],[r[metric] for r in ss],marker="o",label=f"{size} B cache")
        plt.xlabel("Block size (bytes)"); plt.ylabel(ylabel); plt.title(title+" (sequential trace)")
        plt.legend(); plt.tight_layout(); plt.savefig(out_dir/file,dpi=160); plt.close()
    plt.figure()
    for block in (8,16,32,64):
        ss=sorted([r for r in records if r["trace"]=="seq" and r["block_bytes"]==block],key=lambda x:x["cache_bytes"])
        if ss: plt.plot([r["cache_bytes"] for r in ss],[r["hit_ratio"] for r in ss],marker="o",label=f"{block} B block")
    plt.xlabel("Cache size (bytes)"); plt.ylabel("Hit ratio"); plt.title("Hit ratio vs cache size")
    plt.legend(); plt.tight_layout(); plt.savefig(out_dir/"hit_ratio_vs_cache_size.png",dpi=160); plt.close()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--traces-dir",type=Path,default=DEFAULT_TRACES); p.add_argument("--out-dir",type=Path,default=DEFAULT_OUT)
    p.add_argument("--cache",type=int,default=1024); p.add_argument("--block",type=int,default=16)
    p.add_argument("--latency",type=int,default=4); p.add_argument("--no-sweep",action="store_true")
    p.add_argument("--rtl-csv",type=Path); p.add_argument("--trace",type=Path)
    a=p.parse_args(); a.out_dir.mkdir(parents=True,exist_ok=True)
    trace_files=sorted(a.traces_dir.glob("*.trace"))
    if not trace_files: raise SystemExit(f"No traces in {a.traces_dir}; generate them first")
    if a.rtl_csv:
        if not a.trace: p.error("--rtl-csv requires --trace")
        accesses=load_trace(a.trace); _,ref=simulate(accesses,a.cache,a.block,a.latency)
        with a.rtl_csv.open(newline="",encoding="utf-8") as f: actual=list(csv.DictReader(f))
        if len(actual)!=len(accesses): raise ValueError("RTL CSV row count does not match trace")
        hits=sum(int(x["hit"]) for x in actual); misses=len(actual)-hits
        latencies=[int(x["latency_cycles"]) for x in actual]; measured=sum(latencies)/len(latencies)
        result={**ref,"hits":hits,"misses":misses,"hit_ratio":hits/len(actual),
          "miss_ratio":misses/len(actual),"avg_hit_latency_cycles":sum(int(x["latency_cycles"]) for x in actual if int(x["hit"]))/hits if hits else 0,
          "measured_amat_cycles":measured,"formula_amat_cycles":1+(misses/len(actual))*ref["miss_penalty_cycles"],
          "amat_difference_cycles":measured-(1+(misses/len(actual))*ref["miss_penalty_cycles"]),
          "trace":a.trace.stem,"result_source":"RTL simulation CSV"}
        write_csv(a.out_dir/"rtl_summary.csv",[result]); print("RTL summary written"); return
    records=[]
    for path in trace_files:
        accesses=load_trace(path); rows,res=simulate(accesses,a.cache,a.block,a.latency)
        write_csv(a.out_dir/f"{path.stem}_reference.csv",rows)
        records.append({"trace":path.stem,"cache_bytes":a.cache,"block_bytes":a.block,
                        "mem_latency":a.latency,"result_source":"Python reference model",**res})
    write_csv(a.out_dir/"summary.csv",records)
    lines=["# Hit/miss and AMAT analysis","",f"Python reference model; cache {a.cache} B, block {a.block} B, MEM_LATENCY {a.latency}.","",
      "| Trace | Accesses | Hit % | Miss % | Compulsory | Conflict | Capacity | Miss penalty | Measured AMAT | Formula AMAT |",
      "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for r in records:
        lines.append(f"| {r['trace']} | {r['accesses']} | {100*r['hit_ratio']:.2f} | {100*r['miss_ratio']:.2f} | {r['compulsory_misses']} | {r['conflict_misses']} | {r['capacity_misses']} | {r['miss_penalty_cycles']} | {r['measured_amat_cycles']:.3f} | {r['formula_amat_cycles']:.3f} |")
    lines += ["","## Interpretation","",
      "Sequential and row-major traces expose spatial locality; loop accesses expose temporal locality. Random traffic spans a footprint larger than the cache. The 1024-byte stride phase maps repeatedly to one index in a 1 KiB direct-mapped cache.",
      "","Compulsory misses are first references to blocks. An equal-capacity fully associative LRU shadow cache separates later direct-mapped conflict misses (shadow hit) from capacity misses (shadow miss). This is an analytical classification, not extra hardware.",
      "","## AMAT","",
      "AMAT = hit_time + miss_rate × miss_penalty. Here hit_time = 1 and miss_latency = words_per_block × (MEM_LATENCY + 1) + 2; miss_penalty = miss_latency − 1. For 16-byte blocks and MEM_LATENCY=4, miss latency is 22 cycles and miss penalty is 21 cycles. The average per-access latency should equal the formula for the blocking read-only controller.",
      "","## Evidence boundary","",
      "Default results are Python reference-model results, not RTL measurements. Use --rtl-csv with the matching --trace to summarize actual trace-testbench output.",""]
    (a.out_dir/"summary.md").write_text("\n".join(lines),encoding="utf-8")
    if not a.no_sweep:
        sweep=[]
        for size in (512,1024,2048,4096):
            for block in (8,16,32,64):
                if block>size: continue
                for path in trace_files:
                    _,res=simulate(load_trace(path),size,block,a.latency)
                    sweep.append({"trace":path.stem,"cache_bytes":size,"block_bytes":block,"mem_latency":a.latency,**res})
        write_csv(a.out_dir/"parameter_sweep.csv",sweep); make_plots(sweep,a.out_dir)
    print(f"Analysed {len(trace_files)} traces; results: {a.out_dir}")

if __name__=="__main__": main()
