# Synthesis results (M3)

Owner: M3 (Narendra Singh). Scripts: `synth/`. Raw tool output: `synth/reports/`.
Every number in this file is copied from a tool report. The only calculated columns are the storage bit counts in section 3, and they are marked.

## 1. Tools and how to reproduce

| Tool | Version | Used for |
|---|---|---|
| Yosys | 0.71 | synthesis: generic gates, Xilinx 7-series cells, Lattice iCE40 cells |
| nextpnr-ice40 | 0.11.1 | place and route + static timing (Fmax) on iCE40 HX8K |
| Icarus Verilog | 13.0 | simulation only |

Vivado and Quartus are not installed, so there is **no vendor utilisation or timing report**. The Xilinx numbers below are Yosys `synth_xilinx` cell counts, not Vivado numbers.

```
make -C synth                                   # base config, generic cells
make -C synth TARGET=xilinx                     # base config, Xilinx cells
make -C synth CACHE_BYTES=4096 BLOCK_BYTES=64 TARGET=ice40
make -C synth sweep                             # all 24 runs + summary tables (about 1 minute)
make -C synth fmax                              # nextpnr timing runs
```

- Top module is `cache_top`. `rtl/main_memory.v` is **not** synthesised: it is a behavioural testbench model.
- `synth/synth.ys` is the plain Yosys script for the base config. `synth/run_synth.sh` runs the same steps with parameter overrides (`hierarchy -chparam`).
- Per run: `synth/reports/<target>_c<CACHE>_b<BLOCK>.rpt` (Yosys `stat`) and `.json`. All runs together: `synth/reports/summary.csv` and `summary.md`, built by `synth/summarize.py`.
- Full Yosys logs go to `synth/build/` (not in git, about 1 MB each).

**Warnings and latches: none.** `run_synth.sh` fails if the log contains an inferred latch or a warning from our RTL, and runs Yosys `check -assert` (combinational loops, multiple drivers). All 24 runs pass. Nothing to report to M1 or M2.

## 2. Base config (1 KB cache, 16 B blocks, read only)

### 2.1 Generic gates (`synth`), per module

| Module | Cells | of which flip-flops | Share of cells |
|---|---|---|---|
| `data_ram` | 22441 | 8192 | 82.2 % |
| `tag_ram` | 3909 | 1408 | 14.3 % |
| `valid_ram` | 528 | 64 | 1.9 % |
| `cache_top` (two 32-bit counters, word mux, address mux) | 324 | 64 | 1.2 % |
| `tag_comparator` | 80 | 0 | 0.3 % |
| `cache_controller` | 31 | 5 | 0.1 % |
| `addr_decoder` | 0 | 0 | 0 % |
| **Total** | **27313** | **9733** | |

Source: `synth/reports/generic_c1024_b16.rpt`.

### 2.2 FPGA targets

| Target | Logic LUTs | Memory | Flip-flops | Carry | Block RAM |
|---|---|---|---|---|---|
| Xilinx 7-series (`synth_xilinx`) | 312 (LUT2..LUT6) | 150 × `RAM64X1S` = 150 LUTs used as RAM | 133 `FDRE` | 18 `CARRY4` | 0 |
| Lattice iCE40 (`synth_ice40`) | 8996 `SB_LUT4` | none (built from flip-flops) | 9733 `SB_DFF*` | 65 `SB_CARRY` | 0 |

Sources: `xilinx_c1024_b16.rpt`, `ice40_c1024_b16.rpt`.

## 3. Sweep

### 3.1 Storage bits (calculated: lines × width)

| Cache | Block | Lines | Tag bits/line | Data bits | Tag bits | Valid bits | Overhead (tag+valid)/data |
|---|---|---|---|---|---|---|---|
| 512 B | 16 B | 32 | 23 | 4096 | 736 | 32 | 18.8 % |
| **1 KB** | **16 B** | **64** | **22** | **8192** | **1408** | **64** | **18.0 %** |
| 2 KB | 16 B | 128 | 21 | 16384 | 2688 | 128 | 17.2 % |
| 4 KB | 16 B | 256 | 20 | 32768 | 5120 | 256 | 16.4 % |
| 1 KB | 8 B | 128 | 22 | 8192 | 2816 | 128 | 35.9 % |
| 1 KB | 32 B | 32 | 22 | 8192 | 704 | 32 | 9.0 % |
| 1 KB | 64 B | 16 | 22 | 8192 | 352 | 16 | 4.5 % |

### 3.2 Area (from Yosys)

