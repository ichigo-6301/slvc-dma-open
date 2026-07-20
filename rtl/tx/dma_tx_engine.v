`timescale 1ns/1ps
`include "dma_defs.vh"

// TX 主状态机，支持 single-shot 与 descriptor-driven 两类发送入口。
// 它先锁存 channel/descriptor context，再检查 CQ 空间，输出 SHDR64 后消费预取
// payload；AXI 读错误、下游 backpressure 和 CQ 提交都必须经过显式状态才能结束一帧。
module dma_tx_engine #(
    parameter integer TX_RD_MAX_OUTSTANDING = `DMA_TX_RD_MAX_OUTSTANDING
)(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             quiesce,
    input             global_enable,
    input             tx_enable,
    input      [`DMA_MAX_CH*32-1:0] tx_ctrl_flat,
    input      [`DMA_MAX_CH*32-1:0] tx_cfg_flat,
    input      [`DMA_MAX_CH*32-1:0] tx_base_l_flat,
    input      [`DMA_MAX_CH*32-1:0] tx_base_h_flat,
    input      [`DMA_MAX_CH*32-1:0] tx_len_flat,
    input      [`DMA_MAX_CH-1:0] tx_desc_enable_flat,
    input      [`DMA_MAX_CH-1:0] tx_desc_ready_flat,
    output reg        tx_desc_ctx_req,
    output reg [3:0]  tx_desc_ctx_ch,
    input             tx_desc_ctx_valid,
    input      [31:0] tx_desc_ctx_ctrl,
    input      [31:0] tx_desc_ctx_base_l,
    input      [31:0] tx_desc_ctx_base_h,
    input      [31:0] tx_desc_ctx_size,
    input      [31:0] tx_desc_ctx_rd_ptr,
    input      [31:0] tx_desc_ctx_wr_ptr,
    input      [31:0] tx_desc_ctx_status,
    input      [31:0] tx_desc_ctx_err_cnt,
    output            tx_desc_active_valid,
    output     [3:0]  tx_desc_active_ch,
    input             tx_desc_active_stop,
    input      [31:0] cq_size,
    input      [31:0] cq_wr_ptr,
    input      [31:0] cq_rd_ptr,
    input      [31:0] cq_reserved_count,
    output reg        cq_reserve_inc,
    output            busy,
    output            drain_idle,
    output reg [`DMA_MAX_CH-1:0] tx_ch_busy_flat,
    output reg        event_valid,
    output reg [3:0]  event_ch,
    output reg [7:0]  event_status_code,
    output reg        event_inc_frame,
    output reg        event_inc_err,
    output reg        event_clear_start,
    output reg        event_clear_stop,
    output reg        tx_desc_evt_valid,
    output reg [3:0]  tx_desc_evt_ch,
    output reg [31:0] tx_desc_evt_rd_ptr,
    output reg        tx_desc_evt_update_rd_ptr,
    output reg [7:0]  tx_desc_evt_status_code,
    output reg        tx_desc_evt_update_status,
    output reg        tx_desc_evt_inc_err,
    output reg        tx_desc_evt_clear_busy,
    output reg        tx_desc_evt_set_busy,
    output reg        cqe_req_valid,
    input             cqe_req_ready,
    output reg [3:0]  cqe_ch,
    output reg [3:0]  cqe_tc,
    output reg [3:0]  cqe_policy,
    output reg [15:0] cqe_flow_id,
    output reg [15:0] cqe_msg_id,
    output reg [31:0] cqe_addr,
    output reg [31:0] cqe_len,
    output reg [31:0] cqe_aligned_len,
    output reg [31:0] cqe_frame_seq,
    output reg [7:0]  cqe_status_code,
    output reg [15:0] cqe_flags,
    output     [31:0] m_axi_araddr,
    output     [7:0]  m_axi_arlen,
    output     [2:0]  m_axi_arsize,
    output     [1:0]  m_axi_arburst,
    output            m_axi_arvalid,
    input             m_axi_arready,
    input      [63:0] m_axi_rdata,
    input      [1:0]  m_axi_rresp,
    input             m_axi_rlast,
    input             m_axi_rvalid,
    output            m_axi_rready,
    output reg [511:0] tx_axis_tdata,
    output reg         tx_axis_tvalid,
    input              tx_axis_tready
);

// descriptor fetch/parse/context capture 与普通 payload replay 共用后半段状态，
// 但 descriptor ownership 只有在提交边界才推进。
localparam ST_IDLE        = 4'd0;
localparam ST_DESC_SETUP  = 4'd1;
localparam ST_START_SETUP = 4'd2;
localparam ST_HEADER      = 4'd3;
localparam ST_AR          = 4'd4;
localparam ST_RDATA       = 4'd5;
localparam ST_SEND_PAY    = 4'd6;
localparam ST_CQE_REQ     = 4'd7;
localparam ST_DONE        = 4'd8;
localparam ST_DESC_AR     = 4'd9;
localparam ST_DESC_READ   = 4'd10;
localparam ST_DESC_PARSE  = 4'd11;
localparam ST_DESC_HOLD   = 4'd12;
localparam ST_DESC_CTX    = 4'd13;
localparam ST_CQ_CHECK_USED  = 4'd14;
localparam ST_CQ_CHECK_SPACE = 4'd15;

reg [3:0] state;
reg [3:0] active_ch;
reg [3:0] active_tc;
reg [3:0] active_policy;
reg [15:0] active_tag;
reg [31:0] active_addr;
reg [31:0] active_len;
reg [31:0] active_len_limit_q;
reg [31:0] active_aligned_len;
reg [31:0] frame_seq_counter;
reg [31:0] active_frame_seq;
reg [63:0] active_timestamp;
reg [31:0] active_sample_count;
reg [31:0] remaining_bytes;
reg [31:0] rd_addr;
reg [3:0]  words_needed;
reg [3:0]  words_seen;
reg [511:0] payload_buf;
reg [511:0] desc_buf;
reg [31:0] active_desc_rd_ptr;
reg [31:0] active_desc_next_rd_ptr;
reg [31:0] active_desc_ctrl;
reg [31:0] active_desc_base_l;
reg [31:0] active_desc_base_h;
reg [31:0] active_desc_size;
reg [31:0] active_desc_wr_ptr;
reg desc_mode;
reg [7:0] final_status;
reg cpl_en;
reg irq_en;
reg                 tx_sched_req_valid_q;
reg [`DMA_TX_CH_NUM-1:0] tx_sched_start_req_vec_q;
reg [`DMA_TX_CH_NUM-1:0] tx_sched_desc_req_vec_q;
reg                 tx_sched_grant_valid_q;
reg                 tx_sched_grant_is_desc_q;
reg [3:0]           tx_sched_grant_ch_q;
reg                 tx_sched_meta_valid_q;
reg                 tx_sched_meta_is_desc_q;
reg [3:0]           tx_sched_meta_ch_q;
reg [31:0]          tx_sched_meta_ctrl_q;
reg [31:0]          tx_sched_meta_cfg_q;
reg [31:0]          tx_sched_meta_base_l_q;
reg [31:0]          tx_sched_meta_len_q;
reg [`DMA_TX_CH_NUM-1:0] tx_sched_start_req_vec_c;
reg [`DMA_TX_CH_NUM-1:0] tx_sched_desc_req_vec_c;
reg                 tx_sched_req_any_c;
reg                 tx_sched_grant_valid_c;
reg                 tx_sched_grant_is_desc_c;
reg [3:0]           tx_sched_grant_ch_c;
integer sched_req_i;
integer sched_grant_i;

reg [31:0] desc_araddr;
reg [7:0]  desc_arlen;
reg        desc_arvalid;
reg        desc_rready;
reg        pf_cmd_valid;
wire       pf_cmd_ready;
wire       pf_cmd_done;
wire       pf_cmd_error;
wire [31:0] pf_araddr;
wire [7:0]  pf_arlen;
wire        pf_arvalid;
wire        pf_rready;
wire [511:0] pf_out_data;
wire        pf_out_valid;
wire        pf_out_ready;
wire        pf_out_last;
wire [7:0]  pf_debug_outstanding;
wire [7:0]  pf_debug_peak_outstanding;
wire [7:0]  pf_debug_fifo_level;
reg         payload_last_loaded;
reg         payload_error_done;
reg         cq_check_from_desc_q;
reg [31:0]  cq_check_size_q;
reg [31:0]  cq_check_wr_ptr_q;
reg [31:0]  cq_check_rd_ptr_q;
reg [31:0]  cq_check_reserved_q;
reg [31:0]  cq_used_entries_q;
reg         cq_size_nonzero_q;
reg         cq_space_ok_q;
reg         cq_check_consume_q;
reg         cq_check_capture_pending_q;
reg [1:0]   desc_stop_wait_q;
reg         desc_evt_publish_q;

function [31:0] flat_word;
    input [`DMA_MAX_CH*32-1:0] bus;
    input [3:0] ch;
    begin
        flat_word = bus[ch*32 +: 32];
    end
endfunction

wire [31:0] active_ctrl = flat_word(tx_ctrl_flat, active_ch);
wire [511:0] header_beat;
wire [`DMA_MAX_CH-1:0] active_ch_onehot = ({{(`DMA_MAX_CH-1){1'b0}}, 1'b1} << active_ch);
wire tx_sched_idle = !tx_sched_req_valid_q && !tx_sched_grant_valid_q && !tx_sched_meta_valid_q;

assign m_axi_arsize = 3'd3;
assign m_axi_arburst = 2'b01;
assign busy = (state != ST_IDLE);
assign drain_idle = (state == ST_IDLE) && tx_sched_idle;
assign m_axi_araddr = ((state == ST_DESC_AR) || (state == ST_DESC_READ)) ? desc_araddr : pf_araddr;
assign m_axi_arlen = ((state == ST_DESC_AR) || (state == ST_DESC_READ)) ? desc_arlen : pf_arlen;
assign m_axi_arvalid = ((state == ST_DESC_AR) || (state == ST_DESC_READ)) ? desc_arvalid : pf_arvalid;
assign m_axi_rready = ((state == ST_DESC_AR) || (state == ST_DESC_READ)) ? desc_rready : pf_rready;
assign pf_out_ready = (state == ST_SEND_PAY) && !payload_last_loaded &&
                      (!tx_axis_tvalid || tx_axis_tready);
assign tx_desc_active_valid = desc_mode && (state != ST_IDLE);
assign tx_desc_active_ch = active_ch;

dma_tx_header_builder u_header(
    .traffic_class(active_tc),
    .tag_id(active_tag),
    .payload_len(active_len),
    .frame_seq(active_frame_seq),
    .timestamp(active_timestamp),
    .sample_count(active_sample_count),
    .header_beat(header_beat)
);

dma_axi_read_prefetch #(
    .DATA_WIDTH(64),
    .OUT_WIDTH(512),
    .MAX_OUTSTANDING(TX_RD_MAX_OUTSTANDING),
    .FIFO_DEPTH_LOG2(4)
) u_read_prefetch (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .cmd_valid(pf_cmd_valid),
    .cmd_ready(pf_cmd_ready),
    .cmd_addr(active_addr),
    .cmd_len_bytes(active_len),
    .cmd_done(pf_cmd_done),
    .cmd_error(pf_cmd_error),
    .m_axi_araddr(pf_araddr),
    .m_axi_arlen(pf_arlen),
    .m_axi_arsize(),
    .m_axi_arburst(),
    .m_axi_arvalid(pf_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(pf_rready),
    .out_data(pf_out_data),
    .out_valid(pf_out_valid),
    .out_ready(pf_out_ready),
    .out_last(pf_out_last),
    .debug_outstanding_count(pf_debug_outstanding),
    .debug_peak_outstanding(pf_debug_peak_outstanding),
    .debug_fifo_level(pf_debug_fifo_level)
);

always @(*) begin
    tx_sched_start_req_vec_c = {`DMA_TX_CH_NUM{1'b0}};
    tx_sched_desc_req_vec_c = {`DMA_TX_CH_NUM{1'b0}};
    tx_sched_req_any_c = 1'b0;
    for (sched_req_i = 0; sched_req_i < `DMA_TX_CH_NUM; sched_req_i = sched_req_i + 1) begin
        tx_sched_desc_req_vec_c[sched_req_i] =
            !quiesce && global_enable && tx_enable && tx_desc_ready_flat[sched_req_i];
        tx_sched_start_req_vec_c[sched_req_i] =
            !quiesce && global_enable && tx_enable &&
            tx_ctrl_flat[(sched_req_i*32) + `DMA_TX_CTRL_ENABLE] &&
            tx_ctrl_flat[(sched_req_i*32) + `DMA_TX_CTRL_START] &&
            !tx_desc_enable_flat[sched_req_i];
        if (tx_sched_desc_req_vec_c[sched_req_i] || tx_sched_start_req_vec_c[sched_req_i])
            tx_sched_req_any_c = 1'b1;
    end
end

always @(*) begin
    tx_sched_grant_valid_c = 1'b0;
    tx_sched_grant_is_desc_c = 1'b0;
    tx_sched_grant_ch_c = 4'h0;

    for (sched_grant_i = 0; sched_grant_i < `DMA_TX_CH_NUM; sched_grant_i = sched_grant_i + 1) begin
        if (!tx_sched_grant_valid_c && tx_sched_desc_req_vec_q[sched_grant_i]) begin
            tx_sched_grant_valid_c = 1'b1;
            tx_sched_grant_is_desc_c = 1'b1;
            tx_sched_grant_ch_c = sched_grant_i[3:0];
        end
    end

    if (!tx_sched_grant_valid_c) begin
        for (sched_grant_i = 0; sched_grant_i < `DMA_TX_CH_NUM; sched_grant_i = sched_grant_i + 1) begin
            if (!tx_sched_grant_valid_c && tx_sched_start_req_vec_q[sched_grant_i]) begin
                tx_sched_grant_valid_c = 1'b1;
                tx_sched_grant_is_desc_c = 1'b0;
                tx_sched_grant_ch_c = sched_grant_i[3:0];
            end
        end
    end
end

task post_event;
    input [7:0] code;
    input inc_frame;
    input inc_err;
    input clr_start;
    input clr_stop;
    begin
        post_event_ch(active_ch, code, inc_frame, inc_err, clr_start, clr_stop);
    end
endtask

task post_event_ch;
    input [3:0] ch;
    input [7:0] code;
    input inc_frame;
    input inc_err;
    input clr_start;
    input clr_stop;
    begin
        event_valid <= 1'b1;
        event_ch <= ch;
        event_status_code <= code;
        event_inc_frame <= inc_frame;
        event_inc_err <= inc_err;
        event_clear_start <= clr_start;
        event_clear_stop <= clr_stop;
    end
endtask

task post_desc_event;
    input [7:0] code;
    input [31:0] next_rd_ptr;
    input inc_err;
    begin
        tx_desc_evt_valid <= 1'b1;
        tx_desc_evt_ch <= active_ch;
        tx_desc_evt_rd_ptr <= next_rd_ptr;
        tx_desc_evt_update_rd_ptr <= 1'b1;
        tx_desc_evt_status_code <= code;
        tx_desc_evt_update_status <= 1'b1;
        tx_desc_evt_inc_err <= inc_err;
        tx_desc_evt_clear_busy <= 1'b1;
        tx_desc_evt_set_busy <= 1'b0;
    end
endtask

task start_cq_check;
    input from_desc;
    begin
        cq_check_from_desc_q <= from_desc;
        cq_check_capture_pending_q <= 1'b1;
    end
endtask

function [3:0] calc_words;
    input [31:0] bytes;
    begin
        if (bytes >= 32'd64)
            calc_words = 4'd8;
        else
            calc_words = (bytes[5:0] + 7) >> 3;
    end
endfunction

function [7:0] calc_arlen;
    input [31:0] addr;
    input [31:0] bytes;
    reg [31:0] beats;
    reg [31:0] beats_to_4k;
    begin
        beats = (bytes + 7) >> 3;
        if (beats > 8)
            beats = 8;
        beats_to_4k = (32'd4096 - addr[11:0]) >> 3;
        if (beats_to_4k == 0)
            beats_to_4k = 1;
        if (beats > beats_to_4k)
            beats = beats_to_4k;
        calc_arlen = beats[7:0] - 1'b1;
    end
endfunction

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state <= ST_IDLE;
        active_ch <= 4'h0;
        active_tc <= 4'h0;
        active_policy <= 4'h0;
        active_tag <= 16'h0;
        active_addr <= 32'h0;
        active_len <= 32'h0;
        active_aligned_len <= 32'h0;
        frame_seq_counter <= 32'h0;
        active_frame_seq <= 32'h0;
        active_timestamp <= 64'h0;
        active_sample_count <= 32'h0;
        remaining_bytes <= 32'h0;
        rd_addr <= 32'h0;
        words_needed <= 4'h0;
        words_seen <= 4'h0;
        payload_buf <= 512'h0;
        desc_buf <= 512'h0;
        active_desc_rd_ptr <= 32'h0;
        active_desc_next_rd_ptr <= 32'h0;
        active_desc_ctrl <= 32'h0;
        active_desc_base_l <= 32'h0;
        active_desc_base_h <= 32'h0;
        active_desc_size <= 32'h0;
        active_desc_wr_ptr <= 32'h0;
        desc_mode <= 1'b0;
        final_status <= `DMA_ST_OK;
        cpl_en <= 1'b0;
        irq_en <= 1'b0;
        tx_sched_req_valid_q <= 1'b0;
        tx_sched_start_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
        tx_sched_desc_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
        tx_sched_grant_valid_q <= 1'b0;
        tx_sched_grant_is_desc_q <= 1'b0;
        tx_sched_grant_ch_q <= 4'h0;
        tx_sched_meta_valid_q <= 1'b0;
        tx_sched_meta_is_desc_q <= 1'b0;
        tx_sched_meta_ch_q <= 4'h0;
        tx_sched_meta_ctrl_q <= 32'h0;
        tx_sched_meta_cfg_q <= 32'h0;
        tx_sched_meta_base_l_q <= 32'h0;
        tx_sched_meta_len_q <= 32'h0;
        cq_check_from_desc_q <= 1'b0;
        cq_check_size_q <= 32'h0;
        cq_check_wr_ptr_q <= 32'h0;
        cq_check_rd_ptr_q <= 32'h0;
        cq_check_reserved_q <= 32'h0;
        cq_used_entries_q <= 32'h0;
        cq_size_nonzero_q <= 1'b0;
        cq_space_ok_q <= 1'b0;
        cq_check_consume_q <= 1'b0;
        cq_check_capture_pending_q <= 1'b0;
        desc_stop_wait_q <= 2'd0;
        desc_evt_publish_q <= 1'b0;
        cq_reserve_inc <= 1'b0;
        tx_ch_busy_flat <= {`DMA_MAX_CH{1'b0}};
        event_valid <= 1'b0;
        event_ch <= 4'h0;
        event_status_code <= 8'h0;
        event_inc_frame <= 1'b0;
        event_inc_err <= 1'b0;
        event_clear_start <= 1'b0;
        event_clear_stop <= 1'b0;
        tx_desc_ctx_req <= 1'b0;
        tx_desc_ctx_ch <= 4'h0;
        tx_desc_evt_valid <= 1'b0;
        tx_desc_evt_ch <= 4'h0;
        tx_desc_evt_rd_ptr <= 32'h0;
        tx_desc_evt_update_rd_ptr <= 1'b0;
        tx_desc_evt_status_code <= 8'h0;
        tx_desc_evt_update_status <= 1'b0;
        tx_desc_evt_inc_err <= 1'b0;
        tx_desc_evt_clear_busy <= 1'b0;
        tx_desc_evt_set_busy <= 1'b0;
        cqe_req_valid <= 1'b0;
        cqe_ch <= 4'h0;
        cqe_tc <= 4'h0;
        cqe_policy <= 4'h0;
        cqe_flow_id <= 16'h0;
        cqe_msg_id <= 16'h0;
        cqe_addr <= 32'h0;
        cqe_len <= 32'h0;
        cqe_aligned_len <= 32'h0;
        cqe_frame_seq <= 32'h0;
        cqe_status_code <= 8'h0;
        cqe_flags <= 16'h0;
        desc_araddr <= 32'h0;
        desc_arlen <= 8'h0;
        desc_arvalid <= 1'b0;
        desc_rready <= 1'b0;
        pf_cmd_valid <= 1'b0;
        payload_last_loaded <= 1'b0;
        payload_error_done <= 1'b0;
        tx_axis_tdata <= 512'h0;
        tx_axis_tvalid <= 1'b0;
    end else if (soft_reset) begin
        state <= ST_IDLE;
        active_ch <= 4'h0;
        active_tc <= 4'h0;
        active_policy <= 4'h0;
        active_tag <= 16'h0;
        active_addr <= 32'h0;
        active_len <= 32'h0;
        active_aligned_len <= 32'h0;
        frame_seq_counter <= 32'h0;
        active_frame_seq <= 32'h0;
        active_timestamp <= 64'h0;
        active_sample_count <= 32'h0;
        remaining_bytes <= 32'h0;
        rd_addr <= 32'h0;
        words_needed <= 4'h0;
        words_seen <= 4'h0;
        payload_buf <= 512'h0;
        desc_buf <= 512'h0;
        active_desc_rd_ptr <= 32'h0;
        active_desc_next_rd_ptr <= 32'h0;
        active_desc_ctrl <= 32'h0;
        active_desc_base_l <= 32'h0;
        active_desc_base_h <= 32'h0;
        active_desc_size <= 32'h0;
        active_desc_wr_ptr <= 32'h0;
        desc_mode <= 1'b0;
        final_status <= `DMA_ST_OK;
        cpl_en <= 1'b0;
        irq_en <= 1'b0;
        tx_sched_req_valid_q <= 1'b0;
        tx_sched_start_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
        tx_sched_desc_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
        tx_sched_grant_valid_q <= 1'b0;
        tx_sched_grant_is_desc_q <= 1'b0;
        tx_sched_grant_ch_q <= 4'h0;
        tx_sched_meta_valid_q <= 1'b0;
        tx_sched_meta_is_desc_q <= 1'b0;
        tx_sched_meta_ch_q <= 4'h0;
        tx_sched_meta_ctrl_q <= 32'h0;
        tx_sched_meta_cfg_q <= 32'h0;
        tx_sched_meta_base_l_q <= 32'h0;
        tx_sched_meta_len_q <= 32'h0;
        cq_check_from_desc_q <= 1'b0;
        cq_check_size_q <= 32'h0;
        cq_check_wr_ptr_q <= 32'h0;
        cq_check_rd_ptr_q <= 32'h0;
        cq_check_reserved_q <= 32'h0;
        cq_used_entries_q <= 32'h0;
        cq_size_nonzero_q <= 1'b0;
        cq_space_ok_q <= 1'b0;
        cq_check_consume_q <= 1'b0;
        cq_check_capture_pending_q <= 1'b0;
        desc_stop_wait_q <= 2'd0;
        desc_evt_publish_q <= 1'b0;
        cq_reserve_inc <= 1'b0;
        tx_ch_busy_flat <= {`DMA_MAX_CH{1'b0}};
        event_valid <= 1'b0;
        event_ch <= 4'h0;
        event_status_code <= 8'h0;
        event_inc_frame <= 1'b0;
        event_inc_err <= 1'b0;
        event_clear_start <= 1'b0;
        event_clear_stop <= 1'b0;
        tx_desc_ctx_req <= 1'b0;
        tx_desc_ctx_ch <= 4'h0;
        tx_desc_evt_valid <= 1'b0;
        tx_desc_evt_ch <= 4'h0;
        tx_desc_evt_rd_ptr <= 32'h0;
        tx_desc_evt_update_rd_ptr <= 1'b0;
        tx_desc_evt_status_code <= 8'h0;
        tx_desc_evt_update_status <= 1'b0;
        tx_desc_evt_inc_err <= 1'b0;
        tx_desc_evt_clear_busy <= 1'b0;
        tx_desc_evt_set_busy <= 1'b0;
        cqe_req_valid <= 1'b0;
        cqe_ch <= 4'h0;
        cqe_tc <= 4'h0;
        cqe_policy <= 4'h0;
        cqe_flow_id <= 16'h0;
        cqe_msg_id <= 16'h0;
        cqe_addr <= 32'h0;
        cqe_len <= 32'h0;
        cqe_aligned_len <= 32'h0;
        cqe_frame_seq <= 32'h0;
        cqe_status_code <= 8'h0;
        cqe_flags <= 16'h0;
        desc_araddr <= 32'h0;
        desc_arlen <= 8'h0;
        desc_arvalid <= 1'b0;
        desc_rready <= 1'b0;
        pf_cmd_valid <= 1'b0;
        payload_last_loaded <= 1'b0;
        payload_error_done <= 1'b0;
        tx_axis_tdata <= 512'h0;
        tx_axis_tvalid <= 1'b0;
    end else begin
        tx_ch_busy_flat <= busy ? active_ch_onehot : {`DMA_MAX_CH{1'b0}};
        cq_reserve_inc <= 1'b0;
        event_valid <= 1'b0;
        event_inc_frame <= 1'b0;
        event_inc_err <= 1'b0;
        event_clear_start <= 1'b0;
        event_clear_stop <= 1'b0;
        tx_desc_ctx_req <= 1'b0;
        tx_desc_evt_valid <= 1'b0;
        tx_desc_evt_update_rd_ptr <= 1'b0;
        tx_desc_evt_update_status <= 1'b0;
        tx_desc_evt_inc_err <= 1'b0;
        tx_desc_evt_clear_busy <= 1'b0;
        tx_desc_evt_set_busy <= 1'b0;
        if (state != ST_IDLE) begin
            tx_sched_req_valid_q <= 1'b0;
            tx_sched_grant_valid_q <= 1'b0;
            tx_sched_meta_valid_q <= 1'b0;
        end

        if (cq_check_capture_pending_q) begin
            cq_check_capture_pending_q <= 1'b0;
            cq_check_size_q <= cq_size;
            cq_check_wr_ptr_q <= cq_wr_ptr;
            cq_check_rd_ptr_q <= cq_rd_ptr;
            cq_check_reserved_q <= cq_reserved_count;
            cq_used_entries_q <= 32'h0;
            cq_size_nonzero_q <= 1'b0;
            cq_space_ok_q <= 1'b0;
            cq_check_consume_q <= 1'b0;
            state <= ST_CQ_CHECK_USED;
        end else case (state)
        ST_IDLE: begin
            tx_axis_tvalid <= 1'b0;
            desc_arvalid <= 1'b0;
            desc_rready <= 1'b0;
            pf_cmd_valid <= 1'b0;
            payload_last_loaded <= 1'b0;
            payload_error_done <= 1'b0;
            cqe_req_valid <= 1'b0;
            desc_mode <= 1'b0;
            if (quiesce) begin
                tx_sched_req_valid_q <= 1'b0;
                tx_sched_grant_valid_q <= 1'b0;
                tx_sched_meta_valid_q <= 1'b0;
                tx_sched_start_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
                tx_sched_desc_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
            end else if (tx_sched_meta_valid_q) begin
                tx_sched_meta_valid_q <= 1'b0;
                active_ch <= tx_sched_meta_ch_q;
                cpl_en <= tx_sched_meta_ctrl_q[`DMA_TX_CTRL_CPL_EN];
                irq_en <= tx_sched_meta_ctrl_q[`DMA_TX_CTRL_IRQ_EN];
                final_status <= `DMA_ST_TX_DONE;
                if (tx_sched_meta_is_desc_q) begin
                    active_tc <= `DMA_TC_FC;
                    active_policy <= `DMA_TX_POL_SINGLE_SHOT;
                    active_tag <= tx_sched_meta_ch_q;
                    active_addr <= 32'h0;
                    active_len <= 32'h0;
                    active_len_limit_q <= tx_sched_meta_len_q;
                    active_aligned_len <= 32'h0;
                    active_frame_seq <= frame_seq_counter;
                    active_timestamp <= 64'h0;
                    active_sample_count <= 32'h0;
                    active_desc_rd_ptr <= 32'h0;
                    active_desc_next_rd_ptr <= 32'h0;
                    active_desc_ctrl <= 32'h0;
                    active_desc_base_l <= 32'h0;
                    active_desc_base_h <= 32'h0;
                    active_desc_size <= 32'h0;
                    active_desc_wr_ptr <= 32'h0;
                    desc_mode <= 1'b1;
                    tx_desc_ctx_req <= 1'b1;
                    tx_desc_ctx_ch <= tx_sched_meta_ch_q;
                    state <= ST_DESC_CTX;
                end else begin
                    active_tc <= tx_sched_meta_cfg_q[3:0];
                    active_policy <= tx_sched_meta_cfg_q[7:4];
                    active_tag <= tx_sched_meta_cfg_q[31:16];
                    active_addr <= tx_sched_meta_base_l_q;
                    active_len <= tx_sched_meta_len_q;
                    active_len_limit_q <= tx_sched_meta_len_q;
                    active_aligned_len <= (tx_sched_meta_len_q + 32'd63) & 32'hffff_ffc0;
                    active_frame_seq <= frame_seq_counter;
                    active_timestamp <= 64'h0;
                    active_sample_count <= 32'h0;
                    frame_seq_counter <= frame_seq_counter + 1'b1;
                    remaining_bytes <= tx_sched_meta_len_q;
                    rd_addr <= tx_sched_meta_base_l_q;
                    post_event_ch(tx_sched_meta_ch_q, `DMA_ST_OK, 1'b0, 1'b0, 1'b1, 1'b0);
                    state <= ST_START_SETUP;
                end
            end else if (tx_sched_grant_valid_q) begin
                tx_sched_grant_valid_q <= 1'b0;
                tx_sched_meta_valid_q <= 1'b1;
                tx_sched_meta_is_desc_q <= tx_sched_grant_is_desc_q;
                tx_sched_meta_ch_q <= tx_sched_grant_ch_q;
                tx_sched_meta_ctrl_q <= flat_word(tx_ctrl_flat, tx_sched_grant_ch_q);
                tx_sched_meta_cfg_q <= tx_sched_grant_is_desc_q ? 32'h0 : flat_word(tx_cfg_flat, tx_sched_grant_ch_q);
                tx_sched_meta_base_l_q <= tx_sched_grant_is_desc_q ? 32'h0 : flat_word(tx_base_l_flat, tx_sched_grant_ch_q);
                tx_sched_meta_len_q <= flat_word(tx_len_flat, tx_sched_grant_ch_q);
            end else if (tx_sched_req_valid_q) begin
                tx_sched_req_valid_q <= 1'b0;
                tx_sched_grant_valid_q <= tx_sched_grant_valid_c;
                tx_sched_grant_is_desc_q <= tx_sched_grant_is_desc_c;
                tx_sched_grant_ch_q <= tx_sched_grant_ch_c;
            end else if (tx_sched_idle && tx_sched_req_any_c) begin
                tx_sched_req_valid_q <= 1'b1;
                tx_sched_start_req_vec_q <= tx_sched_start_req_vec_c;
                tx_sched_desc_req_vec_q <= tx_sched_desc_req_vec_c;
            end else if (tx_sched_idle) begin
                tx_sched_start_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
                tx_sched_desc_req_vec_q <= {`DMA_TX_CH_NUM{1'b0}};
            end
        end
        ST_DESC_CTX: begin
            tx_desc_ctx_req <= 1'b1;
            tx_desc_ctx_ch <= active_ch;
            if (tx_desc_ctx_valid) begin
                desc_buf <= 512'h0;
                active_desc_ctrl <= tx_desc_ctx_ctrl;
                active_addr <= tx_desc_ctx_base_l + tx_desc_ctx_rd_ptr;
                active_desc_rd_ptr <= tx_desc_ctx_rd_ptr;
                active_desc_next_rd_ptr <=
                    (tx_desc_ctx_rd_ptr + `DMA_TX_DESC_BYTES >= tx_desc_ctx_size) ?
                    32'h0 : (tx_desc_ctx_rd_ptr + `DMA_TX_DESC_BYTES);
                active_desc_base_l <= tx_desc_ctx_base_l;
                active_desc_base_h <= tx_desc_ctx_base_h;
                active_desc_size <= tx_desc_ctx_size;
                active_desc_wr_ptr <= tx_desc_ctx_wr_ptr;
                state <= ST_DESC_SETUP;
            end
        end
        ST_DESC_SETUP: begin
            if ((active_desc_size == 0) ||
                (active_desc_base_h != 32'h0) ||
                (active_desc_base_l[5:0] != 6'h0) ||
                (active_desc_size[5:0] != 6'h0) ||
                (active_desc_rd_ptr[5:0] != 6'h0) ||
                (active_desc_wr_ptr[5:0] != 6'h0) ||
                (active_desc_rd_ptr >= active_desc_size) ||
                (active_desc_wr_ptr >= active_desc_size)) begin
                final_status <= `DMA_ST_TX_DESC_RING_ERR;
                active_desc_next_rd_ptr <= active_desc_rd_ptr;
                state <= ST_DONE;
            end else begin
                desc_araddr <= active_desc_base_l + active_desc_rd_ptr;
                desc_arlen <= 8'd7;
                desc_arvalid <= 1'b1;
                words_seen <= 4'h0;
                state <= ST_DESC_AR;
            end
        end
        ST_START_SETUP: begin
            if (active_policy != `DMA_TX_POL_SINGLE_SHOT) begin
                final_status <= `DMA_ST_UNSUPPORTED_FEATURE;
                state <= ST_CQE_REQ;
            end else if (active_len == 0) begin
                state <= ST_HEADER;
            end else if (active_addr[2:0] != 3'h0) begin
                final_status <= `DMA_ST_ADDR_ALIGN;
                state <= ST_CQE_REQ;
            end else if (cpl_en) begin
                start_cq_check(1'b0);
            end else begin
                state <= ST_HEADER;
            end
        end
        ST_DESC_AR: begin
            if (desc_arvalid && m_axi_arready) begin
                desc_arvalid <= 1'b0;
                desc_rready <= 1'b1;
                state <= ST_DESC_READ;
            end
        end
        ST_DESC_READ: begin
            if (m_axi_rvalid && desc_rready) begin
                case (words_seen)
                4'd0: desc_buf[  0 +: 64] <= m_axi_rdata;
                4'd1: desc_buf[ 64 +: 64] <= m_axi_rdata;
                4'd2: desc_buf[128 +: 64] <= m_axi_rdata;
                4'd3: desc_buf[192 +: 64] <= m_axi_rdata;
                4'd4: desc_buf[256 +: 64] <= m_axi_rdata;
                4'd5: desc_buf[320 +: 64] <= m_axi_rdata;
                4'd6: desc_buf[384 +: 64] <= m_axi_rdata;
                default: desc_buf[448 +: 64] <= m_axi_rdata;
                endcase
                words_seen <= words_seen + 1'b1;
                if (m_axi_rresp != 2'b00) begin
                    final_status <= `DMA_ST_TX_DESC_FETCH_ERR;
                    desc_rready <= 1'b0;
                    state <= ST_CQE_REQ;
                end else if (m_axi_rlast || (words_seen == 4'd7)) begin
                    desc_rready <= 1'b0;
                    state <= ST_DESC_PARSE;
                end
            end
        end
        ST_DESC_PARSE: begin
            active_tc <= `DMA_TC_FC;
            active_policy <= `DMA_TX_POL_SINGLE_SHOT;
            active_tag <= desc_buf[8*8 +: 16];
            active_len <= desc_buf[12*8 +: 32];
            active_addr <= desc_buf[16*8 +: 32];
            active_aligned_len <= (desc_buf[12*8 +: 32] + 32'd63) & 32'hffff_ffc0;
            active_frame_seq <= desc_buf[24*8 +: 32];
            active_timestamp <= {desc_buf[32*8 +: 32], desc_buf[28*8 +: 32]};
            active_sample_count <= desc_buf[36*8 +: 32];
            remaining_bytes <= desc_buf[12*8 +: 32];
            rd_addr <= desc_buf[16*8 +: 32];
            if (!desc_buf[`DMA_TX_DESC_OWNER_VALID]) begin
                final_status <= `DMA_ST_TX_DESC_OWNER_ERR;
                state <= ST_CQE_REQ;
            end else if ((desc_buf[12*8 +: 32] > active_len_limit_q) ||
                         (desc_buf[12*8 +: 32] == 32'h0)) begin
                final_status <= `DMA_ST_TX_DESC_LEN_ERR;
                state <= ST_CQE_REQ;
            end else if ((desc_buf[130:128] != 3'h0) ||
                         (desc_buf[20*8 +: 32] != 32'h0)) begin
                final_status <= `DMA_ST_TX_DESC_ADDR_ERR;
                state <= ST_CQE_REQ;
            end else if (cpl_en) begin
                start_cq_check(1'b1);
            end else begin
                final_status <= `DMA_ST_TX_DONE;
                frame_seq_counter <= frame_seq_counter + 1'b1;
                state <= ST_HEADER;
            end
        end
        ST_CQ_CHECK_USED: begin
            cq_check_consume_q <= 1'b0;
            cq_size_nonzero_q <= (cq_check_size_q != 32'h0);
            if (cq_check_size_q == 32'h0)
                cq_used_entries_q <= 32'h0;
            else if (cq_check_wr_ptr_q >= cq_check_rd_ptr_q)
                cq_used_entries_q <= cq_check_wr_ptr_q - cq_check_rd_ptr_q;
            else
                cq_used_entries_q <= cq_check_size_q - cq_check_rd_ptr_q + cq_check_wr_ptr_q;
            state <= ST_CQ_CHECK_SPACE;
        end
        ST_CQ_CHECK_SPACE: begin
            if (!cq_check_consume_q) begin
                if (!cq_size_nonzero_q)
                    cq_space_ok_q <= 1'b0;
                else if (cq_check_size_q <= cq_used_entries_q)
                    cq_space_ok_q <= 1'b0;
                else
                    cq_space_ok_q <= ((cq_check_size_q - cq_used_entries_q - 32'd1) > cq_check_reserved_q);
                cq_check_consume_q <= 1'b1;
            end else begin
                cq_check_consume_q <= 1'b0;
                if (!cq_space_ok_q) begin
                    final_status <= `DMA_ST_TX_CQ_BLOCKED;
                    state <= ST_DONE;
                end else begin
                    cq_reserve_inc <= 1'b1;
                    if (cq_check_from_desc_q) begin
                        final_status <= `DMA_ST_TX_DONE;
                        frame_seq_counter <= frame_seq_counter + 1'b1;
                    end
                    state <= ST_HEADER;
                end
            end
        end
        ST_HEADER: begin
            tx_axis_tdata <= header_beat;
            tx_axis_tvalid <= 1'b1;
            if (tx_axis_tvalid && tx_axis_tready) begin
                tx_axis_tvalid <= 1'b0;
                if (remaining_bytes == 0) begin
                    state <= ST_CQE_REQ;
                end else begin
                    state <= ST_AR;
                end
            end
        end
        ST_AR: begin
            tx_axis_tvalid <= 1'b0;
            payload_last_loaded <= 1'b0;
            payload_error_done <= 1'b0;
            pf_cmd_valid <= 1'b1;
            if (pf_cmd_valid && pf_cmd_ready) begin
                pf_cmd_valid <= 1'b0;
                state <= ST_SEND_PAY;
            end
        end
        ST_RDATA: begin
            if (desc_stop_wait_q != 0) begin
                desc_stop_wait_q <= desc_stop_wait_q - 1'b1;
            end else begin
                state <= ST_DESC_HOLD;
            end
        end
        ST_SEND_PAY: begin
            if ((!tx_axis_tvalid || tx_axis_tready) && !payload_last_loaded) begin
                tx_axis_tdata <= pf_out_data;
                tx_axis_tvalid <= pf_out_valid;
                if (pf_out_valid && pf_out_last)
                    payload_last_loaded <= 1'b1;
            end
            if (pf_cmd_done && pf_cmd_error) begin
                final_status <= `DMA_ST_AXI_READ_ERR;
                payload_error_done <= 1'b1;
            end
            if (payload_error_done && (!tx_axis_tvalid || tx_axis_tready)) begin
                tx_axis_tvalid <= 1'b0;
                state <= ST_CQE_REQ;
            end else if (payload_last_loaded && tx_axis_tvalid && tx_axis_tready) begin
                tx_axis_tvalid <= 1'b0;
                state <= ST_CQE_REQ;
            end
        end
        ST_CQE_REQ: begin
            tx_axis_tvalid <= 1'b0;
            if (cpl_en) begin
                cqe_req_valid <= 1'b1;
                cqe_ch <= active_ch;
                cqe_tc <= active_tc;
                cqe_policy <= active_policy;
                cqe_flow_id <= (active_tc == `DMA_TC_AUX) ? 16'h0 : active_tag;
                cqe_msg_id <= (active_tc == `DMA_TC_AUX) ? active_tag : 16'h0;
                cqe_addr <= active_addr;
                cqe_len <= active_len;
                cqe_aligned_len <= active_aligned_len;
                cqe_frame_seq <= active_frame_seq;
                cqe_status_code <= final_status;
                cqe_flags <= (final_status == `DMA_ST_AXI_READ_ERR) ? (16'h1 << `DMA_CQE_FLAG_AXI_ERROR) :
                             (final_status == `DMA_ST_TX_CQ_BLOCKED) ? (16'h1 << `DMA_CQE_FLAG_CQ_BLOCKED) : 16'h0;
                if (cqe_req_valid && cqe_req_ready) begin
                    cqe_req_valid <= 1'b0;
                    state <= ST_DONE;
                end
            end else begin
                state <= ST_DONE;
            end
        end
        ST_DONE: begin
            post_event(final_status,
                       final_status == `DMA_ST_TX_DONE,
                       final_status != `DMA_ST_TX_DONE,
                       !desc_mode,
                       active_ctrl[`DMA_TX_CTRL_STOP]);
            if (desc_mode) begin
                // Let the registered descriptor STOP view observe a CSR command
                // accepted at the completion boundary before publishing status.
                desc_stop_wait_q <= 2'd2;
                desc_evt_publish_q <= 1'b0;
                state <= ST_RDATA;
            end else begin
                state <= ST_IDLE;
            end
        end
        ST_DESC_HOLD: begin
            if (!desc_evt_publish_q) begin
                post_desc_event((tx_desc_active_stop &&
                                 (final_status == `DMA_ST_TX_DONE)) ? `DMA_ST_TX_STOPPED : final_status,
                                active_desc_next_rd_ptr,
                                final_status != `DMA_ST_TX_DONE);
                desc_evt_publish_q <= 1'b1;
            end else begin
                desc_evt_publish_q <= 1'b0;
                state <= ST_IDLE;
            end
        end
        default: state <= ST_IDLE;
        endcase
    end
end

endmodule
