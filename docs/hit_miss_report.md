# Hit/miss report and AMAT analysis

## Objective and configuration

This study evaluates a parameterized direct-mapped cache using representative memory-access traces. The baseline uses 32-bit words, a 1 KiB cache, 16-byte blocks (four words per line), 64 cache lines and a four-cycle main-memory latency. The trace generator creates sequential, random, repeated-loop, phased-stride, row-major matrix, column-major matrix and mixed hot-set workloads.

## Address mapping

A 32-bit byte address is split into 22 tag bits, 6 index bits and 4 block-offset bits for the baseline. The index selects one of 64 cache lines, the tag identifies which memory block occupies that line, and the offset selects one of four words. The two least-significant byte-address bits are ignored because the interface uses word-aligned accesses.

## Locality hypotheses

Sequential and row-major accesses expose spatial locality. Repeated loop accesses expose temporal locality when the working set fits in cache. Uniform random traffic spans a much larger footprint and should have a lower hit ratio. Column-major matrix traversal changes the order of line reuse without changing the matrix data. The 1024-byte stride phase is useful for showing direct-map conflicts in a 1 KiB cache because addresses separated by the cache capacity map to the same index but have different tags.

## Metrics and miss classification

Hit ratio = hits / total accesses; miss ratio = misses / total accesses. A compulsory miss is the first reference to a memory block. The analysis maintains an equal-capacity fully associative LRU shadow cache: a later direct-mapped miss that would hit in the shadow is classified as a conflict miss; a miss in both is classified as a capacity miss. This is an explicit analytical convention, not extra cache hardware.

## Average memory access time

The controller answers a hit in one cycle. For W words per block and memory latency L, a miss takes W × (L + 1) + 2 cycles end-to-end. The miss penalty above the one-cycle hit time is therefore W × (L + 1) + 1. At the baseline (W=4, L=4), miss latency is 22 cycles and miss penalty is 21 cycles.

AMAT = hit_time + miss_rate × miss_penalty

At the baseline, AMAT = 1 + miss_rate × 21 cycles. The analysis script also calculates measured average latency as the mean of per-access latency values. For this blocking read-only controller, measured and formula AMAT should agree.

## Reproducible results

Run the trace generator followed by the analysis script:

    python3 traces/gen_traces.py --count 3000 --seed 20261116
    python3 analysis/analyze.py

The analysis writes per-trace reference-model CSVs, a summary CSV and Markdown table, a sweep across cache sizes 512 B/1 KiB/2 KiB/4 KiB and block sizes 8 B/16 B/32 B/64 B, and plots for hit ratio and AMAT.

**Evidence boundary:** default outputs are Python reference-model results, not RTL measurements. Once M4's trace-driven testbench has generated a simulation CSV, analyse it with:

    python3 analysis/analyze.py --rtl-csv analysis/results/seq_sim.csv --trace traces/seq.trace --cache 1024 --block 16 --latency 4

Do not label reference-model results as RTL results.

## Architectural interpretation

Larger blocks can improve spatial reuse, but they also increase the number of words transferred on a miss. Larger caches generally reduce conflict and capacity pressure, but consume more hardware resources. Direct mapping is simple and fast to index, yet frequently used blocks with the same index can evict one another. The parameter sweep makes these trade-offs measurable rather than assuming that the largest block or cache always gives the best AMAT.

## Limitations and future work

The baseline traces contain reads only, matching the frozen project scope. The Python model follows the repository's deterministic memory hash and documented refill timing. Final implementation evidence should include actual RTL trace CSVs. Natural extensions include set associativity and write-back policy comparisons.
