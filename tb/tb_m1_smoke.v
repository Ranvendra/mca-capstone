// =============================================================================
// tb_m1_smoke.v  (M1) quick self-check of cache_top + cache_controller.
// This is NOT the M4 verification suite; it only proves the M1 FSM/wiring:
//   cold miss -> refill -> same-block hits, conflict miss, stat pulse rule,
//   latency numbers used in docs/fsm.md, and (WS=1) write-through behaviour.
//
// Run (before real M2/M3 exist, with the temporary stubs):
//   iverilog -g2012 -o /tmp/m1_smoke tb/stubs/m2_m3_stubs.v rtl/cache_controller.v \
//            rtl/cache_top.v tb/tb_m1_smoke.v && vvp /tmp/m1_smoke
// With write support:  add  -Ptb_m1_smoke.WS=1
// With the real files: replace the stub file by rtl/*.v (except nothing else needed).
// Waveform: tb_m1_smoke.vcd
// =============================================================================
`timescale 1ns/1ps
module tb_m1_smoke;
    parameter WS      = 0;
    parameter LATENCY = 4;

    reg         clk = 0, rst_n = 0;
    reg         cpu_valid = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata, hit_count, miss_count;
    wire        cpu_ready, stat_hit, stat_miss;
    wire        mem_req, mem_we, mem_ack;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;

    always #5 clk = ~clk;

    cache_top #(.WRITE_SUPPORT(WS)) dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_valid(cpu_valid), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .stat_hit(stat_hit), .stat_miss(stat_miss),
        .hit_count(hit_count), .miss_count(miss_count),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ack(mem_ack)
    );

    main_memory #(.MEM_LATENCY(LATENCY)) mem (
        .clk(clk), .rst_n(rst_n), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
    );

    integer errors = 0, n_req = 0;
    integer hits_seen = 0, misses_seen = 0;

    function [31:0] expect_word(input [31:0] a);
        expect_word = (a >> 2) * 32'h9E3779B1;
    endfunction

    // One request. lat counts cycles from cpu_valid up to and including cpu_ready.
    reg [31:0] r_data; reg r_hit, r_miss; integer r_lat, r_pulses;
    task access(input we, input [31:0] addr, input [31:0] wdata);
        reg done;
        begin
            cpu_valid = 1; cpu_we = we; cpu_addr = addr; cpu_wdata = wdata;
            r_lat = 0; r_hit = 0; r_miss = 0; r_pulses = 0; done = 0;
            while (!done) begin
                @(negedge clk);                     // mid-cycle: everything settled
                r_lat = r_lat + 1;
                if (stat_hit)  begin r_hit  = 1; r_pulses = r_pulses + 1; end
                if (stat_miss) begin r_miss = 1; r_pulses = r_pulses + 1; end
                if (stat_hit && stat_miss) begin errors = errors + 1; $display("FAIL: hit and miss together"); end
                if (cpu_ready) begin r_data = cpu_rdata; done = 1; end
                if (r_lat > 200) begin errors = errors + 1; $display("FAIL: timeout"); done = 1; end
            end
            @(posedge clk); #1;
            n_req = n_req + 1;
            if (r_pulses != 1) begin errors = errors + 1; $display("FAIL: %0d stat pulses for one request", r_pulses); end
            if (r_hit) hits_seen = hits_seen + 1;
            if (r_miss) misses_seen = misses_seen + 1;
            $display("%0s addr=%08h  %s  data=%08h  latency=%0d", we ? "W" : "R", addr,
                     r_hit ? "HIT " : "MISS", r_data, r_lat);
        end
    endtask

    task check(input cond, input [255:0] what);
        if (!cond) begin errors = errors + 1; $display("FAIL: %0s", what); end
    endtask

    localparam MISS_LAT = 4*LATENCY + 6;   // see docs/fsm.md

    initial begin
        $dumpfile("tb_m1_smoke.vcd");
        $dumpvars(0, tb_m1_smoke);
        repeat (3) @(posedge clk);
        #1 rst_n = 1;
        @(posedge clk); #1;

        // cold miss then 3 hits in the same 16 B block
        access(0, 32'h0000_1000, 0); check(r_miss && r_lat == MISS_LAT, "cold miss latency");
                                     check(r_data == expect_word(32'h1000), "data 1000");
        access(0, 32'h0000_1004, 0); check(r_hit && r_lat == 1, "hit 1004");
                                     check(r_data == expect_word(32'h1004), "data 1004");
        access(0, 32'h0000_1008, 0); check(r_hit && r_lat == 1, "hit 1008");
                                     check(r_data == expect_word(32'h1008), "data 1008");
        access(0, 32'h0000_100C, 0); check(r_hit && r_lat == 1, "hit 100C");
                                     check(r_data == expect_word(32'h100C), "data 100C");

        // tag 0 / index 0 right after reset must still be a miss (valid bit)
        access(0, 32'h0000_0000, 0); check(r_miss, "addr 0 first access must miss");
                                     check(r_data == expect_word(0), "data 0");

        // conflict: 0x1400 has the same index as 0x1000 (1 KB apart), different tag
        access(0, 32'h0000_1400, 0); check(r_miss, "conflict miss 1400");
        access(0, 32'h0000_1000, 0); check(r_miss, "1000 evicted, must miss");
                                     check(r_data == expect_word(32'h1000), "data 1000 again");

        // request on a word in the middle of a block that is not the first word
        access(0, 32'h0000_2008, 0); check(r_miss, "miss on 2008");
                                     check(r_data == expect_word(32'h2008), "data 2008 (critical word)");
        access(0, 32'h0000_2000, 0); check(r_hit, "2000 hit after refill from 2008");

        if (WS) begin
            access(1, 32'h0000_2004, 32'hCAFE0001); check(r_hit, "write hit");
            access(0, 32'h0000_2004, 0);            check(r_hit && r_data == 32'hCAFE0001, "read-after-write hit");
            access(1, 32'h0000_3000, 32'hCAFE0002); check(r_miss, "write miss");
            access(0, 32'h0000_3000, 0);            check(r_miss && r_data == 32'hCAFE0002, "no-write-allocate: read misses, memory has data");
        end else begin
            access(1, 32'h0000_2004, 32'hCAFE0001); check(r_hit && r_data == expect_word(32'h2004), "WS=0: write behaves as read");
        end

        cpu_valid = 0;
        @(posedge clk); @(posedge clk);

        check(hit_count == hits_seen && miss_count == misses_seen, "counters match pulses seen");
        check(hit_count + miss_count == n_req, "hit+miss == requests");
        $display("requests=%0d hit_count=%0d miss_count=%0d", n_req, hit_count, miss_count);

        if (errors == 0) $display("PASS (WS=%0d, MEM_LATENCY=%0d)", WS, LATENCY);
        else             $display("FAILED: %0d errors", errors);
        $finish;
    end
endmodule
