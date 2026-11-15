#!/usr/bin/env python3
"""Generate deterministic, word-aligned memory traces for the cache study.

Usage: python3 traces/gen_traces.py [--count 3000] [--seed 20261116]
All generated addresses stay in the 256 KiB memory model.
"""
from __future__ import annotations

import argparse
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MEM_BYTES = 256 * 1024
WORD_BYTES = 4
MATRIX_N = 64


def word_addr(index: int) -> int:
    return (index % (MEM_BYTES // WORD_BYTES)) * WORD_BYTES


def generate(count: int, seed: int) -> dict[str, list[int]]:
    rng = random.Random(seed)
    seq = [word_addr(i) for i in range(count)]
    random_trace = [word_addr(rng.randrange(MEM_BYTES // WORD_BYTES)) for _ in range(count)]

    # A 512-byte working set: 128 words, revisited in a deterministic shuffled order.
    working_set = list(range(128))
    rng.shuffle(working_set)
    loop = [word_addr(working_set[i % len(working_set)]) for i in range(count)]

    # Three phases isolate block, line and index-stride effects.
    strides = (16, 64, 1024)
    stride = [((i // (count // 3 or 1)) % len(strides)) for i in range(count)]
    stride_trace = [word_addr((i * strides[stride[i]]) // WORD_BYTES) for i in range(count)]

    matrix_words = MATRIX_N * MATRIX_N
    row_order = [r * MATRIX_N + c for r in range(MATRIX_N) for c in range(MATRIX_N)]
    col_order = [r * MATRIX_N + c for c in range(MATRIX_N) for r in range(MATRIX_N)]
    matrix_row = [word_addr(row_order[i % matrix_words]) for i in range(count)]
    matrix_col = [word_addr(col_order[i % matrix_words]) for i in range(count)]

    # Mostly reuse a compact hot set, with a small fraction of cold random traffic.
    hot = [word_addr(i) for i in range(96)]
    mixed = []
    for _ in range(count):
        mixed.append(rng.choice(hot) if rng.random() < 0.85 else word_addr(rng.randrange(MEM_BYTES // WORD_BYTES)))

    return {
        "seq": seq,
        "random": random_trace,
        "loop": loop,
        "stride": stride_trace,
        "matrix_row": matrix_row,
        "matrix_col": matrix_col,
        "mixed": mixed,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=3000, help="accesses per trace (minimum 2000)")
    parser.add_argument("--seed", type=int, default=20261116)
    args = parser.parse_args()
    if args.count < 2000:
        parser.error("--count must be at least 2000")

    for name, addresses in generate(args.count, args.seed).items():
        path = ROOT / f"{name}.trace"
        path.write_text("".join(f"0 {addr:08x}\n" for addr in addresses), encoding="ascii")
        print(f"{path.name}: {len(addresses)} read accesses")


if __name__ == "__main__":
    main()
