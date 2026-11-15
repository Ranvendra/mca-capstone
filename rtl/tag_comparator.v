// =============================================================================
// tag_comparator.v  (M2)
// Purpose : decide hit/miss for the line selected by the index.
// Ports   : tag_a (stored tag from tag_ram), tag_b (tag of cpu_addr),
//           valid (valid bit of the line)  ->  hit.
// Timing  : purely combinational.
//
//   hit = valid & (tag_a == tag_b)
//
// The valid bit is mandatory: after reset the tag RAM holds garbage (or 0),
// so without it address 0x0 (tag 0) could falsely "hit" on an empty line.
// =============================================================================
module tag_comparator #(
    parameter TAG_W = 22
) (
    input  wire [TAG_W-1:0] tag_a,
    input  wire [TAG_W-1:0] tag_b,
    input  wire             valid,
    output wire             hit
);

    assign hit = valid & (tag_a == tag_b);

endmodule
