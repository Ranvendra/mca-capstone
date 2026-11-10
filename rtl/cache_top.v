// =============================================================================
// cache_top.v  (M1)
// Direct-mapped cache: wires the M2 datapath modules to the M1 controller and
// exposes the CPU-side and memory-side ports of plan.md section 4.1 / 4.2.
// main_memory (M3) is NOT inside this module.
//
//   cpu_addr --> addr_decoder --> tag / index / offset / word_sel
//   index --> tag_ram, valid_ram, data_ram (async read)
//   tag_comparator: hit = valid & (stored tag == tag of cpu_addr)
//   cache_controller: decides writes and memory traffic
//
// Assumes 32-bit words and BLOCK_BYTES >= 8 (at least 2 words per block).
// =============================================================================
module cache_top #(
    parameter ADDR_W        = 32,
    parameter CACHE_BYTES   = 1024,
    parameter BLOCK_BYTES   = 16,
    parameter WRITE_SUPPORT = 0          // 0 = read only, 1 = write-through + no-write-allocate
) (
    input  wire              clk,
    input  wire              rst_n,

    // CPU side (plan.md 4.1)
    input  wire              cpu_valid,
    input  wire              cpu_we,
    input  wire [ADDR_W-1:0] cpu_addr,
    input  wire [31:0]       cpu_wdata,
    output wire [31:0]       cpu_rdata,
    output wire              cpu_ready,
    output wire              stat_hit,
    output wire              stat_miss,
    output reg  [31:0]       hit_count,
    output reg  [31:0]       miss_count,

    // Memory side (plan.md 4.2)
    output wire              mem_req,
    output wire              mem_we,
    output wire [ADDR_W-1:0] mem_addr,
    output wire [31:0]       mem_wdata,
    input  wire [31:0]       mem_rdata,
    input  wire              mem_ack
);

    // ---- derived sizes -------------------------------------------------------
    localparam NUM_LINES       = CACHE_BYTES / BLOCK_BYTES;
    localparam OFF_W           = $clog2(BLOCK_BYTES);
    localparam INDEX_W         = $clog2(NUM_LINES);
    localparam TAG_W           = ADDR_W - INDEX_W - OFF_W;
    localparam WORDS_PER_BLOCK = BLOCK_BYTES / 4;
    localparam WSEL_W          = $clog2(WORDS_PER_BLOCK);
    localparam BLOCK_BITS      = BLOCK_BYTES * 8;

    // ---- address fields ------------------------------------------------------
    wire [TAG_W-1:0]   tag;
    wire [INDEX_W-1:0] index;
    wire [OFF_W-1:0]   offset;
    wire [WSEL_W-1:0]  word_sel;

    addr_decoder #(
        .ADDR_W      (ADDR_W),
        .CACHE_BYTES (CACHE_BYTES),
        .BLOCK_BYTES (BLOCK_BYTES)
    ) u_decoder (
        .addr     (cpu_addr),
        .tag      (tag),
        .index    (index),
        .offset   (offset),
        .word_sel (word_sel)
    );

    // ---- controller write strobes -------------------------------------------
    wire              data_we, tag_we, valid_we, data_from_cpu;
    wire [WSEL_W-1:0] data_wsel, refill_word;

    // ---- storage -------------------------------------------------------------
    wire [TAG_W-1:0]      stored_tag;
    wire                  stored_valid;
    wire [BLOCK_BITS-1:0] rd_block;
    wire [31:0]           w_word = data_from_cpu ? cpu_wdata : mem_rdata;

    tag_ram #(
        .INDEX_W (INDEX_W),
        .TAG_W   (TAG_W)
    ) u_tag_ram (
        .clk     (clk),
        .index   (index),
        .tag_out (stored_tag),
        .we      (tag_we),
        .w_index (index),
        .w_tag   (tag)
    );

    valid_ram #(
        .INDEX_W (INDEX_W)
    ) u_valid_ram (
        .clk       (clk),
        .rst_n     (rst_n),
        .index     (index),
        .valid_out (stored_valid),
        .we        (valid_we),
        .w_index   (index),
        .w_valid   (1'b1)           // lines are only ever set; reset clears them
    );

    data_ram #(
        .INDEX_W     (INDEX_W),
        .BLOCK_BYTES (BLOCK_BYTES)
    ) u_data_ram (
        .clk        (clk),
        .index      (index),
        .rd_block   (rd_block),
        .we         (data_we),
        .w_index    (index),
        .w_word_sel (data_wsel),
        .w_word     (w_word)
    );

    // ---- hit detect ----------------------------------------------------------
    wire hit;

    tag_comparator #(
        .TAG_W (TAG_W)
    ) u_cmp (
        .tag_a (stored_tag),
        .tag_b (tag),
        .valid (stored_valid),
        .hit   (hit)
    );

    // ---- controller ----------------------------------------------------------
    cache_controller #(
        .WORDS_PER_BLOCK (WORDS_PER_BLOCK),
        .WRITE_SUPPORT   (WRITE_SUPPORT)
    ) u_ctrl (
        .clk           (clk),
        .rst_n         (rst_n),
        .cpu_valid     (cpu_valid),
        .cpu_we        (cpu_we),
        .hit           (hit),
        .req_word_sel  (word_sel),
        .cpu_ready     (cpu_ready),
        .stat_hit      (stat_hit),
        .stat_miss     (stat_miss),
        .mem_req       (mem_req),
        .mem_we        (mem_we),
        .mem_ack       (mem_ack),
        .refill_word   (refill_word),
        .data_we       (data_we),
        .data_wsel     (data_wsel),
        .data_from_cpu (data_from_cpu),
        .tag_we        (tag_we),
        .valid_we      (valid_we)
    );

    // ---- CPU read data: pick the requested word out of the block -------------
    assign cpu_rdata = rd_block[word_sel*32 +: 32];

    // ---- memory address / data ----------------------------------------------
    // Refill : block-aligned base + refill_word*4.  Write-through : the word itself.
    assign mem_addr  = mem_we ? {cpu_addr[ADDR_W-1:2], 2'b00}
                              : {cpu_addr[ADDR_W-1:OFF_W], refill_word, 2'b00};
    assign mem_wdata = cpu_wdata;

    // ---- statistics counters -------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            hit_count  <= 32'd0;
            miss_count <= 32'd0;
        end else begin
            if (stat_hit)  hit_count  <= hit_count  + 32'd1;
            if (stat_miss) miss_count <= miss_count + 32'd1;
        end
    end

endmodule
