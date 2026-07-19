`timescale 1ns/1ps
`include "dma_defs.vh"

// 将 RX ingress metadata/payload 适配到共享 frame pool 的 context 接口。
// adapter 负责 context reservation、pool block 申请/提交和读回请求的握手；
// RDQ/本地 FIFO 选项用于切断 pool ready 与上层 RX admission 的长组合路径。
module dma_rx_frame_shared_adapter #(
    parameter integer CH_NUM = `DMA_MAX_CH,
    parameter integer CH_ID_W = 4,
    parameter integer BLOCK_NUM = `DMA_FRAME_POOL_BLOCK_NUM,
    parameter integer BLOCK_AW = `DMA_FRAME_POOL_BLOCK_AW,
    parameter integer CTX_DEPTH = `DMA_RX_FC_INGRESS_META_DEPTH,
    parameter integer CTX_AW = `DMA_RX_FC_INGRESS_META_AW,
    parameter integer PAYLOAD_AW = `DMA_RX_FC_INGRESS_PAYLOAD_AW,
    parameter integer WIDE_READ_ENABLE = 0
)(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             ch_reset_valid,
    input      [3:0]  ch_reset_ch,

    input      [3:0]  req_ch,
    input      [3:0]  req_policy,
    input      [31:0] req_aligned_len,
    output            can_accept_frame,
    output            near_full,
    output            full,
    output     [CH_NUM*32-1:0] used_bytes_flat,
    output     [CH_NUM*32-1:0] meta_used_flat,

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
    output reg  [63:0] payload_rd_data,

    input              wide_payload_enable,
    output             wide_payload_tvalid,
    input              wide_payload_tready,
    output     [511:0] wide_payload_tdata,
    output      [63:0] wide_payload_tkeep,
    output             wide_payload_tlast,

    output wire [15:0] pool_free_count,
    output wire [15:0] pool_alloc_count,
    output wire [15:0] pool_committed_frame_count,
    output wire [15:0] pool_dropped_frame_count,
    output wire        pool_overflow_sticky,
    output wire        pool_leak_check_error,
    output wire        busy,

    output reg         drop_event_valid,
    output reg  [3:0]  drop_event_ch
);

