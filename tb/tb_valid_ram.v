// =============================================================================
// tb_valid_ram.v  (M2) self-checking unit test for rtl/valid_ram.v
// Valid-bit handling is an evaluation focus, so reset is tested carefully:
//   1. after reset every line reads 0
//   2. write a few lines -> only those read 1
//   3. write w_valid=0 clears a single line
//   4. reset is synchronous (no effect until the clock edge)
//   5. reset again (mid-use) -> every line 0 again
//   6. reset has priority over a write in the same cycle
// Run: iverilog -g2012 -o /tmp/tb rtl/valid_ram.v tb/tb_valid_ram.v && vvp /tmp/tb
// =============================================================================
`timescale 1ns/1ps
module tb_valid_ram;
    localparam INDEX_W = 6, DEPTH = 1 << INDEX_W;

    reg                clk = 0, rst_n = 0, we = 0, w_valid = 0;
    reg  [INDEX_W-1:0] index = 0, w_index = 0;
    wire               valid_out;
    integer            errors = 0, i;

    always #5 clk = ~clk;

    valid_ram #(.INDEX_W(INDEX_W)) dut (
        .clk(clk), .rst_n(rst_n), .index(index), .valid_out(valid_out),
        .we(we), .w_index(w_index), .w_valid(w_valid)
    );

    task write(input [INDEX_W-1:0] idx, input v);
        begin
            @(negedge clk); we = 1; w_index = idx; w_valid = v;
            @(negedge clk); we = 0;
        end
    endtask

    // count lines that read 1; check against expected set (via function below)
    task check_all(input [DEPTH-1:0] exp, input [8*32-1:0] what);
        integer k, bad;
        begin
            bad = 0;
            for (k = 0; k < DEPTH; k = k + 1) begin
                index = k; #1;
                if (valid_out !== exp[k]) bad = bad + 1;
            end
            if (bad) begin errors = errors + 1; $display("FAIL %0s: %0d lines wrong", what, bad); end
            else     $display("ok   %0s", what);
        end
    endtask

    reg [DEPTH-1:0] expv;

    initial begin
        // 1. reset
        repeat (2) @(posedge clk);
        @(negedge clk); rst_n = 1;
        check_all({DEPTH{1'b0}}, "after reset all lines invalid");

        // 2. set some lines
        write(0, 1); write(5, 1); write(34, 1); write(DEPTH-1, 1);
        expv = 0; expv[0] = 1; expv[5] = 1; expv[34] = 1; expv[DEPTH-1] = 1;
        check_all(expv, "only written lines are valid");

        // 3. clear one line
        write(5, 0); expv[5] = 0;
        check_all(expv, "w_valid=0 clears one line");

        // fill everything
        for (i = 0; i < DEPTH; i = i + 1) write(i, 1);
        check_all({DEPTH{1'b1}}, "all lines set");

        // 4. reset is synchronous: not visible until posedge
        @(negedge clk); rst_n = 0; index = 7; #1;
        if (valid_out !== 1'b1) begin errors = errors + 1; $display("FAIL reset acted asynchronously"); end
        @(posedge clk); #1;
        if (valid_out !== 1'b0) begin errors = errors + 1; $display("FAIL reset not applied at clock edge"); end
        else $display("ok   reset is synchronous");

        // 5. after mid-use reset everything is invalid
        @(negedge clk); rst_n = 1;
        check_all({DEPTH{1'b0}}, "second reset clears all lines");

        // 6. reset beats write in the same cycle
        @(negedge clk); rst_n = 0; we = 1; w_index = 12; w_valid = 1;
        @(negedge clk); rst_n = 1; we = 0;
        check_all({DEPTH{1'b0}}, "reset has priority over write");

        if (errors == 0) $display("PASS tb_valid_ram");
        else             $display("FAIL tb_valid_ram: %0d errors", errors);
        $finish;
    end
endmodule
