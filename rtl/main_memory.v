// =============================================================================
// main_memory.v  (M3)
// Behavioural main-memory model + the word-by-word handshake of plan.md 4.2.
// Simulation only: it is NOT part of the synthesised design (synth/ uses
// cache_top as the top; this module sits next to it in the testbench).
//
// Handshake (one 32-bit word per request)
//   - The cache raises mem_req and keeps mem_req / mem_we / mem_addr / mem_wdata
//     stable until it sees mem_ack.
//   - mem_ack is a 1-cycle pulse, MEM_LATENCY cycles after the request is
//     first seen (MEM_LATENCY >= 1; 0 or negative is treated as 1).
//   - Read : mem_rdata is valid in the mem_ack cycle.
//   - Write: mem[word] is updated at the clock edge that raises mem_ack.
//   - If mem_req is still high in the ack cycle, that is the tail of the old
//     request. A new request starts in the following cycle with a fresh
//     latency count, so back-to-back words each cost MEM_LATENCY + 1 cycles
//     (this is the "+1 per word" in the miss-penalty formula of docs/fsm.md).
//   - Dropping mem_req before the ack cancels the request (no ack, no write).
//
//   cycle      0    1    2    3    4    5    6        (MEM_LATENCY = 4)
//   mem_req    _____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____
//   mem_ack    _________________________/‾‾‾‾\____
//   mem_rdata  -------------------------< D  >----
//
// Contents (plan.md 4.6): mem[w] = w * 32'h9E3779B1, w = word index.
// Word index = mem_addr[31:2] % MEM_WORDS, so mem_addr[1:0] is ignored and
// addresses above the memory size wrap around. Reset does NOT restore the
// contents (like a real RAM); it only clears the handshake and the counters.
//
// Counters: mem_read_count / mem_write_count = completed (acked) word reads /
// writes since reset. Cross-check: mem_read_count == miss_count * words per
// block for a read-only run.
//
// STRICT_RDATA = 1 drives mem_rdata to X whenever mem_ack is low, so a cache
// that samples the data in the wrong cycle is caught in simulation.
// =============================================================================
module main_memory #(
    parameter MEM_WORDS    = 65536,     // 65536 words = 256 KB
    parameter MEM_LATENCY  = 4,         // cycles from request to ack, min 1
    parameter STRICT_RDATA = 0          // 1: mem_rdata is X outside the ack cycle
) (
    input  wire        clk,
    input  wire        rst_n,           // active low, synchronous
    input  wire        mem_req,
    input  wire        mem_we,
    input  wire [31:0] mem_addr,        // byte address, word aligned
    input  wire [31:0] mem_wdata,
    output wire [31:0] mem_rdata,
    output reg         mem_ack,
    output reg  [31:0] mem_read_count,
    output reg  [31:0] mem_write_count
);

    localparam integer LAT = (MEM_LATENCY < 1) ? 1 : MEM_LATENCY;

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [31:0] rdata_q;
    reg [31:0] wait_cnt;                // request cycles already seen

    wire [31:0] word_idx = (mem_addr >> 2) % MEM_WORDS;

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = i * 32'h9E3779B1;
        mem_ack         = 1'b0;
        mem_read_count  = 32'd0;
        mem_write_count = 32'd0;
        wait_cnt        = 32'd0;
    end

    always @(posedge clk) begin
        mem_ack <= 1'b0;                              // ack is a 1-cycle pulse
        if (!rst_n) begin
            wait_cnt        <= 32'd0;
            mem_read_count  <= 32'd0;
            mem_write_count <= 32'd0;
        end else if (mem_req && !mem_ack) begin
            if (wait_cnt == LAT - 1) begin            // LAT-th cycle of this request
                wait_cnt <= 32'd0;
                mem_ack  <= 1'b1;
                if (mem_we) begin
                    mem[word_idx]   <= mem_wdata;
                    mem_write_count <= mem_write_count + 32'd1;
                end else begin
                    rdata_q         <= mem[word_idx];
                    mem_read_count  <= mem_read_count + 32'd1;
                end
            end else begin
                wait_cnt <= wait_cnt + 32'd1;
            end
        end else begin
            wait_cnt <= 32'd0;                        // idle, cancelled, or ack cycle
        end
    end

    assign mem_rdata = (STRICT_RDATA != 0 && !mem_ack) ? 32'hxxxxxxxx : rdata_q;

endmodule
