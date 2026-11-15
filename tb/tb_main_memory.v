// =============================================================================
// tb_main_memory.v  (M3) unit test of rtl/main_memory.v
//
// Run for one latency (default 4):
//   iverilog -g2012 -Wall -o /tmp/tb_mm rtl/main_memory.v tb/tb_main_memory.v && vvp -n /tmp/tb_mm
// Other latency: add  -Ptb_main_memory.LATENCY=10
// All M3 tests (latency 1, 4, 10 + cache integration):  sh tb/run_m3_tests.sh
//
// Cycle convention: inputs change just after a rising edge, outputs are
// sampled at the falling edge (middle of the cycle). "Cycle 0" is the first
// cycle in which mem_req is high. The ack must be seen in cycle LATENCY.
// =============================================================================
`timescale 1ns/1ps
module tb_main_memory;
    parameter LATENCY = 4;
    localparam WORDS  = 65536;

    reg         clk = 0, rst_n = 0;
    reg         mem_req = 0, mem_we = 0;
    reg  [31:0] mem_addr = 0, mem_wdata = 0;
    wire [31:0] mem_rdata, rd_cnt, wr_cnt;
    wire        mem_ack;

    always #5 clk = ~clk;

    main_memory #(.MEM_WORDS(WORDS), .MEM_LATENCY(LATENCY)) dut (
        .clk(clk), .rst_n(rst_n), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
        .mem_read_count(rd_cnt), .mem_write_count(wr_cnt)
    );

    // Same stimulus on two more instances:
    //   strict : STRICT_RDATA=1, rdata must be X outside the ack cycle
    //   lat0   : MEM_LATENCY=0 must behave exactly like MEM_LATENCY=1
    wire [31:0] s_rdata, z_rdata;
    wire        s_ack, z_ack;
    main_memory #(.MEM_WORDS(WORDS), .MEM_LATENCY(LATENCY), .STRICT_RDATA(1)) strict (
        .clk(clk), .rst_n(rst_n), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(s_rdata), .mem_ack(s_ack),
        .mem_read_count(), .mem_write_count()
    );
    reg z_req = 0; reg [31:0] z_addr = 0;
    main_memory #(.MEM_WORDS(WORDS), .MEM_LATENCY(0)) lat0 (
        .clk(clk), .rst_n(rst_n), .mem_req(z_req), .mem_we(1'b0),
        .mem_addr(z_addr), .mem_wdata(32'd0), .mem_rdata(z_rdata), .mem_ack(z_ack),
        .mem_read_count(), .mem_write_count()
    );

    integer errors = 0, checks = 0;
    integer exp_reads = 0, exp_writes = 0;

    task check(input cond, input [511:0] what);
        begin
            checks = checks + 1;
            if (cond !== 1'b1) begin errors = errors + 1; $display("FAIL: %0s (t=%0t)", what, $time); end
        end
    endtask

    function [31:0] init_word(input [31:0] a);          // plan.md 4.6
        init_word = ((a >> 2) % WORDS) * 32'h9E3779B1;
    endfunction

    // ack must never be high for two cycles in a row, strict copy must agree
    reg ack_prev = 0;
    always @(negedge clk) begin
        if (mem_ack && ack_prev) begin errors = errors + 1; $display("FAIL: mem_ack high for 2 cycles (t=%0t)", $time); end
        if (mem_ack && !mem_req) begin errors = errors + 1; $display("FAIL: mem_ack without mem_req (t=%0t)", $time); end
        if (s_ack !== mem_ack)   begin errors = errors + 1; $display("FAIL: strict instance ack differs (t=%0t)", $time); end
        if (!s_ack && s_rdata !== 32'hxxxxxxxx) begin errors = errors + 1; $display("FAIL: STRICT_RDATA not X outside ack (t=%0t)", $time); end
        if (s_ack && !mem_we && s_rdata !== mem_rdata) begin errors = errors + 1; $display("FAIL: strict rdata differs in ack cycle (t=%0t)", $time); end
        ack_prev = mem_ack;
    end

    // One transfer. Must be called just after a rising edge. Returns just
    // after the rising edge that ends the ack cycle. mem_req stays as `hold`.
    reg [31:0] x_data; integer x_cyc;
    task xfer(input we, input [31:0] addr, input [31:0] wdata, input hold);
        reg done;
        begin
            mem_req = 1; mem_we = we; mem_addr = addr; mem_wdata = wdata;
            x_cyc = 0; done = 0;
            while (!done) begin
                @(negedge clk);
                if (mem_ack) begin x_data = mem_rdata; done = 1; end
                else begin
                    x_cyc = x_cyc + 1;
                    if (x_cyc > 100) begin errors = errors + 1; $display("FAIL: no ack (timeout)"); done = 1; end
                end
            end
            @(posedge clk); #1;
            mem_req = hold;
            if (we) exp_writes = exp_writes + 1; else exp_reads = exp_reads + 1;
        end
    endtask

    task idle(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk); check(!mem_ack, "ack while idle");
                @(posedge clk); #1;
            end
        end
    endtask

    integer k; reg [31:0] a;

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        check(!mem_ack, "ack low in reset");
        check(rd_cnt == 0 && wr_cnt == 0, "counters 0 in reset");
        @(posedge clk); #1 rst_n = 1;
        idle(5);                                             // no request -> no ack

        // ---- 1. single reads: latency and initial contents -------------------
        xfer(0, 32'h0000_0000, 0, 0); check(x_cyc == LATENCY, "read 0: ack in cycle LATENCY");
                                      check(x_data == 32'h0, "mem[0] = 0");
        @(negedge clk); check(!mem_ack, "ack is a 1-cycle pulse"); @(posedge clk); #1;
        xfer(0, 32'h0000_0004, 0, 0); check(x_cyc == LATENCY && x_data == 32'h9E3779B1, "mem[1] = 9E3779B1");
        xfer(0, 32'h0000_1A2C, 0, 0); check(x_cyc == LATENCY && x_data == init_word(32'h1A2C), "data 1A2C");
        xfer(0, 32'h0003_FFFC, 0, 0); check(x_cyc == LATENCY && x_data == 32'hFFFF * 32'h9E3779B1, "last word 3FFFC");
        idle(3);

        // ---- 2. back-to-back, the way the controller refills a block ---------
        // req stays high, address changes in the cycle after each ack.
        for (k = 0; k < 4; k = k + 1) begin
            xfer(0, 32'h0000_2000 + 4*k, 0, 1);
            check(x_cyc == LATENCY, "back-to-back: fresh latency count per word");
            check(x_data == init_word(32'h2000 + 4*k), "back-to-back data");
        end
        // req still high, SAME address: second ack must be a new full request
        xfer(0, 32'h0000_200C, 0, 1); check(x_cyc == LATENCY && x_data == init_word(32'h200C), "repeat same address");
        mem_req = 0;
        idle(3);

        // ---- 3. addr[1:0] ignored, wrap above MEM_WORDS ----------------------
        xfer(0, 32'h0000_0107, 0, 0); check(x_data == init_word(32'h0104), "addr[1:0] ignored");
        xfer(0, 32'h0004_0010, 0, 0); check(x_data == init_word(32'h0010), "wrap: 0x40010 -> word 4");
        xfer(0, 32'hFFFF_FFFC, 0, 0); check(x_data == 32'hFFFF * 32'h9E3779B1, "wrap: top of 4 GB -> last word");

        // ---- 4. write, read back, neighbours untouched -----------------------
        xfer(1, 32'h0000_3004, 32'hCAFE_F00D, 0); check(x_cyc == LATENCY, "write latency");
        xfer(0, 32'h0000_3004, 0, 0); check(x_data == 32'hCAFE_F00D, "read back written word");
        xfer(0, 32'h0000_3000, 0, 0); check(x_data == init_word(32'h3000), "word below unchanged");
        xfer(0, 32'h0000_3008, 0, 0); check(x_data == init_word(32'h3008), "word above unchanged");
        // write immediately followed by read of the same word, req held high
        xfer(1, 32'h0000_3010, 32'h1234_5678, 1);
        xfer(0, 32'h0000_3010, 0, 0); check(x_cyc == LATENCY && x_data == 32'h1234_5678, "write then read back-to-back");

        // ---- 5. request dropped before the ack is cancelled ------------------
        if (LATENCY > 1) begin
            mem_req = 1; mem_we = 1; mem_addr = 32'h0000_4000; mem_wdata = 32'hDEAD_BEEF;
            repeat (LATENCY - 1) begin @(negedge clk); check(!mem_ack, "no early ack"); @(posedge clk); #1; end
            mem_req = 0; mem_we = 0;
            idle(LATENCY + 3);                               // never acked
            xfer(0, 32'h0000_4000, 0, 0);
            check(x_cyc == LATENCY, "full latency after a cancelled request");
            check(x_data == init_word(32'h4000), "cancelled write did not change memory");
        end

        // ---- 6. counters ------------------------------------------------------
        @(negedge clk);
        check(rd_cnt == exp_reads,  "mem_read_count == acked reads");
        check(wr_cnt == exp_writes, "mem_write_count == acked writes");
        @(posedge clk); #1;

        // ---- 7. reset in the middle of a request ------------------------------
        mem_req = 1; mem_we = 0; mem_addr = 32'h0000_5000;
        if (LATENCY > 1) begin @(posedge clk); #1; end
        rst_n = 0;
        repeat (LATENCY + 2) begin @(posedge clk); #1; end
        @(negedge clk);
        check(!mem_ack, "no ack while in reset");
        check(rd_cnt == 0 && wr_cnt == 0, "reset clears the counters");
        @(posedge clk); #1;
        mem_req = 0; rst_n = 1;
        idle(2);
        xfer(0, 32'h0000_5000, 0, 0); check(x_cyc == LATENCY && x_data == init_word(32'h5000), "read after reset");
        xfer(0, 32'h0000_3004, 0, 0); check(x_data == 32'hCAFE_F00D, "reset does not restore contents");
        @(negedge clk); check(rd_cnt == 2 && wr_cnt == 0, "counters restart after reset"); @(posedge clk); #1;

        // ---- 8. random reads against the formula ------------------------------
        for (k = 0; k < 300; k = k + 1) begin
            a = {$random} & 32'h0003_FFFC;
            if (a != 32'h3004 && a != 32'h3010) begin
                xfer(0, a, 0, k[0]);
                if (x_cyc != LATENCY || x_data !== init_word(a)) begin
                    errors = errors + 1; $display("FAIL: random read %08h got %08h after %0d cycles", a, x_data, x_cyc);
                end
            end
        end
        mem_req = 0;

        // ---- 9. MEM_LATENCY=0 is clamped to 1 ---------------------------------
        @(posedge clk); #1;
        z_req = 1; z_addr = 32'h0000_0008;
        @(negedge clk); check(!z_ack, "LATENCY 0: no ack in the request cycle");
        @(negedge clk); check(z_ack && z_rdata == init_word(32'h8), "LATENCY 0 behaves like 1");
        @(posedge clk); #1 z_req = 0;

        idle(3);
        if (errors == 0) $display("PASS tb_main_memory (MEM_LATENCY=%0d, %0d checks)", LATENCY, checks);
        else             $display("FAIL tb_main_memory (MEM_LATENCY=%0d): %0d errors", LATENCY, errors);
        $finish;
    end
endmodule
