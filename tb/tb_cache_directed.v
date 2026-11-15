// =============================================================================
// tb_cache_directed.v  (M4 Verification Suite)
// Directed, self-checking testbench for cache_top + main_memory.
// Covers all test cases specified in plan.md Section 10.4:
//   1. Reset state: tag=0/index=0 address 0x0 must be a MISS on cold start.
//   2. Cold miss followed by immediate hit (temporal locality).
//   3. Spatial locality: 4 words in a 16 B block => 1 miss + 3 hits.
//   4. Critical word / non-aligned access: access word 2 first, then remaining words.
//   5. Conflict misses: same index, different tags (A, B=A+1024), ping-pong => all misses.
//   6. Stale data check: line replacement updates data correctly.
//   7. Cache capacity sweep: fill all 64 lines (all miss), re-read all 64 (all hit).
//   8. Mid-test synchronous reset: resets valid RAM and statistic counters.
//   9. Counter integrity: exactly 1 stat pulse per request, hit_count + miss_count == total.
//  10. Cycle-accurate latency checks: hit = 1 cycle, miss = 4*(MEM_LATENCY+1)+2 cycles.
//
// Compile and run:
//   iverilog -g2012 -o /tmp/tb_directed rtl/*.v tb/tb_cache_directed.v
//   vvp /tmp/tb_directed
// =============================================================================

