// =============================================================================
// data_ram.v  (M2)
// Purpose : hold the cached data blocks.
// Size    : 2^INDEX_W lines x (BLOCK_BYTES*8) bits.
// Ports   : read  -> index, rd_block (whole block; cache_top picks the word)
//           write -> clk, we, w_index, w_word_sel, w_word[31:0]
// Timing  : asynchronous read of the full block, synchronous WORD-granular
//           write on posedge clk: only word w_word_sel of line w_index is
//           updated, the other words of that block keep their value.
//
// Word w of a block sits at bits [w*32+31 : w*32] (word 0 = lowest address).
// w_word_sel width = $clog2(BLOCK_BYTES) - 2  (plan.md 4.3).
// No reset: contents are only used when the line is valid.
// =============================================================================
module data_ram #(
    parameter INDEX_W     = 6,
    parameter BLOCK_BYTES = 16
) (
    input  wire                           clk,
    // read port (async, whole block)
    input  wire [INDEX_W-1:0]             index,
    output wire [BLOCK_BYTES*8-1:0]       rd_block,
    // write port (sync, one 32-bit word)
    input  wire                           we,
    input  wire [INDEX_W-1:0]             w_index,
    input  wire [$clog2(BLOCK_BYTES)-3:0] w_word_sel,
    input  wire [31:0]                    w_word
);

    localparam DEPTH      = 1 << INDEX_W;
    localparam BLOCK_BITS = BLOCK_BYTES * 8;

    reg [BLOCK_BITS-1:0] mem [0:DEPTH-1];

    assign rd_block = mem[index];

    always @(posedge clk) begin
        if (we)
            mem[w_index][w_word_sel*32 +: 32] <= w_word;
    end

endmodule
