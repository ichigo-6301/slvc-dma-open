`timescale 1ns/1ps
`include "dma_defs.vh"

// FC ingress bank 为多通道提供统一的 payload/metadata 存储窗口。
// 地址由 channel 与队列索引拼接得到，数据 RAM 和 metadata RAM 分离，便于按包
// 进行 admission、回收和 pause/resume 控制，而不把每个通道复制成独立大 FIFO。
module dma_rx_fc_ingress_bank #(
    parameter CHANNELS      = `DMA_MAX_CH,
    parameter PAYLOAD_WORDS = `DMA_RX_FC_INGRESS_PAYLOAD_WORDS,
    parameter PAYLOAD_AW    = `DMA_RX_FC_INGRESS_PAYLOAD_AW,
    parameter META_DEPTH    = `DMA_RX_FC_INGRESS_META_DEPTH,
    parameter META_AW       = `DMA_RX_FC_INGRESS_META_AW
)(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             ch_reset_valid,
    input      [3:0]  ch_reset_ch,

    input      [3:0]  req_ch,
    input      [31:0] req_aligned_len,
    output            can_accept_frame,
    output            near_full,
    output            full,
    output     [CHANNELS*32-1:0] used_bytes_flat,
    output     [CHANNELS*32-1:0] meta_used_flat,

    input             start_frame,
    input      [3:0]  in_ch,
    input      [3:0]  in_tc,
    input      [3:0]  in_policy,
    input      [15:0] in_flow_id,
    input      [15:0] in_msg_id,
    input      [31:0] in_payload_len,
    input      [31:0] in_aligned_len,
    input      [31:0] in_dst_addr,
    input      [31:0] in_next_wr_ptr,
    input      [31:0] in_frame_seq,
    input      [63:0] in_timestamp,
    input      [31:0] in_sample_count,
    input             in_cpl_en,
    input             in_ring,
    input             in_wrap_before,

    input      [511:0] payload_tdata,
    input              payload_tvalid,
    output             payload_tready,
    output reg         collect_done,

    output             meta_valid,
    input              meta_pop,
    output      [3:0]  out_ch,
    output      [3:0]  out_tc,
    output      [3:0]  out_policy,
    output     [15:0]  out_flow_id,
    output     [15:0]  out_msg_id,
    output     [31:0]  out_payload_len,
    output     [31:0]  out_aligned_len,
    output     [31:0]  out_dst_addr,
    output     [31:0]  out_next_wr_ptr,
    output     [31:0]  out_frame_seq,
    output     [63:0]  out_timestamp,
    output     [31:0]  out_sample_count,
    output             out_cpl_en,
    output             out_ring,
    output             out_wrap_before,
    input              payload_rd_req,
    input      [PAYLOAD_AW-1:0] payload_rd_index,
    output reg         payload_rd_valid,
    output     [63:0]  payload_rd_data
);

function integer clog2;
    input integer value;
    integer v;
    begin
        v = value - 1;
        for (clog2 = 0; v > 0; clog2 = clog2 + 1)
            v = v >> 1;
    end
endfunction

localparam PAYLOAD_BEATS    = PAYLOAD_WORDS / 8;
localparam PAYLOAD_BEAT_AW  = PAYLOAD_AW - 3;
localparam TOTAL_BEATS      = CHANNELS * PAYLOAD_BEATS;
localparam TOTAL_BEAT_AW    = clog2(TOTAL_BEATS);
localparam TOTAL_META       = CHANNELS * META_DEPTH;
localparam META_ADDR_W      = clog2(TOTAL_META);
localparam META_W           = 4 + 4 + 16 + 16 + 32 + 32 + 32 + 32 +
                              32 + 64 + 32 + 32 + 1 + 1 + 1 +
                              PAYLOAD_AW + (PAYLOAD_AW + 1);
localparam META_ALLOC_LSB   = 0;
localparam META_START_LSB   = META_ALLOC_LSB + PAYLOAD_AW + 1;
localparam META_WRAP_LSB    = META_START_LSB + PAYLOAD_AW;
localparam META_RING_LSB    = META_WRAP_LSB + 1;
localparam META_CPL_LSB     = META_RING_LSB + 1;
localparam META_SEQ_LSB     = META_CPL_LSB + 1;
localparam META_SAMPLE_LSB  = META_SEQ_LSB + 32;
localparam META_TS_LSB      = META_SAMPLE_LSB + 32;
localparam META_FRAME_LSB   = META_TS_LSB + 64;
localparam META_NEXT_LSB    = META_FRAME_LSB + 32;
localparam META_DST_LSB     = META_NEXT_LSB + 32;
localparam META_ALIGNED_LSB = META_DST_LSB + 32;
localparam META_PAYLOAD_LSB = META_ALIGNED_LSB + 32;
localparam META_MSG_LSB     = META_PAYLOAD_LSB + 32;
localparam META_FLOW_LSB    = META_MSG_LSB + 16;
localparam META_POLICY_LSB  = META_FLOW_LSB + 16;
localparam META_TC_LSB      = META_POLICY_LSB + 4;

`ifndef DMA_SYNTHESIS
initial begin
    if (CHANNELS > `DMA_MAX_CH)
        $fatal(1, "dma_rx_fc_ingress_bank CHANNELS must be <= DMA_MAX_CH");
    if ((PAYLOAD_WORDS * 8) < 4096)
        $fatal(1, "RX_FC_INGRESS_DEPTH_BYTES must be >= RX_FC_MAX_PAYLOAD_BYTES");
    if (META_DEPTH < 2)
        $fatal(1, "RX_FC_INGRESS_META_DEPTH must be >= 2");
    if (PAYLOAD_AW < 3)
        $fatal(1, "PAYLOAD_AW must cover at least one 512-bit beat");
    if (PAYLOAD_WORDS != (1 << PAYLOAD_AW))
        $fatal(1, "PAYLOAD_WORDS must match PAYLOAD_AW and be power-of-two");
    if ((PAYLOAD_WORDS & 7) != 0)
        $fatal(1, "PAYLOAD_WORDS must be a multiple of 8");
end
`endif

reg [META_W-1:0] meta_mem [0:TOTAL_META-1];
reg [META_W-1:0] meta_mem_wr_data_q;
reg [META_ADDR_W-1:0] meta_mem_wr_addr_q;
reg                   meta_mem_wr_pending_q;
reg [META_ADDR_W-1:0] meta_mem_rd_addr_q;
reg                   meta_mem_rd_addr_valid_q;
reg [META_W-1:0]       meta_mem_rd_data_q;

reg [PAYLOAD_BEAT_AW-1:0] payload_wr_beat_ptr [0:CHANNELS-1];
reg [META_AW-1:0] meta_wr_ptr [0:CHANNELS-1];
reg [META_AW-1:0] meta_rd_ptr [0:CHANNELS-1];
reg [META_AW:0] meta_count [0:CHANNELS-1];
reg [PAYLOAD_AW:0] used_words [0:CHANNELS-1];
reg [CHANNELS-1:0] meta_nonempty_q;

reg [3:0] rr_ptr;
reg [31:0] seq_counter;
reg collect_active;
reg [3:0] collect_ch;
reg [PAYLOAD_BEAT_AW-1:0] collect_wr_beat_ptr;
reg [PAYLOAD_BEAT_AW-1:0] collect_start_beat_ptr;
reg [8:0] beats_needed;
reg [8:0] beats_seen;
reg [PAYLOAD_AW:0] collect_alloc_words;
reg [PAYLOAD_BEAT_AW:0] collect_alloc_beats;
reg                       commit_valid_q;
reg [3:0]                 commit_ch_q;
reg [META_AW-1:0]         commit_meta_wr_q;
reg [PAYLOAD_AW-1:0]      commit_payload_start_q;
reg [PAYLOAD_AW:0]        commit_alloc_words_q;
reg [PAYLOAD_BEAT_AW:0]   commit_alloc_beats_q;

reg [3:0]  pend_tc;
reg [3:0]  pend_policy;
reg [15:0] pend_flow_id;
reg [15:0] pend_msg_id;
reg [31:0] pend_payload_len;
reg [31:0] pend_aligned_len;
reg [31:0] pend_dst_addr;
reg [31:0] pend_next_wr_ptr;
reg [31:0] pend_frame_seq;
reg [63:0] pend_timestamp;
reg [31:0] pend_sample_count;
reg [31:0] pend_seq;
reg        pend_cpl_en;
reg        pend_ring;
reg        pend_wrap_before;

reg        sel_valid;
reg [3:0]  sel_ch;
reg [3:0]  scan_ch;
reg [META_AW-1:0] sel_meta_rd;
integer scan_i;
integer scan_idx;

reg        out_valid_q;
reg [3:0]  out_ch_q;
reg [PAYLOAD_AW-1:0] out_payload_start_q;
reg [PAYLOAD_AW:0]   out_alloc_words_q;
reg [META_AW-1:0]    out_meta_rd_q;
reg [META_W-1:0]      out_meta_q;
reg                   meta_read_pending_q;
reg [3:0]             meta_read_ch_q;
reg [META_AW-1:0]     meta_read_idx_q;

wire payload_ram_wr_en;
wire [TOTAL_BEAT_AW-1:0] payload_ram_wr_addr;
wire [511:0] payload_ram_wr_data;
wire payload_ram_rd_en;
wire [TOTAL_BEAT_AW-1:0] payload_ram_rd_addr;
wire [511:0] payload_ram_rd_data;
reg payload_ram_wr_en_q;
reg [TOTAL_BEAT_AW-1:0] payload_ram_wr_addr_q;
reg [511:0] payload_ram_wr_data_q;
reg payload_ram_rd_en_q;
(* max_fanout = 4 *)
reg [TOTAL_BEAT_AW-1:0] payload_ram_rd_addr_q;
reg [2:0] payload_ram_rd_lane_q;
reg [2:0] payload_rd_lane_q;

wire [PAYLOAD_AW:0] req_words = req_aligned_len[PAYLOAD_AW+2:3];
wire [PAYLOAD_AW:0] req_free_words = PAYLOAD_WORDS[PAYLOAD_AW:0] - used_words[req_ch];
wire [META_AW:0] req_meta_count = meta_count[req_ch];
wire ch_reset_fire = (ch_reset_valid === 1'b1);
wire collect_last_fire = collect_active && payload_tvalid && payload_tready &&
                         ((beats_seen + 1'b1) >= beats_needed);
wire commit_fire = commit_valid_q &&
                   !(ch_reset_fire && (commit_ch_q == ch_reset_ch));
wire commit_frame = commit_fire;
wire pop_frame = meta_pop && out_valid_q && !ch_reset_fire;
wire [3:0] commit_ch = commit_ch_q;
wire [PAYLOAD_AW:0] commit_alloc_words = commit_alloc_words_q;
wire [META_AW-1:0] collect_meta_wr_next =
    (meta_wr_ptr[collect_ch] == META_DEPTH-1) ? {META_AW{1'b0}} : meta_wr_ptr[collect_ch] + 1'b1;
wire [META_AW-1:0] in_meta_wr_next =
    (meta_wr_ptr[in_ch] == META_DEPTH-1) ? {META_AW{1'b0}} : meta_wr_ptr[in_ch] + 1'b1;
wire [META_AW-1:0] out_meta_rd_next =
    (out_meta_rd_q == META_DEPTH-1) ? {META_AW{1'b0}} : out_meta_rd_q + 1'b1;
wire [31:0] out_payload_base_beat = out_ch_q * PAYLOAD_BEATS;
wire [31:0] collect_payload_base_beat = collect_ch * PAYLOAD_BEATS;
wire [PAYLOAD_AW-1:0] selected_word_offset =
    wrap_add_words(out_payload_start_q, payload_rd_index);
wire [PAYLOAD_BEAT_AW-1:0] selected_beat_offset =
    selected_word_offset[PAYLOAD_AW-1:3];
wire [2:0] selected_lane = selected_word_offset[2:0];
wire [31:0] payload_ram_rd_addr_calc = out_payload_base_beat + selected_beat_offset;
wire [31:0] payload_ram_wr_addr_calc = collect_payload_base_beat + collect_wr_beat_ptr;
wire payload_write_fire = payload_tvalid && payload_tready;
wire [META_ADDR_W-1:0] meta_write_addr =
    (commit_ch_q * META_DEPTH) + commit_meta_wr_q;
wire [META_ADDR_W-1:0] meta_read_addr =
    (sel_ch * META_DEPTH) + sel_meta_rd;
wire [META_W-1:0] meta_write_data = {
    pend_tc,
    pend_policy,
    pend_flow_id,
    pend_msg_id,
    pend_payload_len,
    pend_aligned_len,
    pend_dst_addr,
    pend_next_wr_ptr,
    pend_frame_seq,
    pend_timestamp,
    pend_sample_count,
    pend_seq,
    pend_cpl_en,
    pend_ring,
    pend_wrap_before,
    commit_payload_start_q,
    commit_alloc_words_q
};
wire meta_read_issue = !out_valid_q && !meta_read_pending_q &&
                       !meta_mem_rd_addr_valid_q && sel_valid &&
                       !ch_reset_fire;

wire [3:0]  out_meta_tc = out_meta_q[META_TC_LSB +: 4];
wire [3:0]  out_meta_policy = out_meta_q[META_POLICY_LSB +: 4];
wire [15:0] out_meta_flow_id = out_meta_q[META_FLOW_LSB +: 16];
wire [15:0] out_meta_msg_id = out_meta_q[META_MSG_LSB +: 16];
wire [31:0] out_meta_payload_len = out_meta_q[META_PAYLOAD_LSB +: 32];
wire [31:0] out_meta_aligned_len = out_meta_q[META_ALIGNED_LSB +: 32];
wire [31:0] out_meta_dst_addr = out_meta_q[META_DST_LSB +: 32];
wire [31:0] out_meta_next_wr_ptr = out_meta_q[META_NEXT_LSB +: 32];
wire [31:0] out_meta_frame_seq = out_meta_q[META_FRAME_LSB +: 32];
wire [63:0] out_meta_timestamp = out_meta_q[META_TS_LSB +: 64];
wire [31:0] out_meta_sample_count = out_meta_q[META_SAMPLE_LSB +: 32];
wire        out_meta_cpl_en = out_meta_q[META_CPL_LSB];
wire        out_meta_ring = out_meta_q[META_RING_LSB];
wire        out_meta_wrap_before = out_meta_q[META_WRAP_LSB];
wire [PAYLOAD_AW-1:0] out_meta_payload_start = out_meta_q[META_START_LSB +: PAYLOAD_AW];
wire [PAYLOAD_AW:0] out_meta_alloc_words = out_meta_q[META_ALLOC_LSB +: (PAYLOAD_AW + 1)];

assign can_accept_frame = !commit_valid_q &&
                          (req_meta_count < META_DEPTH[META_AW:0]) &&
                          (req_free_words >= req_words);
assign near_full = (req_free_words <= (PAYLOAD_WORDS/4));
assign full = (req_meta_count >= META_DEPTH[META_AW:0]) || (req_free_words == 0);
assign payload_tready = collect_active;
assign meta_valid = out_valid_q;
assign out_ch = out_ch_q;
assign out_tc = out_meta_tc;
assign out_policy = out_meta_policy;
assign out_flow_id = out_meta_flow_id;
assign out_msg_id = out_meta_msg_id;
assign out_payload_len = out_meta_payload_len;
assign out_aligned_len = out_meta_aligned_len;
assign out_dst_addr = out_meta_dst_addr;
assign out_next_wr_ptr = out_meta_next_wr_ptr;
assign out_frame_seq = out_meta_frame_seq;
assign out_timestamp = out_meta_timestamp;
assign out_sample_count = out_meta_sample_count;
assign out_cpl_en = out_meta_cpl_en;
assign out_ring = out_meta_ring;
assign out_wrap_before = out_meta_wrap_before;
assign payload_rd_data = payload_ram_rd_data[payload_rd_lane_q*64 +: 64];
assign payload_ram_wr_en = payload_ram_wr_en_q;
assign payload_ram_wr_addr = payload_ram_wr_addr_q;
assign payload_ram_wr_data = payload_ram_wr_data_q;
assign payload_ram_rd_en = payload_ram_rd_en_q;
assign payload_ram_rd_addr = payload_ram_rd_addr_q;

genvar gi;
generate
    for (gi = 0; gi < CHANNELS; gi = gi + 1) begin : g_used_flat
        assign used_bytes_flat[gi*32 +: 32] = {18'h0, used_words[gi], 3'b000};
        assign meta_used_flat[gi*32 +: 32] = {{(32-META_AW-1){1'b0}}, meta_count[gi]};
    end
endgenerate

dma_payload_beat_ram #(
    .DATA_WIDTH(512),
    .DEPTH(TOTAL_BEATS),
    .ADDR_WIDTH(TOTAL_BEAT_AW),
    .RAM_STYLE("block")
) u_payload_ram (
    .clk(clk),
    .wr_en(payload_ram_wr_en),
    .wr_addr(payload_ram_wr_addr),
    .wr_data(payload_ram_wr_data),
    .rd_en(payload_ram_rd_en),
    .rd_addr(payload_ram_rd_addr),
    .rd_data(payload_ram_rd_data)
);

function [PAYLOAD_BEAT_AW-1:0] wrap_add_beats;
    input [PAYLOAD_BEAT_AW-1:0] base;
    input [PAYLOAD_BEAT_AW:0] inc;
    reg [PAYLOAD_BEAT_AW:0] sum;
    begin
        sum = {1'b0, base} + inc;
        if (sum >= PAYLOAD_BEATS[PAYLOAD_BEAT_AW:0])
            wrap_add_beats = sum - PAYLOAD_BEATS[PAYLOAD_BEAT_AW:0];
        else
            wrap_add_beats = sum[PAYLOAD_BEAT_AW-1:0];
    end
endfunction

function [PAYLOAD_AW-1:0] wrap_add_words;
    input [PAYLOAD_AW-1:0] base;
    input [PAYLOAD_AW-1:0] inc;
    reg [PAYLOAD_AW:0] sum;
    begin
        sum = {1'b0, base} + {1'b0, inc};
        if (sum >= PAYLOAD_WORDS[PAYLOAD_AW:0])
            wrap_add_words = sum - PAYLOAD_WORDS[PAYLOAD_AW:0];
        else
            wrap_add_words = sum[PAYLOAD_AW-1:0];
    end
endfunction

always @(*) begin
    sel_valid = 1'b0;
    sel_ch = rr_ptr;
    sel_meta_rd = {META_AW{1'b0}};
    for (scan_i = 0; scan_i < CHANNELS; scan_i = scan_i + 1) begin
        scan_idx = rr_ptr + scan_i;
        if (scan_idx >= CHANNELS)
            scan_idx = scan_idx - CHANNELS;
        scan_ch = scan_idx[3:0];
        if (!sel_valid && meta_nonempty_q[scan_ch]) begin
            sel_valid = 1'b1;
            sel_ch = scan_ch;
            sel_meta_rd = meta_rd_ptr[scan_ch];
        end
    end
end

always @(posedge clk) begin
    if (!rstn || soft_reset) begin
        meta_mem_wr_pending_q <= 1'b0;
        meta_mem_rd_addr_valid_q <= 1'b0;
    end else begin
        meta_mem_wr_pending_q <= commit_fire;
        if (commit_fire) begin
            meta_mem_wr_addr_q <= meta_write_addr;
            meta_mem_wr_data_q <= meta_write_data;
        end
        meta_mem_rd_addr_valid_q <= meta_read_issue;
        if (meta_read_issue)
            meta_mem_rd_addr_q <= meta_read_addr;
        if (ch_reset_fire && (meta_read_ch_q == ch_reset_ch))
            meta_mem_rd_addr_valid_q <= 1'b0;
    end
end

always @(posedge clk) begin
    if (meta_mem_wr_pending_q)
        meta_mem[meta_mem_wr_addr_q] <= meta_mem_wr_data_q;
end

always @(posedge clk) begin
    if (meta_mem_rd_addr_valid_q)
        meta_mem_rd_data_q <= meta_mem[meta_mem_rd_addr_q];
end

always @(posedge clk) begin
    if (!rstn || soft_reset) begin
        payload_ram_wr_en_q <= 1'b0;
        payload_ram_rd_en_q <= 1'b0;
    end else begin
        payload_ram_wr_en_q <= payload_write_fire;
        if (payload_write_fire) begin
            payload_ram_wr_addr_q <= payload_ram_wr_addr_calc[TOTAL_BEAT_AW-1:0];
            payload_ram_wr_data_q <= payload_tdata;
        end

        payload_ram_rd_en_q <= payload_rd_req;
        if (payload_rd_req) begin
            payload_ram_rd_addr_q <= payload_ram_rd_addr_calc[TOTAL_BEAT_AW-1:0];
            payload_ram_rd_lane_q <= selected_lane;
        end
    end
end

integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        rr_ptr <= 4'h0;
        seq_counter <= 32'h0;
        collect_active <= 1'b0;
        commit_valid_q <= 1'b0;
        collect_done <= 1'b0;
        payload_rd_valid <= 1'b0;
        meta_read_pending_q <= 1'b0;
        out_valid_q <= 1'b0;
        meta_nonempty_q <= {CHANNELS{1'b0}};
        for (i = 0; i < CHANNELS; i = i + 1) begin
            payload_wr_beat_ptr[i] <= {PAYLOAD_BEAT_AW{1'b0}};
            meta_wr_ptr[i] <= {META_AW{1'b0}};
            meta_rd_ptr[i] <= {META_AW{1'b0}};
            meta_count[i] <= {(META_AW+1){1'b0}};
            used_words[i] <= {(PAYLOAD_AW+1){1'b0}};
        end
    end else if (soft_reset) begin
        rr_ptr <= 4'h0;
        seq_counter <= 32'h0;
        collect_active <= 1'b0;
        commit_valid_q <= 1'b0;
        collect_done <= 1'b0;
        payload_rd_valid <= 1'b0;
        meta_read_pending_q <= 1'b0;
        out_valid_q <= 1'b0;
        meta_nonempty_q <= {CHANNELS{1'b0}};
        for (i = 0; i < CHANNELS; i = i + 1) begin
            payload_wr_beat_ptr[i] <= {PAYLOAD_BEAT_AW{1'b0}};
            meta_wr_ptr[i] <= {META_AW{1'b0}};
            meta_rd_ptr[i] <= {META_AW{1'b0}};
            meta_count[i] <= {(META_AW+1){1'b0}};
            used_words[i] <= {(PAYLOAD_AW+1){1'b0}};
        end
    end else begin
        collect_done <= 1'b0;
        if (commit_fire) begin
            payload_wr_beat_ptr[commit_ch_q] <=
                wrap_add_beats(commit_payload_start_q[PAYLOAD_AW-1:3],
                               commit_alloc_beats_q);
            meta_wr_ptr[commit_ch_q] <=
                (commit_meta_wr_q == META_DEPTH-1) ? {META_AW{1'b0}} : commit_meta_wr_q + 1'b1;
            commit_valid_q <= 1'b0;
            collect_done <= 1'b1;
        end
        payload_rd_valid <= payload_ram_rd_en_q;
        if (payload_ram_rd_en_q)
            payload_rd_lane_q <= payload_ram_rd_lane_q;
        meta_read_pending_q <= meta_mem_rd_addr_valid_q;
        if (meta_read_issue) begin
            meta_read_ch_q <= sel_ch;
            meta_read_idx_q <= sel_meta_rd;
        end
        if (meta_read_pending_q) begin
            out_valid_q <= 1'b1;
            out_ch_q <= meta_read_ch_q;
            out_meta_rd_q <= meta_read_idx_q;
            out_meta_q <= meta_mem_rd_data_q;
            out_payload_start_q <= meta_mem_rd_data_q[META_START_LSB +: PAYLOAD_AW];
            out_alloc_words_q <= meta_mem_rd_data_q[META_ALLOC_LSB +: (PAYLOAD_AW + 1)];
        end

        if (ch_reset_fire) begin
            payload_wr_beat_ptr[ch_reset_ch] <= {PAYLOAD_BEAT_AW{1'b0}};
            meta_wr_ptr[ch_reset_ch] <= {META_AW{1'b0}};
            meta_rd_ptr[ch_reset_ch] <= {META_AW{1'b0}};
            meta_count[ch_reset_ch] <= {(META_AW+1){1'b0}};
            used_words[ch_reset_ch] <= {(PAYLOAD_AW+1){1'b0}};
            meta_nonempty_q[ch_reset_ch] <= 1'b0;
            if (collect_active && (collect_ch == ch_reset_ch)) begin
                collect_active <= 1'b0;
                collect_done <= 1'b1;
            end
            if (commit_valid_q && (commit_ch_q == ch_reset_ch)) begin
                commit_valid_q <= 1'b0;
                collect_done <= 1'b1;
            end
            if (meta_read_ch_q == ch_reset_ch)
                meta_read_pending_q <= 1'b0;
            if ((out_valid_q && (out_ch_q == ch_reset_ch)) ||
                (meta_read_pending_q && (meta_read_ch_q == ch_reset_ch)))
                out_valid_q <= 1'b0;
        end else if (start_frame) begin
            pend_tc <= in_tc;
            pend_policy <= in_policy;
            pend_flow_id <= in_flow_id;
            pend_msg_id <= in_msg_id;
            pend_payload_len <= in_payload_len;
            pend_aligned_len <= in_aligned_len;
            pend_dst_addr <= in_dst_addr;
            pend_next_wr_ptr <= in_next_wr_ptr;
            pend_frame_seq <= in_frame_seq;
            pend_timestamp <= in_timestamp;
            pend_sample_count <= in_sample_count;
            pend_seq <= seq_counter;
            pend_cpl_en <= in_cpl_en;
            pend_ring <= in_ring;
            pend_wrap_before <= in_wrap_before;
            collect_ch <= in_ch;
            collect_start_beat_ptr <= payload_wr_beat_ptr[in_ch];
            collect_wr_beat_ptr <= payload_wr_beat_ptr[in_ch];
            collect_alloc_words <= in_aligned_len[PAYLOAD_AW+2:3];
            collect_alloc_beats <= in_aligned_len[PAYLOAD_AW+2:6];
            beats_needed <= (in_aligned_len + 32'd63) >> 6;
            beats_seen <= 9'h0;
            collect_active <= (in_payload_len != 0);
            if (in_payload_len == 0) begin
                commit_valid_q <= 1'b1;
                commit_ch_q <= in_ch;
                commit_meta_wr_q <= meta_wr_ptr[in_ch];
                commit_payload_start_q <= {payload_wr_beat_ptr[in_ch], 3'b000};
                commit_alloc_words_q <= {(PAYLOAD_AW+1){1'b0}};
                commit_alloc_beats_q <= {(PAYLOAD_BEAT_AW+1){1'b0}};
            end
            seq_counter <= seq_counter + 1'b1;
        end else if (payload_tvalid && payload_tready) begin
            collect_wr_beat_ptr <= wrap_add_beats(collect_wr_beat_ptr, {{PAYLOAD_BEAT_AW{1'b0}}, 1'b1});
            beats_seen <= beats_seen + 1'b1;
            if (collect_last_fire) begin
                commit_valid_q <= 1'b1;
                commit_ch_q <= collect_ch;
                commit_meta_wr_q <= meta_wr_ptr[collect_ch];
                commit_payload_start_q <= {collect_start_beat_ptr, 3'b000};
                commit_alloc_words_q <= collect_alloc_words;
                commit_alloc_beats_q <= collect_alloc_beats;
                collect_active <= 1'b0;
            end
        end

        if (pop_frame) begin
            meta_rd_ptr[out_ch_q] <= out_meta_rd_next;
            rr_ptr <= (out_ch_q == CHANNELS-1) ? 4'h0 : out_ch_q + 1'b1;
            out_valid_q <= 1'b0;
        end

        case ({commit_frame, pop_frame})
        2'b10: begin
            meta_count[commit_ch] <= meta_count[commit_ch] + 1'b1;
            used_words[commit_ch] <= used_words[commit_ch] + commit_alloc_words;
            meta_nonempty_q[commit_ch] <= 1'b1;
        end
        2'b01: begin
            meta_count[out_ch_q] <= meta_count[out_ch_q] - 1'b1;
            used_words[out_ch_q] <= used_words[out_ch_q] - out_alloc_words_q;
            if (meta_count[out_ch_q] == {{META_AW{1'b0}}, 1'b1})
                meta_nonempty_q[out_ch_q] <= 1'b0;
        end
        2'b11: begin
            if (commit_ch == out_ch_q) begin
                used_words[out_ch_q] <= used_words[out_ch_q] + commit_alloc_words - out_alloc_words_q;
                meta_nonempty_q[out_ch_q] <= 1'b1;
            end else begin
                meta_count[commit_ch] <= meta_count[commit_ch] + 1'b1;
                used_words[commit_ch] <= used_words[commit_ch] + commit_alloc_words;
                meta_nonempty_q[commit_ch] <= 1'b1;
                meta_count[out_ch_q] <= meta_count[out_ch_q] - 1'b1;
                used_words[out_ch_q] <= used_words[out_ch_q] - out_alloc_words_q;
                if (meta_count[out_ch_q] == {{META_AW{1'b0}}, 1'b1})
                    meta_nonempty_q[out_ch_q] <= 1'b0;
            end
        end
        default: ;
        endcase
    end
end

endmodule