localparam integer TOTAL_CTX = CH_NUM * CTX_DEPTH;
localparam integer CTX_ADDR_W = $clog2(TOTAL_CTX);
localparam integer CTX_TOTAL_W = $clog2(TOTAL_CTX + 1);
localparam integer CTX_W = 299;
localparam [CTX_AW:0] CTX_DEPTH_COUNT = CTX_DEPTH;
localparam [15:0] BLOCK_NUM_COUNT = BLOCK_NUM;
localparam HAS_RD_REQ_QUEUE = (`DMA_ENABLE_FRAME_SHARED_RD_REQ_QUEUE != 0);
localparam integer RDQ_DEPTH = 8;
localparam integer RDQ_AW = 3;
localparam [RDQ_AW:0] RDQ_DEPTH_COUNT = RDQ_DEPTH;
localparam integer POOL_IN_DEPTH = 2;

reg [CTX_W-1:0] ctx_mem [0:TOTAL_CTX-1];
reg [CTX_W-1:0] ctx_mem_rd_data_q;
reg [CTX_ADDR_W-1:0] ctx_mem_rd_addr_q;
reg                   ctx_mem_rd_addr_valid_q;
reg             ctx_read_pending_q;
reg [CH_ID_W-1:0] ctx_read_ch_q;
reg [CTX_ADDR_W-1:0] ctx_mem_wr_addr_q;
reg [CTX_W-1:0]      ctx_mem_wr_data_q;
reg                   ctx_mem_wr_pending_q;
reg             pool_accept_q;

reg [CTX_AW-1:0] ctx_wr_ptr [0:CH_NUM-1];
reg [CTX_AW-1:0] ctx_rd_ptr [0:CH_NUM-1];
reg [CTX_AW:0] ctx_count [0:CH_NUM-1];
reg [CTX_TOTAL_W-1:0] ctx_total_count_q;

reg collect_active;
reg [3:0] collect_ch;
reg [8:0] beats_needed;
reg [8:0] beats_seen;
reg [31:0] bytes_remaining;
reg        collect_input_done_q;
reg [511:0] pool_in_data [0:POOL_IN_DEPTH-1];
reg [63:0]  pool_in_keep [0:POOL_IN_DEPTH-1];
reg         pool_in_last [0:POOL_IN_DEPTH-1];
reg [3:0]   pool_in_ch [0:POOL_IN_DEPTH-1];
reg         pool_in_drop_enable [0:POOL_IN_DEPTH-1];
reg         pool_in_no_drop [0:POOL_IN_DEPTH-1];
reg         pool_in_wr_ptr_q;
reg         pool_in_rd_ptr_q;
reg [1:0]   pool_in_count_q;
reg         pool_issue_valid_q;
reg [511:0] pool_issue_data_q;
reg [63:0]  pool_issue_keep_q;
reg         pool_issue_last_q;
reg [3:0]   pool_issue_ch_q;
reg         pool_issue_drop_enable_q;
reg         pool_issue_no_drop_q;

reg [3:0]  pend_ch;
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
reg        pend_cpl_en;
reg        pend_ring;
reg        pend_wrap_before;

reg frame_valid_q;
reg [3:0] frame_ch_q;
reg [3:0] frame_tc_q;
reg [3:0] frame_policy_q;
reg [15:0] frame_flow_id_q;
reg [15:0] frame_msg_id_q;
reg [31:0] frame_payload_len_q;
reg [31:0] frame_aligned_len_q;
reg [31:0] frame_dst_addr_q;
reg [31:0] frame_next_wr_ptr_q;
reg [31:0] frame_frame_seq_q;
reg [63:0] frame_timestamp_q;
reg [31:0] frame_sample_count_q;
reg frame_cpl_en_q;
reg frame_ring_q;
reg frame_wrap_before_q;
reg [511:0] beat_buf_q;
reg [63:0] beat_buf_keep_q;
reg beat_buf_last_q;
reg [15:0] beat_block_q;
reg beat_buf_valid_q;
reg pending_rd_q;
reg [PAYLOAD_AW-1:0] pending_rd_index_q;
reg [PAYLOAD_AW-1:0] rdq_index [0:RDQ_DEPTH-1];
reg [RDQ_AW-1:0] rdq_wr_ptr;
reg [RDQ_AW-1:0] rdq_rd_ptr;
reg [RDQ_AW:0] rdq_count;

wire pool_s_valid = pool_issue_valid_q;
wire pool_s_ready;
wire incoming_pool_last = ((beats_seen + 1'b1) >= beats_needed);
wire [6:0] last_keep_count =
    (bytes_remaining >= 32'd64) ? 7'd64 : {1'b0, bytes_remaining[5:0]};
wire [63:0] last_keep =
    (last_keep_count == 7'd64) ? 64'hffff_ffff_ffff_ffff :
    ((64'h1 << last_keep_count) - 64'h1);
wire [63:0] incoming_pool_keep = incoming_pool_last ? last_keep : 64'hffff_ffff_ffff_ffff;
wire [511:0] pool_s_data = pool_issue_data_q;
wire [63:0] pool_s_keep = pool_issue_keep_q;
wire pool_s_last = pool_issue_last_q;
wire [3:0] pool_s_ch = pool_issue_ch_q;
wire pool_s_drop_enable = pool_issue_drop_enable_q;
wire pool_s_no_drop = pool_issue_no_drop_q;
wire payload_fire = payload_tvalid && payload_tready;
wire pool_s_fire = pool_s_valid && pool_s_ready;
wire pool_issue_ready = !pool_issue_valid_q || pool_s_ready;
wire pool_fifo_pop = pool_issue_ready && (pool_in_count_q != 0);

wire pool_m_valid;
wire pool_m_ready;
wire [CH_ID_W-1:0] pool_m_ch_id;
wire [511:0] pool_m_data;
wire [63:0] pool_m_keep;
wire pool_m_last;
wire pool_commit_event_valid;
wire [CH_ID_W-1:0] pool_commit_event_ch;
wire [31:0] pool_commit_event_byte_count;
wire pool_drop_event_valid;
wire [CH_ID_W-1:0] pool_drop_event_ch;
wire pool_double_free_error;
wire pool_double_alloc_error;

wire [15:0] req_blocks = (req_aligned_len + 32'd63) >> 6;
wire req_ctx_has_space = (ctx_count[req_ch] < CTX_DEPTH_COUNT);

assign can_accept_frame = req_ctx_has_space &&
                          !collect_active &&
                          (pool_in_count_q == 0) &&
                          !pool_issue_valid_q &&
                          (pool_free_count >= req_blocks);
assign near_full = (pool_free_count <= (BLOCK_NUM_COUNT >> 2));
assign full = (pool_free_count == 16'h0) || !req_ctx_has_space;
assign payload_tready = collect_active && !collect_input_done_q &&
                        (pool_in_count_q < POOL_IN_DEPTH);

wire [CTX_ADDR_W-1:0] ctx_prefetch_addr =
    (pool_m_ch_id * CTX_DEPTH) + ctx_rd_ptr[pool_m_ch_id];

assign meta_valid = frame_valid_q;
assign busy = collect_active || collect_input_done_q || (pool_in_count_q != 0) ||
              pool_issue_valid_q ||
              frame_valid_q || ctx_mem_rd_addr_valid_q ||
              ctx_read_pending_q || ctx_mem_wr_pending_q || beat_buf_valid_q ||
              pool_m_valid || pool_accept_q ||
              (ctx_total_count_q != 0);
assign out_ch = frame_ch_q;
assign out_tc = frame_tc_q;
assign out_policy = frame_policy_q;
assign out_flow_id = frame_flow_id_q;
assign out_msg_id = frame_msg_id_q;
assign out_payload_len = frame_payload_len_q;
assign out_aligned_len = frame_aligned_len_q;
assign out_dst_addr = frame_dst_addr_q;
assign out_next_wr_ptr = frame_next_wr_ptr_q;
assign out_frame_seq = frame_frame_seq_q;
assign out_timestamp = frame_timestamp_q;
assign out_sample_count = frame_sample_count_q;
assign out_cpl_en = frame_cpl_en_q;
assign out_ring = frame_ring_q;
assign out_wrap_before = frame_wrap_before_q;

wire [15:0] rd_block = payload_rd_index[PAYLOAD_AW-1:3];
wire [2:0] rd_lane = payload_rd_index[2:0];
wire [15:0] pending_rd_block = pending_rd_index_q[PAYLOAD_AW-1:3];
wire [2:0] pending_rd_lane = pending_rd_index_q[2:0];
wire rdq_valid = (rdq_count != 0);
wire [PAYLOAD_AW-1:0] rdq_front_index = rdq_index[rdq_rd_ptr];
wire [15:0] rdq_front_block = rdq_front_index[PAYLOAD_AW-1:3];
wire [2:0] rdq_front_lane = rdq_front_index[2:0];
wire rdq_front_hit = rdq_valid && beat_buf_valid_q && (beat_block_q == rdq_front_block);
wire rdq_front_need_pool = rdq_valid &&
    (!beat_buf_valid_q || (beat_block_q != rdq_front_block));
wire rdq_push = HAS_RD_REQ_QUEUE && payload_rd_req;
wire legacy_need_pool_for_pending = pending_rd_q &&
    (!beat_buf_valid_q || (beat_block_q != pending_rd_block));
wire need_pool_for_pending = HAS_RD_REQ_QUEUE ? rdq_front_need_pool : legacy_need_pool_for_pending;
wire pool_prefetch_candidate = !frame_valid_q &&
                               (HAS_RD_REQ_QUEUE ? (rdq_count == 0) : !pending_rd_q) &&
                               !beat_buf_valid_q &&
                               (ctx_count[pool_m_ch_id] != 0);
wire pool_prefetch_ready = pool_prefetch_candidate &&
                           !ctx_mem_rd_addr_valid_q &&
                           !ctx_read_pending_q;
wire pool_read_ready = frame_valid_q &&
                       need_pool_for_pending &&
                       (pool_m_ch_id == frame_ch_q);
wire wide_beat_buf_valid = (WIDE_READ_ENABLE != 0) && wide_payload_enable &&
                           frame_valid_q && beat_buf_valid_q;
wire wide_pool_valid = (WIDE_READ_ENABLE != 0) && wide_payload_enable &&
                       frame_valid_q && !beat_buf_valid_q && pool_m_valid &&
                       (pool_m_ch_id == frame_ch_q);
wire wide_beat_buf_fire = wide_beat_buf_valid && wide_payload_tready;
wire wide_pool_ready = (WIDE_READ_ENABLE != 0) && wide_payload_enable &&
                       frame_valid_q && !beat_buf_valid_q &&
                       (pool_m_ch_id == frame_ch_q) && wide_payload_tready;
assign wide_payload_tvalid = wide_beat_buf_valid || wide_pool_valid;
assign wide_payload_tdata = wide_beat_buf_valid ? beat_buf_q : pool_m_data;
assign wide_payload_tkeep = wide_beat_buf_valid ? beat_buf_keep_q : pool_m_keep;
assign wide_payload_tlast = wide_beat_buf_valid ? beat_buf_last_q : pool_m_last;
assign pool_m_ready = (WIDE_READ_ENABLE != 0) ?
                      (pool_m_valid && (pool_prefetch_ready || wide_pool_ready)) :
                      (pool_m_valid && pool_accept_q);
wire pool_m_fire = pool_m_valid && pool_m_ready;
wire ctx_read_issue = pool_m_fire && pool_prefetch_ready;
wire rdq_pop = HAS_RD_REQ_QUEUE && ((pool_m_fire && pool_read_ready) || rdq_front_hit);
wire ctx_pop = meta_pop && frame_valid_q;
wire ctx_pop_same_ch = ctx_pop && (pool_commit_event_ch == frame_ch_q);
wire ctx_push = pool_commit_event_valid &&
                ((ctx_count[pool_commit_event_ch] < CTX_DEPTH[CTX_AW:0]) ||
                 ctx_pop_same_ch);
wire ctx_push_pop_same_ch = ctx_push && ctx_pop_same_ch;
wire [CTX_ADDR_W-1:0] ctx_write_addr =
    (pool_commit_event_ch * CTX_DEPTH) + ctx_wr_ptr[pool_commit_event_ch];
wire [CTX_W-1:0] ctx_write_data = {
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
    pend_cpl_en,
    pend_ring,
    pend_wrap_before
};

genvar gi;
generate
    for (gi = 0; gi < CH_NUM; gi = gi + 1) begin : g_ctx_flat
        assign used_bytes_flat[gi*32 +: 32] =
            {27'h0, ctx_count[gi], 3'b000} |
            ((collect_active && (collect_ch == gi[3:0])) ? 32'd64 : 32'h0);
        assign meta_used_flat[gi*32 +: 32] =
            {{(32-CTX_AW-1){1'b0}}, ctx_count[gi]};
    end
endgenerate

function [CTX_AW-1:0] ctx_ptr_next;
    input [CTX_AW-1:0] ptr;
    begin
        if (ptr == CTX_DEPTH-1)
            ctx_ptr_next = {CTX_AW{1'b0}};
        else
            ctx_ptr_next = ptr + 1'b1;
    end
endfunction

always @(posedge clk) begin
    if (!rstn || soft_reset) begin
        ctx_mem_wr_pending_q <= 1'b0;
        ctx_mem_rd_addr_valid_q <= 1'b0;
    end else begin
        ctx_mem_wr_pending_q <= ctx_push;
        if (ctx_push) begin
            ctx_mem_wr_addr_q <= ctx_write_addr;
            ctx_mem_wr_data_q <= ctx_write_data;
        end
        ctx_mem_rd_addr_valid_q <= ctx_read_issue;
        if (ctx_read_issue)
            ctx_mem_rd_addr_q <= ctx_prefetch_addr;
        if (ch_reset_valid && (ctx_read_ch_q == ch_reset_ch))
            ctx_mem_rd_addr_valid_q <= 1'b0;
    end
end

always @(posedge clk) begin
    if (ctx_mem_wr_pending_q)
        ctx_mem[ctx_mem_wr_addr_q] <= ctx_mem_wr_data_q;
end

always @(posedge clk) begin
    if (ctx_mem_rd_addr_valid_q)
        ctx_mem_rd_data_q <= ctx_mem[ctx_mem_rd_addr_q];
end

dma_frame_shared_pool #(
    .CH_NUM(CH_NUM),
    .CH_ID_W(CH_ID_W),
    .BLOCK_NUM(BLOCK_NUM),
    .BLOCK_AW(BLOCK_AW),
    .DATA_W(512),
    .KEEP_W(64),
    .META_DEPTH(CTX_DEPTH),
    .META_AW(CTX_AW),
    .MAX_FRAME_BLOCKS(BLOCK_NUM),
    .DEBUG_OWNERSHIP(0),
    .SERIAL_INGRESS(`DMA_ENABLE_FRAME_SHARED_SERIAL_INGRESS)
) u_pool (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .s_valid(pool_s_valid),
    .s_ready(pool_s_ready),
    .s_ch_id(pool_s_ch),
    .s_data(pool_s_data),
    .s_keep(pool_s_keep),
    .s_last(pool_s_last),
    .s_drop_enable(pool_s_drop_enable),
    .s_no_drop(pool_s_no_drop),
    .m_valid(pool_m_valid),
    .m_ready(pool_m_ready),
    .m_ch_id(pool_m_ch_id),
    .m_data(pool_m_data),
    .m_keep(pool_m_keep),
    .m_last(pool_m_last),
    .free_count(pool_free_count),
    .alloc_count(pool_alloc_count),
    .committed_frame_count(pool_committed_frame_count),
    .dropped_frame_count(pool_dropped_frame_count),
    .overflow_sticky(pool_overflow_sticky),
    .double_free_error(pool_double_free_error),
    .double_alloc_error(pool_double_alloc_error),
    .leak_check_error(pool_leak_check_error),
    .commit_event_valid(pool_commit_event_valid),
    .commit_event_ch(pool_commit_event_ch),
    .commit_event_byte_count(pool_commit_event_byte_count),
    .drop_event_valid(pool_drop_event_valid),
    .drop_event_ch(pool_drop_event_ch)
);

