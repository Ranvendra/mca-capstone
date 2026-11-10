// =============================================================================
// TEMPORARY stand-ins for the M2 modules and the M3 main_memory, written by M1
// only so that cache_controller / cache_top can be simulated before the real
// files exist. Parameter and port names follow plan.md 4.2 / 4.3.
//
// DO NOT compile together with rtl/addr_decoder.v, tag_ram.v, valid_ram.v,
// data_ram.v, tag_comparator.v, main_memory.v (duplicate module names).
// Delete this file once the real M2/M3 files are merged.
// =============================================================================

module addr_decoder #(
    parameter ADDR_W = 32, parameter CACHE_BYTES = 1024, parameter BLOCK_BYTES = 16
) (
    input  wire [ADDR_W-1:0] addr,
    output wire [ADDR_W-$clog2(CACHE_BYTES)-1:0]       tag,
    output wire [$clog2(CACHE_BYTES/BLOCK_BYTES)-1:0]  index,
    output wire [$clog2(BLOCK_BYTES)-1:0]              offset,
    output wire [$clog2(BLOCK_BYTES)-3:0]              word_sel
);
    localparam OFF_W   = $clog2(BLOCK_BYTES);
    localparam INDEX_W = $clog2(CACHE_BYTES/BLOCK_BYTES);
    assign offset   = addr[OFF_W-1:0];
    assign index    = addr[OFF_W+INDEX_W-1:OFF_W];
    assign tag      = addr[ADDR_W-1:OFF_W+INDEX_W];
    assign word_sel = addr[OFF_W-1:2];
endmodule

module tag_ram #(parameter INDEX_W = 6, parameter TAG_W = 22) (
    input  wire clk,
    input  wire [INDEX_W-1:0] index,
    output wire [TAG_W-1:0]   tag_out,
    input  wire we,
    input  wire [INDEX_W-1:0] w_index,
    input  wire [TAG_W-1:0]   w_tag
);
    reg [TAG_W-1:0] mem [0:(1<<INDEX_W)-1];
    assign tag_out = mem[index];
    always @(posedge clk) if (we) mem[w_index] <= w_tag;
endmodule

module valid_ram #(parameter INDEX_W = 6) (
    input  wire clk,
    input  wire rst_n,
    input  wire [INDEX_W-1:0] index,
    output wire valid_out,
    input  wire we,
    input  wire [INDEX_W-1:0] w_index,
    input  wire w_valid
);
    reg [(1<<INDEX_W)-1:0] v;
    assign valid_out = v[index];
    always @(posedge clk) begin
        if (!rst_n)  v <= {(1<<INDEX_W){1'b0}};
        else if (we) v[w_index] <= w_valid;
    end
endmodule

module data_ram #(parameter INDEX_W = 6, parameter BLOCK_BYTES = 16) (
    input  wire clk,
    input  wire [INDEX_W-1:0] index,
    output wire [BLOCK_BYTES*8-1:0] rd_block,
    input  wire we,
    input  wire [INDEX_W-1:0] w_index,
    input  wire [$clog2(BLOCK_BYTES)-3:0] w_word_sel,
    input  wire [31:0] w_word
);
    reg [BLOCK_BYTES*8-1:0] mem [0:(1<<INDEX_W)-1];
    assign rd_block = mem[index];
    always @(posedge clk) if (we) mem[w_index][w_word_sel*32 +: 32] <= w_word;
endmodule

module tag_comparator #(parameter TAG_W = 22) (
    input  wire [TAG_W-1:0] tag_a,
    input  wire [TAG_W-1:0] tag_b,
    input  wire valid,
    output wire hit
);
    assign hit = valid & (tag_a == tag_b);
endmodule

// Memory: ack comes MEM_LATENCY cycles after mem_req is first seen (plan.md 4.2),
// mem[w] = w * 32'h9E3779B1 initially (plan.md 4.6).
module main_memory #(parameter MEM_WORDS = 65536, parameter MEM_LATENCY = 4) (
    input  wire clk,
    input  wire rst_n,
    input  wire mem_req,
    input  wire mem_we,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    output reg  [31:0] mem_rdata,
    output reg  mem_ack
);
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;
    initial for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = i * 32'h9E3779B1;

    reg [31:0] cnt;
    wire [31:0] widx = (mem_addr >> 2) % MEM_WORDS;

    always @(posedge clk) begin
        mem_ack <= 1'b0;
        if (!rst_n) begin
            cnt <= 0;
        end else if (mem_req && !mem_ack) begin
            if (cnt == MEM_LATENCY - 1) begin
                cnt     <= 0;
                mem_ack <= 1'b1;
                if (mem_we) mem[widx] <= mem_wdata;
                else        mem_rdata <= mem[widx];
            end else begin
                cnt <= cnt + 1;
            end
        end else begin
            cnt <= 0;
        end
    end
endmodule
