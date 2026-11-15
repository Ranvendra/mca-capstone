// =============================================================================
// tb_addr_decoder.v  (M2) self-checking unit test for rtl/addr_decoder.v
//   1. Base config (1 KB, 16 B): hand-calculated addresses.
//   2. Changed config (2 KB, 32 B): hand-calculated addresses.
//   3. Every CACHE_BYTES (512..4096) x BLOCK_BYTES (8..64) combination:
//      random addresses, check that {tag,index,offset} == addr and that each
//      field has the expected width.
// Run: iverilog -g2012 -o /tmp/tb rtl/addr_decoder.v tb/tb_addr_decoder.v && vvp /tmp/tb
// =============================================================================
`timescale 1ns/1ps

// Checks one (CACHE_BYTES, BLOCK_BYTES) pair with random addresses.
module addr_decoder_sweep_check #(
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16
) (
    output reg [31:0] errors
);
    localparam OFF_W   = $clog2(BLOCK_BYTES);
    localparam INDEX_W = $clog2(CACHE_BYTES / BLOCK_BYTES);
    localparam TAG_W   = 32 - INDEX_W - OFF_W;

    reg  [31:0]        addr;
    wire [TAG_W-1:0]   tag;
    wire [INDEX_W-1:0] index;
    wire [OFF_W-1:0]   offset;
    wire [OFF_W-3:0]   word_sel;

    addr_decoder #(.ADDR_W(32), .CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES)) dut (
        .addr(addr), .tag(tag), .index(index), .offset(offset), .word_sel(word_sel)
    );

    integer i, seed;
    initial begin
        errors = 0;
        seed   = CACHE_BYTES * 131 + BLOCK_BYTES;
        if ($bits(tag) + $bits(index) + $bits(offset) != 32) errors = errors + 1;
        if ($bits(index) != INDEX_W || (1 << $bits(index)) != CACHE_BYTES / BLOCK_BYTES) errors = errors + 1;
        for (i = 0; i < 200; i = i + 1) begin
            addr = $random(seed);
            #1;
            if ({tag, index, offset} !== addr)       errors = errors + 1;
            if (index    !== (addr / BLOCK_BYTES) % (CACHE_BYTES / BLOCK_BYTES)) errors = errors + 1;
            if (tag      !== addr / CACHE_BYTES)     errors = errors + 1;
            if (word_sel !== (addr % BLOCK_BYTES) / 4) errors = errors + 1;
        end
    end
endmodule

module tb_addr_decoder;
    integer errors = 0;

    // ---------------- base config: 1 KB, 16 B => tag 22, index 6, offset 4 ----
    reg  [31:0] a1;
    wire [21:0] t1;
    wire [5:0]  i1;
    wire [3:0]  o1;
    wire [1:0]  w1;
    addr_decoder #(.ADDR_W(32), .CACHE_BYTES(1024), .BLOCK_BYTES(16)) dut1 (
        .addr(a1), .tag(t1), .index(i1), .offset(o1), .word_sel(w1)
    );

    // ---------------- changed config: 2 KB, 32 B => tag 21, index 6, offset 5 -
    reg  [31:0] a2;
    wire [20:0] t2;
    wire [5:0]  i2;
    wire [4:0]  o2;
    wire [2:0]  w2;
    addr_decoder #(.ADDR_W(32), .CACHE_BYTES(2048), .BLOCK_BYTES(32)) dut2 (
        .addr(a2), .tag(t2), .index(i2), .offset(o2), .word_sel(w2)
    );

    task check1(input [31:0] addr, input [21:0] et, input [5:0] ei, input [3:0] eo, input [1:0] ew);
        begin
            a1 = addr; #1;
            if (t1 !== et || i1 !== ei || o1 !== eo || w1 !== ew) begin
                errors = errors + 1;
                $display("FAIL 1K/16B addr=%08h got tag=%h idx=%h off=%h ws=%h  exp tag=%h idx=%h off=%h ws=%h",
                         addr, t1, i1, o1, w1, et, ei, eo, ew);
            end else
                $display("ok   1K/16B addr=%08h tag=%06h idx=%02h off=%h ws=%0d", addr, t1, i1, o1, w1);
        end
    endtask

    task check2(input [31:0] addr, input [20:0] et, input [5:0] ei, input [4:0] eo, input [2:0] ew);
        begin
            a2 = addr; #1;
            if (t2 !== et || i2 !== ei || o2 !== eo || w2 !== ew) begin
                errors = errors + 1;
                $display("FAIL 2K/32B addr=%08h got tag=%h idx=%h off=%h ws=%h  exp tag=%h idx=%h off=%h ws=%h",
                         addr, t2, i2, o2, w2, et, ei, eo, ew);
            end else
                $display("ok   2K/32B addr=%08h tag=%06h idx=%02h off=%02h ws=%0d", addr, t2, i2, o2, w2);
        end
    endtask

    // ---------------- sweep: all sizes used by M5 -----------------------------
    wire [31:0] e_512_8,  e_512_16,  e_512_32,  e_512_64;
    wire [31:0] e_1k_8,   e_1k_16,   e_1k_32,   e_1k_64;
    wire [31:0] e_2k_8,   e_2k_16,   e_2k_32,   e_2k_64;
    wire [31:0] e_4k_8,   e_4k_16,   e_4k_32,   e_4k_64;
    addr_decoder_sweep_check #(512,  8)  s00 (e_512_8);
    addr_decoder_sweep_check #(512,  16) s01 (e_512_16);
    addr_decoder_sweep_check #(512,  32) s02 (e_512_32);
    addr_decoder_sweep_check #(512,  64) s03 (e_512_64);
    addr_decoder_sweep_check #(1024, 8)  s10 (e_1k_8);
    addr_decoder_sweep_check #(1024, 16) s11 (e_1k_16);
    addr_decoder_sweep_check #(1024, 32) s12 (e_1k_32);
    addr_decoder_sweep_check #(1024, 64) s13 (e_1k_64);
    addr_decoder_sweep_check #(2048, 8)  s20 (e_2k_8);
    addr_decoder_sweep_check #(2048, 16) s21 (e_2k_16);
    addr_decoder_sweep_check #(2048, 32) s22 (e_2k_32);
    addr_decoder_sweep_check #(2048, 64) s23 (e_2k_64);
    addr_decoder_sweep_check #(4096, 8)  s30 (e_4k_8);
    addr_decoder_sweep_check #(4096, 16) s31 (e_4k_16);
    addr_decoder_sweep_check #(4096, 32) s32 (e_4k_32);
    addr_decoder_sweep_check #(4096, 64) s33 (e_4k_64);

    integer sweep_errors;

    initial begin
        // Base config, hand-calculated:  tag = addr>>10, idx = (addr>>4)&3F, off = addr&F, ws = (addr>>2)&3
        //  0x00000000 : all zero
        //  0x00001A2C : 0x1A2C>>10 = 6, (0x1A2)&3F = 0x22, off C, ws 3   (docs/address_breakdown.md)
        //  0x00001E2C : 0x1A2C + 1 KB => same index 0x22, tag 7 (conflict pair)
        //  0x0003FFF4 : top of trace range: tag 0xFF, idx 0x3F, off 4, ws 1
        //  0x12345678 : tag 0x48D15, idx 0x1234567&3F = 0x27, off 8, ws 2
        //  0xFFFFFFFF : tag 0x3FFFFF, idx 0x3F, off F, ws 3
        check1(32'h0000_0000, 22'h000000, 6'h00, 4'h0, 2'd0);
        check1(32'h0000_1A2C, 22'h000006, 6'h22, 4'hC, 2'd3);
        check1(32'h0000_1E2C, 22'h000007, 6'h22, 4'hC, 2'd3);
        check1(32'h0003_FFF4, 22'h0000FF, 6'h3F, 4'h4, 2'd1);
        check1(32'h1234_5678, 22'h048D15, 6'h27, 4'h8, 2'd2);
        check1(32'hFFFF_FFFF, 22'h3FFFFF, 6'h3F, 4'hF, 2'd3);

        // 2 KB / 32 B: tag = addr>>11, idx = (addr>>5)&3F, off = addr&1F, ws = (addr>>2)&7
        //  0x00001A2C : tag 3, (0xD1)&3F = 0x11, off 0x0C, ws 3
        //  0x00001A3C : same block, off 0x1C, ws 7 (last word of a 32 B block)
        //  0x12345678 : tag 0x2468A, (0x91A2B3)&3F = 0x33, off 0x18, ws 6
        //  0xFFFFFFFF : tag 0x1FFFFF, idx 0x3F, off 0x1F, ws 7
        check2(32'h0000_1A2C, 21'h000003, 6'h11, 5'h0C, 3'd3);
        check2(32'h0000_1A3C, 21'h000003, 6'h11, 5'h1C, 3'd7);
        check2(32'h1234_5678, 21'h02468A, 6'h33, 5'h18, 3'd6);
        check2(32'hFFFF_FFFF, 21'h1FFFFF, 6'h3F, 5'h1F, 3'd7);

        #300;   // let all sweep instances finish (200 x #1 each)
        sweep_errors = e_512_8 + e_512_16 + e_512_32 + e_512_64
                     + e_1k_8  + e_1k_16  + e_1k_32  + e_1k_64
                     + e_2k_8  + e_2k_16  + e_2k_32  + e_2k_64
                     + e_4k_8  + e_4k_16  + e_4k_32  + e_4k_64;
        if (sweep_errors != 0)
            $display("FAIL sweep: %0d errors over 16 configs", sweep_errors);
        else
            $display("ok   sweep: 16 configs (512..4096 B x 8..64 B), 200 random addresses each");
        errors = errors + sweep_errors;

        if (errors == 0) $display("PASS tb_addr_decoder");
        else             $display("FAIL tb_addr_decoder: %0d errors", errors);
        $finish;
    end
endmodule