integer i;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        pool_accept_q <= 1'b0;
        collect_active <= 1'b0;
        collect_input_done_q <= 1'b0;
        pool_in_wr_ptr_q <= 1'b0;
        pool_in_rd_ptr_q <= 1'b0;
        pool_in_count_q <= 2'h0;
        pool_issue_valid_q <= 1'b0;
        collect_done <= 1'b0;
        ctx_read_pending_q <= 1'b0;
        ctx_total_count_q <= {CTX_TOTAL_W{1'b0}};
        frame_valid_q <= 1'b0;
        beat_buf_valid_q <= 1'b0;
        beat_buf_keep_q <= 64'h0;
        beat_buf_last_q <= 1'b0;
        pending_rd_q <= 1'b0;
        rdq_wr_ptr <= {RDQ_AW{1'b0}};
        rdq_rd_ptr <= {RDQ_AW{1'b0}};
        rdq_count <= {(RDQ_AW+1){1'b0}};
        payload_rd_valid <= 1'b0;
        drop_event_valid <= 1'b0;
        for (i = 0; i < CH_NUM; i = i + 1) begin
            ctx_wr_ptr[i] <= {CTX_AW{1'b0}};
            ctx_rd_ptr[i] <= {CTX_AW{1'b0}};
            ctx_count[i] <= {(CTX_AW+1){1'b0}};
        end
    end else if (soft_reset) begin
        pool_accept_q <= 1'b0;
        collect_active <= 1'b0;
        collect_input_done_q <= 1'b0;
        pool_in_wr_ptr_q <= 1'b0;
        pool_in_rd_ptr_q <= 1'b0;
        pool_in_count_q <= 2'h0;
        pool_issue_valid_q <= 1'b0;
        collect_done <= 1'b0;
        ctx_read_pending_q <= 1'b0;
        ctx_total_count_q <= {CTX_TOTAL_W{1'b0}};
        frame_valid_q <= 1'b0;
        beat_buf_valid_q <= 1'b0;
        beat_buf_keep_q <= 64'h0;
        beat_buf_last_q <= 1'b0;
        pending_rd_q <= 1'b0;
        rdq_wr_ptr <= {RDQ_AW{1'b0}};
        rdq_rd_ptr <= {RDQ_AW{1'b0}};
        rdq_count <= {(RDQ_AW+1){1'b0}};
        payload_rd_valid <= 1'b0;
        drop_event_valid <= 1'b0;
        for (i = 0; i < CH_NUM; i = i + 1) begin
            ctx_wr_ptr[i] <= {CTX_AW{1'b0}};
            ctx_rd_ptr[i] <= {CTX_AW{1'b0}};
            ctx_count[i] <= {(CTX_AW+1){1'b0}};
        end
    end else begin
        if (WIDE_READ_ENABLE != 0) begin
            pool_accept_q <= 1'b0;
        end else begin
            if (pool_m_fire)
                pool_accept_q <= 1'b0;
            else if (!pool_accept_q && pool_m_valid && (pool_prefetch_ready || pool_read_ready))
                pool_accept_q <= 1'b1;
        end
        ctx_read_pending_q <= ctx_mem_rd_addr_valid_q;
        if (ctx_read_issue)
            ctx_read_ch_q <= pool_m_ch_id;
        if (ctx_read_pending_q) begin
            frame_ch_q <= ctx_read_ch_q;
            {
                frame_tc_q,
                frame_policy_q,
                frame_flow_id_q,
                frame_msg_id_q,
                frame_payload_len_q,
                frame_aligned_len_q,
                frame_dst_addr_q,
                frame_next_wr_ptr_q,
                frame_frame_seq_q,
                frame_timestamp_q,
                frame_sample_count_q,
                frame_cpl_en_q,
                frame_ring_q,
                frame_wrap_before_q
            } <= ctx_mem_rd_data_q;
            frame_valid_q <= 1'b1;
        end
        collect_done <= 1'b0;
        payload_rd_valid <= 1'b0;
        drop_event_valid <= 1'b0;

        if (ch_reset_valid) begin
            ctx_total_count_q <= ctx_total_count_q - ctx_count[ch_reset_ch];
            ctx_wr_ptr[ch_reset_ch] <= {CTX_AW{1'b0}};
            ctx_rd_ptr[ch_reset_ch] <= {CTX_AW{1'b0}};
            ctx_count[ch_reset_ch] <= {(CTX_AW+1){1'b0}};
            if (ctx_read_ch_q == ch_reset_ch) begin
                ctx_read_pending_q <= 1'b0;
                frame_valid_q <= 1'b0;
            end
            if (collect_active && (collect_ch == ch_reset_ch)) begin
                collect_active <= 1'b0;
                collect_input_done_q <= 1'b0;
                pool_in_wr_ptr_q <= 1'b0;
                pool_in_rd_ptr_q <= 1'b0;
                pool_in_count_q <= 2'h0;
                pool_issue_valid_q <= 1'b0;
                collect_done <= 1'b1;
            end
            if (frame_valid_q && (frame_ch_q == ch_reset_ch)) begin
                frame_valid_q <= 1'b0;
                beat_buf_valid_q <= 1'b0;
                pending_rd_q <= 1'b0;
                rdq_wr_ptr <= {RDQ_AW{1'b0}};
                rdq_rd_ptr <= {RDQ_AW{1'b0}};
                rdq_count <= {(RDQ_AW+1){1'b0}};
            end
        end else begin
            if (start_frame) begin
                collect_active <= (in_payload_len != 0);
                collect_ch <= in_ch;
                beats_needed <= (in_aligned_len + 32'd63) >> 6;
                beats_seen <= 9'h0;
                bytes_remaining <= in_payload_len;
                collect_input_done_q <= 1'b0;
                pool_in_wr_ptr_q <= 1'b0;
                pool_in_rd_ptr_q <= 1'b0;
                pool_in_count_q <= 2'h0;
                pool_issue_valid_q <= 1'b0;
                pend_ch <= in_ch;
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
                pend_cpl_en <= in_cpl_en;
                pend_ring <= in_ring;
                pend_wrap_before <= in_wrap_before;
                if (in_payload_len == 0)
                    collect_done <= 1'b1;
            end else begin
                if (payload_fire) begin
                    pool_in_data[pool_in_wr_ptr_q] <= payload_tdata;
                    pool_in_keep[pool_in_wr_ptr_q] <= incoming_pool_keep;
                    pool_in_last[pool_in_wr_ptr_q] <= incoming_pool_last;
                    pool_in_ch[pool_in_wr_ptr_q] <= collect_ch;
                    pool_in_drop_enable[pool_in_wr_ptr_q] <=
                        (pend_policy == `DMA_RX_POL_QUEUE_DROP_NEW);
                    pool_in_no_drop[pool_in_wr_ptr_q] <=
                        (pend_policy != `DMA_RX_POL_QUEUE_DROP_NEW);
                    pool_in_wr_ptr_q <= pool_in_wr_ptr_q + 1'b1;
                    beats_seen <= beats_seen + 1'b1;
                    if (bytes_remaining > 32'd64)
                        bytes_remaining <= bytes_remaining - 32'd64;
                    else
                        bytes_remaining <= 32'h0;
                    if (incoming_pool_last)
                        collect_input_done_q <= 1'b1;
                end

                if (pool_issue_ready) begin
                    pool_issue_valid_q <= (pool_in_count_q != 0);
                    if (pool_in_count_q != 0) begin
                        pool_issue_data_q <= pool_in_data[pool_in_rd_ptr_q];
                        pool_issue_keep_q <= pool_in_keep[pool_in_rd_ptr_q];
                        pool_issue_last_q <= pool_in_last[pool_in_rd_ptr_q];
                        pool_issue_ch_q <= pool_in_ch[pool_in_rd_ptr_q];
                        pool_issue_drop_enable_q <= pool_in_drop_enable[pool_in_rd_ptr_q];
                        pool_issue_no_drop_q <= pool_in_no_drop[pool_in_rd_ptr_q];
                    end
                end

                if (pool_fifo_pop)
                    pool_in_rd_ptr_q <= pool_in_rd_ptr_q + 1'b1;

                if (pool_s_fire) begin
                    if (pool_s_last) begin
                        collect_active <= 1'b0;
                        collect_input_done_q <= 1'b0;
                        collect_done <= 1'b1;
                    end
                end

                case ({payload_fire, pool_fifo_pop})
                2'b10: pool_in_count_q <= pool_in_count_q + 1'b1;
                2'b01: pool_in_count_q <= pool_in_count_q - 1'b1;
                default: pool_in_count_q <= pool_in_count_q;
                endcase
            end

            if (ctx_push) begin
                ctx_wr_ptr[pool_commit_event_ch] <= ctx_ptr_next(ctx_wr_ptr[pool_commit_event_ch]);
                if (!ctx_push_pop_same_ch)
                    ctx_count[pool_commit_event_ch] <= ctx_count[pool_commit_event_ch] + 1'b1;
            end

            if (pool_drop_event_valid) begin
                drop_event_valid <= 1'b1;
                drop_event_ch <= pool_drop_event_ch;
            end

            if (WIDE_READ_ENABLE != 0) begin
                if (pool_m_fire && pool_prefetch_ready) begin
                    beat_buf_q <= pool_m_data;
                    beat_buf_keep_q <= pool_m_keep;
                    beat_buf_last_q <= pool_m_last;
                    beat_block_q <= 16'h0;
                    beat_buf_valid_q <= 1'b1;
                end
                if (wide_beat_buf_fire)
                    beat_buf_valid_q <= 1'b0;
            end else if (HAS_RD_REQ_QUEUE) begin
                if (pool_m_fire) begin
                    beat_buf_q <= pool_m_data;
                    beat_buf_keep_q <= pool_m_keep;
                    beat_buf_last_q <= pool_m_last;
                    if (pool_prefetch_ready) begin
                        beat_block_q <= 16'h0;
                        beat_buf_valid_q <= 1'b1;
                    end else if (pool_read_ready) begin
                        beat_block_q <= rdq_front_block;
                        beat_buf_valid_q <= 1'b1;
                        payload_rd_valid <= 1'b1;
                        payload_rd_data <= pool_m_data[rdq_front_lane*64 +: 64];
                    end
                end

                if (rdq_front_hit) begin
                    payload_rd_valid <= 1'b1;
                    payload_rd_data <= beat_buf_q[rdq_front_lane*64 +: 64];
                end

                if (rdq_push) begin
                    rdq_index[rdq_wr_ptr] <= payload_rd_index;
                    rdq_wr_ptr <= rdq_wr_ptr + 1'b1;
                end
                if (rdq_pop)
                    rdq_rd_ptr <= rdq_rd_ptr + 1'b1;
                case ({rdq_push, rdq_pop})
                2'b10: begin
                    if (rdq_count < RDQ_DEPTH_COUNT)
                        rdq_count <= rdq_count + 1'b1;
                end
                2'b01: begin
                    if (rdq_count != 0)
                        rdq_count <= rdq_count - 1'b1;
                end
                default: begin
                end
                endcase
            end else begin
                if (pool_m_fire) begin
                    beat_buf_q <= pool_m_data;
                    beat_buf_keep_q <= pool_m_keep;
                    beat_buf_last_q <= pool_m_last;
                    if (pool_prefetch_ready) begin
                        beat_block_q <= 16'h0;
                        beat_buf_valid_q <= 1'b1;
                    end else if (pool_read_ready) begin
                        beat_block_q <= pending_rd_block;
                        beat_buf_valid_q <= 1'b1;
                        payload_rd_valid <= 1'b1;
                        payload_rd_data <= pool_m_data[pending_rd_lane*64 +: 64];
                        pending_rd_q <= 1'b0;
                    end
                end

                if (payload_rd_req) begin
                    if (beat_buf_valid_q && (beat_block_q == rd_block)) begin
                        payload_rd_valid <= 1'b1;
                        payload_rd_data <= beat_buf_q[rd_lane*64 +: 64];
                    end else begin
                        pending_rd_q <= 1'b1;
                        pending_rd_index_q <= payload_rd_index;
                    end
                end
            end

            if (ctx_pop) begin
                ctx_rd_ptr[frame_ch_q] <= ctx_ptr_next(ctx_rd_ptr[frame_ch_q]);
                if ((ctx_count[frame_ch_q] != 0) && !ctx_push_pop_same_ch)
                    ctx_count[frame_ch_q] <= ctx_count[frame_ch_q] - 1'b1;
                frame_valid_q <= 1'b0;
                beat_buf_valid_q <= 1'b0;
                pending_rd_q <= 1'b0;
                rdq_wr_ptr <= {RDQ_AW{1'b0}};
                rdq_rd_ptr <= {RDQ_AW{1'b0}};
                rdq_count <= {(RDQ_AW+1){1'b0}};
            end
            case ({ctx_push, ctx_pop})
            2'b10: ctx_total_count_q <= ctx_total_count_q + 1'b1;
            2'b01: ctx_total_count_q <= ctx_total_count_q - 1'b1;
            default: begin
            end
            endcase
        end
    end
end

endmodule
