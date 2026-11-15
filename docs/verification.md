# Verification Plan and Coverage Report (M4)

This document describes the design verification strategy, test plan, reference models, and mutation analysis for the direct-mapped cache controller.

---

## 1. Verification Strategy and Environment

Verification is split into two complementary environments:

1. **Directed self-checking testbench (`tb/tb_cache_directed.v`)**:
   Targeted test sequences that systematically exercise corner cases, reset states, valid-bit handling, spatial/temporal locality, conflict misses, capacity fills, and cycle-accurate latencies.
2. **Trace-driven co-simulation (`tb/tb_cache_trace.v` + `analysis/golden_model.py`)**:
   Execution of real or synthetic memory traces against both the RTL design and a bit-accurate Python golden reference model. Outputs are logged to standard CSV files and cross-checked access-by-access using `analysis/compare.py`.

```
                  +---------------------------+
                  |  Memory Trace (.trace)    |
                  +-------------+-------------+
                                |
                +---------------+---------------+
                |                               |
                v                               v
    +-----------------------+       +-----------------------+
    | RTL Simulation (VVP)  |       | Python Golden Model   |
    | (cache_top + memory)  |       | (golden_model.py)     |
    +-----------+-----------+       +-----------+-----------+
                |                               |
                v                               v
    +-----------------------+       +-----------------------+
    | sim_results.csv       |       | golden_results.csv    |
    +-----------+-----------+       +-----------+-----------+
                |                               |
                +---------------+---------------+
                                |
                                v
                    +-----------------------+
                    |  analysis/compare.py  |
                    |  (exact match check)  |
                    +-----------------------+
```

---

## 2. Test Plan Matrix

| Test ID | Test Name | Stimulus Sequence | What it Validates | Hardware Bug Caught |
|---|---|---|---|---|
| **TC-01** | Cold start reset | Read address `0x00000000` right after reset | Valid bits initialized to 0. Must report MISS even though tag RAM holds 0 | Uninitialized valid RAM falsely hitting on tag 0 |
| **TC-02** | Temporal locality | Immediate re-read of address `0x00000000` | Line refilled in TC-01 is valid and matches tag. Reports HIT with 1-cycle latency | FSM failing to assert `valid_we` or `tag_we` on refill |
| **TC-03** | Spatial locality | Read addresses `0x00000004`, `0x00000008`, `0x0000000C` | 16-byte block refill populates all 4 words. All 3 must HIT with latency 1 | Refill writing only requested word rather than full block |
| **TC-04** | Non-zero word offset | Read `0x00001008` (word 2) cold, then `0x1000`, `0x1004`, `0x100C` | Block-aligned memory refill base address calculation | Address calculation offset bug in memory read request |
| **TC-05** | Conflict misses | Alternating reads between `0x00002010` and `0x00002410` (same index 1, tags 8 and 9) | Direct-mapped eviction behavior; ping-pong sequence yields 100% misses | Cache erroneously behaving as 2-way or ignoring tag mismatch |
| **TC-06** | Stale data check | Read remaining words of newly installed line after conflict eviction | New line completely overwrites old line data; no stale data remains | Data RAM write enable or word select corrupting words |
| **TC-07** | Cache capacity sweep | Read 64 distinct lines (`0x10000` to `0x103F0`), then re-read all 64 | All 64 cache lines function independently without interference | Index decoder bit width or address mapping faults |
| **TC-08** | Mid-test reset | Assert synchronous reset during active cache operation | Reset clears all valid bits and counters without hanging FSM | Reset logic missing in valid RAM or controller state register |
| **TC-09** | Counter & pulse checks | Monitor `stat_hit`, `stat_miss`, `hit_count`, `miss_count` | Exactly one pulse per request; `hit_count + miss_count == total_requests` | FSM double-pulsing on re-lookup or missing pulse |
| **TC-10** | Cycle latency | Measure cycles from `cpu_valid` to `cpu_ready` | Hit = 1 cycle; Miss = 22 cycles (for `MEM_LATENCY=4`) | Controller adding superfluous wait states or early ready |

---

## 3. Cycle-Accurate Timing and Latency

### Hit Timing (1 cycle)
The cache controller implements a Mealy output structure for `cpu_ready` and `stat_hit` in state `S_IDLE`. Because tag comparison and RAM lookups are combinational (asynchronous RAM read), `hit` is available in the same cycle `cpu_valid` is asserted:
- Cycle 1: `cpu_valid=1` -> `hit=1` -> `cpu_ready=1`, `stat_hit=1`, `cpu_rdata` valid. Latency = 1 cycle.

### Miss Penalty Breakdown (22 cycles)
For default parameters (`BLOCK_BYTES=16` -> 4 words per block, `MEM_LATENCY=4`):
- **Cycle 1 (S_IDLE)**: `cpu_valid=1` -> `hit=0` -> `stat_miss=1`. Transition to `S_REFILL`.
- **Cycles 2-6 (S_REFILL, Word 0)**: `mem_req=1` held for 4 latency cycles until `mem_ack` pulses on Cycle 6. Word 0 written to Data RAM.
- **Cycles 7-11 (S_REFILL, Word 1)**: `mem_req` held for 4 cycles. Ack on Cycle 11. Word 1 written.
- **Cycles 12-16 (S_REFILL, Word 2)**: `mem_req` held for 4 cycles. Ack on Cycle 16. Word 2 written.
- **Cycles 17-21 (S_REFILL, Word 3)**: `mem_req` held for 4 cycles. Ack on Cycle 21. Word 3 written, `tag_we=1`, `valid_we=1`. Transition to `S_RESPOND`.
- **Cycle 22 (S_RESPOND)**: `cpu_ready=1`, `cpu_rdata` served from Data RAM. Transition to `S_IDLE`.

