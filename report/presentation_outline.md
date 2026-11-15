# Final presentation outline — Direct-Mapped Cache Controller

Suggested duration: 7–9 minutes. Keep the slides visual and use the speaker notes below to explain the reasoning rather than reading paragraphs.

## Slide 1 — Title and team

**Direct-Mapped Cache Controller: RTL Design and Architectural Performance Analysis**

Show project title, course, team members and each member's role. M5 contribution: trace workloads, hit/miss analysis, AMAT and report coordination.

## Slide 2 — Problem statement

Main memory is slower than a small cache. The project builds a direct-mapped cache that keeps recently used blocks close to the CPU and measures how access patterns affect performance.

**Visual:** CPU → Cache → Main Memory hierarchy.

## Slide 3 — Cache organisation

Explain data RAM, tag RAM, valid-bit RAM, address decoder, comparator and controller FSM.

**Visual:** block diagram from the repository architecture. Emphasise that the valid bit prevents uninitialised tag contents from creating false hits.

## Slide 4 — Address breakdown

For the 1 KiB cache and 16-byte block configuration: 64 lines, 4 offset bits, 6 index bits and 22 tag bits.

**Visual:** 32-bit address split into Tag[31:10], Index[9:4], Offset[3:0]. Mention that the two least-significant byte bits are ignored for word-aligned accesses.

## Slide 5 — Lookup and refill

On a hit, return the selected word in one cycle. On a miss, fetch four words from memory, write the complete line, and only then set tag and valid.

**Visual:** FSM or a cold-miss timing waveform. Explain why the valid bit is asserted only after the final refill word.

## Slide 6 — Verification strategy

Show directed scenarios: reset/invalid line, cold miss then hit, spatial locality, same-index conflict, replacement, returned data and counters.

Use the existing M4 test results and distinguish testbench evidence from analytical-model evidence.

## Slide 7 — Workload design (M5)

Introduce seven traces: sequential, random, loop, stride, matrix row, matrix column and mixed. Explain which locality property each workload isolates.

**Visual:** small access-address sequence examples or a table of workload intent.

## Slide 8 — Hit ratio and miss taxonomy

Define hit ratio and miss ratio. Explain compulsory, conflict and capacity misses, including the equal-capacity fully associative LRU shadow-model convention used in the analysis.

**Visual:** generated hit-ratio-by-trace chart after running the analysis.

## Slide 9 — AMAT calculation

AMAT = hit time + miss rate × miss penalty.

For the base configuration, hit time is 1 cycle. Four words per block and MEM_LATENCY=4 give miss latency 22 cycles and miss penalty 21 cycles. Therefore AMAT = 1 + miss_rate × 21.

**Visual:** one worked example using an actual trace summary value.

## Slide 10 — Parameter sweep and trade-offs

Compare cache capacity (512 B to 4 KiB) and block size (8 B to 64 B). Larger blocks can exploit spatial locality but increase miss transfer cost; larger caches reduce evictions but consume more storage.

**Visual:** hit ratio vs block size, AMAT vs block size and hit ratio vs cache size plots.

## Slide 11 — Synthesis and implementation results

Use the actual synthesis tables from docs/synthesis.md. Explain which storage structures dominate area and whether RAM maps to BRAM, LUTRAM or flip-flops. Do not infer Fmax from Yosys statistics alone.

## Slide 12 — Conclusion and future work

Summarise what locality teaches us, why hit ratio alone is insufficient, and how AMAT captures miss cost. Future work: set associativity, write-back policy and broader workload benchmarks.

**Final takeaway:** cache performance is determined by the interaction between workload locality, mapping policy, capacity, block size and miss cost.
