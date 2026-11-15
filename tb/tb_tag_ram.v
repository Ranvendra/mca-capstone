// =============================================================================
// tb_tag_ram.v  (M2) self-checking unit test for rtl/tag_ram.v
//   - write every line, read all back (async read)
//   - write takes effect only at the clock edge (sync write)
//   - we=0 does not change anything
//   - overwrite one line, neighbours unchanged
//   - read and write ports use different indices in the same cycle
// Run: iverilog -g2012 -o /tmp/tb rtl/tag_ram.v tb/tb_tag_ram.v && vvp /tmp/tb
// =============================================================================
`timescale 1ns/1ps
module tb_tag_ram;
    localparam INDEX_W = 6, TAG_W = 22, DEPTH = 1 << INDEX_W;

    reg                clk = 0, we = 0;
    reg  [INDEX_W-1:0] index = 0, w_index = 0;
    reg  [TAG_W-1:0]   w_tag = 0;
    wire [TAG_W-1:0]   tag_out;
    integer            errors = 0, i;

    always #5 clk = ~clk;

    tag_ram #(.INDEX_W(INDEX_W), .TAG_W(TAG_W)) dut (
        .clk(clk), .index(index), .tag_out(tag_out),
        .we(we), .w_index(w_index), .w_tag(w_tag)
    );

    function [TAG_W-1:0] pattern(input integer k);
        pattern = (k * 22'h01F3A5) ^ 22'h2AAAAA;
    endfunction

    task write(input [INDEX_W-1:0] idx, input [TAG_W-1:0] t);
        begin
            @(negedge clk); we = 1; w_index = idx; w_tag = t;
            @(negedge clk); we = 0;
        end
    endtask

    task expect_tag(input [INDEX_W-1:0] idx, input [TAG_W-1:0] t, input [8*32-1:0] what);
        begin
            index = idx; #1;
            if (tag_out !== t) begin
                errors = errors + 1;
                $display("FAIL %0s: line %0d got %h exp %h", what, idx, tag_out, t);
            end
        end
    endtask

    initial begin
        // 1. fill all lines, read back
        for (i = 0; i < DEPTH; i = i + 1) write(i, pattern(i));
        for (i = 0; i < DEPTH; i = i + 1) expect_tag(i, pattern(i), "fill/readback");
        $display("ok   wrote and read back all %0d lines", DEPTH);

        // 2. sync write: value must not appear before the edge
        @(negedge clk); index = 10; we = 1; w_index = 10; w_tag = 22'h123456;
        #1;
        if (tag_out !== pattern(10)) begin errors = errors + 1; $display("FAIL write visible before clock edge"); end
        @(posedge clk); #1;
        if (tag_out !== 22'h123456) begin errors = errors + 1; $display("FAIL write not visible after clock edge"); end
        @(negedge clk); we = 0;
        $display("ok   write is synchronous, read is asynchronous");

        // 3. we=0 must not write
        @(negedge clk); w_index = 11; w_tag = 22'h3FFFFF; we = 0;
        @(negedge clk);
        expect_tag(11, pattern(11), "we=0 wrote");
        $display("ok   we=0 leaves contents unchanged");

        // 4. neighbours untouched by the line-10 overwrite
        expect_tag(9,  pattern(9),  "neighbour 9");
        expect_tag(11, pattern(11), "neighbour 11");
        $display("ok   overwrite of line 10 did not disturb neighbours");

        // 5. read one line while writing another
        @(negedge clk); index = 20; we = 1; w_index = 21; w_tag = 22'h0ABCDE;
        @(posedge clk); #1;
        if (tag_out !== pattern(20)) begin errors = errors + 1; $display("FAIL read port disturbed by write to other line"); end
        @(negedge clk); we = 0;
        expect_tag(21, 22'h0ABCDE, "write while reading other line");
        $display("ok   independent read/write indices");

        if (errors == 0) $display("PASS tb_tag_ram");
        else             $display("FAIL tb_tag_ram: %0d errors", errors);
        $finish;
    end
endmodule
