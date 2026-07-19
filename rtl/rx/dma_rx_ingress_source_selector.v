`timescale 1ns/1ps

// 在普通 stream ingress 与 shared-frame ingress 之间选择一个包级 source。
// 一旦当前 metadata 被锁定，source 在整个 payload/commit 生命周期内保持不变，
// 防止另一条路径突然变为 valid 时切换数据来源。
module dma_rx_ingress_source_selector #(
    parameter integer PAYLOAD_AW = 10
)(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             meta_take,
    input             meta_pop,

    input             s0_meta_valid,
    output            s0_meta_pop,
    input      [3:0]  s0_ch,
    input      [3:0]  s0_tc,
    input      [3:0]  s0_policy,
    input      [15:0] s0_flow_id,
    input      [15:0] s0_msg_id,
    input      [31:0] s0_payload_len,
    input      [31:0] s0_aligned_len,
    input      [31:0] s0_dst_addr,
    input      [31:0] s0_next_wr_ptr,
    input      [31:0] s0_frame_seq,
    input      [63:0] s0_timestamp,
    input      [31:0] s0_sample_count,
    input             s0_cpl_en,
    input             s0_ring,
    input             s0_wrap_before,
    output            s0_payload_rd_req,
    output     [PAYLOAD_AW-1:0] s0_payload_rd_index,
    input             s0_payload_rd_valid,
    input      [63:0] s0_payload_rd_data,
    output            s0_wide_payload_enable,
    input             s0_wide_payload_tvalid,
    output            s0_wide_payload_tready,
    input      [511:0] s0_wide_payload_tdata,
    input      [63:0] s0_wide_payload_tkeep,
    input             s0_wide_payload_tlast,

    input             s1_meta_valid,
    output            s1_meta_pop,
    input      [3:0]  s1_ch,
    input      [3:0]  s1_tc,
    input      [3:0]  s1_policy,
    input      [15:0] s1_flow_id,
    input      [15:0] s1_msg_id,
    input      [31:0] s1_payload_len,
    input      [31:0] s1_aligned_len,
    input      [31:0] s1_dst_addr,
    input      [31:0] s1_next_wr_ptr,
    input      [31:0] s1_frame_seq,
    input      [63:0] s1_timestamp,
    input      [31:0] s1_sample_count,
    input             s1_cpl_en,
    input             s1_ring,
    input             s1_wrap_before,
    output            s1_payload_rd_req,
    output     [PAYLOAD_AW-1:0] s1_payload_rd_index,
    input             s1_payload_rd_valid,
    input      [63:0] s1_payload_rd_data,
    output            s1_wide_payload_enable,
    input             s1_wide_payload_tvalid,
    output            s1_wide_payload_tready,
    input      [511:0] s1_wide_payload_tdata,
    input      [63:0] s1_wide_payload_tkeep,
    input             s1_wide_payload_tlast,

    output            meta_valid,
    output     [3:0]  out_ch,
    output     [3:0]  out_tc,
    output     [3:0]  out_policy,
    output     [15:0] out_flow_id,
    output     [15:0] out_msg_id,
    output     [31:0] out_payload_len,
    output     [31:0] out_aligned_len,
    output     [31:0] out_dst_addr,
    output     [31:0] out_next_wr_ptr,
    output     [31:0] out_frame_seq,
    output     [63:0] out_timestamp,
    output     [31:0] out_sample_count,
    output            out_cpl_en,
    output            out_ring,
    output            out_wrap_before,
    input             payload_rd_req,
    input      [PAYLOAD_AW-1:0] payload_rd_index,
    output            payload_rd_valid,
    output     [63:0] payload_rd_data,
    output            wide_payload_tvalid,
    input             wide_payload_tready,
    output     [511:0] wide_payload_tdata,
    output      [63:0] wide_payload_tkeep,
    output            wide_payload_tlast,
    output            active_is_frame
);

// frame source 优先用于避免 shared pool metadata 长时间等待；active_q 锁住选择。
localparam SRC_STREAM = 1'b0;
localparam SRC_FRAME  = 1'b1;

reg active_q;
reg src_q;

wire choose_frame = !s0_meta_valid && s1_meta_valid;
wire cur_src = active_q ? src_q : choose_frame;
wire cur_is_frame = (cur_src == SRC_FRAME);

assign meta_valid = active_q ? (src_q ? s1_meta_valid : s0_meta_valid) :
                    (s0_meta_valid || s1_meta_valid);

assign out_ch = cur_is_frame ? s1_ch : s0_ch;
assign out_tc = cur_is_frame ? s1_tc : s0_tc;
assign out_policy = cur_is_frame ? s1_policy : s0_policy;
assign out_flow_id = cur_is_frame ? s1_flow_id : s0_flow_id;
assign out_msg_id = cur_is_frame ? s1_msg_id : s0_msg_id;
assign out_payload_len = cur_is_frame ? s1_payload_len : s0_payload_len;
assign out_aligned_len = cur_is_frame ? s1_aligned_len : s0_aligned_len;
assign out_dst_addr = cur_is_frame ? s1_dst_addr : s0_dst_addr;
assign out_next_wr_ptr = cur_is_frame ? s1_next_wr_ptr : s0_next_wr_ptr;
assign out_frame_seq = cur_is_frame ? s1_frame_seq : s0_frame_seq;
assign out_timestamp = cur_is_frame ? s1_timestamp : s0_timestamp;
assign out_sample_count = cur_is_frame ? s1_sample_count : s0_sample_count;
assign out_cpl_en = cur_is_frame ? s1_cpl_en : s0_cpl_en;
assign out_ring = cur_is_frame ? s1_ring : s0_ring;
assign out_wrap_before = cur_is_frame ? s1_wrap_before : s0_wrap_before;

assign s0_meta_pop = active_q && (src_q == SRC_STREAM) && meta_pop;
assign s1_meta_pop = active_q && (src_q == SRC_FRAME) && meta_pop;
assign s0_payload_rd_req = active_q && (src_q == SRC_STREAM) && payload_rd_req;
assign s1_payload_rd_req = active_q && (src_q == SRC_FRAME) && payload_rd_req;
assign s0_payload_rd_index = payload_rd_index;
assign s1_payload_rd_index = payload_rd_index;
assign payload_rd_valid = (active_q && (src_q == SRC_FRAME)) ? s1_payload_rd_valid : s0_payload_rd_valid;
assign payload_rd_data = (active_q && (src_q == SRC_FRAME)) ? s1_payload_rd_data : s0_payload_rd_data;
assign s0_wide_payload_enable = active_q && (src_q == SRC_STREAM);
assign s1_wide_payload_enable = active_q && (src_q == SRC_FRAME);
assign s0_wide_payload_tready = s0_wide_payload_enable && wide_payload_tready;
assign s1_wide_payload_tready = s1_wide_payload_enable && wide_payload_tready;
assign wide_payload_tvalid = active_q &&
    ((src_q == SRC_FRAME) ? s1_wide_payload_tvalid : s0_wide_payload_tvalid);
assign wide_payload_tdata = (src_q == SRC_FRAME) ? s1_wide_payload_tdata : s0_wide_payload_tdata;
assign wide_payload_tkeep = (src_q == SRC_FRAME) ? s1_wide_payload_tkeep : s0_wide_payload_tkeep;
assign wide_payload_tlast = (src_q == SRC_FRAME) ? s1_wide_payload_tlast : s0_wide_payload_tlast;
assign active_is_frame = active_q && (src_q == SRC_FRAME);

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        active_q <= 1'b0;
        src_q <= SRC_STREAM;
    end else if (soft_reset) begin
        active_q <= 1'b0;
        src_q <= SRC_STREAM;
    end else begin
        if (!active_q && meta_take && meta_valid) begin
            active_q <= 1'b1;
            src_q <= choose_frame ? SRC_FRAME : SRC_STREAM;
        end else if (active_q && meta_pop) begin
            active_q <= 1'b0;
        end
    end
end

endmodule