Formula verified in RTL:
$$\text{Miss Penalty} = W \times (\text{MEM\_LATENCY} + 1) + 2 = 4 \times (4 + 1) + 2 = 22 \text{ cycles}$$

---

## 4. Mutation Analysis (Fault Injection)

To verify the rigor of the test suite, deliberate bugs (mutations) were injected into RTL modules. The directed testbench caught all injected mutations.

### Mutation 1: Missing Valid-bit Reset
- **Mutation**: In `rtl/valid_ram.v`, modified reset to set `valid_bits <= {DEPTH{1'b1}}`.
- **Result**: Caught immediately by TC-08.
- **Output**:
  ```
  FAIL [Time 17716000] Case 8: Cold miss line 0 after reset: Expected MISS, got HIT at addr 00010000
  FAIL [Time 17716000] Case 8: Cold miss line 0 after reset: Expected miss latency 22, got 1 at addr 00010000
  >>> DIRECTED TESTS FAILED WITH 4 ERRORS <<<
  ```

### Mutation 2: Bypassing Valid Bit in Tag Comparator
- **Mutation**: In `rtl/tag_comparator.v`, changed `assign hit = valid & (tag_a == tag_b)` to `assign hit = (tag_a == tag_b)`.
- **Result**: Caught immediately by TC-08.
- **Output**:
  ```
  FAIL [Time 17716000] Case 8: Cold miss line 0 after reset: Expected MISS, got HIT at addr 00010000
  >>> DIRECTED TESTS FAILED WITH 4 ERRORS <<<
  ```

### Mutation 3: Truncated Tag Comparator
- **Mutation**: In `rtl/tag_comparator.v`, compared only upper bits `tag_a[TAG_W-1:4] == tag_b[TAG_W-1:4]`.
- **Result**: Caught with 17 distinct failures across conflict tests (TC-05) and data checks (TC-04, TC-06).
- **Output**:
  ```
  FAIL [Time 386000] Case 4: Cold miss word 2 (0x1008): Expected MISS, got HIT at addr 00001008
  FAIL [Time 696000] Case 5: Conflict miss B evicts A (0x2410): Expected MISS, got HIT at addr 00002410
  >>> DIRECTED TESTS FAILED WITH 17 ERRORS <<<
  ```

---

## 5. Waveform Inspection Guide

Three waveform diagrams are generated from the simulation sequences and available under `docs/waveforms/`:

1. **Cold Miss + Refill**: `docs/waveforms/waveform_cold_miss.svg`
   Shows `cpu_valid` assertion, immediate `stat_miss` pulse in `S_IDLE`, 4 sequential memory reads in `S_REFILL`, `valid_we` assertion on word 3, and `cpu_ready` pulse in `S_RESPOND` on cycle 22.
2. **Spatial Hits**: `docs/waveforms/waveform_spatial_hits.svg`
   Shows 4 sequential word requests within the same cached block. Each word hits in `S_IDLE` with `stat_hit=1` and `cpu_ready=1` in 1 cycle, without accessing main memory.
3. **Conflict Misses**: `docs/waveforms/waveform_conflict_miss.svg`
   Shows ping-pong access between address A (`0x2010`) and address B (`0x2410`). Because both map to cache line 1, every request triggers an eviction, refill, and 100% miss penalty.

When viewing `tb_cache_directed.vcd` in GTKWave, organize signals into the following groups:

### 1. CPU Interface
- `tb_cache_directed.clk`
- `tb_cache_directed.rst_n`
- `tb_cache_directed.cpu_valid`
- `tb_cache_directed.cpu_addr[31:0]`
- `tb_cache_directed.cpu_rdata[31:0]`
- `tb_cache_directed.cpu_ready`
- `tb_cache_directed.stat_hit`
- `tb_cache_directed.stat_miss`

### 2. Cache Controller State & Storage
- `tb_cache_directed.dut.u_ctrl.state[1:0]` (0: IDLE, 1: REFILL, 2: RESPOND, 3: WRITE)
- `tb_cache_directed.dut.u_ctrl.hit`
- `tb_cache_directed.dut.u_ctrl.refill_word[1:0]`
- `tb_cache_directed.dut.tag_we`
- `tb_cache_directed.dut.valid_we`
- `tb_cache_directed.dut.data_we`

### 3. Main Memory Handshake
- `tb_cache_directed.mem_req`
- `tb_cache_directed.mem_addr[31:0]`
- `tb_cache_directed.mem_ack`
- `tb_cache_directed.mem_rdata[31:0]`

---

## 6. Functional Coverage Summary

- **Address Decoding**: 100% of fields exercised (all 64 cache indices, all 4 word offsets, tags spanning small and large addresses).
- **FSM States**: All reachable states exercised (`S_IDLE`, `S_REFILL`, `S_RESPOND`).
- **Memory Handshake**: Back-to-back request/ack sequence verified across 4-word refill blocks under strict memory timing checking.
- **Statistics**: Pulse mutual exclusion and counter integrity verified for 100% of test accesses.
