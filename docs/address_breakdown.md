# Address breakdown (tag / index / offset)

Owner: M1. Config used by the team: 32-bit address, 1 KB cache, 16 B block, 32-bit words.

## 1. Idea

Cache line (block) = 16 bytes, so the CPU address has to answer three questions:

| Field | Question it answers | Used for |
|---|---|---|
| **offset** | Which byte inside the block? | picking the word out of the block |
| **index** | Which cache line? (direct-mapped: only one choice) | addressing Tag RAM, Valid RAM, Data RAM |
| **tag** | Which of the many blocks that map to this line is stored right now? | compare with the stored tag |

```
 31                         10 9          4 3        0
+-----------------------------+------------+----------+
|        tag (22 bits)        | index (6)  | offset(4)|
+-----------------------------+------------+----------+
                                              \_ [3:2] = word_sel (which 32-bit word), [1:0] = byte in word (ignored, word-aligned access)
```

## 2. Formulas

```
NUM_LINES  = CACHE_BYTES / BLOCK_BYTES
OFF_W      = log2(BLOCK_BYTES)
INDEX_W    = log2(NUM_LINES)
TAG_W      = ADDR_W - INDEX_W - OFF_W
WORDS/BLK  = BLOCK_BYTES / 4
WSEL_W     = OFF_W - 2          (= log2(WORDS/BLK))

offset   = addr[OFF_W-1 : 0]
index    = addr[OFF_W+INDEX_W-1 : OFF_W]
tag      = addr[ADDR_W-1 : OFF_W+INDEX_W]
word_sel = addr[OFF_W-1 : 2]
```

For the base config: NUM_LINES = 1024/16 = **64**, OFF_W = **4**, INDEX_W = **6**, TAG_W = 32 - 6 - 4 = **22**, WORDS/BLK = 4, WSEL_W = 2.

Also: `OFF_W + INDEX_W = log2(CACHE_BYTES)`, so the tag is simply `addr >> log2(CACHE_BYTES)`. Two addresses exactly `CACHE_BYTES` (1 KB) apart always have the same index and different tag. That is the conflict-miss case.

## 3. What changes when parameters change

(`ADDR_W = 32`, word = 4 B. Block must be at least 8 B in this design.)

| CACHE_BYTES | BLOCK_BYTES | Lines | OFF_W | INDEX_W | TAG_W | Words/blk |
|---|---|---|---|---|---|---|
| 512  | 8  | 64  | 3 | 6 | 23 | 2 |
| 512  | 16 | 32  | 4 | 5 | 23 | 4 |
| 1024 | 8  | 128 | 3 | 7 | 22 | 2 |
| **1024** | **16** | **64** | **4** | **6** | **22** | **4** |
| 1024 | 32 | 32  | 5 | 5 | 22 | 8 |
| 1024 | 64 | 16  | 6 | 4 | 22 | 16 |
| 2048 | 16 | 128 | 4 | 7 | 21 | 4 |
| 4096 | 16 | 256 | 4 | 8 | 20 | 4 |
| 4096 | 64 | 64  | 6 | 6 | 20 | 16 |

Rules of thumb:
- Bigger block: offset grows, index shrinks (fewer lines), tag same. More spatial locality, but longer miss penalty and more conflicts.
- Bigger cache: index grows, tag shrinks.
- Tag overhead per line = TAG_W + 1 (valid) bits. For the base config 23 bits per 128 data bits, about 18 %.

## 4. Worked examples (base config)

Address `0x00001A2C` = `0000 0000 0000 0000 0001 1010 0010 1100`

| Field | Bits | Value |
|---|---|---|
| tag    | [31:10] | `0x6` (`00 0000 0000 0000 0000 0110`) |
| index  | [9:4]   | `0x22` = 34 (`100010`) |
| offset | [3:0]   | `0xC` = 12 (`1100`) |
| word_sel | [3:2] | 3 |
| block base address | addr with offset cleared | `0x00001A20` |

Check: `0x1A2C >> 10 = 6`, `(0x1A2C >> 4) & 0x3F = 0x1A2 & 0x3F = 0x22`, `0x1A2C & 0xF = 0xC`.

### Example A: cold miss (first access after reset)

1. Request `0x1A2C`. Index 34. `valid[34] = 0` after reset, so **miss** (even if the tag RAM happened to hold 6).
2. Controller refills line 34 with the 4 words at `0x1A20, 0x1A24, 0x1A28, 0x1A2C`.
3. Tag RAM[34] = 6 and valid[34] = 1 are written together with the last word.
4. CPU gets word 3 of the block (the word at `0x1A2C`).

### Example B: hit

Request `0x00001A28` right after example A: tag 6, index 34, offset 8, word_sel 2. `valid[34] = 1` and stored tag 6 equals request tag 6, so **hit**, answered in the same cycle (hit time = 1 cycle). The same is true for `0x1A20` and `0x1A24`: one miss brought in all 4 words (spatial locality).

### Example C: conflict miss

Request `0x00001E2C` (= `0x1A2C + 0x400`): tag 7, index 34, offset 12.
Line 34 is valid, but stored tag is 6, not 7, so **miss**. The line is refilled with block `0x1E20..0x1E2C` and tag 7 replaces tag 6. A later access to `0x1A2C` misses again (tag 6 was evicted). Alternating between these two addresses misses every time (ping-pong). That is the weakness of direct-mapped caches.