| Cache | Block | Generic cells | Generic FFs | `data_ram` share | Xilinx logic LUTs | Xilinx LUTs as RAM | Xilinx RAM primitive | Xilinx FFs | iCE40 LUT4 | iCE40 FFs |
|---|---|---|---|---|---|---|---|---|---|---|
| 512 B | 16 B | 13973 | 4933 | 80.6 % | 252 | 524 | 131 × `RAM32M` | 101 | 4617 | 4933 |
| **1 KB** | **16 B** | **27313** | **9733** | **82.2 %** | **312** | **150** | 150 × `RAM64X1S` | **133** | **8996** | **9733** |
| 2 KB | 16 B | 54329 | 19269 | 83.4 % | 417 | 298 | 149 × `RAM128X1S` | 197 | 17355 | 19269 |
| 4 KB | 16 B | 107553 | 38213 | 84.1 % | 618 | 592 | 148 × `RAM256X1S` | 325 | 35296 | 38213 |
| 1 KB | 8 B | 32015 | 11204 | 70.9 % | 355 | 172 | 86 × `RAM128X1S` | 196 | 10033 | 11204 |
| 1 KB | 32 B | 25298 | 8998 | 89.1 % | 593 | 1036 | 259 × `RAM32M` | 102 | 8526 | 8998 |
| 1 KB | 64 B | 24527 | 8631 | 90.8 % | 1027 | 2060 | 515 × `RAM32M` | 87 | 8418 | 8631 |

Block RAM count is 0 in every run on both FPGA targets. Full tables with every column: `synth/reports/summary.md`.

### 3.3 Write support (stretch goal), base config

| `WRITE_SUPPORT` | Generic cells | Generic FFs | Controller cells | Xilinx logic LUTs | Xilinx `MUXF7/8` | iCE40 LUT4 |
|---|---|---|---|---|---|---|
| 0 | 27313 | 9733 | 31 | 312 | 0 | 8996 |
| 1 | 27329 | 9734 | 47 | 709 | 386 | 9099 |

In generic gates write-through costs 16 cells and 1 flip-flop (the fourth FSM state). `synth_xilinx` reports 397 more LUTs and 386 `MUXF` cells for the same change with the same 150 `RAM64X1S`. I have not traced where the tool spends them, so treat the Xilinx `WRITE_SUPPORT = 1` figure as a tool result that still needs explaining, not as the real cost of the feature.

## 4. Timing (Fmax)

Yosys alone does not report Fmax. The numbers here come from nextpnr-ice40 static timing after routing, on an **iCE40 HX8K** (7680 logic cells, `ct256` package). Reports: `synth/reports/fmax_ice40_*.rpt`.

The timed top is `synth/fmax_wrap.v`, not `cache_top` directly. `cache_top` has 266 port bits (the package has 206 pins) and its hit path is combinational from `cpu_addr` to `cpu_ready`, so the wrapper puts a flip-flop on every input and every output. It adds no logic to the paths.

| Config | Memory built from | Result |
|---|---|---|
| 512 B / 16 B | flip-flops (design as it is) | **does not fit**: 9616 logic cells needed, 7680 available |
| 1 KB / 16 B | flip-flops (design as it is) | **does not fit** (placer runs out of logic cells) |
| 512 B / 16 B | block RAM, see below | 909 logic cells, 10 block RAMs, **89.45 MHz** (seed 1) |
| 1 KB / 16 B | block RAM, see below | 978 logic cells, 10 block RAMs, **83.15 MHz** (seed 1; seeds 2 and 3 gave 89.37 and 83.76 MHz) |

So there is **no Fmax for `cache_top` exactly as written**: on iCE40 the async-read arrays become flip-flops and the result is too big for the largest device nextpnr-ice40 supports.

The block-RAM rows are a different mapping and must be quoted with that condition. In the wrapper `cpu_addr` comes from a flip-flop. Yosys merges that flip-flop into the RAM as a registered read address, which is exactly what a block RAM needs. The function is the same, and it is what a real system looks like if the CPU's address register drives the cache directly. It is not what `cache_top` gives on its own with unregistered inputs.

Critical path of the 1 KB block-RAM run (12.03 ns = 4.70 ns logic + 7.32 ns routing): tag block RAM output → tag compare → controller (`cpu_valid`, hit) → clock enable of an output register. That is the hit path, as expected for a 1-cycle-hit Mealy design.

## 5. Analysis

