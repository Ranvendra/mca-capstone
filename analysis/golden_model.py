#!/usr/bin/env python3
"""
golden_model.py
Python reference model for direct-mapped cache controller.
Matches the architectural parameters and timing defined in plan.md and docs/fsm.md.

Usage:
    python3 golden_model.py <trace_file> [--cache 1024] [--block 16] [--latency 4] [--out <csv_file>]
"""

import argparse
import math
import sys
import os

MEM_DEFAULT_WORDS = 65536  # 256 KB memory footprint

def mem_word(byte_addr, mem_words=MEM_DEFAULT_WORDS):
    """
    Deterministic memory initial contents from plan.md 4.6 and main_memory.v:
    mem[word_idx] = word_idx * 0x9E3779B1
    """
    word_idx = (byte_addr >> 2) % mem_words
    return (word_idx * 0x9E3779B1) & 0xFFFFFFFF


class DirectMappedCacheGolden:
    def __init__(self, addr_w=32, cache_bytes=1024, block_bytes=16, mem_latency=4, write_support=0, mem_words=MEM_DEFAULT_WORDS):
        self.addr_w = addr_w
        self.cache_bytes = cache_bytes
        self.block_bytes = block_bytes
        self.mem_latency = max(1, mem_latency)
        self.write_support = write_support
        self.mem_words = mem_words

        self.num_lines = cache_bytes // block_bytes
        self.words_per_block = block_bytes // 4
        self.off_w = int(math.log2(block_bytes))
        self.index_w = int(math.log2(self.num_lines))
        self.tag_w = addr_w - self.index_w - self.off_w
        self.wsel_w = int(math.log2(self.words_per_block))

        # Miss penalty formula from docs/fsm.md: words_per_block * (MEM_LATENCY + 1) + 2
        self.miss_latency = self.words_per_block * (self.mem_latency + 1) + 2
        self.hit_latency = 1

        self.reset()

    def reset(self):
        """Reset clears valid bits in valid RAM."""
        self.lines = [
            {
                'valid': False,
                'tag': 0,
                'data': [0] * self.words_per_block
            }
            for _ in range(self.num_lines)
        ]
        self.total_requests = 0
        self.hit_count = 0
        self.miss_count = 0

    def decode_address(self, addr):
        offset = addr & ((1 << self.off_w) - 1)
        word_sel = (addr >> 2) & ((1 << self.wsel_w) - 1)
        index = (addr >> self.off_w) & ((1 << self.index_w) - 1)
        tag = (addr >> (self.off_w + self.index_w)) & ((1 << self.tag_w) - 1)
        return tag, index, offset, word_sel

    def access(self, op, addr, wdata=0):
        """
        Simulate a single access.
        op: 0 = Read, 1 = Write
        addr: byte address
        wdata: 32-bit write data (for stretch write support)
        Returns: (hit: int, rdata: int, latency: int)
        """
        self.total_requests += 1
        tag, index, offset, word_sel = self.decode_address(addr)
        line = self.lines[index]

        # Tag comparator: valid & (stored_tag == tag)
        is_hit = line['valid'] and (line['tag'] == tag)

        if is_hit:
            self.hit_count += 1
            hit = 1
            if self.write_support and op == 1:
                # Write hit: update cache line and write-through to memory
                line['data'][word_sel] = wdata & 0xFFFFFFFF
                rdata = 0
                latency = self.mem_latency + 1
            else:
                rdata = line['data'][word_sel]
                latency = self.hit_latency
        else:
            self.miss_count += 1
            hit = 0
            if self.write_support and op == 1:
                # Write miss with no-write-allocate
                rdata = 0
                latency = self.mem_latency + 1
            else:
                # Read miss: fetch entire block from memory into cache
                block_base = addr & ~((1 << self.off_w) - 1)
                for w in range(self.words_per_block):
                    w_addr = block_base + (w * 4)
                    line['data'][w] = mem_word(w_addr, self.mem_words)
                line['tag'] = tag
                line['valid'] = True
                rdata = line['data'][word_sel]
                latency = self.miss_latency

        return hit, rdata, latency


def run_trace(cache, trace_path, out_csv_path=None):
    results = []
    with open(trace_path, 'r') as f:
        idx = 0
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            op = int(parts[0], 16)
            addr = int(parts[1], 16)
            wdata = int(parts[2], 16) if len(parts) >= 3 else 0

            hit, rdata, latency = cache.access(op, addr, wdata)
            results.append((idx, op, addr, hit, rdata, latency))
            idx += 1

    if out_csv_path:
        os.makedirs(os.path.dirname(os.path.abspath(out_csv_path)), exist_ok=True)
        with open(out_csv_path, 'w') as out_f:
            out_f.write("idx,op,addr,hit,rdata,latency_cycles\n")
            for r in results:
                out_f.write(f"{r[0]},{r[1]},{r[2]:08x},{r[3]},{r[4]:08x},{r[5]}\n")

    return results


def main():
    parser = argparse.ArgumentParser(description="Direct-Mapped Cache Python Golden Model")
    parser.add_argument("trace", help="Path to input trace file")
    parser.add_argument("--cache", type=int, default=1024, help="Cache size in bytes (default: 1024)")
    parser.add_argument("--block", type=int, default=16, help="Block size in bytes (default: 16)")
    parser.add_argument("--latency", type=int, default=4, help="Main memory latency cycles (default: 4)")
    parser.add_argument("--write", type=int, default=0, help="Write support: 0=read-only, 1=write-through")
    parser.add_argument("--out", type=str, default=None, help="Output CSV path")

    args = parser.parse_args()

    cache = DirectMappedCacheGolden(
        cache_bytes=args.cache,
        block_bytes=args.block,
        mem_latency=args.latency,
        write_support=args.write
    )

    results = run_trace(cache, args.trace, args.out)

    hit_rate = (cache.hit_count / cache.total_requests * 100.0) if cache.total_requests > 0 else 0.0
    miss_rate = (cache.miss_count / cache.total_requests * 100.0) if cache.total_requests > 0 else 0.0

    print(f"Golden Model Summary:")
    print(f"  Total Requests : {cache.total_requests}")
    print(f"  Hits           : {cache.hit_count} ({hit_rate:.2f}%)")
    print(f"  Misses         : {cache.miss_count} ({miss_rate:.2f}%)")
    if args.out:
        print(f"  Output CSV     : {args.out}")


if __name__ == "__main__":
    main()
