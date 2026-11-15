// =============================================================================
// valid_ram.v  (M2)
// Purpose : one valid bit per cache line. valid=0 means "line is empty",
//           so the tag comparator must report a miss whatever the tag says.
// Size    : 2^INDEX_W x 1 bit.
// Ports   : read  -> index, valid_out
//           write -> clk, we, w_index, w_valid
//           rst_n -> active-low SYNCHRONOUS reset, clears every valid bit.
// Timing  : asynchronous read, synchronous write and reset (posedge clk).
//           Reset has priority over a write in the same cycle.
//
// Stored as a flat bit-vector (not a memory array) so that the whole thing
// can be cleared in one cycle. In hardware this is 2^INDEX_W flip-flops with
// a synchronous clear, plus a 2^INDEX_W:1 read mux.
// =============================================================================
module valid_ram #(
    parameter INDEX_W = 6
) (
    input  wire               clk,
    input  wire               rst_n,
    // read port (async)
    input  wire [INDEX_W-1:0] index,
    output wire               valid_out,
    // write port (sync)
    input  wire               we,
    input  wire [INDEX_W-1:0] w_index,
    input  wire               w_valid
);

    localparam DEPTH = 1 << INDEX_W;

    reg [DEPTH-1:0] valid_bits;

    assign valid_out = valid_bits[index];

    always @(posedge clk) begin
        if (!rst_n)
            valid_bits <= {DEPTH{1'b0}};
        else if (we)
            valid_bits[w_index] <= w_valid;
    end

endmodule
