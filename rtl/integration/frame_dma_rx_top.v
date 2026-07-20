`timescale 1ns/1ps
`include "dma_defs.vh"

// -----------------------------------------------------------------------------
// 模块功能：SLVC DMA 的 Core 集成顶层，协调 RX admission/写入、TX 调度/读取、
// CQ 发布、AXI-Lite 寄存器和共享 AXI Master 仲裁。
// RX 路径：SHDR64 parser -> channel match/context -> admission -> payload write/CQE；
// TX 路径：channel/descriptor context -> read prefetch -> SHDR64 header/payload。
// 控制边界：各子路径先形成已注册 event，再由寄存器/CQ 侧消费，避免数据面状态
// 直接扩散到控制计数。RX、控制和 AXI 主时钟在 aclk 域，TX stream 可独立复位。
// -----------------------------------------------------------------------------
module frame_dma_rx_top #(
    parameter integer TX_RD_MAX_OUTSTANDING = `DMA_TX_RD_MAX_OUTSTANDING,
    parameter integer RX_WR_MAX_OUTSTANDING = `DMA_RX_WR_MAX_OUTSTANDING
)(
    input             aclk,
    input             aresetn,
    input             tx_axis_aclk,
    input             tx_axis_aresetn,
    input      [511:0] rx_axis_tdata,
    input              rx_axis_tvalid,
    output             rx_axis_tready,
    output     [511:0] tx_axis_tdata,
    output             tx_axis_tvalid,
    input              tx_axis_tready,
    input      [31:0]  s_axil_awaddr,
    input              s_axil_awvalid,
    output             s_axil_awready,
    input      [31:0]  s_axil_wdata,
    input      [3:0]   s_axil_wstrb,
    input              s_axil_wvalid,
    output             s_axil_wready,
    output      [1:0]  s_axil_bresp,
    output             s_axil_bvalid,
    input              s_axil_bready,
    input      [31:0]  s_axil_araddr,
    input              s_axil_arvalid,
    output             s_axil_arready,
    output     [31:0]  s_axil_rdata,
    output      [1:0]  s_axil_rresp,
    output             s_axil_rvalid,
    input              s_axil_rready,
    output     [31:0]  m_axi_awaddr,
    output      [7:0]  m_axi_awlen,
    output      [2:0]  m_axi_awsize,
    output      [1:0]  m_axi_awburst,
    output             m_axi_awvalid,
    input              m_axi_awready,
    output     [63:0]  m_axi_wdata,
    output      [7:0]  m_axi_wstrb,
    output             m_axi_wlast,
    output             m_axi_wvalid,
    input              m_axi_wready,
    input       [1:0]  m_axi_bresp,
    input              m_axi_bvalid,
    output             m_axi_bready,
    output      [31:0] m_axi_araddr,
    output      [7:0]  m_axi_arlen,
    output      [2:0]  m_axi_arsize,
    output      [1:0]  m_axi_arburst,
    output             m_axi_arvalid,
    input              m_axi_arready,
    input      [63:0]  m_axi_rdata,
    input      [1:0]   m_axi_rresp,
    input              m_axi_rlast,
    input              m_axi_rvalid,
    output             m_axi_rready,
    output             ufc_tx_valid,
    input              ufc_tx_ready,
    output      [7:0]  ufc_tx_opcode,
    output     [15:0]  ufc_tx_flow_id,
    output     [31:0]  ufc_tx_arg0,
    output     [31:0]  ufc_tx_arg1,
    input              ufc_rx_valid,
    output             ufc_rx_ready,
    input       [7:0]  ufc_rx_opcode,
    input      [15:0]  ufc_rx_flow_id,
    input      [31:0]  ufc_rx_arg0,
    input      [31:0]  ufc_rx_arg1,
    output             irq
`ifdef DMA_RX_MEM_ASYNC_PROFILE
    ,input             mem_clk
    ,input             mem_aresetn
    ,output     [31:0] m_axi_rx_payload_awaddr
    ,output      [7:0] m_axi_rx_payload_awlen
    ,output      [2:0] m_axi_rx_payload_awsize
    ,output      [1:0] m_axi_rx_payload_awburst
    ,output            m_axi_rx_payload_awvalid
    ,input             m_axi_rx_payload_awready
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
    ,output     [63:0] m_axi_rx_payload_wdata
    ,output      [7:0] m_axi_rx_payload_wstrb
`else
    ,output    [511:0] m_axi_rx_payload_wdata
    ,output     [63:0] m_axi_rx_payload_wstrb
`endif
    ,output            m_axi_rx_payload_wlast
    ,output            m_axi_rx_payload_wvalid
    ,input             m_axi_rx_payload_wready
    ,input       [1:0] m_axi_rx_payload_bresp
    ,input             m_axi_rx_payload_bvalid
    ,output            m_axi_rx_payload_bready
`elsif DMA_RX_WIDE_PAYLOAD_PROFILE
    ,output     [31:0] m_axi_rx_payload_awaddr
    ,output      [7:0] m_axi_rx_payload_awlen
    ,output      [2:0] m_axi_rx_payload_awsize
    ,output      [1:0] m_axi_rx_payload_awburst
    ,output            m_axi_rx_payload_awvalid
    ,input             m_axi_rx_payload_awready
    ,output    [511:0] m_axi_rx_payload_wdata
    ,output     [63:0] m_axi_rx_payload_wstrb
    ,output            m_axi_rx_payload_wlast
    ,output            m_axi_rx_payload_wvalid
    ,input             m_axi_rx_payload_wready
    ,input       [1:0] m_axi_rx_payload_bresp
    ,input             m_axi_rx_payload_bvalid
    ,output            m_axi_rx_payload_bready
`endif
);

// RX 状态机把 header 解析、channel context、资源检查、提交和异常恢复分开，
// 这样 admission 只在所有必要资源已确认后改变软件可见状态。
localparam RX_IDLE         = 4'd0;
localparam RX_PARSE_WAIT   = 4'd1;
localparam RX_LOOKUP       = 4'd2;
localparam RX_CH_CTX       = 4'd3;
localparam RX_RELEASE_USED = 4'd4;
localparam RX_RING_FREE    = 4'd5;
localparam RX_RING_NEXT    = 4'd6;
localparam RX_ADMIT_FINAL  = 4'd7;
localparam RX_COMMIT       = 4'd8;
localparam RX_COLLECT      = 4'd9;
localparam RX_DROP         = 4'd10;
localparam RX_GAP          = 4'd11;
localparam RX_ADMIT_CHECK  = 4'd12;
localparam RX_LOOKUP_PIPE  = 4'd13;
localparam RX_RELEASE_CALC = 4'd14;
localparam RX_REJECT_EVAL  = 4'd15;

// 写路径状态机先发 payload command，再等待写响应，最后单独发布 CQE 并回收 frame。
localparam WR_IDLE     = 3'd0;
localparam WR_PAY_CMD  = 3'd1;
localparam WR_PAY_WAIT = 3'd2;
localparam WR_CQE_CMD  = 3'd3;
localparam WR_CQE_WAIT = 3'd4;
localparam WR_POP      = 3'd5;
localparam S_AXIS_DATA_WIDTH = 512;
localparam M_AXI_DATA_WIDTH  = 64;
localparam RX_FC_INGRESS_PAYLOAD_AW = `DMA_RX_FC_INGRESS_PAYLOAD_AW;
localparam HAS_CQ_CMD_CREDIT = (`DMA_ENABLE_CQ_CMD_CREDIT != 0);
localparam HAS_RX_AXIS_SKID = (`DMA_ENABLE_RX_AXIS_SKID != 0);
localparam HAS_CQ_SINGLE_WRITER = (`DMA_ENABLE_CQ_SINGLE_WRITER != 0);
localparam HAS_RX_MATCH_PIPELINE = (`DMA_ENABLE_RX_MATCH_PIPELINE != 0);
localparam [3:0] CQ_CMD_CREDIT_DEPTH = 4'd8;
`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
localparam HAS_RX_WIDE_PAYLOAD = 1;
`elsif DMA_RX_MEM_ASYNC_PROFILE
localparam HAS_RX_WIDE_PAYLOAD = 1;
`else
localparam HAS_RX_WIDE_PAYLOAD = 0;
`endif
`ifdef DMA_RX_MEM_ASYNC_PROFILE
localparam HAS_RX_MEM_ASYNC = 1;
`else
localparam HAS_RX_MEM_ASYNC = 0;
`endif

initial begin
    if (`DMA_RX_CH_NUM > `DMA_MAX_CH)
        $fatal(1, "DMA_RX_CH_NUM must be <= DMA_MAX_CH");
    if (`DMA_TX_CH_NUM > `DMA_MAX_CH)
        $fatal(1, "DMA_TX_CH_NUM must be <= DMA_MAX_CH");
    if (`DMA_HEADER_BYTES != 64)
        $fatal(1, "DMA_HEADER_BYTES must be 64");
    if (!((S_AXIS_DATA_WIDTH == 64) || (S_AXIS_DATA_WIDTH == 128) ||
          (S_AXIS_DATA_WIDTH == 256) || (S_AXIS_DATA_WIDTH == 512)))
        $fatal(1, "S_AXIS_DATA_WIDTH must be 64/128/256/512");
    if (!((M_AXI_DATA_WIDTH == 32) || (M_AXI_DATA_WIDTH == 64) ||
          (M_AXI_DATA_WIDTH == 128) || (M_AXI_DATA_WIDTH == 256)))
        $fatal(1, "M_AXI_DATA_WIDTH must be 32/64/128/256");
    if ((`DMA_ALIGN_BYTES == 0) || ((`DMA_ALIGN_BYTES & (`DMA_ALIGN_BYTES - 1)) != 0))
        $fatal(1, "DMA_ALIGN_BYTES must be a power of two");
    if (`DMA_MAX_BURST_LEN != 16)
        $fatal(1, "DMA v1.0 baseline expects DMA_MAX_BURST_LEN default 16");
`ifdef DMA_RX_MEM_ASYNC_PROFILE
`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
    $fatal(1, "same-clock wide and asynchronous RX memory profiles are mutually exclusive");
`endif
`ifndef DMA_RX_MEM_ASYNC64_PROFILE
`ifndef DMA_RX_MEM_ASYNC512_PROFILE
    $fatal(1, "asynchronous RX memory profile requires 64-bit or 512-bit backend");
`endif
`endif
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
`ifdef DMA_RX_MEM_ASYNC512_PROFILE
    $fatal(1, "asynchronous RX memory width profiles are mutually exclusive");
`endif
`endif
`endif
end

`ifdef DMA_RX_MEM_ASYNC_PROFILE
`ifndef SYNTHESIS
always @(negedge aresetn or negedge mem_aresetn) begin
    #0;
    if (aresetn || mem_aresetn)
        $fatal(1, "asynchronous RX memory profile requires both hard resets asserted together");
end
`endif
`endif

reg [3:0] rx_state;
reg [2:0] wr_state;
reg [8:0] drop_beats_left;
reg       violation_hold;

reg [3:0] active_ch;
reg [3:0] active_tc;
reg [3:0] active_policy;
reg [15:0] active_flow_id;
reg [15:0] active_msg_id;
reg [31:0] active_payload_len;
reg [31:0] active_aligned_len;
reg [31:0] active_dst_addr;
reg [31:0] active_next_wr_ptr;
reg [31:0] active_frame_seq;
reg [63:0] active_timestamp;
reg [31:0] active_sample_count;
reg        active_cpl_en;
reg        active_ring;
reg        active_wrap_before;
reg [31:0] active_cq_next;

// event_* 是 RX/TX 完成结果到控制面的一拍事件；先锁存事件，再更新 channel
// counter、IRQ 和 CQ 状态，避免同周期多个来源直接覆盖计数器。
reg event_valid;
reg event_ch_valid;
reg [3:0] event_ch;
reg [7:0] event_status_code;
reg [31:0] event_aligned_len;
reg [31:0] event_next_wr_ptr;
reg event_inc_frame;
reg event_inc_drop;
reg event_inc_err;
reg event_update_wr_ptr;
reg [15:0] event_irq_mask;
reg event_global_header_err;
reg cq_commit_valid;
reg [31:0] cq_commit_ptr;
reg [31:0] cq_reserved_count;
reg [1:0] cq_reserve_dec_pending_cnt;
reg [3:0] cq_cmd_credit_count;
reg [1:0] cq_cmd_credit_reserve_evt_q;
reg [1:0] cq_cmd_credit_return_evt_q;

reg rx_event_valid;
reg rx_event_ch_valid;
reg [3:0] rx_event_ch;
reg [7:0] rx_event_status_code;
reg [31:0] rx_event_aligned_len;
reg [31:0] rx_event_next_wr_ptr;
reg rx_event_inc_frame;
reg rx_event_inc_drop;
reg rx_event_inc_err;
reg rx_event_update_wr_ptr;
reg [15:0] rx_event_irq_mask;
reg rx_event_global_header_err;

reg event_to_regs_valid;
reg event_to_regs_ch_valid;
reg [3:0] event_to_regs_ch;
reg [7:0] event_to_regs_status_code;
reg [31:0] event_to_regs_aligned_len;
reg [31:0] event_to_regs_next_wr_ptr;
reg event_to_regs_inc_frame;
reg event_to_regs_inc_drop;
reg event_to_regs_inc_err;
reg event_to_regs_update_wr_ptr;
reg [15:0] event_to_regs_irq_mask;
reg event_to_regs_global_header_err;
reg core_busy_to_regs;
reg axi_busy_to_regs;

reg [31:0] shadow_wr_ptr [0:`DMA_MAX_CH-1];
reg [31:0] shadow_rd_ptr [0:`DMA_MAX_CH-1];
reg [31:0] shadow_used [0:`DMA_MAX_CH-1];
reg        shadow_init_active_q;
reg [3:0]  shadow_init_ch_q;
reg        release_pending_valid_q;
reg [3:0]  release_pending_ch_q;
reg [31:0] release_pending_delta_q;
reg [31:0] release_pending_ptr_q;
reg        release_snapshot_valid_q;
reg [15:0] release_snapshot_onehot_q;
reg [31:0] release_snapshot_used_q;
reg [31:0] release_snapshot_delta_q;
reg [31:0] release_snapshot_ptr_q;
reg        release_calc_valid_q;
reg [15:0] release_calc_onehot_q;
reg [31:0] release_calc_used_q;
reg [31:0] release_calc_ptr_q;
wire [`DMA_MAX_CH*32-1:0] shadow_used_flat;
genvar shadow_g;

generate
    for (shadow_g = 0; shadow_g < `DMA_MAX_CH; shadow_g = shadow_g + 1) begin : g_shadow_used_flat
        assign shadow_used_flat[shadow_g*32 +: 32] = shadow_used[shadow_g];
    end
endgenerate

wire global_enable;
wire rx_enable;
wire tx_enable;
wire irq_enable;
wire ufc_enable;
wire axil_soft_reset;
wire axil_soft_reset_request;
wire axil_soft_reset_pending;
wire core_soft_reset;
reg soft_reset_quiesce_q;
reg soft_reset_mem_request_sent_q;
reg soft_reset_drain_idle_q;
reg soft_reset_drain_done_q;
reg ingress_work_busy_q;
reg cq_work_busy_q;
reg [25:0] rx_input_payload_beats_left_q;
wire ingress_work_busy;
wire cq_work_busy;
wire soft_reset_mem_reset_done;
wire soft_reset_drain_done;
wire soft_reset_drain_idle_raw;
wire cdc_protocol_error_status;
wire soft_reset_quiesce = HAS_RX_MEM_ASYNC &&
                          (soft_reset_quiesce_q || axil_soft_reset_pending ||
                           axil_soft_reset_request);
wire soft_reset_mem_request = HAS_RX_MEM_ASYNC && soft_reset_quiesce &&
                              soft_reset_drain_done &&
                              !soft_reset_mem_request_sent_q;
wire soft_reset_ready = !HAS_RX_MEM_ASYNC || soft_reset_mem_reset_done;
assign soft_reset_drain_done = soft_reset_drain_done_q;
`ifndef DMA_RX_MEM_ASYNC_PROFILE
assign soft_reset_mem_reset_done = 1'b1;
assign cdc_protocol_error_status = 1'b0;
`endif
wire axil_ch_reset;
wire [3:0] axil_ch_reset_ch;
wire [511:0] rx_front_tdata;
wire rx_front_tvalid;
wire rx_front_tready;
wire rx_skid_s_ready;
wire rx_axis_input_fire = rx_axis_tvalid && rx_axis_tready;
wire [31:0] rx_axis_header_payload_len = {
    rx_axis_tdata[127:120], rx_axis_tdata[119:112],
    rx_axis_tdata[111:104], rx_axis_tdata[103:96]
};
wire [31:0] rx_axis_header_payload_rounded =
    rx_axis_header_payload_len + 32'd63;
wire rx_quiesce_input_open = !soft_reset_quiesce ||
                             (((rx_state == RX_COLLECT) ||
                               (rx_state == RX_DROP)) &&
                              (rx_input_payload_beats_left_q != 0));
wire rx_quiesce_drain_buffered_header = soft_reset_quiesce &&
                                         HAS_RX_AXIS_SKID &&
                                         rx_front_tvalid;
wire rx_idle_parser_open = !soft_reset_quiesce ||
                           rx_quiesce_drain_buffered_header;
wire [31:0] cq_base_l;
wire [31:0] cq_base_h;
wire [31:0] cq_size;
wire [31:0] cq_wr_ptr;
wire [31:0] cq_rd_ptr;
wire [`DMA_MAX_CH*32-1:0] rx_ctrl_flat;
wire [`DMA_MAX_CH*32-1:0] rx_cfg_flat;
wire [`DMA_MAX_CH*32-1:0] rx_base_l_flat;
wire [`DMA_MAX_CH*32-1:0] rx_base_h_flat;
wire [`DMA_MAX_CH*32-1:0] rx_size_flat;
wire [`DMA_MAX_CH*32-1:0] rx_max_len_flat;
wire [`DMA_MAX_CH*32-1:0] rx_wr_ptr_flat;
wire [`DMA_MAX_CH*32-1:0] rx_rd_ptr_flat;
wire [`DMA_MAX_CH*32-1:0] rx_used_flat;
wire [`DMA_MAX_CH*32-1:0] rx_high_wm_flat;
wire [`DMA_MAX_CH*32-1:0] rx_low_wm_flat;
wire [`DMA_MAX_CH*32-1:0] rx_user_flat;
wire [`DMA_MAX_CH*32-1:0] tx_ctrl_flat;
wire [`DMA_MAX_CH*32-1:0] tx_cfg_flat;
wire [`DMA_MAX_CH*32-1:0] tx_base_l_flat;
wire [`DMA_MAX_CH*32-1:0] tx_base_h_flat;
wire [`DMA_MAX_CH*32-1:0] tx_len_flat;
wire [`DMA_MAX_CH*32-1:0] tx_status_flat;
wire [`DMA_MAX_CH*32-1:0] tx_user_flat;
wire [`DMA_MAX_CH-1:0] tx_desc_enable_flat;
wire [`DMA_MAX_CH-1:0] tx_desc_ready_flat;
wire tx_csr_wr_valid;
wire tx_csr_wr_ready;
wire [3:0] tx_csr_wr_ch;
wire [5:0] tx_csr_wr_off;
wire [31:0] tx_csr_wdata;
wire [3:0] tx_csr_wstrb;
wire [1:0] tx_csr_bresp;
wire tx_csr_wr_rsp_valid;
wire [1:0] tx_csr_wr_rsp_kind;
wire [7:0] tx_csr_wr_rsp_code;
wire tx_csr_global_err;
wire tx_csr_policy_irq;
wire tx_csr_rd_valid;
wire tx_csr_rd_ready;
wire [3:0] tx_csr_rd_ch;
wire [5:0] tx_csr_rd_off;
wire tx_csr_rvalid;
wire [31:0] tx_csr_rdata;
wire [1:0] tx_csr_rresp;
wire tx_tbl_irq_tx_completion;
wire tx_tbl_irq_axi_error;
wire tx_desc_csr_wr_valid;
wire tx_desc_csr_wr_ready;
wire [3:0] tx_desc_csr_wr_ch;
wire [5:0] tx_desc_csr_wr_off;
wire [31:0] tx_desc_csr_wdata;
wire [3:0] tx_desc_csr_wstrb;
wire [1:0] tx_desc_csr_bresp;
wire tx_desc_csr_wr_rsp_valid;
wire [1:0] tx_desc_csr_wr_rsp_kind;
wire [7:0] tx_desc_csr_wr_rsp_code;
wire tx_desc_csr_rd_valid;
wire tx_desc_csr_rd_ready;
wire [3:0] tx_desc_csr_rd_ch;
wire [5:0] tx_desc_csr_rd_off;
wire tx_desc_csr_rvalid;
wire [31:0] tx_desc_csr_rdata;
wire [1:0] tx_desc_csr_rresp;
wire rx_csr_wr_valid;
wire rx_csr_wr_ready;
wire [3:0] rx_csr_wr_ch;
wire [5:0] rx_csr_wr_off;
wire [31:0] rx_csr_wdata;
wire [3:0] rx_csr_wstrb;
wire [1:0] rx_csr_bresp;
wire rx_csr_wr_rsp_valid;
wire [1:0] rx_csr_wr_rsp_kind;
wire [7:0] rx_csr_wr_rsp_code;
wire rx_consumer_release_valid;
wire rx_consumer_release_ready;
wire [3:0] rx_consumer_release_ch;
wire [31:0] rx_consumer_release_delta;
wire [31:0] rx_consumer_release_ptr;
wire rx_consumer_release_fire = rx_consumer_release_valid && rx_consumer_release_ready;
wire release_service_busy = shadow_init_active_q || rx_consumer_release_valid ||
                            release_pending_valid_q ||
                            release_snapshot_valid_q || release_calc_valid_q;
wire [15:0] release_pending_mask =
    (release_pending_valid_q ? (16'h1 << release_pending_ch_q) : 16'h0) |
    (release_snapshot_valid_q ? release_snapshot_onehot_q : 16'h0) |
    (release_calc_valid_q ? release_calc_onehot_q : 16'h0) |
    (rx_consumer_release_valid ? (16'h1 << rx_consumer_release_ch) : 16'h0);
assign rx_consumer_release_ready = !release_pending_valid_q;
wire rx_csr_rd_valid;
wire rx_csr_rd_ready;
wire [3:0] rx_csr_rd_ch;
wire [5:0] rx_csr_rd_off;
wire rx_csr_rvalid;
wire [31:0] rx_csr_rdata;
wire [1:0] rx_csr_rresp;
wire tx_desc_ctx_req;
wire [3:0] tx_desc_ctx_ch;
wire tx_desc_ctx_valid;
wire [31:0] tx_desc_ctx_ctrl;
wire [31:0] tx_desc_ctx_base_l;
wire [31:0] tx_desc_ctx_base_h;
wire [31:0] tx_desc_ctx_size;
wire [31:0] tx_desc_ctx_rd_ptr;
wire [31:0] tx_desc_ctx_wr_ptr;
wire [31:0] tx_desc_ctx_status;
wire [31:0] tx_desc_ctx_err_cnt;
wire tx_desc_active_valid;
wire [3:0] tx_desc_active_ch;
wire tx_desc_active_stop;
wire [`DMA_MAX_CH-1:0] tx_desc_ch_reset_mask = {`DMA_MAX_CH{1'b0}};

wire parser_in_valid;
wire parser_in_ready;
wire parser_out_valid;
wire parser_out_ready;
wire parser_pipe_ok;
wire [7:0] parser_pipe_version;
wire [7:0] parser_pipe_header_len;
wire [3:0] parser_pipe_tc;
wire [15:0] parser_pipe_flow_id;
wire [15:0] parser_pipe_msg_id;
wire [31:0] parser_pipe_payload_len;
wire [31:0] parser_pipe_aligned_len;
wire [31:0] parser_pipe_frame_seq;
wire [63:0] parser_pipe_timestamp;
wire [31:0] parser_pipe_sample_count;

reg parser_ok;
reg [7:0] parser_version;
reg [7:0] parser_header_len;
reg [3:0] parser_tc;
reg [15:0] parser_flow_id;
reg [15:0] parser_msg_id;
reg [31:0] parser_payload_len;
reg [31:0] parser_aligned_len;
reg [31:0] parser_frame_seq;
reg [63:0] parser_timestamp;
reg [31:0] parser_sample_count;
reg [`DMA_MAX_CH-1:0] lookup_busy_preload_mask_q;

reg        admit_valid;
reg [3:0]  admit_ch;
reg [3:0]  admit_tc;
reg [3:0]  admit_policy;
reg [15:0] admit_flow_id;
reg [15:0] admit_msg_id;
reg [31:0] admit_payload_len;
reg [31:0] admit_aligned_len;
reg [31:0] admit_dst_addr;
reg [31:0] admit_next_wr_ptr;
reg [31:0] admit_frame_seq;
reg [63:0] admit_timestamp;
reg [31:0] admit_sample_count;
reg        admit_cpl_en;
reg        admit_ring;
reg        admit_wrap_before;
reg [31:0] admit_used_after_release;
reg        admit_rd_ptr_changed;
reg [31:0] admit_rx_rd_ptr;
reg        admit_accept;
reg        admit_ch_valid;
reg        admit_frame_shared;
reg        admit_inc_drop;
reg        admit_inc_err;
reg        admit_update_wr_ptr;
reg        admit_global_header_err;
reg [7:0]  admit_status_code;
reg [15:0] admit_irq_mask;
reg        admit_queue_can_accept_q;
reg [3:0]  admit_check_ch_q;
reg [3:0]  admit_check_policy_q;
reg [31:0] admit_check_aligned_len_q;
reg        admit_check_frame_shared_q;

reg        lookup_match_valid_q;
reg [3:0]  lookup_match_ch_q;
reg [3:0]  lookup_policy_q;
reg [31:0] lookup_max_len_q;
reg [31:0] lookup_size_q;
reg [31:0] lookup_wr_ptr_q;

reg        s1_valid;
reg        s1_header_ok;
reg        s1_match_valid;
reg        s1_frame_shared;
reg [3:0]  s1_match_ch;
reg [3:0]  s1_tc;
reg [3:0]  s1_policy;
reg [15:0] s1_flow_id;
reg [15:0] s1_msg_id;
reg [31:0] s1_payload_len;
reg [31:0] s1_aligned_len;
reg [31:0] s1_frame_seq;
reg [63:0] s1_timestamp;
reg [31:0] s1_sample_count;
reg [7:0]  s1_reject_code;
reg        s1_reject_drop;

reg        s2_valid;
reg        s2_header_ok;
reg        s2_match_valid;
reg        s2_frame_shared;
reg [3:0]  s2_ch;
reg [3:0]  s2_tc;
reg [3:0]  s2_policy;
reg [15:0] s2_flow_id;
reg [15:0] s2_msg_id;
reg [31:0] s2_payload_len;
reg [31:0] s2_aligned_len;
reg [31:0] s2_frame_seq;
reg [63:0] s2_timestamp;
reg [31:0] s2_sample_count;
reg [7:0]  s2_reject_code;
reg        s2_reject_drop;
reg [31:0] s2_ctrl;
reg [31:0] s2_base_l;
reg [31:0] s2_size;
reg [31:0] s2_rx_rd_ptr;
reg [31:0] s2_shadow_wr_ptr;
reg [31:0] s2_shadow_rd_ptr;
reg [31:0] s2_shadow_used;
reg        s2_pause_active;
reg        s2_ingress_can_accept;
reg        s2_cq_can_accept;

reg        s3_valid;
reg        s3_header_ok;
reg        s3_match_valid;
reg        s3_frame_shared;
reg [3:0]  s3_ch;
reg [3:0]  s3_tc;
reg [3:0]  s3_policy;
reg [15:0] s3_flow_id;
reg [15:0] s3_msg_id;
reg [31:0] s3_payload_len;
reg [31:0] s3_aligned_len;
reg [31:0] s3_frame_seq;
reg [63:0] s3_timestamp;
reg [31:0] s3_sample_count;
reg [7:0]  s3_reject_code;
reg        s3_reject_drop;
reg [31:0] s3_base_l;
reg [31:0] s3_size;
reg [31:0] s3_rx_rd_ptr;
reg [31:0] s3_wr_ptr;
reg [31:0] s3_rd_ptr;
reg [31:0] s3_used_after_release;
reg        s3_rd_ptr_changed;
reg        s3_release_valid;
reg [31:0] release_delta_q;
reg        release_delta_valid_q;
reg        s3_pause_violation;
reg        s3_ingress_can_accept;
reg        s3_cq_can_accept;
reg        s3_cpl_en;

reg        s4_valid;
reg        s4_header_ok;
reg        s4_match_valid;
reg        s4_frame_shared;
reg [3:0]  s4_ch;
reg [3:0]  s4_tc;
reg [3:0]  s4_policy;
reg [15:0] s4_flow_id;
reg [15:0] s4_msg_id;
reg [31:0] s4_payload_len;
reg [31:0] s4_aligned_len;
reg [31:0] s4_frame_seq;
reg [63:0] s4_timestamp;
reg [31:0] s4_sample_count;
reg [7:0]  s4_reject_code;
reg        s4_reject_drop;
reg [31:0] s4_base_l;
reg [31:0] s4_size;
reg [31:0] s4_rx_rd_ptr;
reg [31:0] s4_wr_ptr;
reg [31:0] s4_used_after_release;
reg        s4_rd_ptr_changed;
reg        s4_pause_violation;
reg        s4_ingress_can_accept;
reg        s4_cq_can_accept;
reg        s4_cpl_en;
reg [31:0] s4_free_total;
reg [31:0] s4_tail_space;
reg        s4_need_wrap;
reg        s4_tail_fits;
reg        s4_head_fits;

reg        s5_valid;
reg        s5_header_ok;
reg        s5_match_valid;
reg        s5_frame_shared;
reg [3:0]  s5_ch;
reg [3:0]  s5_tc;
reg [3:0]  s5_policy;
reg [15:0] s5_flow_id;
reg [15:0] s5_msg_id;
reg [31:0] s5_payload_len;
reg [31:0] s5_aligned_len;
reg [31:0] s5_frame_seq;
reg [63:0] s5_timestamp;
reg [31:0] s5_sample_count;
reg [7:0]  s5_reject_code;
reg        s5_reject_drop;
reg [31:0] s5_base_l;
reg [31:0] s5_rx_rd_ptr;
reg [31:0] s5_wr_ptr;
reg [31:0] s5_used_after_release;
reg        s5_rd_ptr_changed;
reg        s5_pause_violation;
reg        s5_ingress_can_accept;
reg        s5_cq_can_accept;
reg        s5_cpl_en;
reg [31:0] s5_dest_addr;
reg [31:0] s5_next_wr_ptr;
reg [31:0] s5_next_used;
reg        s5_wrap_before;
reg        s5_ddr_has_space;
reg [7:0]  s5_ddr_status;

wire match_valid;
wire [3:0] match_ch;
wire [3:0] match_policy;
wire [7:0] reject_code;
wire reject_drop;

function rx_policy_supported;
    input [3:0] tc;
    input [3:0] policy;
    begin
        case (tc)
        `DMA_TC_CONT:
            rx_policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                                  (policy == `DMA_RX_POL_LINEAR_CAPTURE) ||
                                  (policy == `DMA_RX_POL_RING_BUFFER);
        `DMA_TC_FC:
            rx_policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                                  (policy == `DMA_RX_POL_QUEUE_DROP_NEW) ||
                                  (policy == `DMA_RX_POL_QUEUE_WITH_FC) ||
                                  (policy == `DMA_RX_POL_QUEUE_LOSSLESS);
        `DMA_TC_AUX:
            rx_policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                                  (policy == `DMA_RX_POL_LINEAR_CAPTURE) ||
                                  (policy == `DMA_RX_POL_MAILBOX) ||
                                  (policy == `DMA_RX_POL_AUX_FIFO);
        default:
            rx_policy_supported = 1'b0;
        endcase
    end
endfunction

wire frame_shared_candidate =
    (`DMA_ENABLE_FRAME_SHARED_POOL != 0) &&
    parser_ok && match_valid &&
    (parser_tc == `DMA_TC_FC) &&
    (parser_payload_len != 0) &&
    ((`DMA_FRAME_SHARED_CH_MASK & (16'h1 << match_ch)) != 16'h0);

wire queue_can_accept;
wire queue_near_full;
wire queue_full;
wire stream_queue_can_accept;
wire stream_queue_near_full;
wire stream_queue_full;
wire frame_queue_can_accept;
wire frame_queue_near_full;
wire frame_queue_full;
wire [`DMA_MAX_CH-1:0] pause_active_flat;
wire [31:0] cq_next_ptr_check = (cq_wr_ptr + 1 >= cq_size) ? 0 : cq_wr_ptr + 1;
wire [31:0] cq_used_entries = (cq_size == 0) ? 32'h0 :
    ((cq_wr_ptr >= cq_rd_ptr) ? (cq_wr_ptr - cq_rd_ptr) : (cq_size - cq_rd_ptr + cq_wr_ptr));
wire [31:0] cq_free_entries = ((cq_size != 0) && (cq_size > cq_used_entries)) ?
    (cq_size - cq_used_entries - 32'd1) : 32'h0;
wire cq_has_space = (cq_size != 0) && (cq_free_entries > cq_reserved_count);
wire cq_cmd_credit_has_space = (cq_cmd_credit_count != 4'd0);
wire header_can_accept = parser_in_ready;
wire header_fire = parser_in_valid && parser_in_ready;
wire commit_fire = (rx_state == RX_COMMIT) && admit_valid;
wire queue_start = commit_fire && admit_accept;
wire [8:0] admit_drop_beats_needed = (admit_aligned_len + 32'd63) >> 6;
wire cq_reserve_inc = queue_start && admit_cpl_en;
wire cq_raw_full = (cq_size == 0) || (cq_next_ptr_check == cq_rd_ptr);
wire [3:0] ingress_req_ch = (rx_state == RX_CH_CTX) ? s1_match_ch :
                            ((rx_state == RX_ADMIT_CHECK) || (rx_state == RX_ADMIT_FINAL)) ?
                                admit_check_ch_q : admit_ch;
wire [3:0] ingress_req_policy = (rx_state == RX_CH_CTX) ? s1_policy :
                                ((rx_state == RX_ADMIT_CHECK) || (rx_state == RX_ADMIT_FINAL)) ?
                                    admit_check_policy_q : admit_policy;
wire [31:0] ingress_req_aligned_len = (rx_state == RX_CH_CTX) ? s1_aligned_len :
                                      ((rx_state == RX_ADMIT_CHECK) || (rx_state == RX_ADMIT_FINAL)) ?
                                          admit_check_aligned_len_q : admit_aligned_len;
wire ingress_req_frame_shared = (rx_state == RX_CH_CTX) ? s1_frame_shared :
                                ((rx_state == RX_ADMIT_CHECK) || (rx_state == RX_ADMIT_FINAL)) ?
                                    admit_check_frame_shared_q : admit_frame_shared;

wire queue_collect_done;
wire queue_payload_tready;
wire queue_meta_valid;
wire queue_meta_take = (wr_state == WR_IDLE) && queue_meta_valid;
wire queue_pop = (wr_state == WR_POP);
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
wire pay_rd_req;
wire [RX_FC_INGRESS_PAYLOAD_AW-1:0] pay_rd_index;
wire pay_rd_valid;
wire [63:0] pay_rd_data;
wire [`DMA_MAX_CH*32-1:0] queue_used_bytes_flat;
wire [`DMA_MAX_CH*32-1:0] queue_meta_used_flat;
wire [`DMA_MAX_CH*32-1:0] stream_queue_used_bytes_flat;
wire [`DMA_MAX_CH*32-1:0] stream_queue_meta_used_flat;
wire [`DMA_MAX_CH*32-1:0] frame_queue_used_bytes_flat;
wire [`DMA_MAX_CH*32-1:0] frame_queue_meta_used_flat;

wire stream_queue_start = queue_start && !admit_frame_shared;
wire frame_queue_start = queue_start && admit_frame_shared;
wire stream_payload_tvalid = rx_front_tvalid && (rx_state == RX_COLLECT) && !admit_frame_shared;
wire frame_payload_tvalid = rx_front_tvalid && (rx_state == RX_COLLECT) && admit_frame_shared;
wire stream_queue_collect_done;
wire stream_queue_payload_tready;
wire frame_queue_collect_done;
wire frame_queue_payload_tready;

wire stream_meta_valid;
wire stream_meta_pop;
wire [3:0] stream_queue_ch;
wire [3:0] stream_queue_tc;
wire [3:0] stream_queue_policy;
wire [15:0] stream_queue_flow_id;
wire [15:0] stream_queue_msg_id;
wire [31:0] stream_queue_payload_len;
wire [31:0] stream_queue_aligned_len;
wire [31:0] stream_queue_dst_addr;
wire [31:0] stream_queue_next_wr_ptr;
wire [31:0] stream_queue_frame_seq;
wire [63:0] stream_queue_timestamp;
wire [31:0] stream_queue_sample_count;
wire stream_queue_cpl_en;
wire stream_queue_ring;
wire stream_queue_wrap_before;
wire stream_pay_rd_req;
wire [RX_FC_INGRESS_PAYLOAD_AW-1:0] stream_pay_rd_index;
wire stream_pay_rd_valid;
wire [63:0] stream_pay_rd_data;
wire stream_wide_payload_enable;
wire stream_wide_payload_tvalid;
wire stream_wide_payload_tready;
wire [511:0] stream_wide_payload_tdata;
wire [63:0] stream_wide_payload_tkeep;
wire stream_wide_payload_tlast;

wire frame_meta_valid;
wire frame_meta_pop;
wire [3:0] frame_queue_ch;
wire [3:0] frame_queue_tc;
wire [3:0] frame_queue_policy;
wire [15:0] frame_queue_flow_id;
wire [15:0] frame_queue_msg_id;
wire [31:0] frame_queue_payload_len;
wire [31:0] frame_queue_aligned_len;
wire [31:0] frame_queue_dst_addr;
wire [31:0] frame_queue_next_wr_ptr;
wire [31:0] frame_queue_frame_seq;
wire [63:0] frame_queue_timestamp;
wire [31:0] frame_queue_sample_count;
wire frame_queue_cpl_en;
wire frame_queue_ring;
wire frame_queue_wrap_before;
wire frame_pay_rd_req;
wire [RX_FC_INGRESS_PAYLOAD_AW-1:0] frame_pay_rd_index;
wire frame_pay_rd_valid;
wire [63:0] frame_pay_rd_data;
wire frame_wide_payload_enable;
wire frame_wide_payload_tvalid;
wire frame_wide_payload_tready;
wire [511:0] frame_wide_payload_tdata;
wire [63:0] frame_wide_payload_tkeep;
wire frame_wide_payload_tlast;
wire frame_drop_event_valid;
wire [3:0] frame_drop_event_ch;
wire [15:0] frame_pool_free_count;
wire [15:0] frame_pool_alloc_count;
wire [15:0] frame_pool_committed_frame_count;
wire [15:0] frame_pool_dropped_frame_count;
wire frame_pool_overflow_sticky;
wire frame_pool_leak_check_error;
wire frame_queue_busy;
wire queue_active_is_frame;
wire queue_wide_payload_tvalid;
wire queue_wide_payload_tready;
wire [511:0] queue_wide_payload_tdata;
wire [63:0] queue_wide_payload_tkeep;
wire queue_wide_payload_tlast;
wire [`DMA_MAX_CH-1:0] rx_ch_busy_flat;
genvar busy_g;
reg [`DMA_MAX_CH-1:0] lookup_busy_preload_mask_c;
reg lookup_busy_found_c;
reg [15:0] lookup_busy_match_id_c;
reg [31:0] lookup_busy_ctrl_c;
reg [31:0] lookup_busy_cfg_c;
integer lookup_busy_i;
reg lookup_mask_valid_c;
reg [3:0] lookup_mask_ch_c;
integer lookup_mask_i;

assign queue_can_accept = ingress_req_frame_shared ? frame_queue_can_accept : stream_queue_can_accept;
assign queue_near_full = stream_queue_near_full | frame_queue_near_full;
assign queue_full = stream_queue_full | frame_queue_full;
assign queue_collect_done = admit_frame_shared ? frame_queue_collect_done : stream_queue_collect_done;
assign queue_payload_tready = admit_frame_shared ? frame_queue_payload_tready : stream_queue_payload_tready;

genvar queue_stat_g;
generate
    for (queue_stat_g = 0; queue_stat_g < `DMA_MAX_CH; queue_stat_g = queue_stat_g + 1) begin : g_queue_stat
        assign queue_used_bytes_flat[queue_stat_g*32 +: 32] =
            stream_queue_used_bytes_flat[queue_stat_g*32 +: 32] +
            frame_queue_used_bytes_flat[queue_stat_g*32 +: 32];
        assign queue_meta_used_flat[queue_stat_g*32 +: 32] =
            stream_queue_meta_used_flat[queue_stat_g*32 +: 32] +
            frame_queue_meta_used_flat[queue_stat_g*32 +: 32];
    end
endgenerate

always @(*) begin
    lookup_busy_preload_mask_c = {`DMA_MAX_CH{1'b0}};
    lookup_busy_found_c = 1'b0;
    lookup_busy_match_id_c = (parser_pipe_tc == `DMA_TC_AUX) ? parser_pipe_msg_id : parser_pipe_flow_id;
    for (lookup_busy_i = 0; lookup_busy_i < `DMA_MAX_CH; lookup_busy_i = lookup_busy_i + 1) begin
        lookup_busy_ctrl_c = rx_ctrl_flat[lookup_busy_i*32 +: 32];
        lookup_busy_cfg_c = rx_cfg_flat[lookup_busy_i*32 +: 32];
        if (!lookup_busy_found_c &&
            lookup_busy_ctrl_c[`DMA_RX_CTRL_ENABLE] &&
            (lookup_busy_cfg_c[3:0] == parser_pipe_tc) &&
            (lookup_busy_cfg_c[31:16] == lookup_busy_match_id_c)) begin
            lookup_busy_preload_mask_c[lookup_busy_i] = 1'b1;
            lookup_busy_found_c = 1'b1;
        end
    end
end

generate
    for (busy_g = 0; busy_g < `DMA_MAX_CH; busy_g = busy_g + 1) begin : g_rx_ch_busy
        assign rx_ch_busy_flat[busy_g] =
            ((rx_state == RX_LOOKUP) && lookup_busy_preload_mask_q[busy_g]) ||
            ((rx_state == RX_LOOKUP_PIPE) && lookup_busy_preload_mask_q[busy_g]) ||
            ((rx_state == RX_CH_CTX) && s1_match_valid && (s1_match_ch == busy_g[3:0])) ||
            ((rx_state == RX_RELEASE_USED) && s2_match_valid && (s2_ch == busy_g[3:0])) ||
            ((rx_state == RX_RELEASE_CALC) && s3_match_valid && (s3_ch == busy_g[3:0])) ||
            ((rx_state == RX_RING_FREE) && s3_match_valid && (s3_ch == busy_g[3:0])) ||
            ((rx_state == RX_RING_NEXT) && s4_match_valid && (s4_ch == busy_g[3:0])) ||
            ((rx_state == RX_ADMIT_CHECK) && s5_match_valid && (s5_ch == busy_g[3:0])) ||
            ((rx_state == RX_ADMIT_FINAL) && s5_match_valid && (s5_ch == busy_g[3:0])) ||
            ((rx_state == RX_COMMIT) && admit_valid && (admit_ch == busy_g[3:0])) ||
            ((wr_state != WR_IDLE) && (active_ch == busy_g[3:0])) ||
            shadow_init_active_q ||
            release_pending_mask[busy_g] ||
            (queue_meta_used_flat[busy_g*32 +: 32] != 32'h0) ||
            (queue_used_bytes_flat[busy_g*32 +: 32] != 32'h0);
    end
endgenerate

wire pay_error;
wire pay_busy;
wire pay_arbiter_busy;
wire pay_cmd_valid = (wr_state == WR_PAY_CMD);
wire pay_cmd_ready;
wire pay_cmd_fire = pay_cmd_valid && pay_cmd_ready;
wire pay_cpl_valid;
wire pay_cpl_ready = (wr_state == WR_PAY_WAIT);
wire pay_cpl_fire = pay_cpl_valid && pay_cpl_ready;
wire legacy_pay_done;
assign core_soft_reset = axil_soft_reset;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn || core_soft_reset) begin
        rx_input_payload_beats_left_q <= 26'h0;
    end else if ((rx_state == RX_COMMIT) && admit_valid && !admit_accept &&
                 (admit_status_code == `DMA_ST_HEADER_ERR)) begin
        rx_input_payload_beats_left_q <= 26'h0;
    end else if (rx_axis_input_fire) begin
        if (rx_input_payload_beats_left_q == 0)
            rx_input_payload_beats_left_q <=
                rx_axis_header_payload_rounded[31:6];
        else
            rx_input_payload_beats_left_q <=
                rx_input_payload_beats_left_q - 1'b1;
    end
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        soft_reset_quiesce_q <= 1'b0;
        soft_reset_mem_request_sent_q <= 1'b0;
        soft_reset_drain_idle_q <= 1'b0;
        soft_reset_drain_done_q <= 1'b0;
        ingress_work_busy_q <= 1'b0;
        cq_work_busy_q <= 1'b0;
    end else if (!HAS_RX_MEM_ASYNC) begin
        soft_reset_quiesce_q <= 1'b0;
        soft_reset_mem_request_sent_q <= 1'b0;
        soft_reset_drain_idle_q <= 1'b0;
        soft_reset_drain_done_q <= 1'b0;
        ingress_work_busy_q <= 1'b0;
        cq_work_busy_q <= 1'b0;
    end else if (core_soft_reset) begin
        soft_reset_quiesce_q <= 1'b0;
        soft_reset_mem_request_sent_q <= 1'b0;
        soft_reset_drain_idle_q <= 1'b0;
        soft_reset_drain_done_q <= 1'b0;
        ingress_work_busy_q <= 1'b0;
        cq_work_busy_q <= 1'b0;
    end else begin
        ingress_work_busy_q <= ingress_work_busy;
        cq_work_busy_q <= cq_work_busy;
        if (axil_soft_reset_pending || axil_soft_reset_request)
            soft_reset_quiesce_q <= 1'b1;
        if (soft_reset_quiesce) begin
            soft_reset_drain_idle_q <= soft_reset_drain_idle_raw;
            soft_reset_drain_done_q <= soft_reset_drain_idle_q &&
                                       soft_reset_drain_idle_raw;
        end else begin
            soft_reset_drain_idle_q <= 1'b0;
            soft_reset_drain_done_q <= 1'b0;
        end
        if (soft_reset_mem_request)
            soft_reset_mem_request_sent_q <= 1'b1;
    end
end
wire cqe_done;
wire cqe_error;
wire cqe_full;
wire cqe_busy;
wire cqe_done_raw;
wire cqe_error_raw;
wire cqe_busy_raw;
wire tx_cqe_busy;
wire tx_cqe_busy_raw;
wire tx_cqe_done;
wire tx_cqe_error;
wire tx_cqe_done_raw;
wire tx_cqe_error_raw;
wire tx_cqe_req_valid;
wire tx_cqe_req_ready;
wire [3:0] tx_cqe_req_ch;
wire [3:0] tx_cqe_req_tc;
wire [3:0] tx_cqe_req_policy;
wire [15:0] tx_cqe_req_flow_id;
wire [15:0] tx_cqe_req_msg_id;
wire [31:0] tx_cqe_req_addr;
wire [31:0] tx_cqe_req_len;
wire [31:0] tx_cqe_req_aligned_len;
wire [31:0] tx_cqe_req_frame_seq;
wire [7:0] tx_cqe_req_status_code;
wire [15:0] tx_cqe_req_flags;
reg tx_cqe_active;
reg [31:0] tx_cqe_next_ptr;
reg frame_drop_pending;
reg [3:0] frame_drop_pending_ch;
wire cq_single_rx_accept;
wire cq_single_tx_accept;
wire cq_single_rx_done;
wire cq_single_rx_error;
wire cq_single_rx_full;
wire cq_single_tx_done;
wire cq_single_tx_error;
wire cq_single_tx_full;
wire cq_single_commit_valid;
wire [31:0] cq_single_commit_ptr;
wire cq_single_busy;
wire legacy_tx_cqe_start = tx_cqe_req_valid && !tx_cqe_active && !cqe_busy_raw &&
                           (wr_state != WR_CQE_CMD) && (wr_state != WR_CQE_WAIT);
wire tx_cqe_start = HAS_CQ_SINGLE_WRITER ? cq_single_tx_accept : legacy_tx_cqe_start;
assign tx_cqe_req_ready = tx_cqe_active && tx_cqe_done;
wire cqe_start = !HAS_CQ_SINGLE_WRITER &&
                 (wr_state == WR_CQE_CMD) && !cq_raw_full && !tx_cqe_active && !tx_cqe_req_valid;
wire [31:0] cqe_addr = cq_base_l + (cq_wr_ptr << 6);
wire [15:0] active_cqe_flags = active_wrap_before ? (16'h1 << `DMA_CQE_FLAG_WRAP_BEFORE) : 16'h0;
wire cq_reserve_dec = (pay_cpl_fire && pay_error && active_cpl_en) ||
                      (!HAS_CQ_SINGLE_WRITER && (wr_state == WR_CQE_CMD) && cq_raw_full && active_cpl_en) ||
                      ((wr_state == WR_CQE_WAIT) && cqe_done && active_cpl_en);
wire tx_cq_reserve_inc;
wire tx_cq_reserve_dec = tx_cqe_done;
wire cq_reserve_inc_any = cq_reserve_inc || tx_cq_reserve_inc;
wire cq_reserve_dec_any = cq_reserve_dec || tx_cq_reserve_dec;
wire cq_reserve_dec_pending = (cq_reserve_dec_pending_cnt != 2'd0);
wire cq_reserve_dec_enqueue = cq_reserve_dec_any &&
                              ((cq_reserved_count != 32'h0) ||
                               cq_reserve_inc_any ||
                               cq_reserve_dec_pending);
reg [1:0] cq_reserve_dec_pending_next;
wire [1:0] cq_cmd_credit_reserve_evt_c = HAS_CQ_CMD_CREDIT ?
    ({1'b0, cq_reserve_inc} + {1'b0, tx_cq_reserve_inc}) : 2'd0;
wire rx_cq_cmd_return_evt_c = HAS_CQ_CMD_CREDIT &&
                              active_cpl_en &&
                              ((pay_cpl_fire && pay_error) ||
                               (HAS_CQ_SINGLE_WRITER ? cq_single_rx_accept :
                                                        (wr_state == WR_CQE_CMD)));
wire tx_cq_cmd_return_evt_c = HAS_CQ_CMD_CREDIT && tx_cqe_start;
wire [1:0] cq_cmd_credit_return_evt_c =
    {1'b0, rx_cq_cmd_return_evt_c} + {1'b0, tx_cq_cmd_return_evt_c};
wire [4:0] cq_cmd_credit_depth_ext = {1'b0, CQ_CMD_CREDIT_DEPTH};
wire [4:0] cq_cmd_credit_return_ext = {3'b000, cq_cmd_credit_return_evt_q};
wire [4:0] cq_cmd_credit_reserve_ext = {3'b000, cq_cmd_credit_reserve_evt_q};
wire [4:0] cq_cmd_credit_plus_return_ext =
    ({1'b0, cq_cmd_credit_count} + cq_cmd_credit_return_ext > cq_cmd_credit_depth_ext) ?
    cq_cmd_credit_depth_ext : ({1'b0, cq_cmd_credit_count} + cq_cmd_credit_return_ext);
wire [4:0] cq_cmd_credit_next_ext =
    (cq_cmd_credit_plus_return_ext >= cq_cmd_credit_reserve_ext) ?
    (cq_cmd_credit_plus_return_ext - cq_cmd_credit_reserve_ext) : 5'd0;
wire rx_cq_cmd_can_accept = HAS_CQ_CMD_CREDIT ?
                            (!s5_cpl_en || cq_cmd_credit_has_space) :
                            s5_cq_can_accept;

wire [31:0] pay_awaddr;
wire [7:0] pay_awlen;
wire [2:0] pay_awsize;
wire [1:0] pay_awburst;
wire pay_awvalid;
wire pay_awready;
wire [63:0] pay_wdata;
wire [7:0] pay_wstrb;
wire pay_wlast;
wire pay_wvalid;
wire pay_wready;
wire [1:0] pay_bresp;
wire pay_bvalid;
wire pay_bready;

wire [31:0] cqe_awaddr;
wire [7:0] cqe_awlen;
wire [2:0] cqe_awsize;
wire [1:0] cqe_awburst;
wire cqe_awvalid;
wire cqe_awready;
wire [63:0] cqe_wdata;
wire [7:0] cqe_wstrb;
wire cqe_wlast;
wire cqe_wvalid;
wire cqe_wready;
wire [1:0] cqe_bresp;
wire cqe_bvalid;
wire cqe_bready;

wire [31:0] txc_awaddr;
wire [7:0] txc_awlen;
wire [2:0] txc_awsize;
wire [1:0] txc_awburst;
wire txc_awvalid;
wire txc_awready;
wire [63:0] txc_wdata;
wire [7:0] txc_wstrb;
wire txc_wlast;
wire txc_wvalid;
wire txc_wready;
wire [1:0] txc_bresp;
wire txc_bvalid;
wire txc_bready;

wire [31:0] cq_single_awaddr;
wire [7:0] cq_single_awlen;
wire [2:0] cq_single_awsize;
wire [1:0] cq_single_awburst;
wire cq_single_awvalid;
wire cq_single_awready;
wire [63:0] cq_single_wdata;
wire [7:0] cq_single_wstrb;
wire cq_single_wlast;
wire cq_single_wvalid;
wire cq_single_wready;
wire [1:0] cq_single_bresp;
wire cq_single_bvalid;
wire cq_single_bready;

wire use_tx_cqe_axi = tx_cqe_busy_raw;
wire [31:0] legacy_comb_cqe_awaddr = use_tx_cqe_axi ? txc_awaddr : cqe_awaddr;
wire [7:0] legacy_comb_cqe_awlen = use_tx_cqe_axi ? txc_awlen : cqe_awlen;
wire [2:0] legacy_comb_cqe_awsize = use_tx_cqe_axi ? txc_awsize : cqe_awsize;
wire [1:0] legacy_comb_cqe_awburst = use_tx_cqe_axi ? txc_awburst : cqe_awburst;
wire legacy_comb_cqe_awvalid = use_tx_cqe_axi ? txc_awvalid : cqe_awvalid;
wire [63:0] legacy_comb_cqe_wdata = use_tx_cqe_axi ? txc_wdata : cqe_wdata;
wire [7:0] legacy_comb_cqe_wstrb = use_tx_cqe_axi ? txc_wstrb : cqe_wstrb;
wire legacy_comb_cqe_wlast = use_tx_cqe_axi ? txc_wlast : cqe_wlast;
wire legacy_comb_cqe_wvalid = use_tx_cqe_axi ? txc_wvalid : cqe_wvalid;
wire legacy_comb_cqe_bready = use_tx_cqe_axi ? txc_bready : cqe_bready;
wire [31:0] comb_cqe_awaddr = HAS_CQ_SINGLE_WRITER ? cq_single_awaddr : legacy_comb_cqe_awaddr;
wire [7:0] comb_cqe_awlen = HAS_CQ_SINGLE_WRITER ? cq_single_awlen : legacy_comb_cqe_awlen;
wire [2:0] comb_cqe_awsize = HAS_CQ_SINGLE_WRITER ? cq_single_awsize : legacy_comb_cqe_awsize;
wire [1:0] comb_cqe_awburst = HAS_CQ_SINGLE_WRITER ? cq_single_awburst : legacy_comb_cqe_awburst;
wire comb_cqe_awvalid = HAS_CQ_SINGLE_WRITER ? cq_single_awvalid : legacy_comb_cqe_awvalid;
wire [63:0] comb_cqe_wdata = HAS_CQ_SINGLE_WRITER ? cq_single_wdata : legacy_comb_cqe_wdata;
wire [7:0] comb_cqe_wstrb = HAS_CQ_SINGLE_WRITER ? cq_single_wstrb : legacy_comb_cqe_wstrb;
wire comb_cqe_wlast = HAS_CQ_SINGLE_WRITER ? cq_single_wlast : legacy_comb_cqe_wlast;
wire comb_cqe_wvalid = HAS_CQ_SINGLE_WRITER ? cq_single_wvalid : legacy_comb_cqe_wvalid;
wire comb_cqe_bready = HAS_CQ_SINGLE_WRITER ? cq_single_bready : legacy_comb_cqe_bready;
wire comb_cqe_busy = HAS_CQ_SINGLE_WRITER ? cq_single_busy : (tx_cqe_busy_raw | cqe_busy_raw);

wire comb_cqe_awready;
wire comb_cqe_wready;
wire [1:0] comb_cqe_bresp;
wire comb_cqe_bvalid;
assign txc_awready = (!HAS_CQ_SINGLE_WRITER && use_tx_cqe_axi) ? comb_cqe_awready : 1'b0;
assign txc_wready = (!HAS_CQ_SINGLE_WRITER && use_tx_cqe_axi) ? comb_cqe_wready : 1'b0;
assign txc_bresp = (!HAS_CQ_SINGLE_WRITER && use_tx_cqe_axi) ? comb_cqe_bresp : 2'b00;
assign txc_bvalid = (!HAS_CQ_SINGLE_WRITER && use_tx_cqe_axi) ? comb_cqe_bvalid : 1'b0;
assign cqe_awready = (!HAS_CQ_SINGLE_WRITER && !use_tx_cqe_axi) ? comb_cqe_awready : 1'b0;
assign cqe_wready = (!HAS_CQ_SINGLE_WRITER && !use_tx_cqe_axi) ? comb_cqe_wready : 1'b0;
assign cqe_bresp = (!HAS_CQ_SINGLE_WRITER && !use_tx_cqe_axi) ? comb_cqe_bresp : 2'b00;
assign cqe_bvalid = (!HAS_CQ_SINGLE_WRITER && !use_tx_cqe_axi) ? comb_cqe_bvalid : 1'b0;
assign cq_single_awready = HAS_CQ_SINGLE_WRITER ? comb_cqe_awready : 1'b0;
assign cq_single_wready = HAS_CQ_SINGLE_WRITER ? comb_cqe_wready : 1'b0;
assign cq_single_bresp = HAS_CQ_SINGLE_WRITER ? comb_cqe_bresp : 2'b00;
assign cq_single_bvalid = HAS_CQ_SINGLE_WRITER ? comb_cqe_bvalid : 1'b0;
assign cqe_done = HAS_CQ_SINGLE_WRITER ? cq_single_rx_done : cqe_done_raw;
assign cqe_error = HAS_CQ_SINGLE_WRITER ? cq_single_rx_error : cqe_error_raw;
assign cqe_full = HAS_CQ_SINGLE_WRITER ? cq_single_rx_full : 1'b0;
assign cqe_busy = HAS_CQ_SINGLE_WRITER ? cq_single_busy : cqe_busy_raw;
assign tx_cqe_done = HAS_CQ_SINGLE_WRITER ? cq_single_tx_done : tx_cqe_done_raw;
assign tx_cqe_error = HAS_CQ_SINGLE_WRITER ?
                      (cq_single_tx_error || cq_single_tx_full) : tx_cqe_error_raw;
assign tx_cqe_busy = HAS_CQ_SINGLE_WRITER ? 1'b0 : tx_cqe_busy_raw;

wire tx_busy;
wire tx_drain_idle;
wire ufc_tx_busy;
wire [`DMA_MAX_CH-1:0] tx_ch_busy_flat;
wire tx_event_valid;
wire [3:0] tx_event_ch;
wire [7:0] tx_event_status_code;
wire tx_event_inc_frame;
wire tx_event_inc_err;
wire tx_event_clear_start;
wire tx_event_clear_stop;
wire tx_desc_evt_valid;
wire [3:0] tx_desc_evt_ch;
wire [31:0] tx_desc_evt_rd_ptr;
wire tx_desc_evt_update_rd_ptr;
wire [7:0] tx_desc_evt_status_code;
wire tx_desc_evt_update_status;
wire tx_desc_evt_inc_err;
wire tx_desc_evt_clear_busy;
wire tx_desc_evt_set_busy;
wire [31:0] tx_araddr;
wire [7:0] tx_arlen;
wire [2:0] tx_arsize;
wire [1:0] tx_arburst;
wire tx_arvalid;
wire tx_arready;
wire tx_rready;
assign ingress_work_busy = queue_meta_valid || frame_queue_busy ||
                           (|queue_meta_used_flat) || (|queue_used_bytes_flat);
assign cq_work_busy = cqe_busy || tx_cqe_busy || cq_single_busy ||
                      tx_cqe_active || tx_cqe_req_valid ||
                      (cq_reserved_count != 0) || cq_reserve_dec_pending ||
                      (cq_cmd_credit_count != CQ_CMD_CREDIT_DEPTH) ||
                      (cq_cmd_credit_reserve_evt_q != 0) ||
                      (cq_cmd_credit_return_evt_q != 0);
wire core_work_busy = (rx_state != RX_IDLE) || (wr_state != WR_IDLE) ||
                      release_service_busy ||
                      (HAS_RX_AXIS_SKID && rx_front_tvalid) ||
                      ingress_work_busy_q || pay_busy ||
                      cq_work_busy_q || tx_busy || !tx_drain_idle ||
                      ufc_tx_busy || ufc_tx_valid || frame_drop_pending;
assign soft_reset_drain_idle_raw = !core_work_busy;
wire core_busy_raw = core_work_busy || soft_reset_quiesce;
wire axi_busy_raw = pay_busy | cqe_busy | tx_busy | tx_cqe_busy;

assign m_axi_araddr = tx_araddr;
assign m_axi_arlen = tx_arlen;
assign m_axi_arsize = tx_arsize;
assign m_axi_arburst = tx_arburst;
assign m_axi_arvalid = tx_arvalid;
assign tx_arready = m_axi_arready;
assign m_axi_rready = tx_rready;

wire ufc_tx_start;
wire [7:0] ufc_tx_opcode_cfg;
wire [15:0] ufc_tx_flow_id_cfg;
wire [31:0] ufc_tx_arg0_cfg;
wire [31:0] ufc_tx_arg1_cfg;
wire ufc_tx_clear_done;
wire ufc_tx_clear_busy_reject;
wire ufc_tx_done;
wire ufc_tx_busy_reject;
wire ufc_tx_done_event;
wire ufc_rx_clear_pending;
wire ufc_rx_clear_overrun;
wire ufc_rx_pending;
wire ufc_rx_overrun;
wire [7:0] ufc_rx_msg_opcode;
wire [15:0] ufc_rx_msg_flow_id;
wire [31:0] ufc_rx_msg_arg0;
wire [31:0] ufc_rx_msg_arg1;
wire ufc_rx_msg_event;
wire core_ufc_tx_valid;
wire core_ufc_tx_ready;
wire [7:0] core_ufc_tx_opcode;
wire [15:0] core_ufc_tx_flow_id;
wire [31:0] core_ufc_tx_arg0;
wire [31:0] core_ufc_tx_arg1;
wire fc_status_valid;
wire [3:0] fc_status_ch;
wire fc_status_pause;
wire fc_status_low;
wire fc_status_irq;
reg fc_status_commit_valid_q;
reg [3:0] fc_status_commit_ch_q;
reg fc_status_commit_pause_q;
reg fc_status_commit_low_q;
reg fc_status_commit_full_q;
reg fc_status_commit_afull_q;
wire resume_scan_req_valid;
wire [3:0] resume_scan_req_ch;
wire resume_scan_rsp_valid;
wire [3:0] resume_scan_rsp_ch;
wire [31:0] resume_scan_rsp_used;
wire [31:0] resume_scan_rsp_low_wm;
wire [31:0] resume_scan_rsp_size;
wire [15:0] resume_scan_rsp_flow_id;

generate
    if (HAS_RX_AXIS_SKID) begin : g_rx_axis_skid
        dma_axis_skid_buffer #(
            .DATA_WIDTH(512)
        ) u_rx_axis_skid (
            .clk(aclk),
            .rstn(aresetn),
            .soft_reset(core_soft_reset),
            .s_axis_tdata(rx_axis_tdata),
            .s_axis_tvalid(rx_axis_tvalid && rx_quiesce_input_open),
            .s_axis_tready(rx_skid_s_ready),
            .m_axis_tdata(rx_front_tdata),
            .m_axis_tvalid(rx_front_tvalid),
            .m_axis_tready(rx_front_tready)
        );
        assign rx_axis_tready = rx_skid_s_ready && rx_quiesce_input_open;
    end else begin : g_rx_axis_direct
        assign rx_front_tdata = rx_axis_tdata;
        assign rx_front_tvalid = rx_axis_tvalid;
        assign rx_axis_tready = rx_front_tready;
        assign rx_skid_s_ready = 1'b0;
    end
endgenerate

assign parser_in_valid = (rx_state == RX_IDLE) && rx_idle_parser_open &&
                         !release_service_busy && rx_front_tvalid;
assign parser_out_ready = (rx_state == RX_PARSE_WAIT);

assign rx_front_tready = (rx_state == RX_IDLE) ?
                         ((release_service_busy || !rx_idle_parser_open) ?
                             1'b0 : parser_in_ready) :
                         (rx_state == RX_COLLECT) ? queue_payload_tready :
                         (rx_state == RX_DROP) ? 1'b1 :
                         1'b0;

dma_axil_regs #(
    .TX_RD_MAX_OUTSTANDING(TX_RD_MAX_OUTSTANDING),
    .RX_WR_MAX_OUTSTANDING(RX_WR_MAX_OUTSTANDING),
    .DEFER_BUSY_SOFT_RESET(HAS_RX_MEM_ASYNC)
) u_regs(
    .clk(aclk),
    .rstn(aresetn),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .core_busy(core_busy_to_regs),
    .axi_busy(axi_busy_to_regs),
    .soft_reset_ready(soft_reset_ready),
    .soft_reset_quiescing(soft_reset_quiesce),
    .soft_reset_drain_done(soft_reset_drain_done),
    .cdc_protocol_error(cdc_protocol_error_status),
    .event_valid(event_to_regs_valid),
    .event_ch_valid(event_to_regs_ch_valid),
    .event_ch(event_to_regs_ch),
    .event_status_code(event_to_regs_status_code),
    .event_aligned_len(event_to_regs_aligned_len),
    .event_next_wr_ptr(event_to_regs_next_wr_ptr),
    .event_inc_frame(event_to_regs_inc_frame),
    .event_inc_drop(event_to_regs_inc_drop),
    .event_inc_err(event_to_regs_inc_err),
    .event_update_wr_ptr(event_to_regs_update_wr_ptr && event_to_regs_inc_frame),
    .event_irq_mask(event_to_regs_irq_mask),
    .event_global_header_err(event_to_regs_global_header_err),
    .fc_status_valid(fc_status_commit_valid_q),
    .fc_status_ch(fc_status_commit_ch_q),
    .fc_status_pause(fc_status_commit_pause_q),
    .fc_status_low(fc_status_commit_low_q),
    .fc_status_full(fc_status_commit_full_q),
    .fc_status_afull(fc_status_commit_afull_q),
    .fc_status_ovf(1'b0),
    .cq_commit_valid(cq_commit_valid),
    .cq_next_ptr(cq_commit_ptr),
    .rx_ch_busy_flat(rx_ch_busy_flat),
    .tx_ch_busy_flat(tx_ch_busy_flat),
    .tx_desc_enable_flat(tx_desc_enable_flat),
    .tx_event_valid(tx_event_valid),
    .tx_event_ch(tx_event_ch),
    .tx_event_status_code(tx_event_status_code),
    .tx_event_inc_frame(tx_event_inc_frame),
    .tx_event_inc_err(tx_event_inc_err),
    .tx_event_clear_start(tx_event_clear_start),
    .tx_event_clear_stop(tx_event_clear_stop),
    .tx_desc_event_valid(1'b0),
    .tx_desc_event_ch(4'h0),
    .tx_desc_event_rd_ptr(32'h0),
    .tx_desc_event_status_code(8'h0),
    .tx_desc_event_inc_err(1'b0),
    .tx_csr_wr_valid(tx_csr_wr_valid),
    .tx_csr_wr_ready(tx_csr_wr_ready),
    .tx_csr_wr_ch(tx_csr_wr_ch),
    .tx_csr_wr_off(tx_csr_wr_off),
    .tx_csr_wdata(tx_csr_wdata),
    .tx_csr_wstrb(tx_csr_wstrb),
    .tx_csr_bresp(tx_csr_bresp),
    .tx_csr_wr_rsp_valid(tx_csr_wr_rsp_valid),
    .tx_csr_wr_rsp_kind(tx_csr_wr_rsp_kind),
    .tx_csr_wr_rsp_code(tx_csr_wr_rsp_code),
    .tx_csr_global_err(tx_csr_global_err),
    .tx_csr_policy_irq(tx_csr_policy_irq),
    .tx_csr_rd_valid(tx_csr_rd_valid),
    .tx_csr_rd_ready(tx_csr_rd_ready),
    .tx_csr_rd_ch(tx_csr_rd_ch),
    .tx_csr_rd_off(tx_csr_rd_off),
    .tx_csr_rvalid(tx_csr_rvalid),
    .tx_csr_rdata(tx_csr_rdata),
    .tx_csr_rresp(tx_csr_rresp),
    .tx_tbl_irq_tx_completion(tx_tbl_irq_tx_completion),
    .tx_tbl_irq_axi_error(tx_tbl_irq_axi_error),
    .tx_desc_csr_wr_valid(tx_desc_csr_wr_valid),
    .tx_desc_csr_wr_ready(tx_desc_csr_wr_ready),
    .tx_desc_csr_wr_ch(tx_desc_csr_wr_ch),
    .tx_desc_csr_wr_off(tx_desc_csr_wr_off),
    .tx_desc_csr_wdata(tx_desc_csr_wdata),
    .tx_desc_csr_wstrb(tx_desc_csr_wstrb),
    .tx_desc_csr_bresp(tx_desc_csr_bresp),
    .tx_desc_csr_wr_rsp_valid(tx_desc_csr_wr_rsp_valid),
    .tx_desc_csr_wr_rsp_kind(tx_desc_csr_wr_rsp_kind),
    .tx_desc_csr_wr_rsp_code(tx_desc_csr_wr_rsp_code),
    .tx_desc_csr_rd_valid(tx_desc_csr_rd_valid),
    .tx_desc_csr_rd_ready(tx_desc_csr_rd_ready),
    .tx_desc_csr_rd_ch(tx_desc_csr_rd_ch),
    .tx_desc_csr_rd_off(tx_desc_csr_rd_off),
    .tx_desc_csr_rvalid(tx_desc_csr_rvalid),
    .tx_desc_csr_rdata(tx_desc_csr_rdata),
    .tx_desc_csr_rresp(tx_desc_csr_rresp),
    .rx_csr_wr_valid(rx_csr_wr_valid),
    .rx_csr_wr_ready(rx_csr_wr_ready),
    .rx_csr_wr_ch(rx_csr_wr_ch),
    .rx_csr_wr_off(rx_csr_wr_off),
    .rx_csr_wdata(rx_csr_wdata),
    .rx_csr_wstrb(rx_csr_wstrb),
    .rx_csr_bresp(rx_csr_bresp),
    .rx_csr_wr_rsp_valid(rx_csr_wr_rsp_valid),
    .rx_csr_wr_rsp_kind(rx_csr_wr_rsp_kind),
    .rx_csr_wr_rsp_code(rx_csr_wr_rsp_code),
    .rx_csr_rd_valid(rx_csr_rd_valid),
    .rx_csr_rd_ready(rx_csr_rd_ready),
    .rx_csr_rd_ch(rx_csr_rd_ch),
    .rx_csr_rd_off(rx_csr_rd_off),
    .rx_csr_rvalid(rx_csr_rvalid),
    .rx_csr_rdata(rx_csr_rdata),
    .rx_csr_rresp(rx_csr_rresp),
    .global_enable(global_enable),
    .rx_enable(rx_enable),
    .tx_enable(tx_enable),
    .irq_enable(irq_enable),
    .cq_base_l(cq_base_l),
    .cq_base_h(cq_base_h),
    .cq_size(cq_size),
    .cq_wr_ptr(cq_wr_ptr),
    .cq_rd_ptr(cq_rd_ptr),
    .rx_ctrl_flat(),
    .rx_cfg_flat(),
    .rx_base_l_flat(),
    .rx_base_h_flat(),
    .rx_size_flat(),
    .rx_max_len_flat(),
    .rx_wr_ptr_flat(),
    .rx_rd_ptr_flat(),
    .rx_used_flat(),
    .rx_high_wm_flat(),
    .rx_low_wm_flat(),
    .rx_user_flat(),
    .tx_ctrl_flat(),
    .tx_cfg_flat(),
    .tx_base_l_flat(),
    .tx_base_h_flat(),
    .tx_len_flat(),
    .tx_status_flat(),
    .tx_user_flat(),
    .tx_desc_ctrl_flat(),
    .tx_desc_base_l_flat(),
    .tx_desc_base_h_flat(),
    .tx_desc_size_flat(),
    .tx_desc_rd_ptr_flat(),
    .tx_desc_wr_ptr_flat(),
    .tx_desc_status_flat(),
    .ufc_enable(ufc_enable),
    .ufc_tx_start(ufc_tx_start),
    .ufc_tx_opcode_cfg(ufc_tx_opcode_cfg),
    .ufc_tx_flow_id_cfg(ufc_tx_flow_id_cfg),
    .ufc_tx_arg0_cfg(ufc_tx_arg0_cfg),
    .ufc_tx_arg1_cfg(ufc_tx_arg1_cfg),
    .ufc_tx_clear_done(ufc_tx_clear_done),
    .ufc_tx_clear_busy_reject(ufc_tx_clear_busy_reject),
    .ufc_tx_busy(ufc_tx_busy),
    .ufc_tx_done(ufc_tx_done),
    .ufc_tx_busy_reject(ufc_tx_busy_reject),
    .ufc_tx_done_event(ufc_tx_done_event),
    .ufc_rx_clear_pending(ufc_rx_clear_pending),
    .ufc_rx_clear_overrun(ufc_rx_clear_overrun),
    .ufc_rx_pending(ufc_rx_pending),
    .ufc_rx_overrun(ufc_rx_overrun),
    .ufc_rx_opcode(ufc_rx_msg_opcode),
    .ufc_rx_flow_id(ufc_rx_msg_flow_id),
    .ufc_rx_arg0(ufc_rx_msg_arg0),
    .ufc_rx_arg1(ufc_rx_msg_arg1),
    .ufc_rx_msg_event(ufc_rx_msg_event),
    .soft_reset_pending(axil_soft_reset_pending),
    .soft_reset_request_pulse(axil_soft_reset_request),
    .soft_reset_pulse(axil_soft_reset),
    .ch_reset_pulse(),
    .ch_reset_ch(),
    .irq(irq)
);

dma_tx_channel_table u_tx_channel_table(
    .clk(aclk),
    .rstn(aresetn),
    .global_soft_reset(core_soft_reset),
    .csr_wr_valid(tx_csr_wr_valid),
    .csr_wr_ready(tx_csr_wr_ready),
    .csr_wr_ch(tx_csr_wr_ch),
    .csr_wr_off(tx_csr_wr_off),
    .csr_wdata(tx_csr_wdata),
    .csr_wstrb(tx_csr_wstrb),
    .csr_bresp(tx_csr_bresp),
    .csr_wr_rsp_valid(tx_csr_wr_rsp_valid),
    .csr_wr_rsp_kind(tx_csr_wr_rsp_kind),
    .csr_wr_rsp_code(tx_csr_wr_rsp_code),
    .csr_global_err(tx_csr_global_err),
    .csr_policy_irq(tx_csr_policy_irq),
    .csr_rd_valid(tx_csr_rd_valid),
    .csr_rd_ready(tx_csr_rd_ready),
    .csr_rd_ch(tx_csr_rd_ch),
    .csr_rd_off(tx_csr_rd_off),
    .csr_rvalid(tx_csr_rvalid),
    .csr_rdata(tx_csr_rdata),
    .csr_rresp(tx_csr_rresp),
    .tx_event_valid(tx_event_valid),
    .tx_event_ch(tx_event_ch),
    .tx_event_status_code(tx_event_status_code),
    .tx_event_inc_frame(tx_event_inc_frame),
    .tx_event_inc_err(tx_event_inc_err),
    .tx_event_clear_start(tx_event_clear_start),
    .tx_event_clear_stop(tx_event_clear_stop),
    .tx_ch_busy_flat(tx_ch_busy_flat),
    .tx_desc_enable_flat(tx_desc_enable_flat),
    .irq_tx_completion(tx_tbl_irq_tx_completion),
    .irq_axi_error(tx_tbl_irq_axi_error),
    .tx_ctrl_flat(tx_ctrl_flat),
    .tx_cfg_flat(tx_cfg_flat),
    .tx_base_l_flat(tx_base_l_flat),
    .tx_base_h_flat(tx_base_h_flat),
    .tx_len_flat(tx_len_flat),
    .tx_status_flat(tx_status_flat),
    .tx_user_flat(tx_user_flat)
);

dma_rx_channel_table u_rx_channel_table(
    .clk(aclk),
    .rstn(aresetn),
    .global_soft_reset(core_soft_reset),
    .rx_ch_busy_flat(rx_ch_busy_flat),
    .csr_wr_valid(rx_csr_wr_valid),
    .csr_wr_ready(rx_csr_wr_ready),
    .csr_wr_ch(rx_csr_wr_ch),
    .csr_wr_off(rx_csr_wr_off),
    .csr_wdata(rx_csr_wdata),
    .csr_wstrb(rx_csr_wstrb),
    .csr_bresp(rx_csr_bresp),
    .csr_wr_rsp_valid(rx_csr_wr_rsp_valid),
    .csr_wr_rsp_kind(rx_csr_wr_rsp_kind),
    .csr_wr_rsp_code(rx_csr_wr_rsp_code),
    .ch_reset_pulse(axil_ch_reset),
    .ch_reset_ch(axil_ch_reset_ch),
    .resume_scan_req_valid(resume_scan_req_valid),
    .resume_scan_req_ch(resume_scan_req_ch),
    .resume_scan_rsp_valid(resume_scan_rsp_valid),
    .resume_scan_rsp_ch(resume_scan_rsp_ch),
    .resume_scan_rsp_used(resume_scan_rsp_used),
    .resume_scan_rsp_low_wm(resume_scan_rsp_low_wm),
    .resume_scan_rsp_size(resume_scan_rsp_size),
    .resume_scan_rsp_flow_id(resume_scan_rsp_flow_id),
    .consumer_release_valid(rx_consumer_release_valid),
    .consumer_release_ready(rx_consumer_release_ready),
    .consumer_release_ch(rx_consumer_release_ch),
    .consumer_release_delta(rx_consumer_release_delta),
    .consumer_release_ptr(rx_consumer_release_ptr),
    .csr_rd_valid(rx_csr_rd_valid),
    .csr_rd_ready(rx_csr_rd_ready),
    .csr_rd_ch(rx_csr_rd_ch),
    .csr_rd_off(rx_csr_rd_off),
    .csr_rvalid(rx_csr_rvalid),
    .csr_rdata(rx_csr_rdata),
    .csr_rresp(rx_csr_rresp),
    .event_valid(event_to_regs_valid),
    .event_ch_valid(event_to_regs_ch_valid),
    .event_ch(event_to_regs_ch),
    .event_status_code(event_to_regs_status_code),
    .event_aligned_len(event_to_regs_aligned_len),
    .event_next_wr_ptr(event_to_regs_next_wr_ptr),
    .event_inc_frame(event_to_regs_inc_frame),
    .event_inc_drop(event_to_regs_inc_drop),
    .event_inc_err(event_to_regs_inc_err),
    .event_update_wr_ptr(event_to_regs_update_wr_ptr && event_to_regs_inc_frame),
    .fc_status_valid(fc_status_commit_valid_q),
    .fc_status_ch(fc_status_commit_ch_q),
    .fc_status_pause(fc_status_commit_pause_q),
    .fc_status_low(fc_status_commit_low_q),
    .fc_status_full(fc_status_commit_full_q),
    .fc_status_afull(fc_status_commit_afull_q),
    .fc_status_ovf(1'b0),
    .rx_ctrl_flat(rx_ctrl_flat),
    .rx_cfg_flat(rx_cfg_flat),
    .rx_base_l_flat(rx_base_l_flat),
    .rx_base_h_flat(rx_base_h_flat),
    .rx_size_flat(rx_size_flat),
    .rx_max_len_flat(rx_max_len_flat),
    .rx_wr_ptr_flat(rx_wr_ptr_flat),
    .rx_rd_ptr_flat(rx_rd_ptr_flat),
    .rx_used_flat(rx_used_flat),
    .rx_high_wm_flat(rx_high_wm_flat),
    .rx_low_wm_flat(rx_low_wm_flat),
    .rx_user_flat(rx_user_flat)
);

dma_tx_desc_channel_table u_tx_desc_table(
    .clk(aclk),
    .rstn(aresetn),
    .global_soft_reset(core_soft_reset),
    .tx_desc_ch_reset_mask(tx_desc_ch_reset_mask),
    .tx_ch_busy_flat(tx_ch_busy_flat),
    .csr_wr_valid(tx_desc_csr_wr_valid),
    .csr_wr_ready(tx_desc_csr_wr_ready),
    .csr_wr_ch(tx_desc_csr_wr_ch),
    .csr_wr_off(tx_desc_csr_wr_off),
    .csr_wdata(tx_desc_csr_wdata),
    .csr_wstrb(tx_desc_csr_wstrb),
    .csr_bresp(tx_desc_csr_bresp),
    .csr_wr_rsp_valid(tx_desc_csr_wr_rsp_valid),
    .csr_wr_rsp_kind(tx_desc_csr_wr_rsp_kind),
    .csr_wr_rsp_code(tx_desc_csr_wr_rsp_code),
    .csr_rd_valid(tx_desc_csr_rd_valid),
    .csr_rd_ready(tx_desc_csr_rd_ready),
    .csr_rd_ch(tx_desc_csr_rd_ch),
    .csr_rd_off(tx_desc_csr_rd_off),
    .csr_rvalid(tx_desc_csr_rvalid),
    .csr_rdata(tx_desc_csr_rdata),
    .csr_rresp(tx_desc_csr_rresp),
    .tx_desc_enable_flat(tx_desc_enable_flat),
    .tx_desc_ready_flat(tx_desc_ready_flat),
    .tx_desc_ctx_req(tx_desc_ctx_req),
    .tx_desc_ctx_ch(tx_desc_ctx_ch),
    .tx_desc_ctx_valid(tx_desc_ctx_valid),
    .tx_desc_ctx_ctrl(tx_desc_ctx_ctrl),
    .tx_desc_ctx_base_l(tx_desc_ctx_base_l),
    .tx_desc_ctx_base_h(tx_desc_ctx_base_h),
    .tx_desc_ctx_size(tx_desc_ctx_size),
    .tx_desc_ctx_rd_ptr(tx_desc_ctx_rd_ptr),
    .tx_desc_ctx_wr_ptr(tx_desc_ctx_wr_ptr),
    .tx_desc_ctx_status(tx_desc_ctx_status),
    .tx_desc_ctx_err_cnt(tx_desc_ctx_err_cnt),
    .tx_desc_active_valid(tx_desc_active_valid),
    .tx_desc_active_ch(tx_desc_active_ch),
    .tx_desc_active_stop(tx_desc_active_stop),
    .tx_desc_evt_valid(tx_desc_evt_valid),
    .tx_desc_evt_ch(tx_desc_evt_ch),
    .tx_desc_evt_rd_ptr(tx_desc_evt_rd_ptr),
    .tx_desc_evt_update_rd_ptr(tx_desc_evt_update_rd_ptr),
    .tx_desc_evt_status_code(tx_desc_evt_status_code),
    .tx_desc_evt_update_status(tx_desc_evt_update_status),
    .tx_desc_evt_inc_err(tx_desc_evt_inc_err),
    .tx_desc_evt_clear_busy(tx_desc_evt_clear_busy),
    .tx_desc_evt_set_busy(tx_desc_evt_set_busy)
);

dma_ufc_mailbox u_ufc_mailbox(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .quiesce(soft_reset_quiesce),
    .enable(global_enable && ufc_enable),
    .tx_start(ufc_tx_start),
    .tx_cfg_opcode(ufc_tx_opcode_cfg),
    .tx_cfg_flow_id(ufc_tx_flow_id_cfg),
    .tx_cfg_arg0(ufc_tx_arg0_cfg),
    .tx_cfg_arg1(ufc_tx_arg1_cfg),
    .tx_clear_done(ufc_tx_clear_done),
    .tx_clear_busy_reject(ufc_tx_clear_busy_reject),
    .tx_busy(ufc_tx_busy),
    .tx_done(ufc_tx_done),
    .tx_busy_reject(ufc_tx_busy_reject),
    .tx_done_pulse(ufc_tx_done_event),
    .core_tx_valid(core_ufc_tx_valid),
    .core_tx_ready(core_ufc_tx_ready),
    .core_tx_opcode(core_ufc_tx_opcode),
    .core_tx_flow_id(core_ufc_tx_flow_id),
    .core_tx_arg0(core_ufc_tx_arg0),
    .core_tx_arg1(core_ufc_tx_arg1),
    .ufc_tx_valid(ufc_tx_valid),
    .ufc_tx_ready(ufc_tx_ready),
    .ufc_tx_opcode(ufc_tx_opcode),
    .ufc_tx_flow_id(ufc_tx_flow_id),
    .ufc_tx_arg0(ufc_tx_arg0),
    .ufc_tx_arg1(ufc_tx_arg1),
    .ufc_rx_valid(ufc_rx_valid),
    .ufc_rx_ready(ufc_rx_ready),
    .ufc_rx_opcode(ufc_rx_opcode),
    .ufc_rx_flow_id(ufc_rx_flow_id),
    .ufc_rx_arg0(ufc_rx_arg0),
    .ufc_rx_arg1(ufc_rx_arg1),
    .rx_clear_pending(ufc_rx_clear_pending),
    .rx_clear_overrun(ufc_rx_clear_overrun),
    .rx_pending(ufc_rx_pending),
    .rx_overrun(ufc_rx_overrun),
    .rx_msg_opcode(ufc_rx_msg_opcode),
    .rx_msg_flow_id(ufc_rx_msg_flow_id),
    .rx_msg_arg0(ufc_rx_msg_arg0),
    .rx_msg_arg1(ufc_rx_msg_arg1),
    .rx_msg_pulse(ufc_rx_msg_event)
);

dma_rx_parser_pipe u_parser(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .in_valid(parser_in_valid),
    .in_ready(parser_in_ready),
    .in_header_beat(rx_front_tdata),
    .out_valid(parser_out_valid),
    .out_ready(parser_out_ready),
    .out_header_ok(parser_pipe_ok),
    .out_version(parser_pipe_version),
    .out_header_len(parser_pipe_header_len),
    .out_traffic_class(parser_pipe_tc),
    .out_flow_id(parser_pipe_flow_id),
    .out_msg_id(parser_pipe_msg_id),
    .out_payload_len(parser_pipe_payload_len),
    .out_aligned_len(parser_pipe_aligned_len),
    .out_frame_seq(parser_pipe_frame_seq),
    .out_timestamp(parser_pipe_timestamp),
    .out_sample_count(parser_pipe_sample_count)
);

dma_rx_channel_match u_match(
    .traffic_class(parser_tc),
    .flow_id(parser_flow_id),
    .msg_id(parser_msg_id),
    .payload_len(parser_payload_len),
    .rx_ctrl_flat(rx_ctrl_flat),
    .rx_cfg_flat(rx_cfg_flat),
    .rx_size_flat(rx_size_flat),
    .rx_max_len_flat(rx_max_len_flat),
    .rx_wr_ptr_flat(rx_wr_ptr_flat),
    .match_valid(match_valid),
    .match_ch(match_ch),
    .match_policy(match_policy),
    .reject_code(reject_code),
    .reject_drop(reject_drop)
);

dma_rx_fc_ingress_bank #(
    .CHANNELS(`DMA_MAX_CH),
    .PAYLOAD_WORDS(`DMA_RX_FC_INGRESS_PAYLOAD_WORDS),
    .PAYLOAD_AW(`DMA_RX_FC_INGRESS_PAYLOAD_AW),
    .META_DEPTH(`DMA_RX_FC_INGRESS_META_DEPTH),
    .META_AW(`DMA_RX_FC_INGRESS_META_AW),
    .WIDE_READ_ENABLE(HAS_RX_WIDE_PAYLOAD)
) u_ingress_queue(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .ch_reset_valid(axil_ch_reset),
    .ch_reset_ch(axil_ch_reset_ch),
    .req_ch(ingress_req_ch),
    .req_aligned_len(ingress_req_aligned_len),
    .can_accept_frame(stream_queue_can_accept),
    .near_full(stream_queue_near_full),
    .full(stream_queue_full),
    .used_bytes_flat(stream_queue_used_bytes_flat),
    .meta_used_flat(stream_queue_meta_used_flat),
    .start_frame(stream_queue_start),
    .in_ch(admit_ch),
    .in_tc(admit_tc),
    .in_policy(admit_policy),
    .in_flow_id(admit_flow_id),
    .in_msg_id(admit_msg_id),
    .in_payload_len(admit_payload_len),
    .in_aligned_len(admit_aligned_len),
    .in_dst_addr(admit_dst_addr),
    .in_next_wr_ptr(admit_next_wr_ptr),
    .in_frame_seq(admit_frame_seq),
    .in_timestamp(admit_timestamp),
    .in_sample_count(admit_sample_count),
    .in_cpl_en(admit_cpl_en),
    .in_ring(admit_ring),
    .in_wrap_before(admit_wrap_before),
    .payload_tdata(rx_front_tdata),
    .payload_tvalid(stream_payload_tvalid),
    .payload_tready(stream_queue_payload_tready),
    .collect_done(stream_queue_collect_done),
    .meta_valid(stream_meta_valid),
    .meta_pop(stream_meta_pop),
    .out_ch(stream_queue_ch),
    .out_tc(stream_queue_tc),
    .out_policy(stream_queue_policy),
    .out_flow_id(stream_queue_flow_id),
    .out_msg_id(stream_queue_msg_id),
    .out_payload_len(stream_queue_payload_len),
    .out_aligned_len(stream_queue_aligned_len),
    .out_dst_addr(stream_queue_dst_addr),
    .out_next_wr_ptr(stream_queue_next_wr_ptr),
    .out_frame_seq(stream_queue_frame_seq),
    .out_timestamp(stream_queue_timestamp),
    .out_sample_count(stream_queue_sample_count),
    .out_cpl_en(stream_queue_cpl_en),
    .out_ring(stream_queue_ring),
    .out_wrap_before(stream_queue_wrap_before),
    .payload_rd_req(stream_pay_rd_req),
    .payload_rd_index(stream_pay_rd_index),
    .payload_rd_valid(stream_pay_rd_valid),
    .payload_rd_data(stream_pay_rd_data),
    .wide_payload_enable(stream_wide_payload_enable),
    .wide_payload_tvalid(stream_wide_payload_tvalid),
    .wide_payload_tready(stream_wide_payload_tready),
    .wide_payload_tdata(stream_wide_payload_tdata),
    .wide_payload_tkeep(stream_wide_payload_tkeep),
    .wide_payload_tlast(stream_wide_payload_tlast)
);

dma_rx_frame_shared_adapter #(
    .CH_NUM(`DMA_MAX_CH),
    .CH_ID_W(4),
    .BLOCK_NUM(`DMA_FRAME_POOL_BLOCK_NUM),
    .BLOCK_AW(`DMA_FRAME_POOL_BLOCK_AW),
    .CTX_DEPTH(`DMA_RX_FC_INGRESS_META_DEPTH),
    .CTX_AW(`DMA_RX_FC_INGRESS_META_AW),
    .PAYLOAD_AW(`DMA_RX_FC_INGRESS_PAYLOAD_AW),
    .WIDE_READ_ENABLE(HAS_RX_WIDE_PAYLOAD)
) u_frame_shared_adapter (
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .ch_reset_valid(axil_ch_reset),
    .ch_reset_ch(axil_ch_reset_ch),
    .req_ch(ingress_req_ch),
    .req_policy(ingress_req_policy),
    .req_aligned_len(ingress_req_aligned_len),
    .can_accept_frame(frame_queue_can_accept),
    .near_full(frame_queue_near_full),
    .full(frame_queue_full),
    .used_bytes_flat(frame_queue_used_bytes_flat),
    .meta_used_flat(frame_queue_meta_used_flat),
    .start_frame(frame_queue_start),
    .in_ch(admit_ch),
    .in_tc(admit_tc),
    .in_policy(admit_policy),
    .in_flow_id(admit_flow_id),
    .in_msg_id(admit_msg_id),
    .in_payload_len(admit_payload_len),
    .in_aligned_len(admit_aligned_len),
    .in_dst_addr(admit_dst_addr),
    .in_next_wr_ptr(admit_next_wr_ptr),
    .in_frame_seq(admit_frame_seq),
    .in_timestamp(admit_timestamp),
    .in_sample_count(admit_sample_count),
    .in_cpl_en(admit_cpl_en),
    .in_ring(admit_ring),
    .in_wrap_before(admit_wrap_before),
    .payload_tdata(rx_front_tdata),
    .payload_tvalid(frame_payload_tvalid),
    .payload_tready(frame_queue_payload_tready),
    .collect_done(frame_queue_collect_done),
    .meta_valid(frame_meta_valid),
    .meta_pop(frame_meta_pop),
    .out_ch(frame_queue_ch),
    .out_tc(frame_queue_tc),
    .out_policy(frame_queue_policy),
    .out_flow_id(frame_queue_flow_id),
    .out_msg_id(frame_queue_msg_id),
    .out_payload_len(frame_queue_payload_len),
    .out_aligned_len(frame_queue_aligned_len),
    .out_dst_addr(frame_queue_dst_addr),
    .out_next_wr_ptr(frame_queue_next_wr_ptr),
    .out_frame_seq(frame_queue_frame_seq),
    .out_timestamp(frame_queue_timestamp),
    .out_sample_count(frame_queue_sample_count),
    .out_cpl_en(frame_queue_cpl_en),
    .out_ring(frame_queue_ring),
    .out_wrap_before(frame_queue_wrap_before),
    .payload_rd_req(frame_pay_rd_req),
    .payload_rd_index(frame_pay_rd_index),
    .payload_rd_valid(frame_pay_rd_valid),
    .payload_rd_data(frame_pay_rd_data),
    .wide_payload_enable(frame_wide_payload_enable),
    .wide_payload_tvalid(frame_wide_payload_tvalid),
    .wide_payload_tready(frame_wide_payload_tready),
    .wide_payload_tdata(frame_wide_payload_tdata),
    .wide_payload_tkeep(frame_wide_payload_tkeep),
    .wide_payload_tlast(frame_wide_payload_tlast),
    .pool_free_count(frame_pool_free_count),
    .pool_alloc_count(frame_pool_alloc_count),
    .pool_committed_frame_count(frame_pool_committed_frame_count),
    .pool_dropped_frame_count(frame_pool_dropped_frame_count),
    .pool_overflow_sticky(frame_pool_overflow_sticky),
    .pool_leak_check_error(frame_pool_leak_check_error),
    .busy(frame_queue_busy),
    .drop_event_valid(frame_drop_event_valid),
    .drop_event_ch(frame_drop_event_ch)
);

dma_rx_ingress_source_selector #(
    .PAYLOAD_AW(`DMA_RX_FC_INGRESS_PAYLOAD_AW)
) u_ingress_source_selector (
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .meta_take(queue_meta_take),
    .meta_pop(queue_pop),
    .s0_meta_valid(stream_meta_valid),
    .s0_meta_pop(stream_meta_pop),
    .s0_ch(stream_queue_ch),
    .s0_tc(stream_queue_tc),
    .s0_policy(stream_queue_policy),
    .s0_flow_id(stream_queue_flow_id),
    .s0_msg_id(stream_queue_msg_id),
    .s0_payload_len(stream_queue_payload_len),
    .s0_aligned_len(stream_queue_aligned_len),
    .s0_dst_addr(stream_queue_dst_addr),
    .s0_next_wr_ptr(stream_queue_next_wr_ptr),
    .s0_frame_seq(stream_queue_frame_seq),
    .s0_timestamp(stream_queue_timestamp),
    .s0_sample_count(stream_queue_sample_count),
    .s0_cpl_en(stream_queue_cpl_en),
    .s0_ring(stream_queue_ring),
    .s0_wrap_before(stream_queue_wrap_before),
    .s0_payload_rd_req(stream_pay_rd_req),
    .s0_payload_rd_index(stream_pay_rd_index),
    .s0_payload_rd_valid(stream_pay_rd_valid),
    .s0_payload_rd_data(stream_pay_rd_data),
    .s0_wide_payload_enable(stream_wide_payload_enable),
    .s0_wide_payload_tvalid(stream_wide_payload_tvalid),
    .s0_wide_payload_tready(stream_wide_payload_tready),
    .s0_wide_payload_tdata(stream_wide_payload_tdata),
    .s0_wide_payload_tkeep(stream_wide_payload_tkeep),
    .s0_wide_payload_tlast(stream_wide_payload_tlast),
    .s1_meta_valid(frame_meta_valid),
    .s1_meta_pop(frame_meta_pop),
    .s1_ch(frame_queue_ch),
    .s1_tc(frame_queue_tc),
    .s1_policy(frame_queue_policy),
    .s1_flow_id(frame_queue_flow_id),
    .s1_msg_id(frame_queue_msg_id),
    .s1_payload_len(frame_queue_payload_len),
    .s1_aligned_len(frame_queue_aligned_len),
    .s1_dst_addr(frame_queue_dst_addr),
    .s1_next_wr_ptr(frame_queue_next_wr_ptr),
    .s1_frame_seq(frame_queue_frame_seq),
    .s1_timestamp(frame_queue_timestamp),
    .s1_sample_count(frame_queue_sample_count),
    .s1_cpl_en(frame_queue_cpl_en),
    .s1_ring(frame_queue_ring),
    .s1_wrap_before(frame_queue_wrap_before),
    .s1_payload_rd_req(frame_pay_rd_req),
    .s1_payload_rd_index(frame_pay_rd_index),
    .s1_payload_rd_valid(frame_pay_rd_valid),
    .s1_payload_rd_data(frame_pay_rd_data),
    .s1_wide_payload_enable(frame_wide_payload_enable),
    .s1_wide_payload_tvalid(frame_wide_payload_tvalid),
    .s1_wide_payload_tready(frame_wide_payload_tready),
    .s1_wide_payload_tdata(frame_wide_payload_tdata),
    .s1_wide_payload_tkeep(frame_wide_payload_tkeep),
    .s1_wide_payload_tlast(frame_wide_payload_tlast),
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
    .payload_rd_req(pay_rd_req),
    .payload_rd_index(pay_rd_index),
    .payload_rd_valid(pay_rd_valid),
    .payload_rd_data(pay_rd_data),
    .wide_payload_tvalid(queue_wide_payload_tvalid),
    .wide_payload_tready(queue_wide_payload_tready),
    .wide_payload_tdata(queue_wide_payload_tdata),
    .wide_payload_tkeep(queue_wide_payload_tkeep),
    .wide_payload_tlast(queue_wide_payload_tlast),
    .active_is_frame(queue_active_is_frame)
);

dma_rx_fc_ctrl u_fc_ctrl(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .enable(global_enable && rx_enable),
    .ufc_enable(ufc_enable),
    .queue_used_bytes(admit_used_after_release),
    .rx_ctrl_flat(rx_ctrl_flat),
    .rx_cfg_flat(rx_cfg_flat),
    .rx_size_flat(rx_size_flat),
    .rx_used_flat(shadow_used_flat),
    .rx_high_wm_flat(rx_high_wm_flat),
    .rx_low_wm_flat(rx_low_wm_flat),
    .enq_valid(queue_start),
    .enq_ch(admit_ch),
    .enq_policy(admit_policy),
    .enq_flow_id(admit_flow_id),
    .enq_aligned_len(admit_aligned_len),
    .enq_rx_ctrl(rx_ctrl_flat[admit_ch*32 +: 32]),
    .enq_high_wm(rx_high_wm_flat[admit_ch*32 +: 32]),
    .enq_low_wm(rx_low_wm_flat[admit_ch*32 +: 32]),
    .core_tx_valid(core_ufc_tx_valid),
    .core_tx_ready(core_ufc_tx_ready),
    .core_tx_opcode(core_ufc_tx_opcode),
    .core_tx_flow_id(core_ufc_tx_flow_id),
    .core_tx_arg0(core_ufc_tx_arg0),
    .core_tx_arg1(core_ufc_tx_arg1),
    .pause_active_flat(pause_active_flat),
    .ch_reset_valid(axil_ch_reset),
    .ch_reset_ch(axil_ch_reset_ch),
    .resume_scan_req_valid(resume_scan_req_valid),
    .resume_scan_req_ch(resume_scan_req_ch),
    .resume_scan_rsp_valid(resume_scan_rsp_valid),
    .resume_scan_rsp_ch(resume_scan_rsp_ch),
    .resume_scan_rsp_used(resume_scan_rsp_used),
    .resume_scan_rsp_low_wm(resume_scan_rsp_low_wm),
    .resume_scan_rsp_size(resume_scan_rsp_size),
    .resume_scan_rsp_flow_id(resume_scan_rsp_flow_id),
    .status_valid(fc_status_valid),
    .status_ch(fc_status_ch),
    .status_pause(fc_status_pause),
    .status_low(fc_status_low),
    .status_irq(fc_status_irq)
);

dma_tx_engine #(
    .TX_RD_MAX_OUTSTANDING(TX_RD_MAX_OUTSTANDING)
) u_tx_engine(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .quiesce(soft_reset_quiesce),
    .global_enable(global_enable),
    .tx_enable(tx_enable),
    .tx_ctrl_flat(tx_ctrl_flat),
    .tx_cfg_flat(tx_cfg_flat),
    .tx_base_l_flat(tx_base_l_flat),
    .tx_base_h_flat(tx_base_h_flat),
    .tx_len_flat(tx_len_flat),
    .tx_desc_enable_flat(tx_desc_enable_flat),
    .tx_desc_ready_flat(tx_desc_ready_flat),
    .tx_desc_ctx_req(tx_desc_ctx_req),
    .tx_desc_ctx_ch(tx_desc_ctx_ch),
    .tx_desc_ctx_valid(tx_desc_ctx_valid),
    .tx_desc_ctx_ctrl(tx_desc_ctx_ctrl),
    .tx_desc_ctx_base_l(tx_desc_ctx_base_l),
    .tx_desc_ctx_base_h(tx_desc_ctx_base_h),
    .tx_desc_ctx_size(tx_desc_ctx_size),
    .tx_desc_ctx_rd_ptr(tx_desc_ctx_rd_ptr),
    .tx_desc_ctx_wr_ptr(tx_desc_ctx_wr_ptr),
    .tx_desc_ctx_status(tx_desc_ctx_status),
    .tx_desc_ctx_err_cnt(tx_desc_ctx_err_cnt),
    .tx_desc_active_valid(tx_desc_active_valid),
    .tx_desc_active_ch(tx_desc_active_ch),
    .tx_desc_active_stop(tx_desc_active_stop),
    .cq_size(cq_size),
    .cq_wr_ptr(cq_wr_ptr),
    .cq_rd_ptr(cq_rd_ptr),
    .cq_reserved_count(cq_reserved_count),
    .cq_reserve_inc(tx_cq_reserve_inc),
    .busy(tx_busy),
    .drain_idle(tx_drain_idle),
    .tx_ch_busy_flat(tx_ch_busy_flat),
    .event_valid(tx_event_valid),
    .event_ch(tx_event_ch),
    .event_status_code(tx_event_status_code),
    .event_inc_frame(tx_event_inc_frame),
    .event_inc_err(tx_event_inc_err),
    .event_clear_start(tx_event_clear_start),
    .event_clear_stop(tx_event_clear_stop),
    .tx_desc_evt_valid(tx_desc_evt_valid),
    .tx_desc_evt_ch(tx_desc_evt_ch),
    .tx_desc_evt_rd_ptr(tx_desc_evt_rd_ptr),
    .tx_desc_evt_update_rd_ptr(tx_desc_evt_update_rd_ptr),
    .tx_desc_evt_status_code(tx_desc_evt_status_code),
    .tx_desc_evt_update_status(tx_desc_evt_update_status),
    .tx_desc_evt_inc_err(tx_desc_evt_inc_err),
    .tx_desc_evt_clear_busy(tx_desc_evt_clear_busy),
    .tx_desc_evt_set_busy(tx_desc_evt_set_busy),
    .cqe_req_valid(tx_cqe_req_valid),
    .cqe_req_ready(tx_cqe_req_ready),
    .cqe_ch(tx_cqe_req_ch),
    .cqe_tc(tx_cqe_req_tc),
    .cqe_policy(tx_cqe_req_policy),
    .cqe_flow_id(tx_cqe_req_flow_id),
    .cqe_msg_id(tx_cqe_req_msg_id),
    .cqe_addr(tx_cqe_req_addr),
    .cqe_len(tx_cqe_req_len),
    .cqe_aligned_len(tx_cqe_req_aligned_len),
    .cqe_frame_seq(tx_cqe_req_frame_seq),
    .cqe_status_code(tx_cqe_req_status_code),
    .cqe_flags(tx_cqe_req_flags),
    .m_axi_araddr(tx_araddr),
    .m_axi_arlen(tx_arlen),
    .m_axi_arsize(tx_arsize),
    .m_axi_arburst(tx_arburst),
    .m_axi_arvalid(tx_arvalid),
    .m_axi_arready(tx_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(tx_rready),
    .tx_axis_tdata(tx_axis_tdata),
    .tx_axis_tvalid(tx_axis_tvalid),
    .tx_axis_tready(tx_axis_tready)
);

`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
wire wide_payload_cpl_valid;
wire wide_payload_cpl_error;
wire [3:0] wide_payload_cpl_error_code;
wire wide_payload_busy;

assign pay_cpl_valid = wide_payload_cpl_valid;
assign pay_error = wide_payload_cpl_error;
assign pay_busy = wide_payload_busy;
assign pay_arbiter_busy = 1'b0;
assign pay_rd_req = 1'b0;
assign pay_rd_index = {RX_FC_INGRESS_PAYLOAD_AW{1'b0}};
assign pay_awaddr = 32'h0;
assign pay_awlen = 8'h0;
assign pay_awsize = 3'd3;
assign pay_awburst = 2'b01;
assign pay_awvalid = 1'b0;
assign pay_wdata = 64'h0;
assign pay_wstrb = 8'h0;
assign pay_wlast = 1'b0;
assign pay_wvalid = 1'b0;
assign pay_bready = 1'b0;

dma_axi_write_engine_512 #(
    .MAX_BURST_BEATS(`DMA_MAX_BURST_LEN),
    .MAX_OUTSTANDING(RX_WR_MAX_OUTSTANDING),
    .MAX_CMD_BYTES(4096)
) u_payload_writer_512 (
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .cmd_valid(pay_cmd_valid),
    .cmd_ready(pay_cmd_ready),
    .cmd_addr(active_dst_addr),
    .cmd_len(active_payload_len),
    .s_payload_tvalid(queue_wide_payload_tvalid),
    .s_payload_tready(queue_wide_payload_tready),
    .s_payload_tdata(queue_wide_payload_tdata),
    .s_payload_tkeep(queue_wide_payload_tkeep),
    .s_payload_tlast(queue_wide_payload_tlast),
    .s_payload_level(8'h0),
    .m_axi_awaddr(m_axi_rx_payload_awaddr),
    .m_axi_awlen(m_axi_rx_payload_awlen),
    .m_axi_awsize(m_axi_rx_payload_awsize),
    .m_axi_awburst(m_axi_rx_payload_awburst),
    .m_axi_awvalid(m_axi_rx_payload_awvalid),
    .m_axi_awready(m_axi_rx_payload_awready),
    .m_axi_wdata(m_axi_rx_payload_wdata),
    .m_axi_wstrb(m_axi_rx_payload_wstrb),
    .m_axi_wlast(m_axi_rx_payload_wlast),
    .m_axi_wvalid(m_axi_rx_payload_wvalid),
    .m_axi_wready(m_axi_rx_payload_wready),
    .m_axi_bresp(m_axi_rx_payload_bresp),
    .m_axi_bvalid(m_axi_rx_payload_bvalid),
    .m_axi_bready(m_axi_rx_payload_bready),
    .cpl_valid(wide_payload_cpl_valid),
    .cpl_ready(pay_cpl_ready),
    .cpl_error(wide_payload_cpl_error),
    .cpl_error_code(wide_payload_cpl_error_code),
    .busy(wide_payload_busy)
);
`elsif DMA_RX_MEM_ASYNC_PROFILE
wire async_source_rstn;
wire async_mem_rstn;
wire async_mem_soft_reset;
wire async_bridge_cmd_valid;
wire async_bridge_cmd_ready;
wire [31:0] async_bridge_cmd_addr;
wire [31:0] async_bridge_cmd_len;
wire [31:0] async_bridge_cmd_aligned_len;
wire [3:0] async_bridge_cmd_channel;
wire [7:0] async_bridge_cmd_tag;
wire async_bridge_payload_tvalid;
wire async_bridge_payload_tready;
wire [511:0] async_bridge_payload_tdata;
wire [63:0] async_bridge_payload_tkeep;
wire async_bridge_payload_tlast;
wire [5:0] async_bridge_payload_level;
wire async_writer_cpl_valid;
wire async_writer_cpl_ready;
wire async_writer_cpl_error;
wire [3:0] async_writer_cpl_error_code;
wire [7:0] async_source_cpl_tag;
wire async_bridge_busy;
wire async_bridge_protocol_error;
wire async_writer_busy;
wire async_mem_backend_busy;
wire async_mem_protocol_error;

assign pay_busy = async_bridge_busy;
assign pay_arbiter_busy = 1'b0;
assign pay_rd_req = 1'b0;
assign pay_rd_index = {RX_FC_INGRESS_PAYLOAD_AW{1'b0}};
assign pay_awaddr = 32'h0;
assign pay_awlen = 8'h0;
assign pay_awsize = 3'd3;
assign pay_awburst = 2'b01;
assign pay_awvalid = 1'b0;
assign pay_wdata = 64'h0;
assign pay_wstrb = 8'h0;
assign pay_wlast = 1'b0;
assign pay_wvalid = 1'b0;
assign pay_bready = 1'b0;

dma_reset_sync u_rx_payload_source_reset_sync (
    .clk(aclk),
    .arstn(aresetn),
    .rstn(async_source_rstn)
);

dma_reset_sync u_rx_payload_mem_reset_sync (
    .clk(mem_clk),
    .arstn(mem_aresetn),
    .rstn(async_mem_rstn)
);

dma_rx_payload_cdc_bridge #(
    .TAG_WIDTH(8),
    .CMD_FIFO_LOG2(2),
    .PAYLOAD_FIFO_LOG2(5),
    .CPL_FIFO_LOG2(2)
) u_rx_payload_cdc_bridge (
    .s_clk(aclk),
    .s_rst_n(async_source_rstn),
    .s_reset_request(soft_reset_mem_request),
    .s_soft_reset(core_soft_reset),
    .s_reset_done(soft_reset_mem_reset_done),
    .s_cmd_valid(pay_cmd_valid),
    .s_cmd_ready(pay_cmd_ready),
    .s_cmd_addr(active_dst_addr),
    .s_cmd_len(active_payload_len),
    .s_cmd_aligned_len(active_aligned_len),
    .s_cmd_channel(active_ch),
    .s_payload_tvalid(queue_wide_payload_tvalid),
    .s_payload_tready(queue_wide_payload_tready),
    .s_payload_tdata(queue_wide_payload_tdata),
    .s_payload_tkeep(queue_wide_payload_tkeep),
    .s_payload_tlast(queue_wide_payload_tlast),
    .s_cpl_valid(pay_cpl_valid),
    .s_cpl_ready(pay_cpl_ready),
    .s_cpl_error(pay_error),
    .s_cpl_error_code(),
    .s_cpl_tag(async_source_cpl_tag),
    .s_busy(async_bridge_busy),
    .s_protocol_error(async_bridge_protocol_error),
    .m_clk(mem_clk),
    .m_rst_n(async_mem_rstn),
    .m_backend_busy(async_mem_backend_busy),
    .m_protocol_error(async_mem_protocol_error),
    .m_soft_reset(async_mem_soft_reset),
    .m_cmd_valid(async_bridge_cmd_valid),
    .m_cmd_ready(async_bridge_cmd_ready),
    .m_cmd_addr(async_bridge_cmd_addr),
    .m_cmd_len(async_bridge_cmd_len),
    .m_cmd_aligned_len(async_bridge_cmd_aligned_len),
    .m_cmd_channel(async_bridge_cmd_channel),
    .m_cmd_tag(async_bridge_cmd_tag),
    .m_payload_tvalid(async_bridge_payload_tvalid),
    .m_payload_tready(async_bridge_payload_tready),
    .m_payload_tdata(async_bridge_payload_tdata),
    .m_payload_tkeep(async_bridge_payload_tkeep),
    .m_payload_tlast(async_bridge_payload_tlast),
    .m_payload_level(async_bridge_payload_level),
    .m_cpl_valid(async_writer_cpl_valid),
    .m_cpl_ready(async_writer_cpl_ready),
    .m_cpl_error(async_writer_cpl_error),
    .m_cpl_error_code(async_writer_cpl_error_code)
);

`ifdef DMA_RX_MEM_ASYNC64_PROFILE
wire async_serializer_tvalid;
wire async_serializer_tready;
wire [63:0] async_serializer_tdata;
wire [7:0] async_serializer_tkeep;
wire async_serializer_tlast;
wire [3:0] async_serializer_held_beats;
wire async_serializer_format_error;
wire async_serializer_busy;
wire [9:0] async_serializer_available_beats =
    ({4'h0, async_bridge_payload_level} << 3) +
    {6'h0, async_serializer_held_beats};

dma_rx_payload_serializer_512_to_64 u_rx_payload_serializer (
    .clk(mem_clk),
    .rstn(async_mem_rstn),
    .soft_reset(async_mem_soft_reset),
    .s_tvalid(async_bridge_payload_tvalid),
    .s_tready(async_bridge_payload_tready),
    .s_tdata(async_bridge_payload_tdata),
    .s_tkeep(async_bridge_payload_tkeep),
    .s_tlast(async_bridge_payload_tlast),
    .m_tvalid(async_serializer_tvalid),
    .m_tready(async_serializer_tready),
    .m_tdata(async_serializer_tdata),
    .m_tkeep(async_serializer_tkeep),
    .m_tlast(async_serializer_tlast),
    .held_beats(async_serializer_held_beats),
    .format_error(async_serializer_format_error),
    .busy(async_serializer_busy)
);

dma_axi_write_engine_64_stream #(
    .MAX_BURST_BEATS(`DMA_MAX_BURST_LEN),
    .MAX_OUTSTANDING(RX_WR_MAX_OUTSTANDING),
    .MAX_CMD_BYTES(4096),
    .USE_SOURCE_CREDIT(1)
) u_payload_writer_async64 (
    .clk(mem_clk),
    .rstn(async_mem_rstn),
    .soft_reset(async_mem_soft_reset),
    .cmd_valid(async_bridge_cmd_valid),
    .cmd_ready(async_bridge_cmd_ready),
    .cmd_addr(async_bridge_cmd_addr),
    .cmd_len(async_bridge_cmd_len),
    .s_payload_tvalid(async_serializer_tvalid),
    .s_payload_tready(async_serializer_tready),
    .s_payload_tdata(async_serializer_tdata),
    .s_payload_tkeep(async_serializer_tkeep),
    .s_payload_tlast(async_serializer_tlast),
    .s_payload_level(async_serializer_available_beats),
    .m_axi_awaddr(m_axi_rx_payload_awaddr),
    .m_axi_awlen(m_axi_rx_payload_awlen),
    .m_axi_awsize(m_axi_rx_payload_awsize),
    .m_axi_awburst(m_axi_rx_payload_awburst),
    .m_axi_awvalid(m_axi_rx_payload_awvalid),
    .m_axi_awready(m_axi_rx_payload_awready),
    .m_axi_wdata(m_axi_rx_payload_wdata),
    .m_axi_wstrb(m_axi_rx_payload_wstrb),
    .m_axi_wlast(m_axi_rx_payload_wlast),
    .m_axi_wvalid(m_axi_rx_payload_wvalid),
    .m_axi_wready(m_axi_rx_payload_wready),
    .m_axi_bresp(m_axi_rx_payload_bresp),
    .m_axi_bvalid(m_axi_rx_payload_bvalid),
    .m_axi_bready(m_axi_rx_payload_bready),
    .cpl_valid(async_writer_cpl_valid),
    .cpl_ready(async_writer_cpl_ready),
    .cpl_error(async_writer_cpl_error),
    .cpl_error_code(async_writer_cpl_error_code),
    .busy(async_writer_busy)
);
assign async_mem_backend_busy = async_writer_busy || async_serializer_busy;
assign async_mem_protocol_error = async_serializer_format_error;
assign cdc_protocol_error_status = async_bridge_protocol_error;
`else
dma_axi_write_engine_512 #(
    .MAX_BURST_BEATS(`DMA_MAX_BURST_LEN),
    .MAX_OUTSTANDING(RX_WR_MAX_OUTSTANDING),
    .MAX_CMD_BYTES(4096),
    .USE_SOURCE_CREDIT(0)
) u_payload_writer_async512 (
    .clk(mem_clk),
    .rstn(async_mem_rstn),
    .soft_reset(async_mem_soft_reset),
    .cmd_valid(async_bridge_cmd_valid),
    .cmd_ready(async_bridge_cmd_ready),
    .cmd_addr(async_bridge_cmd_addr),
    .cmd_len(async_bridge_cmd_len),
    .s_payload_tvalid(async_bridge_payload_tvalid),
    .s_payload_tready(async_bridge_payload_tready),
    .s_payload_tdata(async_bridge_payload_tdata),
    .s_payload_tkeep(async_bridge_payload_tkeep),
    .s_payload_tlast(async_bridge_payload_tlast),
    .s_payload_level({2'b00, async_bridge_payload_level}),
    .m_axi_awaddr(m_axi_rx_payload_awaddr),
    .m_axi_awlen(m_axi_rx_payload_awlen),
    .m_axi_awsize(m_axi_rx_payload_awsize),
    .m_axi_awburst(m_axi_rx_payload_awburst),
    .m_axi_awvalid(m_axi_rx_payload_awvalid),
    .m_axi_awready(m_axi_rx_payload_awready),
    .m_axi_wdata(m_axi_rx_payload_wdata),
    .m_axi_wstrb(m_axi_rx_payload_wstrb),
    .m_axi_wlast(m_axi_rx_payload_wlast),
    .m_axi_wvalid(m_axi_rx_payload_wvalid),
    .m_axi_wready(m_axi_rx_payload_wready),
    .m_axi_bresp(m_axi_rx_payload_bresp),
    .m_axi_bvalid(m_axi_rx_payload_bvalid),
    .m_axi_bready(m_axi_rx_payload_bready),
    .cpl_valid(async_writer_cpl_valid),
    .cpl_ready(async_writer_cpl_ready),
    .cpl_error(async_writer_cpl_error),
    .cpl_error_code(async_writer_cpl_error_code),
    .busy(async_writer_busy)
);
assign async_mem_backend_busy = async_writer_busy;
assign async_mem_protocol_error = 1'b0;
assign cdc_protocol_error_status = async_bridge_protocol_error;
`endif
`else
assign queue_wide_payload_tready = 1'b0;
assign pay_arbiter_busy = pay_busy;
assign pay_cpl_valid = legacy_pay_done;

dma_axi_write_engine #(
    .INDEX_WIDTH(RX_FC_INGRESS_PAYLOAD_AW),
    .MAX_OUTSTANDING(RX_WR_MAX_OUTSTANDING)
) u_payload_writer(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .cmd_valid(pay_cmd_valid),
    .cmd_ready(pay_cmd_ready),
    .cmd_addr(active_dst_addr),
    .cmd_len(active_payload_len),
    .done(legacy_pay_done),
    .error(pay_error),
    .rd_req(pay_rd_req),
    .rd_index(pay_rd_index),
    .rd_valid(pay_rd_valid),
    .rd_data(pay_rd_data),
    .m_axi_awaddr(pay_awaddr),
    .m_axi_awlen(pay_awlen),
    .m_axi_awsize(pay_awsize),
    .m_axi_awburst(pay_awburst),
    .m_axi_awvalid(pay_awvalid),
    .m_axi_awready(pay_awready),
    .m_axi_wdata(pay_wdata),
    .m_axi_wstrb(pay_wstrb),
    .m_axi_wlast(pay_wlast),
    .m_axi_wvalid(pay_wvalid),
    .m_axi_wready(pay_wready),
    .m_axi_bresp(pay_bresp),
    .m_axi_bvalid(pay_bvalid),
    .m_axi_bready(pay_bready),
    .busy(pay_busy)
);
`endif

generate
    if (HAS_CQ_SINGLE_WRITER) begin : g_cq_single_writer
        dma_cq_single_writer u_cq_single_writer(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .cq_base_l(cq_base_l),
    .cq_size(cq_size),
    .cq_rd_ptr(cq_rd_ptr),
    .cq_wr_ptr_sync(cq_wr_ptr),
    .rx_req_valid(HAS_CQ_SINGLE_WRITER && (wr_state == WR_CQE_CMD)),
    .rx_req_accept(cq_single_rx_accept),
    .rx_ch(active_ch),
    .rx_tc(active_tc),
    .rx_policy(active_policy),
    .rx_flow_id(active_flow_id),
    .rx_msg_id(active_msg_id),
    .rx_payload_addr(active_dst_addr),
    .rx_payload_len(active_payload_len),
    .rx_aligned_len(active_aligned_len),
    .rx_timestamp(active_timestamp),
    .rx_frame_seq(active_frame_seq),
    .rx_sample_count(active_sample_count),
    .rx_cqe_flags(active_cqe_flags),
    .rx_done(cq_single_rx_done),
    .rx_error(cq_single_rx_error),
    .rx_full(cq_single_rx_full),
    .tx_req_valid(HAS_CQ_SINGLE_WRITER && tx_cqe_req_valid && !tx_cqe_active),
    .tx_req_accept(cq_single_tx_accept),
    .tx_ch(tx_cqe_req_ch),
    .tx_tc(tx_cqe_req_tc),
    .tx_policy(tx_cqe_req_policy),
    .tx_flow_id(tx_cqe_req_flow_id),
    .tx_msg_id(tx_cqe_req_msg_id),
    .tx_payload_addr(tx_cqe_req_addr),
    .tx_payload_len(tx_cqe_req_len),
    .tx_aligned_len(tx_cqe_req_aligned_len),
    .tx_frame_seq(tx_cqe_req_frame_seq),
    .tx_status_code(tx_cqe_req_status_code),
    .tx_cqe_flags(tx_cqe_req_flags),
    .tx_done(cq_single_tx_done),
    .tx_error(cq_single_tx_error),
    .tx_full(cq_single_tx_full),
    .cq_commit_valid(cq_single_commit_valid),
    .cq_commit_ptr(cq_single_commit_ptr),
    .m_axi_awaddr(cq_single_awaddr),
    .m_axi_awlen(cq_single_awlen),
    .m_axi_awsize(cq_single_awsize),
    .m_axi_awburst(cq_single_awburst),
    .m_axi_awvalid(cq_single_awvalid),
    .m_axi_awready(cq_single_awready),
    .m_axi_wdata(cq_single_wdata),
    .m_axi_wstrb(cq_single_wstrb),
    .m_axi_wlast(cq_single_wlast),
    .m_axi_wvalid(cq_single_wvalid),
    .m_axi_wready(cq_single_wready),
    .m_axi_bresp(cq_single_bresp),
    .m_axi_bvalid(cq_single_bvalid),
    .m_axi_bready(cq_single_bready),
    .busy(cq_single_busy)
);
    end else begin : g_cq_single_writer_off
        assign cq_single_rx_accept = 1'b0;
        assign cq_single_tx_accept = 1'b0;
        assign cq_single_rx_done = 1'b0;
        assign cq_single_rx_error = 1'b0;
        assign cq_single_rx_full = 1'b0;
        assign cq_single_tx_done = 1'b0;
        assign cq_single_tx_error = 1'b0;
        assign cq_single_tx_full = 1'b0;
        assign cq_single_commit_valid = 1'b0;
        assign cq_single_commit_ptr = 32'h0;
        assign cq_single_awaddr = 32'h0;
        assign cq_single_awlen = 8'h0;
        assign cq_single_awsize = 3'h0;
        assign cq_single_awburst = 2'h0;
        assign cq_single_awvalid = 1'b0;
        assign cq_single_wdata = 64'h0;
        assign cq_single_wstrb = 8'h0;
        assign cq_single_wlast = 1'b0;
        assign cq_single_wvalid = 1'b0;
        assign cq_single_bready = 1'b0;
        assign cq_single_busy = 1'b0;
    end
endgenerate

dma_cq_writer u_cq_writer(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .start(HAS_CQ_SINGLE_WRITER ? 1'b0 : cqe_start),
    .ready(),
    .cqe_addr(cqe_addr),
    .status_code(`DMA_ST_FRAME_DONE),
    .traffic_class(active_tc),
    .policy(active_policy),
    .channel_id({4'h0, active_ch}),
    .direction(`DMA_CQE_DIR_RX),
    .cqe_flags(active_cqe_flags),
    .flow_id(active_flow_id),
    .msg_id(active_msg_id),
    .payload_addr(active_dst_addr),
    .payload_len(active_payload_len),
    .aligned_len(active_aligned_len),
    .timestamp(active_timestamp),
    .frame_seq(active_frame_seq),
    .sample_count(active_sample_count),
    .drop_count(16'h0),
    .overflow_count(16'h0),
    .done(cqe_done_raw),
    .error(cqe_error_raw),
    .m_axi_awaddr(cqe_awaddr),
    .m_axi_awlen(cqe_awlen),
    .m_axi_awsize(cqe_awsize),
    .m_axi_awburst(cqe_awburst),
    .m_axi_awvalid(cqe_awvalid),
    .m_axi_awready(cqe_awready),
    .m_axi_wdata(cqe_wdata),
    .m_axi_wstrb(cqe_wstrb),
    .m_axi_wlast(cqe_wlast),
    .m_axi_wvalid(cqe_wvalid),
    .m_axi_wready(cqe_wready),
    .m_axi_bresp(cqe_bresp),
    .m_axi_bvalid(cqe_bvalid),
    .m_axi_bready(cqe_bready),
    .busy(cqe_busy_raw)
);

dma_cq_writer u_tx_cq_writer(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .start(HAS_CQ_SINGLE_WRITER ? 1'b0 : tx_cqe_start),
    .ready(),
    .cqe_addr(cq_base_l + (cq_wr_ptr << 6)),
    .status_code(tx_cqe_req_status_code),
    .traffic_class(tx_cqe_req_tc),
    .policy(tx_cqe_req_policy),
    .channel_id({4'h0, tx_cqe_req_ch}),
    .direction(`DMA_CQE_DIR_TX),
    .cqe_flags(tx_cqe_req_flags),
    .flow_id(tx_cqe_req_flow_id),
    .msg_id(tx_cqe_req_msg_id),
    .payload_addr(tx_cqe_req_addr),
    .payload_len(tx_cqe_req_len),
    .aligned_len(tx_cqe_req_aligned_len),
    .timestamp(64'h0),
    .frame_seq(tx_cqe_req_frame_seq),
    .sample_count(32'h0),
    .drop_count(16'h0),
    .overflow_count(16'h0),
    .done(tx_cqe_done_raw),
    .error(tx_cqe_error_raw),
    .m_axi_awaddr(txc_awaddr),
    .m_axi_awlen(txc_awlen),
    .m_axi_awsize(txc_awsize),
    .m_axi_awburst(txc_awburst),
    .m_axi_awvalid(txc_awvalid),
    .m_axi_awready(txc_awready),
    .m_axi_wdata(txc_wdata),
    .m_axi_wstrb(txc_wstrb),
    .m_axi_wlast(txc_wlast),
    .m_axi_wvalid(txc_wvalid),
    .m_axi_wready(txc_wready),
    .m_axi_bresp(txc_bresp),
    .m_axi_bvalid(txc_bvalid),
    .m_axi_bready(txc_bready),
    .busy(tx_cqe_busy_raw)
);

dma_rx_write_arbiter u_write_arbiter(
    .clk(aclk),
    .rstn(aresetn),
    .soft_reset(core_soft_reset),
    .payload_busy(pay_arbiter_busy),
    .p_awaddr(pay_awaddr),
    .p_awlen(pay_awlen),
    .p_awsize(pay_awsize),
    .p_awburst(pay_awburst),
    .p_awvalid(pay_awvalid),
    .p_awready(pay_awready),
    .p_wdata(pay_wdata),
    .p_wstrb(pay_wstrb),
    .p_wlast(pay_wlast),
    .p_wvalid(pay_wvalid),
    .p_wready(pay_wready),
    .p_bresp(pay_bresp),
    .p_bvalid(pay_bvalid),
    .p_bready(pay_bready),
    .cqe_busy(comb_cqe_busy),
    .c_awaddr(comb_cqe_awaddr),
    .c_awlen(comb_cqe_awlen),
    .c_awsize(comb_cqe_awsize),
    .c_awburst(comb_cqe_awburst),
    .c_awvalid(comb_cqe_awvalid),
    .c_awready(comb_cqe_awready),
    .c_wdata(comb_cqe_wdata),
    .c_wstrb(comb_cqe_wstrb),
    .c_wlast(comb_cqe_wlast),
    .c_wvalid(comb_cqe_wvalid),
    .c_wready(comb_cqe_wready),
    .c_bresp(comb_cqe_bresp),
    .c_bvalid(comb_cqe_bvalid),
    .c_bready(comb_cqe_bready),
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
    .m_axi_bready(m_axi_bready)
);

task post_event;
    input valid;
    input ch_valid;
    input [3:0] ch;
    input [7:0] status;
    input [31:0] aligned_len;
    input [31:0] next_wr_ptr;
    input inc_frame;
    input inc_drop;
    input inc_err;
    input update_wr_ptr;
    input [15:0] irq_mask_bits;
    input global_header_err;
    begin
        event_valid <= valid;
        event_ch_valid <= ch_valid;
        event_ch <= ch;
        event_status_code <= status;
        event_aligned_len <= aligned_len;
        event_next_wr_ptr <= next_wr_ptr;
        event_inc_frame <= inc_frame;
        event_inc_drop <= inc_drop;
        event_inc_err <= inc_err;
        event_update_wr_ptr <= update_wr_ptr;
        event_irq_mask <= irq_mask_bits;
        event_global_header_err <= global_header_err;
    end
endtask

task post_rx_event;
    input valid;
    input ch_valid;
    input [3:0] ch;
    input [7:0] status;
    input [31:0] aligned_len;
    input [31:0] next_wr_ptr;
    input inc_frame;
    input inc_drop;
    input inc_err;
    input update_wr_ptr;
    input [15:0] irq_mask_bits;
    input global_header_err;
    begin
        rx_event_valid <= valid;
        rx_event_ch_valid <= ch_valid;
        rx_event_ch <= ch;
        rx_event_status_code <= status;
        rx_event_aligned_len <= aligned_len;
        rx_event_next_wr_ptr <= next_wr_ptr;
        rx_event_inc_frame <= inc_frame;
        rx_event_inc_drop <= inc_drop;
        rx_event_inc_err <= inc_err;
        rx_event_update_wr_ptr <= update_wr_ptr;
        rx_event_irq_mask <= irq_mask_bits;
        rx_event_global_header_err <= global_header_err;
    end
endtask

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn || core_soft_reset) begin
        fc_status_commit_valid_q <= 1'b0;
        fc_status_commit_ch_q <= 4'h0;
        fc_status_commit_pause_q <= 1'b0;
        fc_status_commit_low_q <= 1'b0;
        fc_status_commit_full_q <= 1'b0;
        fc_status_commit_afull_q <= 1'b0;
    end else begin
        fc_status_commit_valid_q <= fc_status_valid;
        if (fc_status_valid) begin
            fc_status_commit_ch_q <= fc_status_ch;
            fc_status_commit_pause_q <= fc_status_pause;
            fc_status_commit_low_q <= fc_status_low;
            fc_status_commit_full_q <= queue_full;
            fc_status_commit_afull_q <= queue_near_full;
        end
    end
end

always @(*) begin
    lookup_mask_valid_c = 1'b0;
    lookup_mask_ch_c = 4'hf;
    for (lookup_mask_i = 0; lookup_mask_i < `DMA_MAX_CH; lookup_mask_i = lookup_mask_i + 1) begin
        if (!lookup_mask_valid_c && lookup_busy_preload_mask_q[lookup_mask_i]) begin
            lookup_mask_valid_c = 1'b1;
            lookup_mask_ch_c = lookup_mask_i[3:0];
        end
    end
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn || core_soft_reset) begin
        core_busy_to_regs <= 1'b0;
        axi_busy_to_regs <= 1'b0;
        event_to_regs_valid <= 1'b0;
        event_to_regs_ch_valid <= 1'b0;
        event_to_regs_ch <= 4'h0;
        event_to_regs_status_code <= 8'h0;
        event_to_regs_aligned_len <= 32'h0;
        event_to_regs_next_wr_ptr <= 32'h0;
        event_to_regs_inc_frame <= 1'b0;
        event_to_regs_inc_drop <= 1'b0;
        event_to_regs_inc_err <= 1'b0;
        event_to_regs_update_wr_ptr <= 1'b0;
        event_to_regs_irq_mask <= 16'h0;
        event_to_regs_global_header_err <= 1'b0;
    end else begin
        core_busy_to_regs <= core_busy_raw;
        axi_busy_to_regs <= axi_busy_raw;
        event_to_regs_valid <= event_valid;
        event_to_regs_ch_valid <= event_ch_valid;
        event_to_regs_ch <= event_ch;
        event_to_regs_status_code <= event_status_code;
        event_to_regs_aligned_len <= event_aligned_len;
        event_to_regs_next_wr_ptr <= event_next_wr_ptr;
        event_to_regs_inc_frame <= event_inc_frame;
        event_to_regs_inc_drop <= event_inc_drop;
        event_to_regs_inc_err <= event_inc_err;
        event_to_regs_update_wr_ptr <= event_update_wr_ptr;
        event_to_regs_irq_mask <= event_irq_mask;
        event_to_regs_global_header_err <= event_global_header_err;
    end
end

integer ch_i;
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn || core_soft_reset) begin
        rx_state <= RX_IDLE;
        drop_beats_left <= 9'h0;
        violation_hold <= 1'b0;
        parser_ok <= 1'b0;
        parser_version <= 8'h0;
        parser_header_len <= 8'h0;
        parser_tc <= 4'h0;
        parser_flow_id <= 16'h0;
        parser_msg_id <= 16'h0;
        parser_payload_len <= 32'h0;
        parser_aligned_len <= 32'h0;
        parser_frame_seq <= 32'h0;
        parser_timestamp <= 64'h0;
        parser_sample_count <= 32'h0;
        lookup_busy_preload_mask_q <= {`DMA_MAX_CH{1'b0}};
        admit_valid <= 1'b0;
        admit_ch <= 4'h0;
        admit_tc <= 4'h0;
        admit_policy <= 4'h0;
        admit_frame_shared <= 1'b0;
        admit_flow_id <= 16'h0;
        admit_msg_id <= 16'h0;
        admit_payload_len <= 32'h0;
        admit_aligned_len <= 32'h0;
        admit_dst_addr <= 32'h0;
        admit_next_wr_ptr <= 32'h0;
        admit_frame_seq <= 32'h0;
        admit_timestamp <= 64'h0;
        admit_sample_count <= 32'h0;
        admit_cpl_en <= 1'b0;
        admit_ring <= 1'b0;
        admit_wrap_before <= 1'b0;
        admit_used_after_release <= 32'h0;
        admit_rd_ptr_changed <= 1'b0;
        admit_rx_rd_ptr <= 32'h0;
        admit_accept <= 1'b0;
        admit_ch_valid <= 1'b0;
        admit_inc_drop <= 1'b0;
        admit_inc_err <= 1'b0;
        admit_update_wr_ptr <= 1'b0;
        admit_global_header_err <= 1'b0;
        admit_status_code <= 8'h0;
        admit_irq_mask <= 16'h0;
        admit_queue_can_accept_q <= 1'b0;
        admit_check_ch_q <= 4'h0;
        admit_check_policy_q <= 4'h0;
        admit_check_aligned_len_q <= 32'h0;
        admit_check_frame_shared_q <= 1'b0;
        lookup_match_valid_q <= 1'b0;
        lookup_match_ch_q <= 4'h0;
        lookup_policy_q <= 4'h0;
        s1_valid <= 1'b0;
        s1_header_ok <= 1'b0;
        s1_match_valid <= 1'b0;
        s1_frame_shared <= 1'b0;
        s1_match_ch <= 4'h0;
        s1_tc <= 4'h0;
        s1_policy <= 4'h0;
        s1_flow_id <= 16'h0;
        s1_msg_id <= 16'h0;
        s1_payload_len <= 32'h0;
        s1_aligned_len <= 32'h0;
        s1_frame_seq <= 32'h0;
        s1_timestamp <= 64'h0;
        s1_sample_count <= 32'h0;
        s1_reject_code <= 8'h0;
        s1_reject_drop <= 1'b0;
        s2_valid <= 1'b0;
        s2_header_ok <= 1'b0;
        s2_match_valid <= 1'b0;
        s2_frame_shared <= 1'b0;
        s2_ch <= 4'h0;
        s2_tc <= 4'h0;
        s2_policy <= 4'h0;
        s2_flow_id <= 16'h0;
        s2_msg_id <= 16'h0;
        s2_payload_len <= 32'h0;
        s2_aligned_len <= 32'h0;
        s2_frame_seq <= 32'h0;
        s2_timestamp <= 64'h0;
        s2_sample_count <= 32'h0;
        s2_reject_code <= 8'h0;
        s2_reject_drop <= 1'b0;
        s2_ctrl <= 32'h0;
        s2_base_l <= 32'h0;
        s2_size <= 32'h0;
        s2_rx_rd_ptr <= 32'h0;
        s2_shadow_wr_ptr <= 32'h0;
        s2_shadow_rd_ptr <= 32'h0;
        s2_shadow_used <= 32'h0;
        s2_pause_active <= 1'b0;
        s2_ingress_can_accept <= 1'b0;
        s2_cq_can_accept <= 1'b0;
        s3_valid <= 1'b0;
        s3_header_ok <= 1'b0;
        s3_match_valid <= 1'b0;
        s3_frame_shared <= 1'b0;
        s3_ch <= 4'h0;
        s3_tc <= 4'h0;
        s3_policy <= 4'h0;
        s3_flow_id <= 16'h0;
        s3_msg_id <= 16'h0;
        s3_payload_len <= 32'h0;
        s3_aligned_len <= 32'h0;
        s3_frame_seq <= 32'h0;
        s3_timestamp <= 64'h0;
        s3_sample_count <= 32'h0;
        s3_reject_code <= 8'h0;
        s3_reject_drop <= 1'b0;
        s3_base_l <= 32'h0;
        s3_size <= 32'h0;
        s3_rx_rd_ptr <= 32'h0;
        s3_wr_ptr <= 32'h0;
        s3_rd_ptr <= 32'h0;
        s3_used_after_release <= 32'h0;
        s3_rd_ptr_changed <= 1'b0;
        s3_release_valid <= 1'b0;
        release_delta_q <= 32'h0;
        release_delta_valid_q <= 1'b0;
        s3_pause_violation <= 1'b0;
        s3_ingress_can_accept <= 1'b0;
        s3_cq_can_accept <= 1'b0;
        s3_cpl_en <= 1'b0;
        s4_valid <= 1'b0;
        s4_header_ok <= 1'b0;
        s4_match_valid <= 1'b0;
        s4_frame_shared <= 1'b0;
        s4_ch <= 4'h0;
        s4_tc <= 4'h0;
        s4_policy <= 4'h0;
        s4_flow_id <= 16'h0;
        s4_msg_id <= 16'h0;
        s4_payload_len <= 32'h0;
        s4_aligned_len <= 32'h0;
        s4_frame_seq <= 32'h0;
        s4_timestamp <= 64'h0;
        s4_sample_count <= 32'h0;
        s4_reject_code <= 8'h0;
        s4_reject_drop <= 1'b0;
        s4_base_l <= 32'h0;
        s4_size <= 32'h0;
        s4_rx_rd_ptr <= 32'h0;
        s4_wr_ptr <= 32'h0;
        s4_used_after_release <= 32'h0;
        s4_rd_ptr_changed <= 1'b0;
        s4_pause_violation <= 1'b0;
        s4_ingress_can_accept <= 1'b0;
        s4_cq_can_accept <= 1'b0;
        s4_cpl_en <= 1'b0;
        s4_free_total <= 32'h0;
        s4_tail_space <= 32'h0;
        s4_need_wrap <= 1'b0;
        s4_tail_fits <= 1'b0;
        s4_head_fits <= 1'b0;
        s5_valid <= 1'b0;
        s5_header_ok <= 1'b0;
        s5_match_valid <= 1'b0;
        s5_frame_shared <= 1'b0;
        s5_ch <= 4'h0;
        s5_tc <= 4'h0;
        s5_policy <= 4'h0;
        s5_flow_id <= 16'h0;
        s5_msg_id <= 16'h0;
        s5_payload_len <= 32'h0;
        s5_aligned_len <= 32'h0;
        s5_frame_seq <= 32'h0;
        s5_timestamp <= 64'h0;
        s5_sample_count <= 32'h0;
        s5_reject_code <= 8'h0;
        s5_reject_drop <= 1'b0;
        s5_base_l <= 32'h0;
        s5_rx_rd_ptr <= 32'h0;
        s5_wr_ptr <= 32'h0;
        s5_used_after_release <= 32'h0;
        s5_rd_ptr_changed <= 1'b0;
        s5_pause_violation <= 1'b0;
        s5_ingress_can_accept <= 1'b0;
        s5_cq_can_accept <= 1'b0;
        s5_cpl_en <= 1'b0;
        s5_dest_addr <= 32'h0;
        s5_next_wr_ptr <= 32'h0;
        s5_next_used <= 32'h0;
        s5_wrap_before <= 1'b0;
        s5_ddr_has_space <= 1'b0;
        s5_ddr_status <= 8'h0;
        release_pending_valid_q <= 1'b0;
        release_pending_ch_q <= 4'h0;
        release_pending_delta_q <= 32'h0;
        release_pending_ptr_q <= 32'h0;
        release_snapshot_valid_q <= 1'b0;
        release_snapshot_onehot_q <= 16'h0;
        release_snapshot_used_q <= 32'h0;
        release_snapshot_delta_q <= 32'h0;
        release_snapshot_ptr_q <= 32'h0;
        release_calc_valid_q <= 1'b0;
        release_calc_onehot_q <= 16'h0;
        release_calc_used_q <= 32'h0;
        release_calc_ptr_q <= 32'h0;
        shadow_init_active_q <= 1'b1;
        shadow_init_ch_q <= 4'h0;
        post_rx_event(1'b0, 1'b0, 4'h0, 8'h0, 32'h0, 32'h0, 1'b0, 1'b0, 1'b0, 1'b0, 16'h0, 1'b0);
    end else begin
        post_rx_event(1'b0, 1'b0, 4'h0, 8'h0, 32'h0, 32'h0, 1'b0, 1'b0, 1'b0, 1'b0, 16'h0, 1'b0);
        release_snapshot_valid_q <= 1'b0;
        release_calc_valid_q <= release_snapshot_valid_q;

        if (shadow_init_active_q) begin
            shadow_wr_ptr[shadow_init_ch_q] <= 32'h0;
            shadow_rd_ptr[shadow_init_ch_q] <= 32'h0;
            shadow_used[shadow_init_ch_q] <= 32'h0;
            if (shadow_init_ch_q == (`DMA_MAX_CH-1)) begin
                shadow_init_active_q <= 1'b0;
                shadow_init_ch_q <= 4'h0;
            end else begin
                shadow_init_ch_q <= shadow_init_ch_q + 1'b1;
            end
        end

        if (rx_consumer_release_fire) begin
            release_pending_valid_q <= 1'b1;
            release_pending_ch_q <= rx_consumer_release_ch;
            release_pending_delta_q <= rx_consumer_release_delta;
            release_pending_ptr_q <= rx_consumer_release_ptr;
        end

        if ((rx_state == RX_IDLE) && !shadow_init_active_q && release_pending_valid_q &&
            !release_snapshot_valid_q && !release_calc_valid_q) begin
            release_pending_valid_q <= 1'b0;
            release_snapshot_valid_q <= 1'b1;
            release_snapshot_onehot_q <= 16'h1 << release_pending_ch_q;
            release_snapshot_used_q <= shadow_used[release_pending_ch_q];
            release_snapshot_delta_q <= release_pending_delta_q;
            release_snapshot_ptr_q <= release_pending_ptr_q;
        end

        if (release_snapshot_valid_q) begin
            release_calc_onehot_q <= release_snapshot_onehot_q;
            release_calc_ptr_q <= release_snapshot_ptr_q;
            if (release_snapshot_delta_q <= release_snapshot_used_q)
                release_calc_used_q <= release_snapshot_used_q - release_snapshot_delta_q;
            else
                release_calc_used_q <= release_snapshot_used_q;
        end

        if (release_calc_valid_q) begin
            for (ch_i = 0; ch_i < `DMA_MAX_CH; ch_i = ch_i + 1) begin
                if (release_calc_onehot_q[ch_i]) begin
                    shadow_used[ch_i] <= release_calc_used_q;
                    shadow_rd_ptr[ch_i] <= release_calc_ptr_q;
                end
            end
        end
        if (axil_ch_reset) begin
            shadow_wr_ptr[axil_ch_reset_ch] <= 32'h0;
            shadow_rd_ptr[axil_ch_reset_ch] <= 32'h0;
            shadow_used[axil_ch_reset_ch] <= 32'h0;
        end
        case (rx_state)
        RX_IDLE: begin
            admit_frame_shared <= 1'b0;
            if (header_fire) begin
                rx_state <= RX_PARSE_WAIT;
            end
        end
        RX_PARSE_WAIT: begin
            if (parser_out_valid) begin
                parser_ok <= parser_pipe_ok;
                parser_version <= parser_pipe_version;
                parser_header_len <= parser_pipe_header_len;
                parser_tc <= parser_pipe_tc;
                parser_flow_id <= parser_pipe_flow_id;
                parser_msg_id <= parser_pipe_msg_id;
                parser_payload_len <= parser_pipe_payload_len;
                parser_aligned_len <= parser_pipe_aligned_len;
                parser_frame_seq <= parser_pipe_frame_seq;
                parser_timestamp <= parser_pipe_timestamp;
                parser_sample_count <= parser_pipe_sample_count;
                lookup_busy_preload_mask_q <= parser_pipe_ok ? lookup_busy_preload_mask_c : {`DMA_MAX_CH{1'b0}};
                rx_state <= RX_LOOKUP;
            end
        end
        RX_LOOKUP: begin
            if (!global_enable || !rx_enable) begin
                s1_valid <= 1'b0;
                s1_frame_shared <= 1'b0;
                rx_state <= RX_IDLE;
            end else if (HAS_RX_MATCH_PIPELINE) begin
                lookup_match_valid_q <= parser_ok && lookup_mask_valid_c;
                lookup_match_ch_q <= lookup_mask_ch_c;
                lookup_policy_q <= rx_cfg_flat[lookup_mask_ch_c*32 + 4 +: 4];
                rx_state <= RX_LOOKUP_PIPE;
            end else begin
                s1_valid <= 1'b1;
                s1_header_ok <= parser_ok;
                s1_match_valid <= parser_ok && match_valid;
                s1_frame_shared <= frame_shared_candidate;
                s1_match_ch <= match_ch;
                s1_tc <= parser_tc;
                s1_policy <= match_policy;
                s1_flow_id <= parser_flow_id;
                s1_msg_id <= parser_msg_id;
                s1_payload_len <= parser_payload_len;
                s1_aligned_len <= parser_aligned_len;
                s1_frame_seq <= parser_frame_seq;
                s1_timestamp <= parser_timestamp;
                s1_sample_count <= parser_sample_count;
                s1_reject_code <= parser_ok ? reject_code : `DMA_ST_HEADER_ERR;
                s1_reject_drop <= parser_ok && reject_drop;
                rx_state <= RX_CH_CTX;
            end
            admit_valid <= 1'b0;
        end
        RX_LOOKUP_PIPE: begin
            if (!global_enable || !rx_enable) begin
                s1_valid <= 1'b0;
                s1_frame_shared <= 1'b0;
                rx_state <= RX_IDLE;
            end else begin
                s1_valid <= 1'b1;
                s1_header_ok <= parser_ok;
                s1_match_valid <= lookup_match_valid_q;
                s1_frame_shared <=
                    (`DMA_ENABLE_FRAME_SHARED_POOL != 0) &&
                    parser_ok && lookup_match_valid_q &&
                    (parser_tc == `DMA_TC_FC) &&
                    (parser_payload_len != 0) &&
                    ((`DMA_FRAME_SHARED_CH_MASK & (16'h1 << lookup_match_ch_q)) != 16'h0);
                s1_match_ch <= lookup_match_ch_q;
                s1_tc <= parser_tc;
                s1_policy <= lookup_policy_q;
                s1_flow_id <= parser_flow_id;
                s1_msg_id <= parser_msg_id;
                s1_payload_len <= parser_payload_len;
                s1_aligned_len <= parser_aligned_len;
                s1_frame_seq <= parser_frame_seq;
                s1_timestamp <= parser_timestamp;
                s1_sample_count <= parser_sample_count;
                lookup_max_len_q <= rx_max_len_flat[lookup_match_ch_q*32 +: 32];
                lookup_size_q <= rx_size_flat[lookup_match_ch_q*32 +: 32];
                lookup_wr_ptr_q <= rx_wr_ptr_flat[lookup_match_ch_q*32 +: 32];
                rx_state <= RX_REJECT_EVAL;
            end
            admit_valid <= 1'b0;
        end
        RX_REJECT_EVAL: begin
                if (!s1_header_ok) begin
                    s1_reject_code <= `DMA_ST_HEADER_ERR;
                    s1_reject_drop <= 1'b0;
                end else if (!s1_match_valid) begin
                    s1_reject_code <= `DMA_ST_POLICY_REJECT;
                    s1_reject_drop <= 1'b0;
                end else if (!rx_policy_supported(s1_tc, s1_policy)) begin
                    s1_reject_code <= `DMA_ST_UNSUP_POLICY;
                    s1_reject_drop <= 1'b0;
                end else if ((lookup_max_len_q != 0) &&
                             (s1_payload_len > lookup_max_len_q)) begin
                    s1_reject_code <= `DMA_ST_FRAME_TOO_BIG;
                    s1_reject_drop <= 1'b1;
                end else if ((lookup_size_q != 0) &&
                             (s1_tc != `DMA_TC_FC) &&
                             (lookup_wr_ptr_q + s1_aligned_len > lookup_size_q) &&
                             (s1_policy != `DMA_RX_POL_RING_BUFFER)) begin
                    s1_reject_code <= `DMA_ST_BUFFER_FULL;
                    s1_reject_drop <= 1'b1;
                end else begin
                    s1_reject_code <= `DMA_ST_OK;
                    s1_reject_drop <= 1'b0;
                end
                rx_state <= RX_CH_CTX;
            admit_valid <= 1'b0;
        end
        RX_CH_CTX: begin
            s2_valid <= s1_valid;
            s2_header_ok <= s1_header_ok;
            s2_match_valid <= s1_match_valid;
            s2_frame_shared <= s1_frame_shared;
            s2_ch <= s1_match_ch;
            s2_tc <= s1_tc;
            s2_policy <= s1_policy;
            s2_flow_id <= s1_flow_id;
            s2_msg_id <= s1_msg_id;
            s2_payload_len <= s1_payload_len;
            s2_aligned_len <= s1_aligned_len;
            s2_frame_seq <= s1_frame_seq;
            s2_timestamp <= s1_timestamp;
            s2_sample_count <= s1_sample_count;
            s2_reject_code <= s1_reject_code;
            s2_reject_drop <= s1_reject_drop;
            s2_ctrl <= rx_ctrl_flat[s1_match_ch*32 +: 32];
            s2_base_l <= rx_base_l_flat[s1_match_ch*32 +: 32];
            s2_size <= rx_size_flat[s1_match_ch*32 +: 32];
            s2_rx_rd_ptr <= rx_rd_ptr_flat[s1_match_ch*32 +: 32];
            s2_shadow_wr_ptr <= shadow_wr_ptr[s1_match_ch];
            s2_shadow_rd_ptr <= shadow_rd_ptr[s1_match_ch];
            s2_shadow_used <= shadow_used[s1_match_ch];
            s2_pause_active <= pause_active_flat[s1_match_ch];
            s2_ingress_can_accept <= queue_can_accept;
            s2_cq_can_accept <= HAS_CQ_CMD_CREDIT ? 1'b1 :
                                (!rx_ctrl_flat[s1_match_ch*32 + `DMA_RX_CTRL_CPL_EN] || cq_has_space);
            rx_state <= RX_RELEASE_USED;
        end
        RX_RELEASE_USED: begin
            s3_valid <= s2_valid;
            s3_header_ok <= s2_header_ok;
            s3_match_valid <= s2_match_valid;
            s3_frame_shared <= s2_frame_shared;
            s3_ch <= s2_ch;
            s3_tc <= s2_tc;
            s3_policy <= s2_policy;
            s3_flow_id <= s2_flow_id;
            s3_msg_id <= s2_msg_id;
            s3_payload_len <= s2_payload_len;
            s3_aligned_len <= s2_aligned_len;
            s3_frame_seq <= s2_frame_seq;
            s3_timestamp <= s2_timestamp;
            s3_sample_count <= s2_sample_count;
            s3_reject_code <= s2_reject_code;
            s3_reject_drop <= s2_reject_drop;
            s3_base_l <= s2_base_l;
            s3_size <= s2_size;
            s3_rx_rd_ptr <= s2_rx_rd_ptr;
            s3_wr_ptr <= s2_shadow_wr_ptr;
            s3_rd_ptr <= s2_shadow_rd_ptr;
            s3_rd_ptr_changed <= (s2_rx_rd_ptr != s2_shadow_rd_ptr);
            s3_release_valid <= 1'b0;
            s3_used_after_release <= s2_shadow_used;
            release_delta_q <= 32'h0;
            release_delta_valid_q <= 1'b0;
            if (s2_rx_rd_ptr != s2_shadow_rd_ptr) begin
                if (s2_rx_rd_ptr >= s2_shadow_rd_ptr) begin
                    release_delta_q <= s2_rx_rd_ptr - s2_shadow_rd_ptr;
                    release_delta_valid_q <= 1'b1;
                end else if (s2_size != 0) begin
                    release_delta_q <= s2_size - s2_shadow_rd_ptr + s2_rx_rd_ptr;
                    release_delta_valid_q <= 1'b1;
                end
            end
            s3_pause_violation <= s2_header_ok && s2_match_valid && s2_pause_active &&
                                  (s2_policy == `DMA_RX_POL_QUEUE_WITH_FC);
            s3_ingress_can_accept <= s2_ingress_can_accept;
            s3_cq_can_accept <= s2_cq_can_accept;
            s3_cpl_en <= s2_ctrl[`DMA_RX_CTRL_CPL_EN];
            rx_state <= RX_RELEASE_CALC;
        end
        RX_RELEASE_CALC: begin
            s3_release_valid <= 1'b0;
            if (release_delta_valid_q && (release_delta_q <= s3_used_after_release)) begin
                s3_used_after_release <= s3_used_after_release - release_delta_q;
                s3_release_valid <= 1'b1;
            end
            rx_state <= RX_RING_FREE;
        end
        RX_RING_FREE: begin
            s4_valid <= s3_valid;
            s4_header_ok <= s3_header_ok;
            s4_match_valid <= s3_match_valid;
            s4_frame_shared <= s3_frame_shared;
            s4_ch <= s3_ch;
            s4_tc <= s3_tc;
            s4_policy <= s3_policy;
            s4_flow_id <= s3_flow_id;
            s4_msg_id <= s3_msg_id;
            s4_payload_len <= s3_payload_len;
            s4_aligned_len <= s3_aligned_len;
            s4_frame_seq <= s3_frame_seq;
            s4_timestamp <= s3_timestamp;
            s4_sample_count <= s3_sample_count;
            s4_reject_code <= s3_reject_code;
            s4_reject_drop <= s3_reject_drop;
            s4_base_l <= s3_base_l;
            s4_size <= s3_size;
            s4_rx_rd_ptr <= s3_rx_rd_ptr;
            s4_wr_ptr <= s3_wr_ptr;
            s4_used_after_release <= s3_used_after_release;
            s4_rd_ptr_changed <= s3_rd_ptr_changed;
            s4_pause_violation <= s3_pause_violation;
            s4_ingress_can_accept <= s3_ingress_can_accept;
            s4_cq_can_accept <= s3_cq_can_accept;
            s4_cpl_en <= s3_cpl_en;
            s4_free_total <= (s3_size > s3_used_after_release) ? (s3_size - s3_used_after_release) : 32'h0;
            s4_tail_space <= (s3_size > s3_wr_ptr) ? (s3_size - s3_wr_ptr) : 32'h0;
            s4_need_wrap <= (s3_tc == `DMA_TC_FC) && (s3_size != 0) &&
                            ((s3_wr_ptr + s3_aligned_len) > s3_size);
            s4_tail_fits <= (s3_size == 0) || ((s3_wr_ptr + s3_aligned_len) <= s3_size);
            s4_head_fits <= (s3_aligned_len <= s3_rx_rd_ptr);
            rx_state <= RX_RING_NEXT;
        end
        RX_RING_NEXT: begin
            s5_valid <= s4_valid;
            s5_header_ok <= s4_header_ok;
            s5_match_valid <= s4_match_valid;
            s5_frame_shared <= s4_frame_shared;
            s5_ch <= s4_ch;
            s5_tc <= s4_tc;
            s5_policy <= s4_policy;
            s5_flow_id <= s4_flow_id;
            s5_msg_id <= s4_msg_id;
            s5_payload_len <= s4_payload_len;
            s5_aligned_len <= s4_aligned_len;
            s5_frame_seq <= s4_frame_seq;
            s5_timestamp <= s4_timestamp;
            s5_sample_count <= s4_sample_count;
            s5_reject_code <= s4_reject_code;
            s5_reject_drop <= s4_reject_drop;
            s5_base_l <= s4_base_l;
            s5_rx_rd_ptr <= s4_rx_rd_ptr;
            s5_wr_ptr <= s4_wr_ptr;
            s5_used_after_release <= s4_used_after_release;
            s5_rd_ptr_changed <= s4_rd_ptr_changed;
            s5_pause_violation <= s4_pause_violation;
            s5_ingress_can_accept <= s4_ingress_can_accept;
            s5_cq_can_accept <= s4_cq_can_accept;
            s5_cpl_en <= s4_cpl_en;
            s5_dest_addr <= s4_base_l + s4_wr_ptr;
            s5_next_wr_ptr <= s4_wr_ptr + s4_aligned_len;
            s5_next_used <= s4_used_after_release + s4_aligned_len;
            s5_wrap_before <= 1'b0;
            s5_ddr_has_space <= 1'b1;
            s5_ddr_status <= `DMA_ST_OK;
            if (s4_tc == `DMA_TC_FC) begin
                s5_ddr_has_space <= (s4_size == 0) ||
                                    ((s4_aligned_len <= s4_free_total) &&
                                     (s4_tail_fits || s4_head_fits));
                if ((s4_size != 0) && !(s4_aligned_len <= s4_free_total)) begin
                    s5_ddr_status <= `DMA_ST_DDR_QUEUE_FULL;
                end else if ((s4_size != 0) && !s4_tail_fits && !s4_head_fits) begin
                    s5_ddr_status <= `DMA_ST_WRAP_NOT_ALLOWED;
                end
                if ((s4_size != 0) && !s4_tail_fits && s4_head_fits) begin
                    s5_dest_addr <= s4_base_l;
                    s5_next_wr_ptr <= s4_aligned_len;
                    s5_wrap_before <= 1'b1;
                end else if ((s4_size != 0) && ((s4_wr_ptr + s4_aligned_len) == s4_size)) begin
                    s5_next_wr_ptr <= 32'h0;
                end
            end else if ((s4_policy == `DMA_RX_POL_RING_BUFFER) && (s4_size != 0)) begin
                if ((s4_wr_ptr + s4_aligned_len) >= s4_size)
                    s5_next_wr_ptr <= s4_wr_ptr + s4_aligned_len - s4_size;
            end
            admit_check_ch_q <= s4_ch;
            admit_check_policy_q <= s4_policy;
            admit_check_aligned_len_q <= s4_aligned_len;
            admit_check_frame_shared_q <= s4_frame_shared;
            rx_state <= RX_ADMIT_CHECK;
        end
        RX_ADMIT_CHECK: begin
            admit_valid <= 1'b0;
            admit_accept <= 1'b0;
            admit_queue_can_accept_q <= queue_can_accept;
            rx_state <= RX_ADMIT_FINAL;
        end
        RX_ADMIT_FINAL: begin
            admit_valid <= 1'b1;
            admit_accept <= 1'b0;
            admit_ch_valid <= s5_match_valid;
            admit_frame_shared <= s5_frame_shared;
            admit_ch <= s5_ch;
            admit_tc <= s5_tc;
            admit_policy <= s5_policy;
            admit_flow_id <= s5_flow_id;
            admit_msg_id <= s5_msg_id;
            admit_payload_len <= s5_payload_len;
            admit_aligned_len <= s5_aligned_len;
            admit_dst_addr <= s5_dest_addr;
            admit_next_wr_ptr <= s5_next_wr_ptr;
            admit_frame_seq <= s5_frame_seq;
            admit_timestamp <= s5_timestamp;
            admit_sample_count <= s5_sample_count;
            admit_cpl_en <= s5_cpl_en;
            admit_ring <= (s5_policy == `DMA_RX_POL_RING_BUFFER);
            admit_wrap_before <= s5_wrap_before;
            admit_used_after_release <= s5_used_after_release;
            admit_rd_ptr_changed <= s5_rd_ptr_changed;
            admit_rx_rd_ptr <= s5_rx_rd_ptr;
            admit_inc_drop <= 1'b0;
            admit_inc_err <= 1'b1;
            admit_update_wr_ptr <= 1'b0;
            admit_global_header_err <= 1'b0;
            admit_status_code <= `DMA_ST_OK;
            admit_irq_mask <= 16'h0;
            if (!s5_header_ok) begin
                admit_status_code <= `DMA_ST_HEADER_ERR;
                admit_ch_valid <= 1'b0;
                admit_global_header_err <= 1'b1;
                admit_irq_mask <= (16'h1 << `DMA_IRQ_HEADER_ERROR);
                rx_state <= RX_COMMIT;
            end else if (!s5_match_valid) begin
                admit_status_code <= `DMA_ST_POLICY_REJECT;
                admit_ch_valid <= 1'b0;
                admit_irq_mask <= (16'h1 << `DMA_IRQ_POLICY_REJECT);
                rx_state <= RX_COMMIT;
            end else if (s5_reject_code != `DMA_ST_OK) begin
                admit_status_code <= s5_reject_code;
                admit_inc_drop <= s5_reject_drop;
                admit_irq_mask <= s5_reject_drop ? (16'h1 << `DMA_IRQ_RX_OVERFLOW) :
                                                   (16'h1 << `DMA_IRQ_POLICY_REJECT);
                rx_state <= RX_COMMIT;
            end else if (s5_pause_violation) begin
                admit_status_code <= `DMA_ST_PAUSE_VIOL;
                admit_inc_drop <= 1'b1;
                admit_irq_mask <= (16'h1 << `DMA_IRQ_RX_OVERFLOW);
                rx_state <= RX_COMMIT;
            end else if (!rx_cq_cmd_can_accept) begin
                admit_status_code <= `DMA_ST_CQ_FULL;
                admit_inc_drop <= 1'b1;
                admit_irq_mask <= (16'h1 << `DMA_IRQ_CQ_FULL);
                rx_state <= RX_COMMIT;
            end else if (!s5_ddr_has_space) begin
                admit_status_code <= s5_ddr_status;
                admit_inc_drop <= 1'b1;
                admit_irq_mask <= (16'h1 << `DMA_IRQ_RX_OVERFLOW);
                rx_state <= RX_COMMIT;
            end else if (!admit_queue_can_accept_q && (s5_policy == `DMA_RX_POL_QUEUE_DROP_NEW)) begin
                admit_status_code <= `DMA_ST_DROP_NEW;
                admit_inc_drop <= 1'b1;
                admit_irq_mask <= (16'h1 << `DMA_IRQ_RX_OVERFLOW);
                rx_state <= RX_COMMIT;
            end else if (!admit_queue_can_accept_q) begin
                admit_valid <= 1'b0;
                rx_state <= RX_ADMIT_CHECK;
            end else begin
                admit_accept <= 1'b1;
                admit_inc_err <= 1'b0;
                rx_state <= RX_COMMIT;
            end
        end
        RX_COMMIT: begin
            if (admit_valid) begin
                if (admit_accept) begin
                    shadow_wr_ptr[admit_ch] <= admit_next_wr_ptr;
                    shadow_used[admit_ch] <= admit_used_after_release + admit_aligned_len;
                    if (admit_rd_ptr_changed)
                        shadow_rd_ptr[admit_ch] <= admit_rx_rd_ptr;
                    post_rx_event(1'b1, 1'b1, admit_ch, `DMA_ST_OK, 32'h0, 32'h0,
                                  1'b0, 1'b0, 1'b0, 1'b0, 16'h0, 1'b0);
                    rx_state <= (admit_payload_len == 0) ? RX_IDLE : RX_COLLECT;
                end else begin
                    post_rx_event(1'b1, admit_ch_valid, admit_ch, admit_status_code, 32'h0, 32'h0,
                                  1'b0, admit_inc_drop, admit_inc_err, admit_update_wr_ptr,
                                  admit_irq_mask, admit_global_header_err);
                    drop_beats_left <= admit_drop_beats_needed;
                    rx_state <= (admit_status_code == `DMA_ST_HEADER_ERR) ? RX_IDLE :
                                ((admit_payload_len == 0) ? RX_IDLE : RX_DROP);
                end
                admit_valid <= 1'b0;
            end else begin
                rx_state <= RX_IDLE;
            end
        end
        RX_COLLECT: begin
            if (queue_collect_done)
                rx_state <= RX_GAP;
        end
        RX_GAP: rx_state <= RX_IDLE;
        RX_DROP: begin
            if (rx_front_tvalid) begin
                if (drop_beats_left <= 1)
                    rx_state <= RX_IDLE;
                drop_beats_left <= drop_beats_left - 1'b1;
            end
        end
        default: rx_state <= RX_IDLE;
        endcase
    end
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn || core_soft_reset) begin
        wr_state <= WR_IDLE;
        active_ch <= 4'h0;
        active_tc <= 4'h0;
        active_policy <= 4'h0;
        active_flow_id <= 16'h0;
        active_msg_id <= 16'h0;
        active_payload_len <= 32'h0;
        active_aligned_len <= 32'h0;
        active_dst_addr <= 32'h0;
        active_next_wr_ptr <= 32'h0;
        active_frame_seq <= 32'h0;
        active_timestamp <= 64'h0;
        active_sample_count <= 32'h0;
        active_cpl_en <= 1'b0;
        active_ring <= 1'b0;
        active_wrap_before <= 1'b0;
        active_cq_next <= 32'h0;
        tx_cqe_active <= 1'b0;
        tx_cqe_next_ptr <= 32'h0;
        frame_drop_pending <= 1'b0;
        frame_drop_pending_ch <= 4'h0;
        cq_commit_ptr <= 32'h0;
        cq_reserved_count <= 32'h0;
        cq_reserve_dec_pending_cnt <= 2'd0;
        cq_cmd_credit_count <= CQ_CMD_CREDIT_DEPTH;
        cq_cmd_credit_reserve_evt_q <= 2'd0;
        cq_cmd_credit_return_evt_q <= 2'd0;
        post_event(1'b0, 1'b0, 4'h0, 8'h0, 32'h0, 32'h0, 1'b0, 1'b0, 1'b0, 1'b0, 16'h0, 1'b0);
        cq_commit_valid <= 1'b0;
    end else begin
        post_event(1'b0, 1'b0, 4'h0, 8'h0, 32'h0, 32'h0, 1'b0, 1'b0, 1'b0, 1'b0, 16'h0, 1'b0);
        cq_commit_valid <= 1'b0;
        cq_reserve_dec_pending_next = cq_reserve_dec_pending_cnt;
        if (cq_reserve_dec_pending)
            cq_reserve_dec_pending_next = cq_reserve_dec_pending_next - 1'b1;
        if (cq_reserve_dec_enqueue && (cq_reserve_dec_pending_next != 2'd3))
            cq_reserve_dec_pending_next = cq_reserve_dec_pending_next + 1'b1;
        cq_reserve_dec_pending_cnt <= cq_reserve_dec_pending_next;
        cq_cmd_credit_reserve_evt_q <= cq_cmd_credit_reserve_evt_c;
        cq_cmd_credit_return_evt_q <= cq_cmd_credit_return_evt_c;
        cq_cmd_credit_count <= cq_cmd_credit_next_ext[3:0];
        if (HAS_CQ_SINGLE_WRITER && cq_single_commit_valid) begin
            cq_commit_valid <= 1'b1;
            cq_commit_ptr <= cq_single_commit_ptr;
        end
        if (frame_drop_event_valid) begin
            frame_drop_pending <= 1'b1;
            frame_drop_pending_ch <= frame_drop_event_ch;
        end
        if (cq_reserve_inc_any && !cq_reserve_dec_pending) begin
            cq_reserved_count <= cq_reserved_count + 1'b1;
        end else if (!cq_reserve_inc_any && cq_reserve_dec_pending && (cq_reserved_count != 0)) begin
            cq_reserved_count <= cq_reserved_count - 1'b1;
        end
        if (tx_cqe_start) begin
            tx_cqe_active <= 1'b1;
            if (!HAS_CQ_SINGLE_WRITER)
                tx_cqe_next_ptr <= (cq_wr_ptr + 1 >= cq_size) ? 32'h0 : (cq_wr_ptr + 1);
        end else if (tx_cqe_active && tx_cqe_done) begin
            tx_cqe_active <= 1'b0;
            if (!tx_cqe_error && !HAS_CQ_SINGLE_WRITER) begin
                cq_commit_valid <= 1'b1;
                cq_commit_ptr <= tx_cqe_next_ptr;
            end
        end

        if (rx_event_valid)
            post_event(rx_event_valid, rx_event_ch_valid, rx_event_ch, rx_event_status_code,
                       rx_event_aligned_len, rx_event_next_wr_ptr, rx_event_inc_frame, rx_event_inc_drop,
                       rx_event_inc_err, rx_event_update_wr_ptr,
                       rx_event_irq_mask | (fc_status_irq ? (16'h1 << `DMA_IRQ_FC_PAUSE) : 16'h0),
                       rx_event_global_header_err);
        else if (frame_drop_pending || frame_drop_event_valid) begin
            post_event(1'b1, 1'b1,
                       frame_drop_pending ? frame_drop_pending_ch : frame_drop_event_ch,
                       `DMA_ST_DROP_NEW, 32'h0, 32'h0,
                       1'b0, 1'b1, 1'b0, 1'b0,
                       (16'h1 << `DMA_IRQ_RX_OVERFLOW), 1'b0);
            if (frame_drop_pending && frame_drop_event_valid) begin
                frame_drop_pending <= 1'b1;
                frame_drop_pending_ch <= frame_drop_event_ch;
            end else begin
                frame_drop_pending <= 1'b0;
            end
        end
        else if (fc_status_irq)
            post_event(1'b1, 1'b0, 4'h0, `DMA_ST_OK, 32'h0, 32'h0, 1'b0, 1'b0, 1'b0, 1'b0,
                       (16'h1 << `DMA_IRQ_FC_PAUSE), 1'b0);

        case (wr_state)
        WR_IDLE: begin
            if (queue_meta_valid) begin
                active_ch <= queue_ch;
                active_tc <= queue_tc;
                active_policy <= queue_policy;
                active_flow_id <= queue_flow_id;
                active_msg_id <= queue_msg_id;
                active_payload_len <= queue_payload_len;
                active_aligned_len <= queue_aligned_len;
                active_dst_addr <= queue_dst_addr;
                active_next_wr_ptr <= queue_next_wr_ptr;
                active_frame_seq <= queue_frame_seq;
                active_timestamp <= queue_timestamp;
                active_sample_count <= queue_sample_count;
                active_cpl_en <= queue_cpl_en;
                active_ring <= queue_ring;
                active_wrap_before <= queue_wrap_before;
                if (queue_payload_len == 0) begin
                    wr_state <= queue_cpl_en ? WR_CQE_CMD : WR_POP;
                end else begin
                    wr_state <= WR_PAY_CMD;
                end
            end
        end
        WR_PAY_CMD: begin
            if (pay_cmd_fire)
                wr_state <= WR_PAY_WAIT;
        end
        WR_PAY_WAIT: begin
            if (pay_cpl_fire) begin
                if (pay_error) begin
                    post_event(1'b1, 1'b1, active_ch, `DMA_ST_AXI_ERR, 32'h0, 32'h0, 1'b0, 1'b0, 1'b1, 1'b0,
                               (16'h1 << `DMA_IRQ_AXI_ERROR), 1'b0);
                    wr_state <= WR_POP;
                end else if (active_cpl_en) begin
                    wr_state <= WR_CQE_CMD;
                end else begin
                    post_event(1'b1, 1'b1, active_ch, `DMA_ST_FRAME_DONE, active_aligned_len, active_next_wr_ptr,
                               1'b1, 1'b0, 1'b0, 1'b1, 16'h0, 1'b0);
                    wr_state <= WR_POP;
                end
            end
        end
        WR_CQE_CMD: begin
            if (HAS_CQ_SINGLE_WRITER) begin
                if (cq_single_rx_accept)
                    wr_state <= WR_CQE_WAIT;
            end else begin
                active_cq_next <= (cq_wr_ptr + 1 >= cq_size) ? 0 : cq_wr_ptr + 1;
                if (cq_raw_full) begin
                    post_event(1'b1, 1'b1, active_ch, `DMA_ST_CQ_FULL, 32'h0, 32'h0, 1'b0, 1'b0, 1'b1, 1'b0,
                               (16'h1 << `DMA_IRQ_CQ_FULL), 1'b0);
                    wr_state <= WR_POP;
                end else begin
                    wr_state <= WR_CQE_WAIT;
                end
            end
        end
        WR_CQE_WAIT: begin
            if (cqe_done) begin
                if (HAS_CQ_SINGLE_WRITER && cqe_full) begin
                    post_event(1'b1, 1'b1, active_ch, `DMA_ST_CQ_FULL, 32'h0, 32'h0, 1'b0, 1'b0, 1'b1, 1'b0,
                               (16'h1 << `DMA_IRQ_CQ_FULL), 1'b0);
                end else if (cqe_error) begin
                    post_event(1'b1, 1'b1, active_ch, `DMA_ST_AXI_ERR, 32'h0, 32'h0, 1'b0, 1'b0, 1'b1, 1'b0,
                               (16'h1 << `DMA_IRQ_AXI_ERROR), 1'b0);
                end else begin
                    if (!HAS_CQ_SINGLE_WRITER) begin
                        cq_commit_valid <= 1'b1;
                        cq_commit_ptr <= active_cq_next;
                    end
                    post_event(1'b1, 1'b1, active_ch, `DMA_ST_FRAME_DONE, active_aligned_len, active_next_wr_ptr,
                               1'b1, 1'b0, 1'b0, 1'b1, (16'h1 << `DMA_IRQ_RX_COMPLETION), 1'b0);
                end
                wr_state <= WR_POP;
            end
        end
        WR_POP: begin
            wr_state <= WR_IDLE;
        end
        default: wr_state <= WR_IDLE;
        endcase
    end
end

endmodule
