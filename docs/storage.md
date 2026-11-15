# Storage datapath (M2)

Owner: M2. Files: `rtl/addr_decoder.v`, `rtl/tag_ram.v`, `rtl/valid_ram.v`, `rtl/data_ram.v`, `rtl/tag_comparator.v` and their tests `tb/tb_<module>.v`.
Ports and parameters follow plan.md 4.3 exactly, so `cache_top.v` (M1) connects to them as they are.

## 1. Port table

Base config: `ADDR_W=32, CACHE_BYTES=1024, BLOCK_BYTES=16` gives `INDEX_W=6, TAG_W=22, OFF_W=4, WSEL_W=2, BLOCK_BITS=128`.

| Module | Parameters | Port | Dir | Width | Timing |
|---|---|---|---|---|---|
| `addr_decoder` | `ADDR_W, CACHE_BYTES, BLOCK_BYTES` | `addr` | in | ADDR_W | combinational |
| | | `tag` | out | ADDR_W - log2(CACHE_BYTES) | |
| | | `index` | out | log2(CACHE_BYTES/BLOCK_BYTES) | |
| | | `offset` | out | log2(BLOCK_BYTES) | |
| | | `word_sel` | out | log2(BLOCK_BYTES) - 2 | |
| `tag_ram` | `INDEX_W, TAG_W` | `clk` | in | 1 | |
| | | `index` → `tag_out` | in → out | INDEX_W → TAG_W | async read |
| | | `we, w_index, w_tag` | in | 1, INDEX_W, TAG_W | sync write |
| `valid_ram` | `INDEX_W` | `clk, rst_n` | in | 1, 1 | sync active-low reset clears all bits |
| | | `index` → `valid_out` | in → out | INDEX_W → 1 | async read |
| | | `we, w_index, w_valid` | in | 1, INDEX_W, 1 | sync write (reset wins) |
| `data_ram` | `INDEX_W, BLOCK_BYTES` | `clk` | in | 1 | |
| | | `index` → `rd_block` | in → out | INDEX_W → BLOCK_BYTES*8 | async read of whole block |
| | | `we, w_index, w_word_sel, w_word` | in | 1, INDEX_W, log2(BLOCK_BYTES)-2, 32 | sync write of ONE word |
| `tag_comparator` | `TAG_W` | `tag_a, tag_b, valid` → `hit` | in → out | TAG_W, TAG_W, 1 → 1 | combinational, `hit = valid & (tag_a == tag_b)` |

Word `w` of a block is stored at `rd_block[w*32 +: 32]` (word 0 = lowest address). `cache_top` uses the same convention when it picks `cpu_rdata`.

## 2. Design notes

- **No hard-coded sizes.** Every width comes from parameters through `$clog2`. Supported: power-of-2 sizes, `BLOCK_BYTES >= 8` (≥ 2 words), `CACHE_BYTES >= 2*BLOCK_BYTES`. The unit tests cover every `CACHE_BYTES` in {512, 1K, 2K, 4K} × `BLOCK_BYTES` in {8, 16, 32, 64}.
- **Only `valid_ram` has a reset.** Tag and data contents mean nothing while the valid bit is 0, so resetting them would only add logic. It would also prevent them from mapping to RAM primitives.
- **`valid_ram` is a flat bit-vector, not a memory array**, so all 64 bits can be cleared in one cycle. Reset has priority over a write in the same cycle, so a reset during a refill always leaves the line invalid.
- **Word-granular write in `data_ram`** (`mem[w_index][w_word_sel*32 +: 32] <= w_word`): the controller fills one word per memory ack, and the other words of the block must not change.
- Read ports are asynchronous because the spec wants a 1-cycle hit: index → RAM read → compare → `cpu_ready` all happen in the same cycle.
- Latch-free: there are no `always @(*)` blocks. Everything is either `assign` or `always @(posedge clk)`.