1. **Where the area goes.** The data RAM. In generic gates it is 82 % of all cells in the base config (8192 flip-flops plus the write decoders and 64:1 read muxes around them), the tag RAM is 14 %, and everything that is "logic" (controller, comparator, counters) is under 2 %. The controller FSM is 31 cells and 5 flip-flops.
2. **Tag overhead.** 22 tag bits + 1 valid bit per 128 data bits = 18.0 % in the base config. A bigger cache lowers it slightly (one tag bit less per doubling). A bigger block lowers it a lot (4.5 % at 64 B) because there are fewer lines; 8 B blocks cost 35.9 %.
3. **BRAM, LUTRAM or flip-flops?** Never block RAM. Block RAM on these FPGAs has a registered (synchronous) read, and our RAMs are read asynchronously to get a 1-cycle hit. On Xilinx the data and tag arrays become distributed RAM (LUTRAM): 128 + 22 = 150 one-bit-wide `RAM64X1S` for the base config, single-port because read and write use the same index. On iCE40 there is no LUTRAM, so they become flip-flops: 9733 FFs and 8996 LUTs against 133 FFs and 462 LUTs on Xilinx for the same RTL. `valid_ram` is flip-flops on every target, because it needs a one-cycle clear of all bits.
4. **Scaling with cache size.** Generic cells and iCE40 LUT/FF counts double when the cache doubles. Xilinx grows more slowly because one LUT6 stores 64 bits.
5. **Scaling with block size at a fixed 1 KB.** Data bits stay at 8192, so generic area changes little (32015 → 24527 cells from 8 B to 64 B), and the change is mostly the tag RAM shrinking. The top-level word mux grows instead (259 → 1080 cells). For M5's trade-off: a larger block is slightly cheaper in area and tag overhead, but the miss penalty grows as `W*(L+1)+1` and there are fewer lines, so more conflicts.
6. **A tool effect to be honest about.** For arrays that are 32 or 16 lines deep, `synth_xilinx` chose `RAM32M` and reports more LUTs used as RAM than for the 64-line base config (524 for the 512 B cache against 150 for the 1 KB cache). This is how this Yosys version maps shallow memories, not a property of the design. The Xilinx column is therefore not a clean size trend; the generic and iCE40 columns are.
7. **Design trade-off.** Registering the read address would let the arrays go into block RAM (section 4: 978 logic cells and 10 block RAMs on iCE40 instead of about 9700 flip-flops), but then the RAM output arrives one cycle later and the hit time becomes 2 cycles. We keep the 1-cycle hit that plan.md asks for and accept LUTRAM or flip-flops; at 1 KB that is acceptable.

## 6. What each number means (viva)

| Term | Meaning |
|---|---|
| Cell | one primitive in the netlist: a gate, a mux, a flip-flop, a LUT |
| Generic cells (`$_AND_`, `$_MUX_`, `$_DFFE_PP_`, ...) | technology-independent gates. Good for comparing configs with each other, not an FPGA or ASIC area |
| `$_DFFE_PP_` / `$_SDFFE_PN0P_` | D flip-flop with enable / with enable and synchronous reset |
| LUT4, LUT6 | look-up table with 4 or 6 inputs: the basic logic element of an FPGA. It can implement any function of its inputs |
| LUTRAM (`RAM64X1S`) | a LUT6 used as a 64 × 1-bit RAM: synchronous write, **asynchronous read**. `S` = single port |
| `RAM32M` | a 4-LUT distributed-RAM primitive, 32 deep |
| `FDRE` | Xilinx flip-flop with clock enable and synchronous reset |
| `CARRY4` / `SB_CARRY` | dedicated carry chain: here the two 32-bit hit/miss counters |
| `MUXF7`, `MUXF8` | fixed muxes that combine LUT6 outputs into wider functions |
| BRAM (`RAMB18E1`, `SB_RAM40_4K`) | dedicated block RAM. Dense, but the read is **synchronous** |
| Logic cell (iCE40) | one LUT4 + one flip-flop + carry |
| Fmax | highest clock frequency at which every register-to-register path meets setup time, = 1 / critical path delay. Needs placement and routing, so synthesis alone cannot give it |
| Critical path | the slowest register-to-register path. Here: tag read → compare → hit → `cpu_ready` |
| Seed | starting point of the placer's random search. Different seeds give slightly different Fmax |

Questions to be ready for:

1. *Why is `main_memory` not synthesised?* It is a model of the slow memory outside the cache, used only in simulation.
2. *Why is there no block RAM?* Async read for a 1-cycle hit; block RAM reads synchronously.
3. *Why are the generic numbers so much bigger than the Xilinx ones?* Generic `synth` has no RAM primitive, so every stored bit is a flip-flop with a mux tree. Xilinx packs 64 bits into one LUT.
4. *Do you have an Fmax?* Only for the block-RAM mapping on iCE40 HX8K (83 to 89 MHz depending on seed), with inputs driven by registers. The design as written does not fit that device, and we had no Vivado for a Xilinx timing run.
5. *What limits the clock?* The hit path: RAM read, 22-bit tag compare, controller output logic.
