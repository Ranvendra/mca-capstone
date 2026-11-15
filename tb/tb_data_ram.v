// =============================================================================
// tb_data_ram.v  (M2) self-checking unit test for rtl/data_ram.v
//   1. write 4 words of one block separately, block read has them in the
//      right positions (word 0 = bits [31:0])
//   2. overwrite one word, the other 3 words of that block keep their value
//   3. other lines are not touched
//   4. write is synchronous, read asynchronous
//   5. repeat 1-2 with BLOCK_BYTES = 8, 32, 64 (parameterization)
// Run: iverilog -g2012 -o /tmp/tb rtl/data_ram.v tb/tb_data_ram.v && vvp /tmp/tb
// =============================================================================
`timescale 1ns/1ps

// Generic checker for one BLOCK_BYTES value. Runs when `start` rises.
module data_ram_check #(
    parameter INDEX_W     = 6,
    parameter BLOCK_BYTES = 16
) (
    input  wire       clk,
    input  wire       start,
    output reg        done,
    output reg [31:0] errors
);
    localparam W      = BLOCK_BYTES / 4;
    localparam WSEL_W = $clog2(BLOCK_BYTES) - 2;
    localparam BITS   = BLOCK_BYTES * 8;

    reg  [INDEX_W-1:0] index = 0, w_index = 0;
    reg  [WSEL_W-1:0]  w_word_sel = 0;
    reg  [31:0]        w_word = 0;
    reg                we = 0;
    wire [BITS-1:0]    rd_block;

    data_ram #(.INDEX_W(INDEX_W), .BLOCK_BYTES(BLOCK_BYTES)) dut (
        .clk(clk), .index(index), .rd_block(rd_block),
        .we(we), .w_index(w_index), .w_word_sel(w_word_sel), .w_word(w_word)
    );

    function [31:0] val(input integer line, input integer word, input integer gen);
        val = 32'hA000_0000 + gen * 32'h0100_0000 + line * 32'h100 + word;
    endfunction

    task write(input integer line, input integer word, input [31:0] d);
        begin
            @(negedge clk); we = 1; w_index = line; w_word_sel = word; w_word = d;
            @(negedge clk); we = 0;
        end
    endtask

    task expect_block(input integer line, input [BITS-1:0] exp, input [8*32-1:0] what);
        begin
            index = line; #1;
            if (rd_block !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0dB] %0s line %0d:\n  got %h\n  exp %h", BLOCK_BYTES, what, line, rd_block, exp);
            end
        end
    endtask

    reg [BITS-1:0] exp3, exp4;
    integer k;

    initial begin
        done = 0; errors = 0;
        @(posedge start);

        // 1. words written in a scrambled order into line 3, and into line 4
        for (k = W - 1; k >= 0; k = k - 2) write(3, k, val(3, k, 0));
        for (k = W - 2; k >= 0; k = k - 2) write(3, k, val(3, k, 0));
        for (k = 0; k < W; k = k + 1)      write(4, k, val(4, k, 0));
        for (k = 0; k < W; k = k + 1) begin
            exp3[k*32 +: 32] = val(3, k, 0);
            exp4[k*32 +: 32] = val(4, k, 0);
        end
        expect_block(3, exp3, "words in correct position");
        expect_block(4, exp4, "second line");

        // 2. overwrite a single word (word 1) of line 3
        write(3, 1, 32'hDEAD_BEEF);
        exp3[1*32 +: 32] = 32'hDEAD_BEEF;
        expect_block(3, exp3, "single word overwrite");
        // and the last word
        write(3, W - 1, 32'h1234_5678);
        exp3[(W-1)*32 +: 32] = 32'h1234_5678;
        expect_block(3, exp3, "last word overwrite");

        // 3. neighbour line untouched
        expect_block(4, exp4, "neighbour line untouched");

        // 4. sync write / async read
        @(negedge clk); index = 4; we = 1; w_index = 4; w_word_sel = 0; w_word = 32'h5555_AAAA; #1;
        if (rd_block[31:0] !== val(4, 0, 0)) begin errors = errors + 1; $display("FAIL [%0dB] write visible before edge", BLOCK_BYTES); end
        @(posedge clk); #1;
        if (rd_block[31:0] !== 32'h5555_AAAA) begin errors = errors + 1; $display("FAIL [%0dB] write not visible after edge", BLOCK_BYTES); end
        @(negedge clk); we = 0;

        if (errors == 0) $display("ok   data_ram BLOCK_BYTES=%0d (%0d words/block)", BLOCK_BYTES, W);
        done = 1;
    end
endmodule

module tb_data_ram;
    reg clk = 0, start = 0;
    always #5 clk = ~clk;

    wire        d8, d16, d32, d64;
    wire [31:0] e8, e16, e32, e64;

    data_ram_check #(.INDEX_W(6), .BLOCK_BYTES(16)) c16 (.clk(clk), .start(start), .done(d16), .errors(e16));
    data_ram_check #(.INDEX_W(7), .BLOCK_BYTES(8))  c8  (.clk(clk), .start(start), .done(d8),  .errors(e8));
    data_ram_check #(.INDEX_W(5), .BLOCK_BYTES(32)) c32 (.clk(clk), .start(start), .done(d32), .errors(e32));
    data_ram_check #(.INDEX_W(4), .BLOCK_BYTES(64)) c64 (.clk(clk), .start(start), .done(d64), .errors(e64));

    initial begin
        #12 start = 1;
        wait (d8 && d16 && d32 && d64);
        if (e8 + e16 + e32 + e64 == 0) $display("PASS tb_data_ram");
        else                           $display("FAIL tb_data_ram: %0d errors", e8 + e16 + e32 + e64);
        $finish;
    end

    initial begin
        #100000 $display("FAIL tb_data_ram: timeout"); $finish;
    end
endmodule
