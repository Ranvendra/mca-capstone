# 3-minute project demonstration script (M5)

## 0:00–0:25 — Problem and objective

"Our project implements a direct-mapped cache controller. The key question is not simply whether a cache is fast, but how workload locality changes its hit rate and average memory access time. My responsibility was to create reproducible memory traces and analyse the architectural trade-offs."

## 0:25–0:55 — Trace design

"I created seven workloads: sequential, random, repeated loop, phased stride, row-major matrix, column-major matrix and mixed hot-set traffic. Each has 3,000 word-aligned reads in the 256 KiB memory range. The generator uses a fixed seed, so results can be reproduced exactly."

Show the trace directory and open two examples. Explain that sequential accesses exploit spatial locality, while the repeated 512-byte working set demonstrates temporal locality. The 1,024-byte stride phase stresses a direct-mapped cache because it repeatedly selects the same line index in a 1 KiB cache.

## 0:55–1:35 — Metrics and reasoning

"Hit ratio is hits divided by total requests. Miss ratio is misses divided by total requests. I also classify misses using a same-capacity fully associative LRU shadow model: first-touch misses are compulsory, direct-mapped misses avoided by the shadow are conflict, and misses in both are capacity."

Show the generated summary. Point out that the classification is an analysis convention, not another hardware block.

## 1:35–2:15 — AMAT

"AMAT is hit time plus miss rate multiplied by miss penalty. Our hit time is one cycle. For a 16-byte block, four words are fetched. With four-cycle memory latency, the controller's end-to-end miss latency is 22 cycles, so the miss penalty over a hit is 21 cycles. Therefore AMAT is 1 + miss_rate × 21."

Show the formula and the measured average latency column. Explain that the two should agree for this blocking read-only controller.

## 2:15–2:45 — Trade-off and conclusion

"The sweep changes cache size and block size. Larger blocks can improve spatial reuse, but each miss transfers more words. Larger caches reduce eviction pressure but cost more storage. So the best design depends on both workload and AMAT, not just hit ratio."

## 2:45–3:00 — Evidence boundary

"The current generated tables are clearly labelled Python reference-model results. We use M4's RTL trace simulation CSV as implementation evidence and compare it access-by-access with the golden model. I do not claim a Python result is an RTL measurement."
