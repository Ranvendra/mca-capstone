// =============================================================================
// tb_cache_trace.v  (M4 Verification Suite)
// Trace-driven testbench for direct-mapped cache controller.
// Reads memory access traces and logs cycle-accurate results to CSV.
//
// Arguments:
//   +TRACE=<path_to_trace_file>
//   +OUT=<path_to_output_csv>
//
// Format of trace file (plan.md 4.4):
//   <op> <addr> [<wdata>]
//
// Format of output CSV (plan.md 4.5):
//   idx,op,addr,hit,rdata,latency_cycles
// =============================================================================

`timescale 1ns/1ps

module tb_cache_trace;
    parameter ADDR_W        = 32;
    parameter CACHE_BYTES   = 1024;
    parameter BLOCK_BYTES   = 16;
    parameter WRITE_SUPPORT = 0;
    parameter MEM_LATENCY   = 4;

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

    reg [1023:0] trace_filename = "";
    reg [1023:0] out_filename = "";
    integer      fd_in = 0;
    integer      fd_out = 0;
    reg [1023:0] line_buf;
    integer      scan_cnt;
    integer      access_idx = 0;

    reg [31:0]   op_val;
    reg [31:0]   addr_val;
    reg [31:0]   wdata_val;

    reg [31:0]   r_data;
    reg          r_hit;
    reg          r_miss;
    integer      r_lat;
    integer      r_pulses;
    reg          done;

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_filename)) begin
            $display("ERROR: Missing +TRACE=<filename> argument");
            $finish(1);
        end

        if (!$value$plusargs("OUT=%s", out_filename)) begin
            out_filename = "sim_out.csv";
        end

        fd_in = $fopen(trace_filename, "r");
        if (fd_in == 0) begin
            $display("ERROR: Cannot open trace file: %0s", trace_filename);
            $finish(1);
        end

        fd_out = $fopen(out_filename, "w");
        if (fd_out == 0) begin
            $display("ERROR: Cannot open output CSV file: %0s", out_filename);
            $fclose(fd_in);
            $finish(1);
        end

        // Write CSV header
        $fdisplay(fd_out, "idx,op,addr,hit,rdata,latency_cycles");

        // Synchronous Reset
        rst_n = 0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1;
        repeat (2) @(posedge clk);

        $display("Processing trace: %0s -> %0s", trace_filename, out_filename);

        while ($fgets(line_buf, fd_in)) begin
            wdata_val = 32'd0;
            scan_cnt = $sscanf(line_buf, "%h %h %h", op_val, addr_val, wdata_val);
            if (scan_cnt >= 2) begin
                // Perform access
                @(posedge clk); #1;
                cpu_valid = 1'b1;
                cpu_we    = (op_val != 0);
                cpu_addr  = addr_val;
                cpu_wdata = wdata_val;

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
                    if (cpu_ready) begin
                        r_data = cpu_rdata;
                        done = 1;
                    end
                    if (r_lat > 500) begin
                        $display("ERROR: Timeout (>500 cycles) on access idx=%0d, addr=%08h",
                                 access_idx, addr_val);
                        done = 1;
                    end
                end

                @(posedge clk); #1;
                cpu_valid = 1'b0;
                cpu_we    = 1'b0;

                $fdisplay(fd_out, "%0d,%0d,%08h,%0d,%08h,%0d",
                          access_idx, op_val, addr_val, r_hit ? 1 : 0, r_data, r_lat);

                access_idx = access_idx + 1;
            end
        end

        $fclose(fd_in);
        $fclose(fd_out);

        repeat (2) @(posedge clk);

        $display("Trace Simulation Complete:");
        $display("  Total Accesses : %0d", access_idx);
        $display("  Hits           : %0d", hit_count);
        $display("  Misses         : %0d", miss_count);
        if (access_idx > 0)
            $display("  Hit Ratio      : %0.2f%%", (hit_count * 100.0) / access_idx);

        $finish(0);
    end

endmodule
