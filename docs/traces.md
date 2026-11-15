# Memory-access traces

Owner: M5 (trace generation and architectural analysis).

All traces use the frozen interface format from `plan.md`: one operation and one
hexadecimal byte address per line. Operation `0` means read; addresses are
32-bit, word-aligned and within `0x00000000..0x0003FFFF`. The generator uses a
fixed seed, so the same command produces byte-for-byte reproducible workloads:

```sh
python3 traces/gen_traces.py --count 3000 --seed 20261116
```

## Workload design

| Trace | Access pattern | Locality / question | Expected qualitative result |
|---|---|---|---|
| `seq.trace` | Consecutive 32-bit words | Spatial locality: each 16-byte line supplies four words | About 75% hits after compulsory line fills at the base configuration |
| `random.trace` | Uniform addresses across 256 KiB | Weak temporal and spatial locality | Low hit ratio; larger caches should help |
| `loop.trace` | Repeated shuffled 512-byte working set | Temporal locality: working set fits in a 1 KiB cache | High steady-state hit ratio |
| `stride.trace` | Phases of 16, 64 and 1024-byte strides | Increasing stride exposes line reuse and direct-map index conflicts | 1024-byte phase repeatedly maps to one index in the 1 KiB cache |
| `matrix_row.trace` | 64×64 integer matrix, row-major | Contiguous words within each row | Strong spatial locality |
| `matrix_col.trace` | Same matrix, column-major | Same data, different traversal order | Much weaker line reuse than row-major |
| `mixed.trace` | 85% hot-set accesses, 15% random | A simple mixed working-set workload | Good reuse with occasional cold/conflict misses |

These are hypotheses, not claimed measurements. Exact hit rates depend on cache
capacity, block size, mapping and trace length. The analysis script calculates
the results for each configuration rather than hard-coding expected percentages.

## Reproducibility and validation

The generator defaults to 3,000 accesses per trace and rejects fewer than 2,000.
Every record is a read, and every address is aligned to four bytes. Re-run the
generator after changing the seed or count; generated files are plain text and
can be inspected or consumed by the RTL trace testbench.
