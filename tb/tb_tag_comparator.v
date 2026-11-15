// =============================================================================
// tb_tag_comparator.v  (M2) self-checking unit test for rtl/tag_comparator.v
// Mandatory case: valid=0 with matching tags must be a MISS.
// Run: iverilog -g2012 -o /tmp/tb rtl/tag_comparator.v tb/tb_tag_comparator.v && vvp /tmp/tb
// =============================================================================
`timescale 1ns/1ps
module tb_tag_comparator;
    reg  [21:0] tag_a, tag_b;
    reg         valid;
    wire        hit;
    integer     errors = 0, i, seed = 7;

    tag_comparator #(.TAG_W(22)) dut (.tag_a(tag_a), .tag_b(tag_b), .valid(valid), .hit(hit));

    task check(input [21:0] a, input [21:0] b, input v, input exp, input [8*40-1:0] name);
        begin
            tag_a = a; tag_b = b; valid = v; #1;
            if (hit !== exp) begin
                errors = errors + 1;
                $display("FAIL %0s: a=%h b=%h valid=%b hit=%b exp=%b", name, a, b, v, hit, exp);
            end else
                $display("ok   %0s: hit=%b", name, hit);
        end
    endtask

    initial begin
        check(22'h000000, 22'h000000, 1'b0, 1'b0, "valid=0, tag 0 == 0 (reset case)");
        check(22'h000006, 22'h000006, 1'b0, 1'b0, "valid=0, tags match");
        check(22'h000006, 22'h000006, 1'b1, 1'b1, "valid=1, tags match => hit");
        check(22'h000006, 22'h000007, 1'b1, 1'b0, "valid=1, tags differ (conflict)");
        check(22'h000006, 22'h000007, 1'b0, 1'b0, "valid=0, tags differ");
        check(22'h3FFFFF, 22'h3FFFFF, 1'b1, 1'b1, "all ones match");
        check(22'h200000, 22'h000000, 1'b1, 1'b0, "differ in MSB only");
        check(22'h000001, 22'h000000, 1'b1, 1'b0, "differ in LSB only");

        // random: compare against the reference expression
        for (i = 0; i < 500; i = i + 1) begin
            tag_a = $random(seed);
            tag_b = (i % 2) ? tag_a : $random(seed);
            valid = $random(seed);
            #1;
            if (hit !== (valid && tag_a == tag_b)) errors = errors + 1;
        end
        $display("ok   500 random vectors checked");

        if (errors == 0) $display("PASS tb_tag_comparator");
        else             $display("FAIL tb_tag_comparator: %0d errors", errors);
        $finish;
    end
endmodule