`timescale 1ns/1ps

module tb_cache_directed;
    parameter ADDR_W        = 32;
    parameter CACHE_BYTES   = 1024;
    parameter BLOCK_BYTES   = 16;
    parameter WRITE_SUPPORT = 0;
    parameter MEM_LATENCY   = 4;

    localparam WORDS_PER_BLOCK = BLOCK_BYTES / 4;
    localparam NUM_LINES       = CACHE_BYTES / BLOCK_BYTES;
    localparam EXPECTED_MISS_LATENCY = WORDS_PER_BLOCK * (MEM_LATENCY + 1) + 2;

    reg                     clk = 0;
    reg                     rst_n = 0;
    reg                     cpu_valid = 0;
    reg                     cpu_we = 0;
    reg  [ADDR_W-1:0]       cpu_addr = 0;
    reg  [31:0]             cpu_wdata = 0;

    wire [31:0]             cpu_rdata;
    wire                    cpu_ready;
    wire                    stat_hit;
    wire                    stat_miss;
    wire [31:0]             hit_count;
    wire [31:0]             miss_count;

    wire                    mem_req;
    wire                    mem_we;
    wire [ADDR_W-1:0]       mem_addr;
    wire [31:0]             mem_wdata;
    wire [31:0]             mem_rdata;
    wire                    mem_ack;

    always #5 clk = ~clk;

    cache_top #(
        .ADDR_W        (ADDR_W),
        .CACHE_BYTES   (CACHE_BYTES),
        .BLOCK_BYTES   (BLOCK_BYTES),
        .WRITE_SUPPORT (WRITE_SUPPORT)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpu_valid  (cpu_valid),
        .cpu_we     (cpu_we),
        .cpu_addr   (cpu_addr),
        .cpu_wdata  (cpu_wdata),
        .cpu_rdata  (cpu_rdata),
        .cpu_ready  (cpu_ready),
        .stat_hit   (stat_hit),
        .stat_miss  (stat_miss),
        .hit_count  (hit_count),
        .miss_count (miss_count),
        .mem_req    (mem_req),
        .mem_we     (mem_we),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_rdata  (mem_rdata),
        .mem_ack    (mem_ack)
    );

    main_memory #(
        .MEM_WORDS    (65536),
        .MEM_LATENCY  (MEM_LATENCY),
        .STRICT_RDATA (1)
    ) u_mem (
        .clk             (clk),
        .rst_n           (rst_n),
        .mem_req         (mem_req),
        .mem_we          (mem_we),
        .mem_addr        (mem_addr),
        .mem_wdata       (mem_wdata),
        .mem_rdata       (mem_rdata),
        .mem_ack         (mem_ack),
        .mem_read_count  (),
        .mem_write_count ()
    );

    // Golden memory expected contents function (plan.md 4.6)
    function [31:0] expected_mem(input [31:0] byte_addr);
        reg [31:0] w;
        begin
            w = (byte_addr >> 2) % 65536;
            expected_mem = w * 32'h9E3779B1;
        end
    endfunction

    integer errors = 0;
    integer total_tests = 0;
    integer expected_hits = 0;
    integer expected_misses = 0;

    reg [31:0] r_data;
    reg        r_hit;
    reg        r_miss;
    integer    r_lat;
    integer    r_pulses;

    // Driver task for single memory access
    task access(
        input        we,
        input [31:0] addr,
        input [31:0] wdata,
        input        expect_hit,
        input [255:0] test_name
    );
        reg done;
        reg [31:0] exp_data;
        begin
            total_tests = total_tests + 1;
            exp_data = expected_mem(addr);

            @(posedge clk); #1;
            cpu_valid = 1'b1;
            cpu_we    = we;
            cpu_addr  = addr;
            cpu_wdata = wdata;

            r_lat    = 0;
            r_hit    = 0;
            r_miss   = 0;
            r_pulses = 0;
            done     = 0;

            while (!done) begin
                @(negedge clk);
                r_lat = r_lat + 1;
                if (stat_hit)  begin r_hit  = 1'b1; r_pulses = r_pulses + 1; end
                if (stat_miss) begin r_miss = 1'b1; r_pulses = r_pulses + 1; end

                if (stat_hit && stat_miss) begin
                    errors = errors + 1;
                    $display("FAIL [Time %0t] %0s: stat_hit and stat_miss asserted simultaneously at addr %08h",
                             $time, test_name, addr);
                end

                if (cpu_ready) begin
                    r_data = cpu_rdata;
                    done = 1;
                end

                if (r_lat > 300) begin
                    errors = errors + 1;
                    $display("FAIL [Time %0t] %0s: Timeout (>300 cycles) waiting for cpu_ready at addr %08h",
                             $time, test_name, addr);
                    done = 1;
                end
            end

            @(posedge clk); #1;
            cpu_valid = 1'b0;
            cpu_we    = 1'b0;

            // Stat pulses check
            if (r_pulses != 1) begin
                errors = errors + 1;
                $display("FAIL [Time %0t] %0s: Expected 1 stat pulse, got %0d at addr %08h",
                         $time, test_name, r_pulses, addr);
            end

            // Hit/Miss classification check
            if (expect_hit && !r_hit) begin
                errors = errors + 1;
                $display("FAIL [Time %0t] %0s: Expected HIT, got MISS at addr %08h", $time, test_name, addr);
            end else if (!expect_hit && !r_miss) begin
                errors = errors + 1;
                $display("FAIL [Time %0t] %0s: Expected MISS, got HIT at addr %08h", $time, test_name, addr);
            end

            // Latency check
            if (expect_hit && r_lat != 1) begin
                errors = errors + 1;
                $display("FAIL [Time %0t] %0s: Expected hit latency 1, got %0d at addr %08h",
                         $time, test_name, r_lat, addr);
            end else if (!expect_hit && r_lat != EXPECTED_MISS_LATENCY) begin
                errors = errors + 1;
                $display("FAIL [Time %0t] %0s: Expected miss latency %0d, got %0d at addr %08h",
                         $time, test_name, EXPECTED_MISS_LATENCY, r_lat, addr);
            end

            // Data check (read access)
            if (!we && r_data !== exp_data) begin
                errors = errors + 1;
                $display("FAIL [Time %0t] %0s: Read data mismatch! Got %08h, expected %08h at addr %08h",
                         $time, test_name, r_data, exp_data, addr);
            end

            if (r_hit)  expected_hits   = expected_hits + 1;
            if (r_miss) expected_misses = expected_misses + 1;
        end
    endtask

    integer i;

    initial begin
        $dumpfile("tb_cache_directed.vcd");
        $dumpvars(0, tb_cache_directed);

        $display("==================================================================");
        $display("Starting Directed Verification Suite for Direct-Mapped Cache");
        $display("Configuration: CACHE=%0d B, BLOCK=%0d B, LINES=%0d, MEM_LATENCY=%0d",
                 CACHE_BYTES, BLOCK_BYTES, NUM_LINES, MEM_LATENCY);
        $display("==================================================================");

        // Synchronous Reset
        rst_n = 0;
        repeat (4) @(posedge clk);
        #1 rst_n = 1;
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------------
        // Test 1: Reset state and cold miss on tag 0 / index 0 (addr 0x00000000)
        // ---------------------------------------------------------------------
        $display("\n[Case 1] Reset check: Addr 0x0 must be MISS despite matching tag 0");
        access(0, 32'h0000_0000, 0, 0, "Case 1: Reset cold miss addr 0x0");

        // ---------------------------------------------------------------------
        // Test 2: Temporal locality (immediate re-read of same address)
        // ---------------------------------------------------------------------
        $display("[Case 2] Temporal locality: Re-reading 0x0 must be HIT (1 cycle)");
        access(0, 32'h0000_0000, 0, 1, "Case 2: Temporal hit addr 0x0");

        // ---------------------------------------------------------------------
        // Test 3: Spatial locality within block (1 miss + 3 hits for 16 B block)
        // ---------------------------------------------------------------------
        $display("[Case 3] Spatial locality: Words at 0x0004, 0x0008, 0x000C must HIT");
        access(0, 32'h0000_0004, 0, 1, "Case 3: Spatial hit 0x04");
        access(0, 32'h0000_0008, 0, 1, "Case 3: Spatial hit 0x08");
        access(0, 32'h0000_000C, 0, 1, "Case 3: Spatial hit 0x0C");

        // ---------------------------------------------------------------------
        // Test 4: Critical word / offset non-zero on cold block
        // ---------------------------------------------------------------------
        $display("[Case 4] Offset non-zero cold miss: Access 0x1008 (word 2) then 0x1000..0x100C");
        access(0, 32'h0000_1008, 0, 0, "Case 4: Cold miss word 2 (0x1008)");
        access(0, 32'h0000_1000, 0, 1, "Case 4: Spatial hit word 0 (0x1000)");
        access(0, 32'h0000_1004, 0, 1, "Case 4: Spatial hit word 1 (0x1004)");
        access(0, 32'h0000_100C, 0, 1, "Case 4: Spatial hit word 3 (0x100C)");

        // ---------------------------------------------------------------------
        // Test 5: Conflict miss (ping-pong on same index, different tags)
        // Addr A: 0x0000_2010 (index 1, tag 8)
        // Addr B: 0x0000_2410 (index 1, tag 9, A + 1024)
        // ---------------------------------------------------------------------
        $display("[Case 5] Conflict misses: Ping-pong A=0x2010 and B=0x2410 (same index)");
        access(0, 32'h0000_2010, 0, 0, "Case 5: Cold miss A (0x2010)");
        access(0, 32'h0000_2410, 0, 0, "Case 5: Conflict miss B evicts A (0x2410)");
        access(0, 32'h0000_2010, 0, 0, "Case 5: Conflict miss A evicts B (0x2010)");
        access(0, 32'h0000_2410, 0, 0, "Case 5: Conflict miss B evicts A again (0x2410)");

        // ---------------------------------------------------------------------
        // Test 6: Stale data check
        // Verify line replacement updates all words properly
        // ---------------------------------------------------------------------
        $display("[Case 6] Stale data verification: Check all words of currently cached line B");
        access(0, 32'h0000_2414, 0, 1, "Case 6: Spatial hit B word 1 (0x2414)");
        access(0, 32'h0000_2418, 0, 1, "Case 6: Spatial hit B word 2 (0x2418)");
        access(0, 32'h0000_241C, 0, 1, "Case 6: Spatial hit B word 3 (0x241C)");

        // ---------------------------------------------------------------------
        // Test 7: Full cache capacity fill (all 64 lines)
        // ---------------------------------------------------------------------
        $display("[Case 7] Cache capacity fill: Read 64 distinct lines (all miss), then re-read (all hit)");
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            access(0, 32'h0001_0000 + (i * 16), 0, 0, "Case 7: Cold miss capacity fill");
        end
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            access(0, 32'h0001_0000 + (i * 16), 0, 1, "Case 7: Hit capacity re-read");
        end

        // ---------------------------------------------------------------------
        // Test 8: Mid-test synchronous reset
        // ---------------------------------------------------------------------
        $display("[Case 8] Mid-test synchronous reset: Must invalidate all lines and clear counters");
        @(posedge clk); #1 rst_n = 0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1;
        repeat (2) @(posedge clk);

        if (hit_count !== 0 || miss_count !== 0) begin
            errors = errors + 1;
            $display("FAIL [Case 8]: Counters not cleared on reset (hit_count=%0d, miss_count=%0d)",
                     hit_count, miss_count);
        end

        expected_hits = 0;
        expected_misses = 0;

        // Lines that were cached before reset must now MISS
        access(0, 32'h0001_0000, 0, 0, "Case 8: Cold miss line 0 after reset");
        access(0, 32'h0001_0050, 0, 0, "Case 8: Cold miss line 5 after reset");

        // ---------------------------------------------------------------------
        // Test 9: Counter consistency check
        // ---------------------------------------------------------------------
        $display("[Case 9] Counter consistency check");
        if (hit_count !== expected_hits) begin
            errors = errors + 1;
            $display("FAIL [Case 9]: hit_count mismatch (got %0d, expected %0d)", hit_count, expected_hits);
        end
        if (miss_count !== expected_misses) begin
            errors = errors + 1;
            $display("FAIL [Case 9]: miss_count mismatch (got %0d, expected %0d)", miss_count, expected_misses);
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("DIRECTED VERIFICATION SUMMARY");
        $display("  Total Tests Run : %0d", total_tests);
        $display("  Errors Detected : %0d", errors);
        $display("  DUT Hit Count   : %0d", hit_count);
        $display("  DUT Miss Count  : %0d", miss_count);
        $display("==================================================================");

        if (errors == 0) begin
            $display(">>> ALL DIRECTED TESTS PASSED <<<");
            $finish(0);
        end else begin
            $display(">>> DIRECTED TESTS FAILED WITH %0d ERRORS <<<", errors);
            $finish(1);
        end
    end

endmodule
