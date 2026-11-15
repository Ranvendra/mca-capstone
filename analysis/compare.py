#!/usr/bin/env python3
"""
compare.py
Compares cache simulation CSV output against the golden model CSV output.
Exit code: 0 on exact match, 1 on any discrepancy.

Usage:
    python3 compare.py <rtl_sim_csv> <golden_csv> [--check-latency]
"""

import argparse
import sys
import csv

def compare_csvs(rtl_path, gold_path, check_latency=False):
    print(f"Comparing RTL output ({rtl_path}) vs Golden model ({gold_path})...")

    try:
        with open(rtl_path, 'r', newline='') as f_rtl:
            rtl_reader = list(csv.DictReader(f_rtl))
    except Exception as e:
        print(f"ERROR: Failed to read RTL CSV: {e}")
        return 1

    try:
        with open(gold_path, 'r', newline='') as f_gold:
            gold_reader = list(csv.DictReader(f_gold))
    except Exception as e:
        print(f"ERROR: Failed to read Golden CSV: {e}")
        return 1

    if len(rtl_reader) != len(gold_reader):
        print(f"MISMATCH: Row count differs! RTL has {len(rtl_reader)} rows, Golden has {len(gold_reader)} rows.")
        return 1

    mismatches = 0
    total = len(rtl_reader)

    for i in range(total):
        r = rtl_reader[i]
        g = gold_reader[i]

        r_addr = int(r['addr'], 16)
        g_addr = int(g['addr'], 16)
        r_hit = int(r['hit'])
        g_hit = int(g['hit'])
        r_rdata = int(r['rdata'], 16)
        g_rdata = int(g['rdata'], 16)

        mismatch_fields = []
        if r_addr != g_addr:
            mismatch_fields.append(f"addr (RTL={r['addr']} vs GOLD={g['addr']})")
        if r_hit != g_hit:
            mismatch_fields.append(f"hit (RTL={r_hit} vs GOLD={g_hit})")
        if r_rdata != g_rdata:
            mismatch_fields.append(f"rdata (RTL={r['rdata']} vs GOLD={g['rdata']})")

        if check_latency:
            r_lat = int(r['latency_cycles'])
            g_lat = int(g['latency_cycles'])
            if r_lat != g_lat:
                mismatch_fields.append(f"latency (RTL={r_lat} vs GOLD={g_lat})")

        if mismatch_fields:
            if mismatches == 0:
                print(f"FIRST MISMATCH at row idx={i}: {', '.join(mismatch_fields)}")
            mismatches += 1

    if mismatches > 0:
        print(f"FAILED: Found {mismatches} mismatches out of {total} accesses.")
        return 1

    print(f"PASS: All {total} accesses match exactly between RTL and Golden Model.")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Compare RTL and Golden Model CSVs")
    parser.add_argument("rtl", help="Path to RTL simulation CSV")
    parser.add_argument("golden", help="Path to Golden Model CSV")
    parser.add_argument("--check-latency", action="store_true", help="Also strictly check cycle latency")

    args = parser.parse_args()
    ret = compare_csvs(args.rtl, args.golden, args.check_latency)
    sys.exit(ret)


if __name__ == "__main__":
    main()
