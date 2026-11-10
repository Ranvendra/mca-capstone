// =============================================================================
// cache_controller.v  (M1)
// Direct-mapped cache controller FSM. Blocking cache: one request at a time.
//
// Datapath (RAMs, decoder, comparator) lives in cache_top; this module only
// decides WHEN to read/write them and WHEN to talk to main memory.
//
// States
//   S_IDLE    : look up the request. Hit -> answer in the same cycle.
//               Miss -> pulse stat_miss and go to S_REFILL.
//   S_REFILL  : fetch WORDS_PER_BLOCK words one by one (mem_req/mem_ack).
//               Each word is written into data_ram when its ack arrives.
//               The LAST ack also writes tag_ram and sets the valid bit.
//   S_RESPOND : the block is now in the cache. Give cpu_ready for one cycle,
//               data comes from data_ram. No stat pulse here.
//   S_WRITE   : only when WRITE_SUPPORT=1. Write-through to memory, wait ack.
//
// Mealy vs Moore
//   Outputs here are Mealy (they depend on cpu_valid, hit, mem_ack in the same
//   cycle). Reason: the spec wants hit time = 1 cycle, i.e. cpu_ready must go
//   high in the SAME cycle the request is seen and the tag compare says "hit".
//   A pure Moore FSM would register the hit first and cost one extra cycle on
//   every hit. Mealy is also what lets data_we follow mem_ack directly.
//   There is no combinational loop: `hit` comes from the RAMs + comparator,
//   which are not driven by any output of this module in the same cycle.
//
// Stats rule: exactly one of stat_hit / stat_miss pulses per request, and only
// in S_IDLE. After a miss the FSM leaves S_IDLE, so it never re-classifies the
// request after refill.
//
// Valid-bit rule: valid and tag are written only with the last refill word.
// The cache is blocking, so nobody can read a half-filled line meanwhile, and
// a reset in the middle of a refill clears all valid bits (valid_ram).
//
// cpu_we when WRITE_SUPPORT=0: the request is handled as a READ (lookup and
// refill as usual, nothing is stored). This keeps the CPU from hanging.
// =============================================================================
module cache_controller #(
    parameter WORDS_PER_BLOCK = 4,                    // BLOCK_BYTES / 4
    parameter WRITE_SUPPORT   = 0,                    // 0 = read only, 1 = write-through, no-write-allocate
    parameter WSEL_W          = $clog2(WORDS_PER_BLOCK) // derived, do not override
) (
    input  wire              clk,
    input  wire              rst_n,          // active low, synchronous

    // from the CPU / datapath
    input  wire              cpu_valid,
    input  wire              cpu_we,
    input  wire              hit,            // valid & tag match (combinational, for current cpu_addr)
    input  wire [WSEL_W-1:0] req_word_sel,   // word select of cpu_addr

    // to the CPU
    output reg               cpu_ready,      // 1-cycle pulse
    output reg               stat_hit,       // 1-cycle pulse
    output reg               stat_miss,      // 1-cycle pulse

    // memory handshake
    output reg               mem_req,
    output reg               mem_we,
    input  wire              mem_ack,
    output wire [WSEL_W-1:0] refill_word,    // which word of the block is being fetched

    // datapath write controls
    output reg               data_we,
    output reg  [WSEL_W-1:0] data_wsel,
    output reg               data_from_cpu,  // 0: write mem_rdata, 1: write cpu_wdata
    output reg               tag_we,
    output reg               valid_we
);

    localparam [1:0] S_IDLE    = 2'd0,
                     S_REFILL  = 2'd1,
                     S_RESPOND = 2'd2,
                     S_WRITE   = 2'd3;

    reg [1:0]        state, next_state;
    reg [WSEL_W-1:0] word_cnt;

    assign refill_word = word_cnt;

    wire is_write  = (WRITE_SUPPORT != 0) && cpu_we;
    wire last_word = (word_cnt == WORDS_PER_BLOCK - 1);

    // -------------------------------------------------------------------------
    // State register and refill word counter
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            word_cnt <= {WSEL_W{1'b0}};
        end else begin
            state <= next_state;
            if (state != S_REFILL)
                word_cnt <= {WSEL_W{1'b0}};          // always starts a refill at word 0
            else if (mem_ack)
                word_cnt <= word_cnt + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Next state and outputs. Every output has a default, so no latches.
    // -------------------------------------------------------------------------
    always @* begin
        next_state    = state;
        cpu_ready     = 1'b0;
        stat_hit      = 1'b0;
        stat_miss     = 1'b0;
        mem_req       = 1'b0;
        mem_we        = 1'b0;
        data_we       = 1'b0;
        data_wsel     = req_word_sel;
        data_from_cpu = 1'b0;
        tag_we        = 1'b0;
        valid_we      = 1'b0;

        case (state)
            S_IDLE: begin
                if (cpu_valid) begin
                    if (hit) begin
                        stat_hit = 1'b1;
                        if (is_write) begin
                            data_we       = 1'b1;       // update the cached word
                            data_from_cpu = 1'b1;
                            next_state    = S_WRITE;    // and write through to memory
                        end else begin
                            cpu_ready = 1'b1;           // hit time = 1 cycle
                        end
                    end else begin
                        stat_miss = 1'b1;
                        if (is_write) next_state = S_WRITE;   // no-write-allocate
                        else          next_state = S_REFILL;
                    end
                end
            end

            S_REFILL: begin
                mem_req   = 1'b1;
                data_wsel = word_cnt;
                if (mem_ack) begin
                    data_we = 1'b1;                     // store this word
                    if (last_word) begin
                        tag_we     = 1'b1;              // line is complete: tag + valid now
                        valid_we   = 1'b1;
                        next_state = S_RESPOND;
                    end
                end
            end

            S_RESPOND: begin
                cpu_ready  = 1'b1;                      // data_ram already holds the block
                next_state = S_IDLE;
            end

            S_WRITE: begin
                mem_req = 1'b1;
                mem_we  = 1'b1;
                if (mem_ack) begin
                    cpu_ready  = 1'b1;
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule
