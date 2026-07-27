`timescale 1ns/1ps
`include "dma_defs.vh"

// Flow-only Target B wrapper for the A1 same-clock SRAM study.
// Inputs are already admitted frame metadata and payload; parsing, TX,
// AXI-Lite, CQ publication, and UFC are deliberately outside this target.
module dma_rx512_memory_subsystem_top #(
    parameter integer CHANNELS = 16,
    parameter integer FIXED_PAYLOAD_WORDS = 1024,
    parameter integer FIXED_PAYLOAD_AW = 10,
    parameter integer FIXED_META_DEPTH = 4,
    parameter integer FIXED_META_AW = 2,
    parameter integer SHARED_BLOCK_NUM = 64,
    parameter integer SHARED_BLOCK_AW = 6
)(
    input               clk,
    input               rstn,
    input               soft_reset,
    input               ch_reset_valid,
    input      [3:0]    ch_reset_ch,

    input               fixed_start_frame,
    input      [3:0]    fixed_ch,
    input      [3:0]    fixed_policy,
    input      [31:0]   fixed_payload_len,
    input      [31:0]   fixed_aligned_len,
    input      [31:0]   fixed_dst_addr,
    input      [31:0]   fixed_frame_seq,
    input               fixed_payload_tvalid,
    output              fixed_payload_tready,
    input      [511:0]  fixed_payload_tdata,
    output              fixed_collect_done,
    output              fixed_can_accept,
    output              fixed_near_full,
    output              fixed_full,

    input               shared_start_frame,
    input      [3:0]    shared_ch,
    input      [3:0]    shared_policy,
    input      [31:0]   shared_payload_len,
    input      [31:0]   shared_aligned_len,
    input      [31:0]   shared_dst_addr,
    input      [31:0]   shared_frame_seq,
    input               shared_payload_tvalid,
    output              shared_payload_tready,
    input      [511:0]  shared_payload_tdata,
    output              shared_collect_done,
    output              shared_can_accept,
    output              shared_near_full,
    output              shared_full,

    output     [31:0]   m_axi_awaddr,
    output     [7:0]    m_axi_awlen,
    output     [2:0]    m_axi_awsize,
    output     [1:0]    m_axi_awburst,
    output              m_axi_awvalid,
    input               m_axi_awready,
    output     [511:0]  m_axi_wdata,
    output     [63:0]   m_axi_wstrb,
    output              m_axi_wlast,
    output              m_axi_wvalid,
    input               m_axi_wready,
    input      [1:0]    m_axi_bresp,
    input               m_axi_bvalid,
    output              m_axi_bready,

    output              cpl_valid,
    input               cpl_ready,
    output              cpl_error,
    output     [3:0]    cpl_error_code,
    output     [3:0]    cpl_ch,
    output     [31:0]   cpl_dst_addr,
    output     [31:0]   cpl_payload_len,
    output     [31:0]   cpl_frame_seq,
    output              cpl_source_shared,

    output     [15:0]   shared_pool_free_count,
    output     [15:0]   shared_pool_alloc_count,
    output              shared_pool_overflow_sticky,
    output              shared_pool_leak_check_error,
    output              busy
);

localparam [1:0] CTRL_IDLE = 2'd0;
localparam [1:0] CTRL_CMD  = 2'd1;
localparam [1:0] CTRL_WAIT = 2'd2;

wire [CHANNELS*32-1:0] fixed_used_bytes;
wire [CHANNELS*32-1:0] fixed_meta_used;
wire fixed_meta_valid;
wire fixed_meta_pop;
wire [3:0] fixed_out_ch;
wire [3:0] fixed_out_tc;
wire [3:0] fixed_out_policy;
wire [15:0] fixed_out_flow_id;
wire [15:0] fixed_out_msg_id;
wire [31:0] fixed_out_payload_len;
wire [31:0] fixed_out_aligned_len;
wire [31:0] fixed_out_dst_addr;
wire [31:0] fixed_out_next_wr_ptr;
wire [31:0] fixed_out_frame_seq;
wire [63:0] fixed_out_timestamp;
wire [31:0] fixed_out_sample_count;
wire fixed_out_cpl_en;
wire fixed_out_ring;
wire fixed_out_wrap_before;
wire fixed_payload_rd_req;
wire [FIXED_PAYLOAD_AW-1:0] fixed_payload_rd_index;
wire fixed_payload_rd_valid;
wire [63:0] fixed_payload_rd_data;
wire fixed_wide_enable;
wire fixed_wide_tvalid;
wire fixed_wide_tready;
wire [511:0] fixed_wide_tdata;
wire [63:0] fixed_wide_tkeep;
wire fixed_wide_tlast;

dma_rx_fc_ingress_bank #(
    .CHANNELS(CHANNELS),
    .PAYLOAD_WORDS(FIXED_PAYLOAD_WORDS),
    .PAYLOAD_AW(FIXED_PAYLOAD_AW),
    .META_DEPTH(FIXED_META_DEPTH),
    .META_AW(FIXED_META_AW),
    .WIDE_READ_ENABLE(1)
) u_fixed_ingress (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .ch_reset_valid(ch_reset_valid),
    .ch_reset_ch(ch_reset_ch),
    .req_ch(fixed_ch),
    .req_aligned_len(fixed_aligned_len),
    .can_accept_frame(fixed_can_accept),
    .near_full(fixed_near_full),
    .full(fixed_full),
    .used_bytes_flat(fixed_used_bytes),
    .meta_used_flat(fixed_meta_used),
    .start_frame(fixed_start_frame),
    .in_ch(fixed_ch),
    .in_tc(4'h0),
    .in_policy(fixed_policy),
    .in_flow_id(16'h0),
    .in_msg_id(16'h0),
    .in_payload_len(fixed_payload_len),
    .in_aligned_len(fixed_aligned_len),
    .in_dst_addr(fixed_dst_addr),
    .in_next_wr_ptr(32'h0),
    .in_frame_seq(fixed_frame_seq),
    .in_timestamp(64'h0),
    .in_sample_count(32'h0),
    .in_cpl_en(1'b0),
    .in_ring(1'b0),
    .in_wrap_before(1'b0),
    .payload_tdata(fixed_payload_tdata),
    .payload_tvalid(fixed_payload_tvalid),
    .payload_tready(fixed_payload_tready),
    .collect_done(fixed_collect_done),
    .meta_valid(fixed_meta_valid),
    .meta_pop(fixed_meta_pop),
    .out_ch(fixed_out_ch),
    .out_tc(fixed_out_tc),
    .out_policy(fixed_out_policy),
    .out_flow_id(fixed_out_flow_id),
    .out_msg_id(fixed_out_msg_id),
    .out_payload_len(fixed_out_payload_len),
    .out_aligned_len(fixed_out_aligned_len),
    .out_dst_addr(fixed_out_dst_addr),
    .out_next_wr_ptr(fixed_out_next_wr_ptr),
    .out_frame_seq(fixed_out_frame_seq),
    .out_timestamp(fixed_out_timestamp),
    .out_sample_count(fixed_out_sample_count),
    .out_cpl_en(fixed_out_cpl_en),
    .out_ring(fixed_out_ring),
    .out_wrap_before(fixed_out_wrap_before),
    .payload_rd_req(fixed_payload_rd_req),
    .payload_rd_index(fixed_payload_rd_index),
    .payload_rd_valid(fixed_payload_rd_valid),
    .payload_rd_data(fixed_payload_rd_data),
    .wide_payload_enable(fixed_wide_enable),
    .wide_payload_tvalid(fixed_wide_tvalid),
    .wide_payload_tready(fixed_wide_tready),
    .wide_payload_tdata(fixed_wide_tdata),
    .wide_payload_tkeep(fixed_wide_tkeep),
    .wide_payload_tlast(fixed_wide_tlast)
);

wire [CHANNELS*32-1:0] shared_used_bytes;
wire [CHANNELS*32-1:0] shared_meta_used;
wire shared_meta_valid;
wire shared_meta_pop;
wire [3:0] shared_out_ch;
wire [3:0] shared_out_tc;
wire [3:0] shared_out_policy;
wire [15:0] shared_out_flow_id;
wire [15:0] shared_out_msg_id;
wire [31:0] shared_out_payload_len;
wire [31:0] shared_out_aligned_len;
wire [31:0] shared_out_dst_addr;
wire [31:0] shared_out_next_wr_ptr;
wire [31:0] shared_out_frame_seq;
wire [63:0] shared_out_timestamp;
wire [31:0] shared_out_sample_count;
wire shared_out_cpl_en;
wire shared_out_ring;
wire shared_out_wrap_before;
wire shared_payload_rd_req;
wire [FIXED_PAYLOAD_AW-1:0] shared_payload_rd_index;
wire shared_payload_rd_valid;
wire [63:0] shared_payload_rd_data;
wire shared_wide_enable;
wire shared_wide_tvalid;
wire shared_wide_tready;
wire [511:0] shared_wide_tdata;
wire [63:0] shared_wide_tkeep;
wire shared_wide_tlast;
wire [15:0] shared_pool_committed_count;
wire [15:0] shared_pool_dropped_count;
wire shared_adapter_busy;
wire shared_drop_event_valid;
wire [3:0] shared_drop_event_ch;

dma_rx_frame_shared_adapter #(
    .CH_NUM(CHANNELS),
    .CH_ID_W(4),
    .BLOCK_NUM(SHARED_BLOCK_NUM),
    .BLOCK_AW(SHARED_BLOCK_AW),
    .CTX_DEPTH(FIXED_META_DEPTH),
    .CTX_AW(FIXED_META_AW),
    .PAYLOAD_AW(FIXED_PAYLOAD_AW),
    .WIDE_READ_ENABLE(1)
) u_shared_ingress (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .ch_reset_valid(ch_reset_valid),
    .ch_reset_ch(ch_reset_ch),
    .req_ch(shared_ch),
    .req_policy(shared_policy),
    .req_aligned_len(shared_aligned_len),
    .can_accept_frame(shared_can_accept),
    .near_full(shared_near_full),
    .full(shared_full),
    .used_bytes_flat(shared_used_bytes),
    .meta_used_flat(shared_meta_used),
    .start_frame(shared_start_frame),
    .in_ch(shared_ch),
    .in_tc(4'h0),
    .in_policy(shared_policy),
    .in_flow_id(16'h0),
    .in_msg_id(16'h0),
    .in_payload_len(shared_payload_len),
    .in_aligned_len(shared_aligned_len),
    .in_dst_addr(shared_dst_addr),
    .in_next_wr_ptr(32'h0),
    .in_frame_seq(shared_frame_seq),
    .in_timestamp(64'h0),
    .in_sample_count(32'h0),
    .in_cpl_en(1'b0),
    .in_ring(1'b0),
    .in_wrap_before(1'b0),
    .payload_tdata(shared_payload_tdata),
    .payload_tvalid(shared_payload_tvalid),
    .payload_tready(shared_payload_tready),
    .collect_done(shared_collect_done),
    .meta_valid(shared_meta_valid),
    .meta_pop(shared_meta_pop),
    .out_ch(shared_out_ch),
    .out_tc(shared_out_tc),
    .out_policy(shared_out_policy),
    .out_flow_id(shared_out_flow_id),
    .out_msg_id(shared_out_msg_id),
    .out_payload_len(shared_out_payload_len),
    .out_aligned_len(shared_out_aligned_len),
    .out_dst_addr(shared_out_dst_addr),
    .out_next_wr_ptr(shared_out_next_wr_ptr),
    .out_frame_seq(shared_out_frame_seq),
    .out_timestamp(shared_out_timestamp),
    .out_sample_count(shared_out_sample_count),
    .out_cpl_en(shared_out_cpl_en),
    .out_ring(shared_out_ring),
    .out_wrap_before(shared_out_wrap_before),
    .payload_rd_req(shared_payload_rd_req),
    .payload_rd_index(shared_payload_rd_index),
    .payload_rd_valid(shared_payload_rd_valid),
    .payload_rd_data(shared_payload_rd_data),
    .wide_payload_enable(shared_wide_enable),
    .wide_payload_tvalid(shared_wide_tvalid),
    .wide_payload_tready(shared_wide_tready),
    .wide_payload_tdata(shared_wide_tdata),
    .wide_payload_tkeep(shared_wide_tkeep),
    .wide_payload_tlast(shared_wide_tlast),
    .pool_free_count(shared_pool_free_count),
    .pool_alloc_count(shared_pool_alloc_count),
    .pool_committed_frame_count(shared_pool_committed_count),
    .pool_dropped_frame_count(shared_pool_dropped_count),
    .pool_overflow_sticky(shared_pool_overflow_sticky),
    .pool_leak_check_error(shared_pool_leak_check_error),
    .busy(shared_adapter_busy),
    .drop_event_valid(shared_drop_event_valid),
    .drop_event_ch(shared_drop_event_ch)
);

wire queue_meta_valid;
wire queue_meta_take;
wire queue_meta_pop;
wire [3:0] queue_ch;
wire [3:0] queue_tc;
wire [3:0] queue_policy;
wire [15:0] queue_flow_id;
wire [15:0] queue_msg_id;
wire [31:0] queue_payload_len;
wire [31:0] queue_aligned_len;
wire [31:0] queue_dst_addr;
wire [31:0] queue_next_wr_ptr;
wire [31:0] queue_frame_seq;
wire [63:0] queue_timestamp;
wire [31:0] queue_sample_count;
wire queue_cpl_en;
wire queue_ring;
wire queue_wrap_before;
wire queue_payload_rd_valid;
wire [63:0] queue_payload_rd_data;
wire queue_wide_tvalid;
wire queue_wide_tready;
wire [511:0] queue_wide_tdata;
wire [63:0] queue_wide_tkeep;
wire queue_wide_tlast;
wire queue_active_is_frame;

dma_rx_ingress_source_selector #(
    .PAYLOAD_AW(FIXED_PAYLOAD_AW)
) u_source_selector (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .meta_take(queue_meta_take),
    .meta_pop(queue_meta_pop),
    .s0_meta_valid(fixed_meta_valid),
    .s0_meta_pop(fixed_meta_pop),
    .s0_ch(fixed_out_ch),
    .s0_tc(fixed_out_tc),
    .s0_policy(fixed_out_policy),
    .s0_flow_id(fixed_out_flow_id),
    .s0_msg_id(fixed_out_msg_id),
    .s0_payload_len(fixed_out_payload_len),
    .s0_aligned_len(fixed_out_aligned_len),
    .s0_dst_addr(fixed_out_dst_addr),
    .s0_next_wr_ptr(fixed_out_next_wr_ptr),
    .s0_frame_seq(fixed_out_frame_seq),
    .s0_timestamp(fixed_out_timestamp),
    .s0_sample_count(fixed_out_sample_count),
    .s0_cpl_en(fixed_out_cpl_en),
    .s0_ring(fixed_out_ring),
    .s0_wrap_before(fixed_out_wrap_before),
    .s0_payload_rd_req(fixed_payload_rd_req),
    .s0_payload_rd_index(fixed_payload_rd_index),
    .s0_payload_rd_valid(fixed_payload_rd_valid),
    .s0_payload_rd_data(fixed_payload_rd_data),
    .s0_wide_payload_enable(fixed_wide_enable),
    .s0_wide_payload_tvalid(fixed_wide_tvalid),
    .s0_wide_payload_tready(fixed_wide_tready),
    .s0_wide_payload_tdata(fixed_wide_tdata),
    .s0_wide_payload_tkeep(fixed_wide_tkeep),
    .s0_wide_payload_tlast(fixed_wide_tlast),
    .s1_meta_valid(shared_meta_valid),
    .s1_meta_pop(shared_meta_pop),
    .s1_ch(shared_out_ch),
    .s1_tc(shared_out_tc),
    .s1_policy(shared_out_policy),
    .s1_flow_id(shared_out_flow_id),
    .s1_msg_id(shared_out_msg_id),
    .s1_payload_len(shared_out_payload_len),
    .s1_aligned_len(shared_out_aligned_len),
    .s1_dst_addr(shared_out_dst_addr),
    .s1_next_wr_ptr(shared_out_next_wr_ptr),
    .s1_frame_seq(shared_out_frame_seq),
    .s1_timestamp(shared_out_timestamp),
    .s1_sample_count(shared_out_sample_count),
    .s1_cpl_en(shared_out_cpl_en),
    .s1_ring(shared_out_ring),
    .s1_wrap_before(shared_out_wrap_before),
    .s1_payload_rd_req(shared_payload_rd_req),
    .s1_payload_rd_index(shared_payload_rd_index),
    .s1_payload_rd_valid(shared_payload_rd_valid),
    .s1_payload_rd_data(shared_payload_rd_data),
    .s1_wide_payload_enable(shared_wide_enable),
    .s1_wide_payload_tvalid(shared_wide_tvalid),
    .s1_wide_payload_tready(shared_wide_tready),
    .s1_wide_payload_tdata(shared_wide_tdata),
    .s1_wide_payload_tkeep(shared_wide_tkeep),
    .s1_wide_payload_tlast(shared_wide_tlast),
    .meta_valid(queue_meta_valid),
    .out_ch(queue_ch),
    .out_tc(queue_tc),
    .out_policy(queue_policy),
    .out_flow_id(queue_flow_id),
    .out_msg_id(queue_msg_id),
    .out_payload_len(queue_payload_len),
    .out_aligned_len(queue_aligned_len),
    .out_dst_addr(queue_dst_addr),
    .out_next_wr_ptr(queue_next_wr_ptr),
    .out_frame_seq(queue_frame_seq),
    .out_timestamp(queue_timestamp),
    .out_sample_count(queue_sample_count),
    .out_cpl_en(queue_cpl_en),
    .out_ring(queue_ring),
    .out_wrap_before(queue_wrap_before),
    .payload_rd_req(1'b0),
    .payload_rd_index({FIXED_PAYLOAD_AW{1'b0}}),
    .payload_rd_valid(queue_payload_rd_valid),
    .payload_rd_data(queue_payload_rd_data),
    .wide_payload_tvalid(queue_wide_tvalid),
    .wide_payload_tready(queue_wide_tready),
    .wide_payload_tdata(queue_wide_tdata),
    .wide_payload_tkeep(queue_wide_tkeep),
    .wide_payload_tlast(queue_wide_tlast),
    .active_is_frame(queue_active_is_frame)
);

reg [1:0] ctrl_state_q;
reg [3:0] active_ch_q;
reg [31:0] active_dst_addr_q;
reg [31:0] active_payload_len_q;
reg [31:0] active_frame_seq_q;
reg active_source_shared_q;

wire writer_cmd_valid = (ctrl_state_q == CTRL_CMD);
wire writer_cmd_ready;
wire writer_cmd_fire = writer_cmd_valid && writer_cmd_ready;
wire writer_cpl_valid;
wire writer_cpl_ready = (ctrl_state_q == CTRL_WAIT) && cpl_ready;
wire writer_cpl_error;
wire [3:0] writer_cpl_error_code;
wire writer_busy;
wire cpl_fire = cpl_valid && cpl_ready;

assign queue_meta_take = (ctrl_state_q == CTRL_IDLE) && queue_meta_valid;
assign queue_meta_pop = cpl_fire;
assign cpl_valid = (ctrl_state_q == CTRL_WAIT) && writer_cpl_valid;
assign cpl_error = writer_cpl_error;
assign cpl_error_code = writer_cpl_error_code;
assign cpl_ch = active_ch_q;
assign cpl_dst_addr = active_dst_addr_q;
assign cpl_payload_len = active_payload_len_q;
assign cpl_frame_seq = active_frame_seq_q;
assign cpl_source_shared = active_source_shared_q;
assign busy = (ctrl_state_q != CTRL_IDLE) || writer_busy ||
              fixed_meta_valid || shared_adapter_busy;

dma_rx512_writer_route_top u_writer_target (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .cmd_valid(writer_cmd_valid),
    .cmd_ready(writer_cmd_ready),
    .cmd_addr(active_dst_addr_q),
    .cmd_len(active_payload_len_q),
    .s_payload_tvalid(queue_wide_tvalid),
    .s_payload_tready(queue_wide_tready),
    .s_payload_tdata(queue_wide_tdata),
    .s_payload_tkeep(queue_wide_tkeep),
    .s_payload_tlast(queue_wide_tlast),
    .s_payload_level(8'h0),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .cpl_valid(writer_cpl_valid),
    .cpl_ready(writer_cpl_ready),
    .cpl_error(writer_cpl_error),
    .cpl_error_code(writer_cpl_error_code),
    .busy(writer_busy)
);

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ctrl_state_q <= CTRL_IDLE;
        active_ch_q <= 4'h0;
        active_dst_addr_q <= 32'h0;
        active_payload_len_q <= 32'h0;
        active_frame_seq_q <= 32'h0;
        active_source_shared_q <= 1'b0;
    end else if (soft_reset) begin
        ctrl_state_q <= CTRL_IDLE;
        active_ch_q <= 4'h0;
        active_dst_addr_q <= 32'h0;
        active_payload_len_q <= 32'h0;
        active_frame_seq_q <= 32'h0;
        active_source_shared_q <= 1'b0;
    end else begin
        case (ctrl_state_q)
        CTRL_IDLE: begin
            if (queue_meta_take) begin
                active_ch_q <= queue_ch;
                active_dst_addr_q <= queue_dst_addr;
                active_payload_len_q <= queue_payload_len;
                active_frame_seq_q <= queue_frame_seq;
                // Source 0 has priority when both metadata queues are valid.
                active_source_shared_q <= !fixed_meta_valid && shared_meta_valid;
                ctrl_state_q <= CTRL_CMD;
            end
        end
        CTRL_CMD: begin
            if (writer_cmd_fire)
                ctrl_state_q <= CTRL_WAIT;
        end
        CTRL_WAIT: begin
            // Metadata ownership is released only with accepted completion.
            if (cpl_fire)
                ctrl_state_q <= CTRL_IDLE;
        end
        default: ctrl_state_q <= CTRL_IDLE;
        endcase
    end
end

endmodule
