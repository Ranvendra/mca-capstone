# Main-memory model (M3)

Owner: M3 (Narendra Singh). Files: `rtl/main_memory.v`, `tb/tb_main_memory.v`, `tb/tb_m3_cache_mem.v`, `tb/run_m3_tests.sh`.
It follows plan.md 4.2 (handshake) and 4.6 (contents). It is a **simulation model**: it is not synthesised (see `docs/synthesis.md`).

## 1. Ports and parameters

| Parameter | Default | Meaning |
|---|---|---|
| `MEM_WORDS` | 65536 | number of 32-bit words (65536 = 256 KB, covers trace addresses `0x0`..`0x3FFFF`) |
| `MEM_LATENCY` | 4 | cycles from request to ack. Minimum 1; 0 is treated as 1 |
| `STRICT_RDATA` | 0 | 1 = `mem_rdata` is X outside the ack cycle (debug aid, see section 4) |

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `clk`, `rst_n` | in | 1, 1 | clock, active-low synchronous reset |
| `mem_req` | in | 1 | request, held high until `mem_ack` |
| `mem_we` | in | 1 | 0 = read, 1 = write (write-through stretch goal) |
| `mem_addr` | in | 32 | byte address; `mem_addr[1:0]` is ignored |
| `mem_wdata` | in | 32 | write data |
| `mem_rdata` | out | 32 | read data, valid in the `mem_ack` cycle |
| `mem_ack` | out | 1 | 1-cycle pulse |
| `mem_read_count` | out | 32 | completed word reads since reset |
| `mem_write_count` | out | 32 | completed word writes since reset |

The two counters are extra outputs (not in plan.md 4.2). Testbenches that do not need them can leave them unconnected, as `tb_m1_smoke.v` does.

## 2. Behaviour

- `mem_ack` comes `MEM_LATENCY` cycles after the cycle in which `mem_req` is first high. With `MEM_LATENCY = 4`: request in cycle 1, ack in cycle 5. This is the timeline in `docs/fsm.md` section 4.
- Back-to-back words: `mem_req` may stay high. The ack cycle belongs to the old request; the next request starts in the cycle after it with a fresh count. So each word of a refill costs `MEM_LATENCY + 1` cycles, which is where `W*(L+1)` in the miss-penalty formula comes from.
- Dropping `mem_req` before the ack cancels the request: no ack, no write.
- Contents: `mem[w] = w * 32'h9E3779B1` (32-bit wrap-around), `w = mem_addr[31:2] % MEM_WORDS`. So the word at byte address `A` is `(A >> 2) * 0x9E3779B1`. Addresses above 256 KB wrap around.
- Reset clears the handshake and both counters. It does **not** restore the contents (a real RAM would not either). A testbench that writes and then wants the initial data back must restart the simulation.

## 3. Cross-check for M4 / M5

For a read-only run: `mem_read_count == miss_count * (BLOCK_BYTES / 4)`. Hits never touch memory. `tb_m3_cache_mem.v` checks this (base config, `MEM_LATENCY = 4`: 1824 requests, 1054 misses, 4216 word reads).

## 4. Tests

```
sh tb/run_m3_tests.sh
```

| Test | What it checks |
|---|---|
| `tb_main_memory.v` at latency 1, 4, 10 | ack arrives in exactly cycle `MEM_LATENCY`; ack is one cycle wide and never comes without a request; initial contents at fixed and 300 random addresses; back-to-back requests each get a full latency; `addr[1:0]` ignored; wrap above 256 KB; write, read back, neighbours unchanged; cancelled request does nothing; reset in the middle of a request; both counters; `MEM_LATENCY = 0` behaves like 1; `STRICT_RDATA` |
| `tb_m3_cache_mem.v` (6 configs) | `cache_top` + this memory with `STRICT_RDATA = 1`: data correct for sequential, repeated, random and ping-pong reads; hit latency 1 and miss latency `W*(L+1)+2`; refill addresses are block base, +4, +8, ...; `mem_read_count == miss_count * W` |
| `tb_m1_smoke.v` (M1's test) | run on the real `rtl/*.v` with `WRITE_SUPPORT` 0 and 1 at latency 1, 4, 10 |

Result: all 15 runs PASS. `iverilog -g2012 -Wall` gives no warnings for `rtl/main_memory.v` apart from the missing-timescale note that all RTL files have.

**Mutation check.** Each bug was put into a copy of `main_memory.v` and the unit test was run on it:

| Injected bug | `tb_main_memory` | `tb_m3_cache_mem` |
|---|---|---|
| ack one cycle late | FAIL | FAIL |
| wrong hash constant | FAIL | FAIL |
| ack stays high for 2 cycles | FAIL | FAIL |
| address not converted from bytes to words | FAIL | FAIL |
| writes ignored | FAIL | pass (read-only test) |
| cancelled request not forgotten | FAIL | pass (cache never cancels) |
| read counter also counts writes | FAIL | pass (read-only test) |
| no wrap-around above `MEM_WORDS` | FAIL | pass (addresses in range) |
| reset does not clear the counters | FAIL | pass (one reset only) |

## 5. Changes to other members' files

- `tb/stubs/m2_m3_stubs.v` is deleted. It was M1's temporary stand-in and plan.md 4.3 says to delete it once the real M2 and M3 files exist. From now on compile with `rtl/*.v`.
- `tb/tb_m1_smoke.v`: only the run command in the header comment was updated.

## 6. Viva questions to be ready for

1. *Why is the memory a behavioural model and not synthesised?* It stands for the slow level below the cache (DRAM or a bus). The project is about the cache; the model only has to give the right data after the right delay.
2. *Why a multiplicative hash for the contents?* Every word is different and can be computed from its address, so the testbench and the Python golden model know the expected data without a data file.
3. *What does `MEM_LATENCY` model?* The access time of main memory in clock cycles. Miss penalty = `W*(L+1)+1`, so it sets how expensive a miss is and therefore the AMAT.
4. *Why does each word cost `L+1` and not `L`?* The cache stores the word in the ack cycle and can only present the next address in the following cycle.
