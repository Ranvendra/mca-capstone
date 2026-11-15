// =============================================================================
// tb_m3_cache_mem.v  (M3) cache_top + the real main_memory, end to end.
// Not the M4 verification suite. It only proves the memory side:
//   - the data the CPU gets is the memory contents (plan.md 4.6)
//   - every miss costs exactly WORDS_PER_BLOCK memory reads
//     (mem_read_count == miss_count * WORDS_PER_BLOCK), hits cost none
//   - miss latency == W*(MEM_LATENCY+1)+2 and hit latency == 1 (docs/fsm.md)
//   - the cache samples mem_rdata only in the ack cycle (STRICT_RDATA=1 makes
//     the memory drive X at all other times)
//   - the refill addresses are the block base, +4, +8, ...
//
// Run:  iverilog -g2012 -o /tmp/m3_int rtl/*.v tb/tb_m3_cache_mem.v && vvp -n /tmp/m3_int
// Parameters: -Ptb_m3_cache_mem.LATENCY=10 -Ptb_m3_cache_mem.CACHE_BYTES=2048 ...
// =============================================================================
`timescale 1ns/1ps
module tb_m3_cache_mem;
    parameter LATENCY     = 4;
    parameter CACHE_BYTES = 1024;
    parameter BLOCK_BYTES = 16;
    localparam W          = BLOCK_BYTES / 4;
    localparam MISS_LAT   = W * (LATENCY + 1) + 2;

    reg         clk = 0, rst_n = 0;
    reg         cpu_valid = 0;
    reg  [31:0] cpu_addr = 0;
    wire [31:0] cpu_rdata, hit_count, miss_count;
    wire        cpu_ready, stat_hit, stat_miss;
    wire        mem_req, mem_we, mem_ack;
    wire [31:0] mem_addr, mem_wdata, mem_rdata, rd_cnt, wr_cnt;

    always #5 clk = ~clk;

    cache_top #(.CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES)) dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_valid(cpu_valid), .cpu_we(1'b0), .cpu_addr(cpu_addr), .cpu_wdata(32'd0),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .stat_hit(stat_hit), .stat_miss(stat_miss),
        .hit_count(hit_count), .miss_count(miss_count),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ack(mem_ack)
    );

    main_memory #(.MEM_LATENCY(LATENCY), .STRICT_RDATA(1)) mem (
        .clk(clk), .rst_n(rst_n), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
        .mem_read_count(rd_cnt), .mem_write_count(wr_cnt)
    );

    integer errors = 0, n_req = 0, n_miss = 0;

    // refill address check: k-th ack of a miss must be for block base + 4*k
    integer ack_no = 0;
    always @(negedge clk) begin
        if (cpu_ready) ack_no = 0;
        else if (mem_ack) begin
            if (mem_addr !== ((cpu_addr & ~(BLOCK_BYTES-1)) + 4*ack_no)) begin
                errors = errors + 1;
                $display("FAIL: refill word %0d of %08h asked for %08h", ack_no, cpu_addr, mem_addr);
            end
            ack_no = ack_no + 1;
        end
    end

    task rd(input [31:0] addr);
        integer lat; reg miss, done;
        begin
            cpu_valid = 1; cpu_addr = addr; lat = 0; miss = 0; done = 0;
            while (!done) begin
                @(negedge clk);
                lat = lat + 1;
                if (stat_miss) miss = 1;
                if (cpu_ready) done = 1;
                if (lat > 1000) begin errors = errors + 1; $display("FAIL: timeout at %08h", addr); done = 1; end
            end
            if (cpu_rdata !== (addr >> 2) * 32'h9E3779B1) begin
                errors = errors + 1; $display("FAIL: addr %08h data %08h", addr, cpu_rdata);
            end
            if (lat != (miss ? MISS_LAT : 1)) begin
                errors = errors + 1; $display("FAIL: addr %08h %0s latency %0d", addr, miss ? "miss" : "hit", lat);
            end
            n_req = n_req + 1; n_miss = n_miss + miss;
            @(posedge clk); #1;
        end
    endtask

    integer k;
    initial begin
        repeat (3) @(posedge clk);
        #1 rst_n = 1;
        @(posedge clk); #1;

        for (k = 0; k < 512; k = k + 1) rd(4*k);                        // sequential, 2 KB
        for (k = 0; k < 512; k = k + 1) rd(4*k);                        // again
        for (k = 0; k < 600; k = k + 1) rd({$random} & 32'h0003_FFFC);  // random over 256 KB
        for (k = 0; k < 200; k = k + 1) rd((k % 2) * CACHE_BYTES + 32'h100);  // ping-pong conflict
        cpu_valid = 0;
        repeat (2) @(posedge clk);
        @(negedge clk);

        if (miss_count != n_miss || hit_count + miss_count != n_req) begin
            errors = errors + 1; $display("FAIL: counters hit=%0d miss=%0d, tb saw %0d requests %0d misses", hit_count, miss_count, n_req, n_miss);
        end
        if (rd_cnt != miss_count * W) begin
            errors = errors + 1; $display("FAIL: mem_read_count %0d != miss_count %0d * %0d", rd_cnt, miss_count, W);
        end
        if (wr_cnt != 0) begin errors = errors + 1; $display("FAIL: memory written in a read-only run"); end

        $display("requests=%0d hits=%0d misses=%0d mem_read_count=%0d (= misses x %0d words)", n_req, hit_count, miss_count, rd_cnt, W);
        if (errors == 0) $display("PASS tb_m3_cache_mem (CACHE=%0d BLOCK=%0d MEM_LATENCY=%0d)", CACHE_BYTES, BLOCK_BYTES, LATENCY);
        else             $display("FAIL tb_m3_cache_mem (CACHE=%0d BLOCK=%0d MEM_LATENCY=%0d): %0d errors", CACHE_BYTES, BLOCK_BYTES, LATENCY, errors);
        $finish;
    end
endmodule
