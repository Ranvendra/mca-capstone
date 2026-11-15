# M5 analysis methodology

## Reproducibility

The committed trace inputs contain 3,000 read requests each. They are word-aligned and remain within the 256 KiB behavioural memory address range. The generator is deterministic for a fixed seed. To regenerate the same set:

    python3 traces/gen_traces.py --count 3000 --seed 20261116

## Reference model versus implementation evidence

The analysis script models the direct-mapped organisation in the RTL: block number determines index and tag; a valid matching tag is a hit; otherwise the complete block is fetched and replaces that line. The deterministic word value is derived from the same address hash as the behavioural memory model.

Reference-model output is useful for validating workload design and comparing configurations. It is not proof that the Verilog implementation is correct. For implementation evidence, run M4's trace-driven testbench, compare every access's hit/miss and returned data with its golden model, then pass the RTL-generated CSV to the analysis CLI. Keep the two result sources labelled separately.

## Metrics

Hit ratio and miss ratio are complementary fractions of total requests. Average hit latency is calculated from hit rows. Measured AMAT is the arithmetic mean of per-access latency. Formula AMAT uses the documented one-cycle hit time and the miss penalty derived from the actual FSM timing. For the baseline, four words are transferred, each word costs MEM_LATENCY + 1 cycles, and the FSM adds a detection and response cycle. Thus miss latency is 22 cycles and miss penalty is 21 cycles at MEM_LATENCY=4.

## Three-C miss taxonomy

A block's first reference is compulsory. The model additionally maintains a fully associative LRU cache with the same number of lines. If a later direct-mapped miss would have hit in that shadow cache, it is a conflict miss; if it would miss there too, it is classified as capacity. This convention is documented because the traditional 3C taxonomy can vary with the chosen fully associative replacement policy.

## Parameter sweep

The sweep varies cache capacity (512 B, 1 KiB, 2 KiB, 4 KiB) and block size (8 B, 16 B, 32 B, 64 B) independently. A larger block may exploit spatial locality but increases transfer cost. A larger cache can reduce evictions but increases storage. Compare both hit ratio and AMAT: the configuration with the highest hit ratio need not have the lowest AMAT.
