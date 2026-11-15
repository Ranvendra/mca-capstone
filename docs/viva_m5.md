# M5 viva preparation

## Why do we need multiple traces?

A cache's performance depends on access patterns, not just cache capacity. Sequential and row-major workloads reveal spatial locality; repeated loops reveal temporal locality; random traffic provides a low-locality baseline; stride traffic can expose index conflicts.

## Why is a sequential trace expected to approach 75% hits with 16-byte blocks?

A 16-byte line holds four 32-bit words. When the first word of a new line is accessed, it misses and fills all four words. If the line is not evicted, the next three sequential word accesses hit. Over a long sequential stream, this is approximately one miss and three hits per line.

## Why can a 1,024-byte stride cause conflict misses?

A direct-mapped cache with 1 KiB capacity maps each memory block to one of 64 line indices. Addresses separated by 1 KiB have the same index bits but a different tag. Alternating between them repeatedly replaces the same cache line.

## What is AMAT?

Average Memory Access Time estimates average access cost: AMAT = hit time + miss rate × miss penalty. A low miss rate is valuable because a miss costs many more cycles than a hit.

## Why is miss penalty 21 cycles in the baseline?

There are four 32-bit words per 16-byte block. Each memory word costs MEM_LATENCY + 1 = 5 cycles because the ack cycle stores the word before the next request starts. The controller adds a miss-detection cycle and a response cycle, giving miss latency 4×5+2 = 22 cycles. Subtract the one-cycle hit time: miss penalty = 21 cycles.

## Why do measured AMAT and formula AMAT match?

For the blocking read-only controller, every request is either a one-cycle hit or a fixed-latency miss. The arithmetic average of those latencies is therefore exactly 1 + miss_rate × 21 (for the baseline configuration).

## Is a Python golden/reference model enough to prove RTL correctness?

No. It is an independent behavioural expectation and useful for fast sweeps. RTL correctness requires running the trace through the Verilog testbench and comparing each returned data word and hit/miss outcome. Keep reference-model and RTL measurements clearly labelled.

## What is the limitation of a direct-mapped cache?

Each memory block has exactly one possible line. Two active blocks with the same index compete even if other lines are unused. Set associativity gives a block multiple candidate lines and can reduce conflict misses at additional hardware complexity.