## 3. How this maps in synthesis (for M3's report and the viva)

| Storage | Bits (base config) | Likely FPGA mapping | Why |
|---|---|---|---|
| `data_ram` | 64 × 128 = 8192 | **LUTRAM** (distributed RAM), or flip-flops + muxes in generic `synth` | Async read. Block RAM (BRAM) on Xilinx/Intel/iCE40 has a **synchronous** (registered) read, so an async-read array cannot go into BRAM. |
| `tag_ram` | 64 × 22 = 1408 | LUTRAM / FFs | Same reason. Small anyway. |
| `valid_ram` | 64 × 1 | **Flip-flops** (64 FFs with sync clear + 64:1 mux) | Needs a one-cycle clear of all bits. RAM primitives cannot clear every word at once. |
| decoder | 0 | wires only | It only slices bits. |
| comparator | 0 | ~22 XNOR + AND tree (a few LUTs) | Equality compare. |

- Yosys generic `synth` (no FPGA target) has no RAM primitives, so it turns these arrays into `$dff` cells and read muxes. The cell count will be dominated by `data_ram`.
- With `synth_xilinx` the 64-deep arrays fit `RAM64M`/`RAM64X1D` LUTRAM. With `synth_ice40` there is no LUTRAM, and BRAM needs a sync read, so the arrays end up as flops (large).
- To get BRAM you would register the read address: the RAM output would then come one cycle later, so hit time would be 2 cycles. That is a design trade-off to mention in the report, not a bug.
- Tag overhead = (TAG_W + 1) / (BLOCK_BYTES*8) = 23 / 128 ≈ 18 % for the base config.

## 4. Unit tests

Run all of them (needs Icarus Verilog):

```
sh tb/run_m2_tests.sh
```

| Testbench | What it checks |
|---|---|
| `tb_addr_decoder.v` | 6 hand-calculated addresses for 1K/16B (including the `0x1A2C` / `0x1E2C` conflict pair from `docs/address_breakdown.md`), 4 for 2K/32B, plus 200 random addresses on each of the 16 size combinations (`{tag,index,offset} == addr`, field widths). |
| `tb_tag_comparator.v` | valid=0 with matching tags gives a miss (mandatory case, also with tag 0), match/mismatch, MSB/LSB difference, 500 random vectors. |
| `tb_tag_ram.v` | fill and read back all 64 lines, write is synchronous, `we=0` does nothing, neighbours untouched, read and write at different indices in the same cycle. |
| `tb_valid_ram.v` | all 0 after reset, only written lines are 1, `w_valid=0` clears one line, reset is synchronous, a second reset clears everything, reset wins over a write in the same cycle. |
| `tb_data_ram.v` | 4 words written separately (in scrambled order) land in the right positions, overwriting one word leaves the other 3 intact, other lines untouched, sync write / async read. Repeated for BLOCK_BYTES = 8, 16, 32, 64. |

Results on this branch: all 5 PASS. `iverilog -g2012 -Wall` gives no warnings for the five RTL files.

**Mutation check.** Each bug below was put in by hand, the tests were run, and then the change was reverted:

| Injected bug | Caught by |
|---|---|
| `valid_ram` reset does not clear the bits | `tb_valid_ram` (FAIL) |
| comparator ignores the valid bit | `tb_tag_comparator` (FAIL) |
| `data_ram` always writes word 0 | `tb_data_ram` (FAIL) |
| decoder index shifted by one bit | `tb_addr_decoder` (FAIL) |

**Integration.** M1's `tb/tb_m1_smoke.v` was also run with the real M2 files in place of the stubs. Only `main_memory` still came from the stub file, because M3's version is not merged yet. It passed with `WS=0` and with `WS=1`.

Note for M1: once M3's `rtl/main_memory.v` is merged, delete `tb/stubs/m2_m3_stubs.v`. Until then, do not compile it together with `rtl/*.v`, because the module names would be defined twice.
