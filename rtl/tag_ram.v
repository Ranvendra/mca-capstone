// =============================================================================
// tag_ram.v  (M2)
// Purpose : store the tag of the block currently held in each cache line.
// Size    : 2^INDEX_W entries x TAG_W bits.
// Ports   : read  -> index, tag_out
//           write -> clk, we, w_index, w_tag
// Timing  : asynchronous (combinational) read, synchronous write on posedge clk.
//           A write is visible on tag_out from the next cycle.
//
// No reset: the contents do not matter while the line's valid bit is 0
// (valid_ram is reset, tag_ram is not). This also lets synthesis map it to
// distributed/LUT RAM instead of flip-flops with reset logic.
// =============================================================================
module tag_ram #(
    parameter INDEX_W = 6,
    parameter TAG_W   = 22
) (
    input  wire               clk,
    // read port (async)
    input  wire [INDEX_W-1:0] index,
    output wire [TAG_W-1:0]   tag_out,
    // write port (sync)
    input  wire               we,
    input  wire [INDEX_W-1:0] w_index,
    input  wire [TAG_W-1:0]   w_tag
);

    localparam DEPTH = 1 << INDEX_W;

    reg [TAG_W-1:0] mem [0:DEPTH-1];

    assign tag_out = mem[index];

    always @(posedge clk) begin
        if (we)
            mem[w_index] <= w_tag;
    end

endmodule
