// =============================================================================
// fmax_wrap.v  (M3)  timing-only wrapper around cache_top. NOT part of the design.
//
// cache_top has 266 port bits (more than the FPGA package has pins) and its
// hit path is combinational from cpu_addr to cpu_ready (Mealy, 1-cycle hit).
// To let the place-and-route tool report a register-to-register Fmax, every
// input is driven from a flip-flop (one long shift register fed by `si`) and
// every output is captured in a flip-flop (reduced to the single pin `so`).
// The wrapper adds flip-flops only; it adds no logic on the timed paths.
// Used by synth/run_fmax.sh.
// =============================================================================
module fmax_wrap #(
    parameter CACHE_BYTES   = 1024,
    parameter BLOCK_BYTES   = 16,
    parameter WRITE_SUPPORT = 0
) (
    input  wire clk,
    input  wire si,
    output reg  so
);
    localparam NIN  = 1 + 1 + 1 + 32 + 32 + 32 + 1;       // rst_n, cpu_valid, cpu_we, cpu_addr, cpu_wdata, mem_rdata, mem_ack
    localparam NOUT = 32 + 1 + 1 + 1 + 32 + 32 + 1 + 1 + 32 + 32;

    reg  [NIN-1:0]  in_q;
    wire [NOUT-1:0] out_d;
    reg  [NOUT-1:0] out_q;

    always @(posedge clk) begin
        in_q  <= {in_q[NIN-2:0], si};
        out_q <= out_d;
        so    <= ^out_q;
    end

    cache_top #(
        .CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES), .WRITE_SUPPORT(WRITE_SUPPORT)
    ) u_cache (
        .clk       (clk),
        .rst_n     (in_q[0]),
        .cpu_valid (in_q[1]),
        .cpu_we    (in_q[2]),
        .cpu_addr  (in_q[34:3]),
        .cpu_wdata (in_q[66:35]),
        .mem_rdata (in_q[98:67]),
        .mem_ack   (in_q[99]),
        .cpu_rdata (out_d[31:0]),
        .cpu_ready (out_d[32]),
        .stat_hit  (out_d[33]),
        .stat_miss (out_d[34]),
        .hit_count (out_d[66:35]),
        .miss_count(out_d[98:67]),
        .mem_req   (out_d[99]),
        .mem_we    (out_d[100]),
        .mem_addr  (out_d[132:101]),
        .mem_wdata (out_d[164:133])
    );
endmodule
