`timescale 1ns/1ps
`include "dma_sim_def.vh"

module tb #(
    parameter integer HP0_SHARED_SERVICE = 1,
    parameter integer HP0_RESPONSE_LATENCY = 16,
    parameter integer HP0_SERVICE_PERCENT = 100,
    parameter integer MEM_PHASE_NS = 3
);

localparam integer RX_CH_CPL    = 0;
localparam integer RX_CH_NOCPL  = 1;
localparam integer TX_CH        = 0;
localparam integer MAX_TRACKED_FRAMES = 1024;
localparam integer MAX_TX_DESC  = 1024;
localparam integer SCENARIO_TIMEOUT_CYCLES = 12000000;
localparam integer PERF_FRAME_COUNT = 1024;
localparam integer PERF_CHANNELS = 16;

localparam [15:0] FLOW_ID_CPL   = 16'h2200;
localparam [15:0] FLOW_ID_NOCPL = 16'h2201;
localparam [15:0] FLOW_ID_TX    = 16'h2290;
localparam [15:0] STREAM_ID_TX  = 16'h3390;

localparam [31:0] TX_PAYLOAD_BASE = 32'h0000_0000;
localparam [31:0] TX_DESC_BASE    = 32'h0040_0000;
localparam [31:0] TX_DESC_SIZE    = 32'h0002_0000;
localparam [31:0] CQ_BASE         = 32'h0044_0000;
localparam [31:0] RX0_BASE        = 32'h0080_0000;
localparam [31:0] RX1_BASE        = 32'h0084_0000;
localparam [31:0] RX_RING_SIZE    = 32'h0080_0000;
localparam [31:0] PERF_CH_RING_BYTES = 32'h0004_0000;
localparam [31:0] PERF_CQ_ENTRIES = 32'd4096;
localparam [15:0] PERF_FLOW_BASE  = 16'h3000;

localparam [2:0] WR_IDLE        = 3'd0;
localparam [2:0] WR_CQE_CMD     = 3'd3;
localparam [2:0] CQ_ST_IDLE     = 3'd0;

reg clk;
reg rstn;
reg mem_clk;
reg mem_rstn;
reg [7:0] sys_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] ref_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] pkt_mem [0:`DMA_PKT_MEM_BYTES-1];

reg [511:0] rx_axis_tdata;
reg         rx_axis_tvalid;
wire        rx_axis_tready;
wire [511:0] dut_rx_axis_tdata;
wire         dut_rx_axis_tvalid;
wire         dut_rx_axis_tready;

wire [511:0] tx_axis_tdata;
wire         tx_axis_tvalid;
reg          tx_axis_tready;
wire         dut_tx_axis_tready;

reg          loopback_enable;
reg          loop_valid_q;
reg [511:0]  loop_data_q;

wire [31:0] s_axil_awaddr;
wire        s_axil_awvalid;
wire        s_axil_awready;
wire [31:0] s_axil_wdata;
wire [3:0]  s_axil_wstrb;
wire        s_axil_wvalid;
wire        s_axil_wready;
wire [1:0]  s_axil_bresp;
wire        s_axil_bvalid;
wire        s_axil_bready;
wire [31:0] s_axil_araddr;
wire        s_axil_arvalid;
wire        s_axil_arready;
wire [31:0] s_axil_rdata;
wire [1:0]  s_axil_rresp;
wire        s_axil_rvalid;
wire        s_axil_rready;

wire [31:0] dut_m_axi_awaddr;
wire [7:0]  dut_m_axi_awlen;
wire [2:0]  dut_m_axi_awsize;
wire [1:0]  dut_m_axi_awburst;
wire        dut_m_axi_awvalid;
wire        dut_m_axi_awready;
wire [63:0] dut_m_axi_wdata;
wire [7:0]  dut_m_axi_wstrb;
wire        dut_m_axi_wlast;
wire        dut_m_axi_wvalid;
wire        dut_m_axi_wready;
wire [1:0]  dut_m_axi_bresp;
wire        dut_m_axi_bvalid;
wire        dut_m_axi_bready;
wire [31:0] dut_m_axi_araddr;
wire [7:0]  dut_m_axi_arlen;
wire [2:0]  dut_m_axi_arsize;
wire [1:0]  dut_m_axi_arburst;
wire        dut_m_axi_arvalid;
wire        dut_m_axi_arready;
wire [63:0] dut_m_axi_rdata;
wire [1:0]  dut_m_axi_rresp;
wire        dut_m_axi_rlast;
wire        dut_m_axi_rvalid;
wire        dut_m_axi_rready;

wire [31:0] rx_mem_awaddr;
wire [7:0]  rx_mem_awlen;
wire [2:0]  rx_mem_awsize;
wire [1:0]  rx_mem_awburst;
wire        rx_mem_awvalid;
wire        rx_mem_awready;
wire [63:0] rx_mem_wdata;
wire [7:0]  rx_mem_wstrb;
wire        rx_mem_wlast;
wire        rx_mem_wvalid;
wire        rx_mem_wready;
wire [1:0]  rx_mem_bresp;
wire        rx_mem_bvalid;
wire        rx_mem_bready;

wire [31:0] mem_m_axi_awaddr;
wire [7:0]  mem_m_axi_awlen;
wire [2:0]  mem_m_axi_awsize;
wire [1:0]  mem_m_axi_awburst;
wire        mem_m_axi_awvalid;
wire        mem_m_axi_awready;
wire [63:0] mem_m_axi_wdata;
wire [7:0]  mem_m_axi_wstrb;
wire        mem_m_axi_wlast;
wire        mem_m_axi_wvalid;
wire        mem_m_axi_wready;
wire [1:0]  mem_m_axi_bresp;
wire        mem_m_axi_bvalid;
wire        mem_m_axi_bready;
wire [31:0] mem_m_axi_araddr;
wire [7:0]  mem_m_axi_arlen;
wire [2:0]  mem_m_axi_arsize;
wire [1:0]  mem_m_axi_arburst;
wire        mem_m_axi_arvalid;
wire        mem_m_axi_arready;
wire [63:0] mem_m_axi_rdata;
wire [1:0]  mem_m_axi_rresp;
wire        mem_m_axi_rlast;
wire        mem_m_axi_rvalid;
wire        mem_m_axi_rready;

wire        irq;

wire        ufc_tx_valid;
wire        ufc_tx_ready;
wire [7:0]  ufc_tx_opcode;
wire [15:0] ufc_tx_flow_id;
wire [31:0] ufc_tx_arg0;
wire [31:0] ufc_tx_arg1;
wire        ufc_rx_valid;
wire        ufc_rx_ready;
wire [7:0]  ufc_rx_opcode;
wire [15:0] ufc_rx_flow_id;
wire [31:0] ufc_rx_arg0;
wire [31:0] ufc_rx_arg1;

reg         stall_enable;
reg         stall_random_mode;
reg [7:0]   stall_aw_mod;
reg [7:0]   stall_w_mod;
reg [7:0]   stall_b_mod;
reg [31:0]  stall_lfsr;
reg [31:0]  stall_cycle_count;

reg         scenario_active;
reg [8*32-1:0] scenario_name_q;
reg [31:0]  scenario_seed_q;
reg [63:0]  scenario_cycles_q;
reg [31:0]  scenario_frame_count_q;
reg [31:0]  scenario_expected_cqe_q;
reg [31:0]  scenario_expected_tx_desc_q;
reg [31:0]  scenario_deadlock_q;

reg [63:0] rx_accept_beats_q;
reg [63:0] rx_accept_bytes_q;
reg [63:0] rx_tvalid_cycles_q;
reg [63:0] rx_tready_cycles_q;
reg [63:0] rx_fire_cycles_q;
reg [63:0] payload_write_bytes_q;
reg [63:0] payload_aw_bursts_q;
reg [63:0] payload_w_beats_q;
reg [63:0] axi_w_fire_cycles_q;
reg [63:0] cq_rx_req_q;
reg [63:0] cq_tx_req_q;
reg [63:0] cq_rx_accept_q;
reg [63:0] cq_tx_accept_q;
reg [63:0] cq_busy_cycles_q;
reg [63:0] cq_rx_full_q;
reg [63:0] cq_tx_full_q;
reg [63:0] cq_cqe_completed_q;
reg [63:0] cq_credit_stall_cycles_q;
reg [63:0] skid_hist_0_q;
reg [63:0] skid_hist_1_q;
reg [63:0] skid_hist_2_q;
reg [63:0] rx_frame_done_q;
reg [63:0] rx_frame_fail_q;
reg [63:0] rx_frame_drop_q;
reg [63:0] rx_event_ok_q;
reg [63:0] tx_req_lat_sum_q;
reg [63:0] tx_req_lat_cnt_q;
reg [63:0] tx_req_lat_max_q;
reg [63:0] rx_req_lat_sum_q;
reg [63:0] rx_req_lat_cnt_q;
reg [63:0] rx_req_lat_max_q;
reg        tx_req_pending_end_q;

reg [63:0] latency_sum_q;
reg [63:0] latency_min_q;
reg [63:0] latency_max_q;
reg [63:0] latency_count_q;
reg [63:0] dbg_pay_rd_req_q;
reg [63:0] dbg_pay_rd_valid_q;
reg [63:0] dbg_stream_rd_valid_q;
reg [63:0] dbg_frame_rd_valid_q;
reg [63:0] dbg_frame_pool_fire_q;
reg [63:0] dbg_w_run_q;
reg [63:0] dbg_w_run_max_q;

reg [31:0] exp_rx_base [0:PERF_CHANNELS-1];
reg [31:0] exp_rx_wr_ptr [0:PERF_CHANNELS-1];
reg [31:0] exp_rx_flow [0:PERF_CHANNELS-1];
reg        exp_rx_cpl [0:PERF_CHANNELS-1];

reg [31:0] frame_len_q [0:MAX_TRACKED_FRAMES-1];
reg [31:0] frame_src_q [0:MAX_TRACKED_FRAMES-1];
reg [31:0] frame_dst_q [0:MAX_TRACKED_FRAMES-1];
reg [3:0]  frame_ch_q [0:MAX_TRACKED_FRAMES-1];
integer frame_expected_count_q;

reg [63:0] lat_start_cycle_q [0:MAX_TRACKED_FRAMES-1];
reg [31:0] lat_payload_len_q [0:MAX_TRACKED_FRAMES-1];
reg [3:0]  lat_ch_q [0:MAX_TRACKED_FRAMES-1];
integer lat_head_q;
integer lat_tail_q;
integer lat_count_pending_q;

integer tx_desc_count_q;

reg        tx_req_waiting_q;
reg        tx_req_accepted_q;
reg [63:0] tx_req_start_cycle_q;
reg        rx_req_waiting_q;
reg [63:0] rx_req_start_cycle_q;

reg        prev_tx_cqe_req_valid_q;
reg        prev_wr_cqe_cmd_q;
reg        prev_cq_single_rx_full_q;
reg        prev_cq_single_tx_full_q;
reg [63:0] lat_cycles_q;

reg [8*32-1:0] tp_case_q;
integer tp_frames_q;
integer tp_payload_bytes_q;
reg tp_is_loopback_q;
reg tp_is_mixed_q;
reg tp_doorbell_pending_q;
reg tp_hw_started_q;
reg tp_hw_finished_q;
reg tp_steady_started_q;
reg tp_steady_finished_q;
reg [63:0] tp_global_cycle_q;
reg [63:0] tp_hw_start_cycle_q;
reg [63:0] tp_hw_end_cycle_q;
reg [63:0] tp_steady_start_cycle_q;
reg [63:0] tp_steady_end_cycle_q;
reg [63:0] tp_expected_payload_bytes_q;
reg [63:0] tp_rx_payload_bytes_q;
reg [63:0] tp_main_read_bytes_q;
reg [63:0] tp_main_write_bytes_q;
reg [63:0] tp_main_ar_bursts_q;
reg [63:0] tp_main_aw_bursts_q;
reg [63:0] tp_rx_aw_bursts_q;
reg [63:0] tp_rx_axis_valid_q;
reg [63:0] tp_rx_axis_ready_q;
reg [63:0] tp_rx_axis_fire_q;
reg [63:0] tp_tx_axis_valid_q;
reg [63:0] tp_tx_axis_ready_q;
reg [63:0] tp_tx_axis_fire_q;
reg [63:0] tp_rx_cqe_done_q;
reg [63:0] tp_tx_cqe_done_q;
reg [63:0] tp_rx_input_stall_q;
reg [63:0] tp_cdc_payload_stall_q;
reg [63:0] tp_aw_stall_q;
reg [63:0] tp_w_stall_q;
reg [63:0] tp_b_stall_q;
reg [63:0] tp_ar_stall_q;
reg [63:0] tp_r_stall_q;
reg [7:0] tp_rx_peak_outstanding_q;
reg [31:0] tp_payload_crc_q;
reg [31:0] tp_protocol_error_q;
reg [31:0] tp_rx_stream_frame_q;
reg [31:0] tp_rx_stream_payload_beats_left_q;
reg [63:0] tp_flow_done_q [0:PERF_CHANNELS-1];
reg [63:0] tp_flow_last_done_q [0:PERF_CHANNELS-1];
reg [63:0] tp_flow_min_gap_q [0:PERF_CHANNELS-1];
reg [63:0] tp_flow_max_gap_q [0:PERF_CHANNELS-1];
reg [31:0] tp_cqe_rx_scanned_q;
reg [31:0] tp_cqe_tx_scanned_q;
reg [63:0] tp_latency_sample_q [0:MAX_TRACKED_FRAMES-1];
reg [63:0] tp_frame_start_by_seq_q [0:MAX_TRACKED_FRAMES-1];
reg [31:0] tp_latency_count_q;
reg [63:0] tp_latency_cycles_tmp_q;
reg tp_prev_bridge_error_q;
reg tp_bridge_cause_reported_q;

integer rd32_q;
integer i;
integer single_scenario_q;

wire aw_gate = !stall_enable ? 1'b1 :
               stall_random_mode ? stall_lfsr[0] :
               ((stall_aw_mod <= 1) ? 1'b1 : ((stall_cycle_count % stall_aw_mod) != (stall_aw_mod - 1)));
wire w_gate = !stall_enable ? 1'b1 :
              stall_random_mode ? stall_lfsr[5] :
              ((stall_w_mod <= 1) ? 1'b1 : ((stall_cycle_count % stall_w_mod) != (stall_w_mod - 1)));
wire b_gate = !stall_enable ? 1'b1 :
              stall_random_mode ? stall_lfsr[11] :
              ((stall_b_mod <= 1) ? 1'b1 : ((stall_cycle_count % stall_b_mod) != (stall_b_mod - 1)));

assign mem_m_axi_awaddr  = dut_m_axi_awaddr;
assign mem_m_axi_awlen   = dut_m_axi_awlen;
assign mem_m_axi_awsize  = dut_m_axi_awsize;
assign mem_m_axi_awburst = dut_m_axi_awburst;
assign mem_m_axi_awvalid = dut_m_axi_awvalid && aw_gate;
assign dut_m_axi_awready = mem_m_axi_awready && aw_gate;

assign mem_m_axi_wdata   = dut_m_axi_wdata;
assign mem_m_axi_wstrb   = dut_m_axi_wstrb;
assign mem_m_axi_wlast   = dut_m_axi_wlast;
assign mem_m_axi_wvalid  = dut_m_axi_wvalid && w_gate;
assign dut_m_axi_wready  = mem_m_axi_wready && w_gate;

assign dut_m_axi_bresp   = mem_m_axi_bresp;
assign dut_m_axi_bvalid  = mem_m_axi_bvalid && b_gate;
assign mem_m_axi_bready  = dut_m_axi_bready && b_gate;

assign mem_m_axi_araddr  = dut_m_axi_araddr;
assign mem_m_axi_arlen   = dut_m_axi_arlen;
assign mem_m_axi_arsize  = dut_m_axi_arsize;
assign mem_m_axi_arburst = dut_m_axi_arburst;
assign mem_m_axi_arvalid = dut_m_axi_arvalid;
assign dut_m_axi_arready = mem_m_axi_arready;

assign dut_m_axi_rdata   = mem_m_axi_rdata;
assign dut_m_axi_rresp   = mem_m_axi_rresp;
assign dut_m_axi_rlast   = mem_m_axi_rlast;
assign dut_m_axi_rvalid  = mem_m_axi_rvalid;
assign mem_m_axi_rready  = dut_m_axi_rready;

dma_ref_model u_ref();

ps_axil_bfm u_ps(
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
    .irq(irq),
    .clk(clk),
    .rstn(rstn)
);

axi_hp0_dual_master_64_model #(
    .SHARED_SERVICE(HP0_SHARED_SERVICE),
    .RESPONSE_LATENCY(HP0_RESPONSE_LATENCY),
    .SERVICE_PERCENT(HP0_SERVICE_PERCENT)
) u_hp0 (
    .hp_clk(clk),
    .hp_rstn(rstn),
    .m0_clk(clk),
    .m0_rstn(rstn),
    .m0_awaddr(mem_m_axi_awaddr),
    .m0_awlen(mem_m_axi_awlen),
    .m0_awsize(mem_m_axi_awsize),
    .m0_awburst(mem_m_axi_awburst),
    .m0_awvalid(mem_m_axi_awvalid),
    .m0_awready(mem_m_axi_awready),
    .m0_wdata(mem_m_axi_wdata),
    .m0_wstrb(mem_m_axi_wstrb),
    .m0_wlast(mem_m_axi_wlast),
    .m0_wvalid(mem_m_axi_wvalid),
    .m0_wready(mem_m_axi_wready),
    .m0_bresp(mem_m_axi_bresp),
    .m0_bvalid(mem_m_axi_bvalid),
    .m0_bready(mem_m_axi_bready),
    .m0_araddr(mem_m_axi_araddr),
    .m0_arlen(mem_m_axi_arlen),
    .m0_arsize(mem_m_axi_arsize),
    .m0_arburst(mem_m_axi_arburst),
    .m0_arvalid(mem_m_axi_arvalid),
    .m0_arready(mem_m_axi_arready),
    .m0_rdata(mem_m_axi_rdata),
    .m0_rresp(mem_m_axi_rresp),
    .m0_rlast(mem_m_axi_rlast),
    .m0_rvalid(mem_m_axi_rvalid),
    .m0_rready(mem_m_axi_rready),
    .m1_clk(mem_clk),
    .m1_rstn(mem_rstn),
    .m1_awaddr(rx_mem_awaddr),
    .m1_awlen(rx_mem_awlen),
    .m1_awsize(rx_mem_awsize),
    .m1_awburst(rx_mem_awburst),
    .m1_awvalid(rx_mem_awvalid),
    .m1_awready(rx_mem_awready),
    .m1_wdata(rx_mem_wdata),
    .m1_wstrb(rx_mem_wstrb),
    .m1_wlast(rx_mem_wlast),
    .m1_wvalid(rx_mem_wvalid),
    .m1_wready(rx_mem_wready),
    .m1_bresp(rx_mem_bresp),
    .m1_bvalid(rx_mem_bvalid),
    .m1_bready(rx_mem_bready)
);

frame_dma_rx_top u_dut(
    .aclk(clk),
    .aresetn(rstn),
    .tx_axis_aclk(clk),
    .tx_axis_aresetn(rstn),
    .rx_axis_tdata(dut_rx_axis_tdata),
    .rx_axis_tvalid(dut_rx_axis_tvalid),
    .rx_axis_tready(dut_rx_axis_tready),
    .tx_axis_tdata(tx_axis_tdata),
    .tx_axis_tvalid(tx_axis_tvalid),
    .tx_axis_tready(dut_tx_axis_tready),
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
    .m_axi_awaddr(dut_m_axi_awaddr),
    .m_axi_awlen(dut_m_axi_awlen),
    .m_axi_awsize(dut_m_axi_awsize),
    .m_axi_awburst(dut_m_axi_awburst),
    .m_axi_awvalid(dut_m_axi_awvalid),
    .m_axi_awready(dut_m_axi_awready),
    .m_axi_wdata(dut_m_axi_wdata),
    .m_axi_wstrb(dut_m_axi_wstrb),
    .m_axi_wlast(dut_m_axi_wlast),
    .m_axi_wvalid(dut_m_axi_wvalid),
    .m_axi_wready(dut_m_axi_wready),
    .m_axi_bresp(dut_m_axi_bresp),
    .m_axi_bvalid(dut_m_axi_bvalid),
    .m_axi_bready(dut_m_axi_bready),
    .m_axi_araddr(dut_m_axi_araddr),
    .m_axi_arlen(dut_m_axi_arlen),
    .m_axi_arsize(dut_m_axi_arsize),
    .m_axi_arburst(dut_m_axi_arburst),
    .m_axi_arvalid(dut_m_axi_arvalid),
    .m_axi_arready(dut_m_axi_arready),
    .m_axi_rdata(dut_m_axi_rdata),
    .m_axi_rresp(dut_m_axi_rresp),
    .m_axi_rlast(dut_m_axi_rlast),
    .m_axi_rvalid(dut_m_axi_rvalid),
    .m_axi_rready(dut_m_axi_rready),
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
    .irq(irq),
    .mem_clk(mem_clk),
    .mem_aresetn(mem_rstn),
    .m_axi_rx_payload_awaddr(rx_mem_awaddr),
    .m_axi_rx_payload_awlen(rx_mem_awlen),
    .m_axi_rx_payload_awsize(rx_mem_awsize),
    .m_axi_rx_payload_awburst(rx_mem_awburst),
    .m_axi_rx_payload_awvalid(rx_mem_awvalid),
    .m_axi_rx_payload_awready(rx_mem_awready),
    .m_axi_rx_payload_wdata(rx_mem_wdata),
    .m_axi_rx_payload_wstrb(rx_mem_wstrb),
    .m_axi_rx_payload_wlast(rx_mem_wlast),
    .m_axi_rx_payload_wvalid(rx_mem_wvalid),
    .m_axi_rx_payload_wready(rx_mem_wready),
    .m_axi_rx_payload_bresp(rx_mem_bresp),
    .m_axi_rx_payload_bvalid(rx_mem_bvalid),
    .m_axi_rx_payload_bready(rx_mem_bready)
);

assign ufc_tx_ready = 1'b1;
assign ufc_rx_valid = 1'b0;
assign ufc_rx_opcode = 8'h0;
assign ufc_rx_flow_id = 16'h0;
assign ufc_rx_arg0 = 32'h0;
assign ufc_rx_arg1 = 32'h0;

assign dut_rx_axis_tdata = loopback_enable ? loop_data_q : rx_axis_tdata;
assign dut_rx_axis_tvalid = loopback_enable ? loop_valid_q : rx_axis_tvalid;
assign rx_axis_tready = loopback_enable ? 1'b0 : dut_rx_axis_tready;
assign dut_tx_axis_tready = loopback_enable ? (!loop_valid_q || dut_rx_axis_tready) :
                              tx_axis_tready;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        loop_valid_q <= 1'b0;
        loop_data_q <= 512'h0;
    end else if (!loopback_enable) begin
        loop_valid_q <= 1'b0;
    end else if (dut_tx_axis_tready) begin
        loop_valid_q <= tx_axis_tvalid;
        if (tx_axis_tvalid)
            loop_data_q <= tx_axis_tdata;
    end
end

always #5 clk = ~clk;

initial begin
    mem_clk = 1'b0;
    #(MEM_PHASE_NS);
    forever #5 mem_clk = ~mem_clk;
end

function [31:0] ch_addr;
    input [11:0] base;
    input integer ch;
    input [11:0] off;
    begin
        ch_addr = base + (ch * `DMA_CH_STRIDE) + off;
    end
endfunction

function [31:0] align64;
    input [31:0] value;
    begin
        align64 = (value + 32'd63) & 32'hffff_ffc0;
    end
endfunction

function [31:0] perf_size_for_index;
    input integer index;
    begin
        case (index % 5)
        0: perf_size_for_index = 32'd64;
        1: perf_size_for_index = 32'd128;
        2: perf_size_for_index = 32'd256;
        3: perf_size_for_index = 32'd1024;
        default: perf_size_for_index = 32'd4096;
        endcase
    end
endfunction

function integer popcount8;
    input [7:0] value;
    integer bit_i;
    begin
        popcount8 = 0;
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1)
            if (value[bit_i])
                popcount8 = popcount8 + 1;
    end
endfunction

function [7:0] sys_u8;
    input [31:0] addr;
    begin
        sys_u8 = `DMA_SYS_MEM_PATH[addr];
    end
endfunction

function [15:0] sys_u16;
    input [31:0] addr;
    begin
        sys_u16 = {sys_u8(addr + 1), sys_u8(addr)};
    end
endfunction

function [31:0] sys_u32;
    input [31:0] addr;
    begin
        sys_u32 = {sys_u8(addr + 3), sys_u8(addr + 2),
                   sys_u8(addr + 1), sys_u8(addr)};
    end
endfunction

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] data;
    integer bit_i;
    reg [31:0] crc;
    begin
        crc = crc_in ^ {24'h0, data};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1)
            crc = crc[0] ? ((crc >> 1) ^ 32'hedb8_8320) : (crc >> 1);
        crc32_byte = crc;
    end
endfunction

task fail;
    input [8*64-1:0] msg;
    begin
        $display("Error: %0s", msg);
        $finish;
    end
endtask

task clear_frame_expectations;
    begin
        frame_expected_count_q = 0;
        lat_head_q = 0;
        lat_tail_q = 0;
        lat_count_pending_q = 0;
    end
endtask

task clear_throughput_metrics;
    integer ch_i;
    integer frame_i;
    begin
        tp_doorbell_pending_q = 1'b0;
        tp_hw_started_q = 1'b0;
        tp_hw_finished_q = 1'b0;
        tp_steady_started_q = 1'b0;
        tp_steady_finished_q = 1'b0;
        tp_hw_start_cycle_q = 64'd0;
        tp_hw_end_cycle_q = 64'd0;
        tp_steady_start_cycle_q = 64'd0;
        tp_steady_end_cycle_q = 64'd0;
        tp_expected_payload_bytes_q = 64'd0;
        tp_rx_payload_bytes_q = 64'd0;
        tp_main_read_bytes_q = 64'd0;
        tp_main_write_bytes_q = 64'd0;
        tp_main_ar_bursts_q = 64'd0;
        tp_main_aw_bursts_q = 64'd0;
        tp_rx_aw_bursts_q = 64'd0;
        tp_rx_axis_valid_q = 64'd0;
        tp_rx_axis_ready_q = 64'd0;
        tp_rx_axis_fire_q = 64'd0;
        tp_tx_axis_valid_q = 64'd0;
        tp_tx_axis_ready_q = 64'd0;
        tp_tx_axis_fire_q = 64'd0;
        tp_rx_cqe_done_q = 64'd0;
        tp_tx_cqe_done_q = 64'd0;
        tp_rx_input_stall_q = 64'd0;
        tp_cdc_payload_stall_q = 64'd0;
        tp_aw_stall_q = 64'd0;
        tp_w_stall_q = 64'd0;
        tp_b_stall_q = 64'd0;
        tp_ar_stall_q = 64'd0;
        tp_r_stall_q = 64'd0;
        tp_rx_peak_outstanding_q = 8'd0;
        tp_payload_crc_q = 32'hffff_ffff;
        tp_protocol_error_q = 32'd0;
        tp_prev_bridge_error_q = 1'b0;
        tp_bridge_cause_reported_q = 1'b0;
        tp_rx_stream_frame_q = 32'd0;
        tp_rx_stream_payload_beats_left_q = 32'd0;
        tp_cqe_rx_scanned_q = 32'd0;
        tp_cqe_tx_scanned_q = 32'd0;
        tp_latency_count_q = 32'd0;
        for (ch_i = 0; ch_i < PERF_CHANNELS; ch_i = ch_i + 1) begin
            tp_flow_done_q[ch_i] = 64'd0;
            tp_flow_last_done_q[ch_i] = 64'd0;
            tp_flow_min_gap_q[ch_i] = 64'hffff_ffff_ffff_ffff;
            tp_flow_max_gap_q[ch_i] = 64'd0;
        end
        for (frame_i = 0; frame_i < MAX_TRACKED_FRAMES;
             frame_i = frame_i + 1) begin
            tp_frame_start_by_seq_q[frame_i] = 64'd0;
            tp_latency_sample_q[frame_i] = 64'd0;
        end
    end
endtask

task clear_scenario_metrics;
    begin
        scenario_cycles_q = 64'd0;
        scenario_frame_count_q = 32'd0;
        scenario_expected_cqe_q = 32'd0;
        scenario_expected_tx_desc_q = 32'd0;
        scenario_deadlock_q = 32'd0;
        rx_accept_beats_q = 64'd0;
        rx_accept_bytes_q = 64'd0;
        rx_tvalid_cycles_q = 64'd0;
        rx_tready_cycles_q = 64'd0;
        rx_fire_cycles_q = 64'd0;
        payload_write_bytes_q = 64'd0;
        payload_aw_bursts_q = 64'd0;
        payload_w_beats_q = 64'd0;
        axi_w_fire_cycles_q = 64'd0;
        cq_rx_req_q = 64'd0;
        cq_tx_req_q = 64'd0;
        cq_rx_accept_q = 64'd0;
        cq_tx_accept_q = 64'd0;
        cq_busy_cycles_q = 64'd0;
        cq_rx_full_q = 64'd0;
        cq_tx_full_q = 64'd0;
        cq_cqe_completed_q = 64'd0;
        cq_credit_stall_cycles_q = 64'd0;
        skid_hist_0_q = 64'd0;
        skid_hist_1_q = 64'd0;
        skid_hist_2_q = 64'd0;
        rx_frame_done_q = 64'd0;
        rx_frame_fail_q = 64'd0;
        rx_frame_drop_q = 64'd0;
        rx_event_ok_q = 64'd0;
        tx_req_lat_sum_q = 64'd0;
        tx_req_lat_cnt_q = 64'd0;
        tx_req_lat_max_q = 64'd0;
        rx_req_lat_sum_q = 64'd0;
        rx_req_lat_cnt_q = 64'd0;
        rx_req_lat_max_q = 64'd0;
        tx_req_pending_end_q = 1'b0;
        latency_sum_q = 64'd0;
        latency_min_q = 64'hffff_ffff_ffff_ffff;
        latency_max_q = 64'd0;
        latency_count_q = 64'd0;
        dbg_pay_rd_req_q = 64'd0;
        dbg_pay_rd_valid_q = 64'd0;
        dbg_stream_rd_valid_q = 64'd0;
        dbg_frame_rd_valid_q = 64'd0;
        dbg_frame_pool_fire_q = 64'd0;
        dbg_w_run_q = 64'd0;
        dbg_w_run_max_q = 64'd0;
        tx_req_waiting_q = 1'b0;
        tx_req_accepted_q = 1'b0;
        tx_req_start_cycle_q = 64'd0;
        rx_req_waiting_q = 1'b0;
        rx_req_start_cycle_q = 64'd0;
        prev_tx_cqe_req_valid_q = 1'b0;
        prev_wr_cqe_cmd_q = 1'b0;
        prev_cq_single_rx_full_q = 1'b0;
        prev_cq_single_tx_full_q = 1'b0;
        tx_desc_count_q = 0;
        clear_frame_expectations();
        clear_throughput_metrics();
    end
endtask

task start_scenario;
    input [8*32-1:0] name;
    input [31:0] seed;
    begin
        clear_scenario_metrics();
        scenario_name_q = name;
        scenario_seed_q = seed;
        scenario_active = 1'b1;
    end
endtask

task finish_scenario;
    input [8*32-1:0] name;
    begin
        scenario_active = 1'b0;
        tx_req_pending_end_q = tx_req_waiting_q && !tx_req_accepted_q;
        $display("E20A22_RESULT scenario=%0s frames=%0d payload_bytes=%0d cycles=%0d rx_accept_beats=%0d rx_accept_bytes=%0d rx_tvalid_cycles=%0d rx_tready_cycles=%0d rx_fire_cycles=%0d payload_write_bytes=%0d payload_aw_bursts=%0d payload_w_beats=%0d axi_w_fire_cycles=%0d cq_rx_req=%0d cq_tx_req=%0d cq_rx_accept=%0d cq_tx_accept=%0d cq_busy_cycles=%0d cq_rx_full=%0d cq_tx_full=%0d cq_completed=%0d cmd_credit_stall_cycles=%0d frame_done=%0d frame_fail=%0d frame_drop=%0d latency_count=%0d latency_min=%0d latency_max=%0d latency_sum=%0d deadlock=%0d",
                 name,
                 scenario_frame_count_q,
                 payload_write_bytes_q,
                 scenario_cycles_q,
                 rx_accept_beats_q,
                 rx_accept_bytes_q,
                 rx_tvalid_cycles_q,
                 rx_tready_cycles_q,
                 rx_fire_cycles_q,
                 payload_write_bytes_q,
                 payload_aw_bursts_q,
                 payload_w_beats_q,
                 axi_w_fire_cycles_q,
                 cq_rx_req_q,
                 cq_tx_req_q,
                 cq_rx_accept_q,
                 cq_tx_accept_q,
                 cq_busy_cycles_q,
                 cq_rx_full_q,
                 cq_tx_full_q,
                 cq_cqe_completed_q,
                 cq_credit_stall_cycles_q,
                 rx_frame_done_q,
                 rx_frame_fail_q,
                 rx_frame_drop_q,
                 latency_count_q,
                 (latency_count_q == 0) ? 64'd0 : latency_min_q,
                 latency_max_q,
                 latency_sum_q,
                 scenario_deadlock_q);
        $display("E20A22_HIST scenario=%0s skid0=%0d skid1=%0d skid2=%0d", name, skid_hist_0_q, skid_hist_1_q, skid_hist_2_q);
        $display("E20A22_FAIRNESS scenario=%0s tx_lat_max=%0d tx_lat_sum=%0d tx_lat_cnt=%0d rx_lat_max=%0d rx_lat_sum=%0d rx_lat_cnt=%0d tx_accept=%0d rx_accept=%0d tx_pending_end=%0d",
                 name,
                 tx_req_lat_max_q,
                 tx_req_lat_sum_q,
                 tx_req_lat_cnt_q,
                 rx_req_lat_max_q,
                 rx_req_lat_sum_q,
                 rx_req_lat_cnt_q,
                 cq_tx_accept_q,
                 cq_rx_accept_q,
                 tx_req_pending_end_q);
        $display("E20A23_DEBUG scenario=%0s pay_rd_req=%0d pay_rd_valid=%0d stream_rd_valid=%0d frame_rd_valid=%0d frame_pool_fire=%0d max_w_run=%0d",
                 name,
                 dbg_pay_rd_req_q,
                 dbg_pay_rd_valid_q,
                 dbg_stream_rd_valid_q,
                 dbg_frame_rd_valid_q,
                 dbg_frame_pool_fire_q,
                 dbg_w_run_max_q);
    end
endtask

task init_test_memories;
    integer idx;
    begin
        u_hp0.clear_all();
        for (idx = 0; idx < `DMA_PKT_MEM_BYTES; idx = idx + 1)
            pkt_mem[idx] = 8'h0;
        for (idx = 0; idx < `DMA_SIM_MEM_BYTES; idx = idx + 1)
            ref_mem[idx] = 8'h0;
    end
endtask

task reset_dut;
    begin
        rstn = 1'b0;
        mem_rstn = 1'b0;
        rx_axis_tdata = 512'h0;
        rx_axis_tvalid = 1'b0;
        tx_axis_tready = 1'b1;
        loopback_enable = 1'b0;
        stall_enable = 1'b0;
        stall_random_mode = 1'b0;
        stall_aw_mod = 8'd0;
        stall_w_mod = 8'd0;
        stall_b_mod = 8'd0;
        stall_lfsr = 32'h1ace_beef;
        stall_cycle_count = 32'h0;
        repeat (12) @(posedge clk);
        rstn = 1'b1;
        mem_rstn = 1'b1;
        repeat (20) @(posedge clk);
    end
endtask

task config_cq;
    input [31:0] cq_size_words;
    begin
        u_ps.dma_config_cq(CQ_BASE, cq_size_words);
    end
endtask

task config_rx_channel_ext;
    input integer ch;
    input [31:0] base;
    input [31:0] size;
    input [31:0] max_len;
    input [15:0] flow_id;
    input [3:0]  policy;
    input [31:0] high_wm;
    input [31:0] low_wm;
    input         cpl_en;
    input         irq_en;
    input         fc_en;
    reg [31:0] cfg;
    reg [31:0] ctrl;
    begin
        cfg = {flow_id, 4'h0, 4'h0, policy, `DMA_TC_FC};
        ctrl = (1 << `DMA_RX_CTRL_ENABLE);
        if (cpl_en)
            ctrl = ctrl | (1 << `DMA_RX_CTRL_CPL_EN);
        if (irq_en)
            ctrl = ctrl | (1 << `DMA_RX_CTRL_IRQ_EN);
        if (fc_en)
            ctrl = ctrl | (1 << `DMA_RX_CTRL_FC_EN);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_CFG), cfg);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_BASE_L), base);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_BASE_H), 32'h0);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_SIZE), size);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_MAX_LEN), max_len);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_RX_CH_HIGH_WM), high_wm);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_RX_CH_LOW_WM), low_wm);
        u_ps.axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_CTRL), ctrl);
        exp_rx_base[ch] = base;
        exp_rx_wr_ptr[ch] = 32'h0;
        exp_rx_flow[ch] = flow_id;
        exp_rx_cpl[ch] = cpl_en;
    end
endtask

task config_default_env;
    input [31:0] cq_size_words;
    begin
        u_ps.axil_write(`DMA_REG_IRQ_MASK, 32'hffff_ffff);
        config_cq(cq_size_words);
        config_rx_channel_ext(RX_CH_CPL, RX0_BASE, RX_RING_SIZE, 32'd32768, FLOW_ID_CPL,
                              `DMA_RX_POL_QUEUE_WITH_FC, RX_RING_SIZE - 32'd64, RX_RING_SIZE >> 1, 1'b1, 1'b1, 1'b1);
        config_rx_channel_ext(RX_CH_NOCPL, RX1_BASE, RX_RING_SIZE, 32'd32768, FLOW_ID_NOCPL,
                              `DMA_RX_POL_QUEUE_WITH_FC, RX_RING_SIZE - 32'd64, RX_RING_SIZE >> 1, 1'b0, 1'b1, 1'b1);
        u_ps.dma_global_enable(1'b1, 1'b1, 1'b1, 1'b1);
    end
endtask

task config_throughput_env;
    input loopback_mode;
    input mixed_mode;
    integer ch_i;
    reg [15:0] flow_id;
    reg [31:0] ring_base;
    reg [31:0] ring_size;
    begin
        u_ps.axil_write(`DMA_REG_IRQ_MASK, 32'hffff_ffff);
        config_cq(PERF_CQ_ENTRIES);
        if (mixed_mode) begin
            for (ch_i = 0; ch_i < PERF_CHANNELS; ch_i = ch_i + 1) begin
                flow_id = PERF_FLOW_BASE + ch_i[15:0];
                ring_base = RX0_BASE + (ch_i * PERF_CH_RING_BYTES);
                config_rx_channel_ext(ch_i, ring_base, PERF_CH_RING_BYTES,
                                      32'd32768, flow_id,
                                      `DMA_RX_POL_QUEUE_WITH_FC,
                                      PERF_CH_RING_BYTES - 32'd64,
                                      PERF_CH_RING_BYTES >> 1,
                                      1'b1, 1'b1, 1'b1);
            end
        end else begin
            flow_id = loopback_mode ? FLOW_ID_TX : FLOW_ID_CPL;
            config_rx_channel_ext(RX_CH_CPL, RX0_BASE, RX_RING_SIZE,
                                  32'd32768, flow_id,
                                  `DMA_RX_POL_QUEUE_WITH_FC,
                                  RX_RING_SIZE - 32'd64,
                                  RX_RING_SIZE >> 1,
                                  1'b1, 1'b1, 1'b1);
        end
        u_ps.dma_global_enable(1'b1, 1'b1, 1'b1, 1'b1);
    end
endtask

task put_u32;
    input [31:0] addr;
    input [31:0] data;
    begin
        `DMA_SYS_MEM_PATH[addr + 0] = data[7:0];
        `DMA_SYS_MEM_PATH[addr + 1] = data[15:8];
        `DMA_SYS_MEM_PATH[addr + 2] = data[23:16];
        `DMA_SYS_MEM_PATH[addr + 3] = data[31:24];
    end
endtask

task write_tx_desc;
    input [31:0] desc_addr;
    input [31:0] payload_len;
    input [31:0] src_addr;
    input [31:0] seq;
    integer j;
    begin
        for (j = 0; j < `DMA_TX_DESC_BYTES; j = j + 1)
            `DMA_SYS_MEM_PATH[desc_addr + j] = 8'h0;
        put_u32(desc_addr + `DMA_TX_DESC_CTRL_OFF, (1 << `DMA_TX_DESC_OWNER_VALID));
        put_u32(desc_addr + `DMA_TX_DESC_CH_STREAM_OFF, {STREAM_ID_TX, FLOW_ID_TX});
        put_u32(desc_addr + `DMA_TX_DESC_LEN_OFF, payload_len);
        put_u32(desc_addr + `DMA_TX_DESC_ADDR_LO_OFF, src_addr);
        put_u32(desc_addr + `DMA_TX_DESC_SEQ_OFF, seq);
        put_u32(desc_addr + `DMA_TX_DESC_SAMPLE_OFF, 32'h2200_0000 | seq[15:0]);
    end
endtask

task write_tx_desc_flow;
    input [31:0] desc_addr;
    input [31:0] payload_len;
    input [31:0] src_addr;
    input [31:0] seq;
    input [15:0] flow_id;
    integer j;
    begin
        for (j = 0; j < `DMA_TX_DESC_BYTES; j = j + 1)
            `DMA_SYS_MEM_PATH[desc_addr + j] = 8'h0;
        put_u32(desc_addr + `DMA_TX_DESC_CTRL_OFF,
                (1 << `DMA_TX_DESC_OWNER_VALID));
        put_u32(desc_addr + `DMA_TX_DESC_CH_STREAM_OFF,
                {STREAM_ID_TX, flow_id});
        put_u32(desc_addr + `DMA_TX_DESC_LEN_OFF, payload_len);
        put_u32(desc_addr + `DMA_TX_DESC_ADDR_LO_OFF, src_addr);
        put_u32(desc_addr + `DMA_TX_DESC_SEQ_OFF, seq);
        put_u32(desc_addr + `DMA_TX_DESC_SAMPLE_OFF,
                32'h7100_0000 | seq[15:0]);
    end
endtask

task config_tx_desc_queue;
    begin
        u_ps.axil_write(ch_addr(`DMA_TX_CH_BASE, TX_CH, `DMA_CH_CFG),
                        {FLOW_ID_TX, 4'h0, 4'h0, `DMA_TX_POL_SINGLE_SHOT, `DMA_TC_FC});
        u_ps.axil_write(ch_addr(`DMA_TX_CH_BASE, TX_CH, `DMA_TX_CH_LEN), 32'd8192);
        u_ps.axil_write(ch_addr(`DMA_TX_CH_BASE, TX_CH, `DMA_CH_CTRL),
                        (1 << `DMA_TX_CTRL_ENABLE) |
                        (1 << `DMA_TX_CTRL_CPL_EN) |
                        (1 << `DMA_TX_CTRL_IRQ_EN));
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH, `DMA_TX_DESC_BASE_L), TX_DESC_BASE);
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH, `DMA_TX_DESC_SIZE), TX_DESC_SIZE);
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH, `DMA_TX_DESC_RD_PTR), 32'h0);
    end
endtask

task config_tx_desc_queue_throughput;
    begin
        u_ps.axil_write(ch_addr(`DMA_TX_CH_BASE, TX_CH, `DMA_CH_CFG),
                        {FLOW_ID_TX, 4'h0, 4'h0,
                         `DMA_TX_POL_SINGLE_SHOT, `DMA_TC_FC});
        u_ps.axil_write(ch_addr(`DMA_TX_CH_BASE, TX_CH, `DMA_TX_CH_LEN),
                        32'd32768);
        u_ps.axil_write(ch_addr(`DMA_TX_CH_BASE, TX_CH, `DMA_CH_CTRL),
                        (1 << `DMA_TX_CTRL_ENABLE) |
                        (1 << `DMA_TX_CTRL_CPL_EN) |
                        (1 << `DMA_TX_CTRL_IRQ_EN));
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH,
                                `DMA_TX_DESC_BASE_L), TX_DESC_BASE);
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH,
                                `DMA_TX_DESC_SIZE), TX_DESC_SIZE);
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH,
                                `DMA_TX_DESC_RD_PTR), 32'h0);
    end
endtask

task start_tx_desc_queue_throughput;
    input integer desc_count;
    begin
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH,
                                `DMA_TX_DESC_WR_PTR),
                        desc_count * `DMA_TX_DESC_BYTES);
        tp_doorbell_pending_q = 1'b1;
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH,
                                `DMA_TX_DESC_CTRL),
                        (1 << `DMA_TX_DESC_CTRL_ENABLE) |
                        (1 << `DMA_TX_DESC_CTRL_START) |
                        (1 << `DMA_TX_DESC_CTRL_IRQ_EN));
        scenario_expected_cqe_q = scenario_expected_cqe_q + desc_count;
        scenario_expected_tx_desc_q = desc_count;
        tx_desc_count_q = desc_count;
    end
endtask

task start_tx_desc_queue;
    input integer desc_count;
    begin
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH, `DMA_TX_DESC_WR_PTR),
                        desc_count * `DMA_TX_DESC_BYTES);
        u_ps.axil_write(ch_addr(`DMA_TX_DESC_CH_BASE, TX_CH, `DMA_TX_DESC_CTRL),
                        (1 << `DMA_TX_DESC_CTRL_ENABLE) |
                        (1 << `DMA_TX_DESC_CTRL_START) |
                        (1 << `DMA_TX_DESC_CTRL_IRQ_EN));
        scenario_expected_cqe_q = scenario_expected_cqe_q + desc_count;
        scenario_expected_tx_desc_q = desc_count;
        tx_desc_count_q = desc_count;
    end
endtask

task prepare_tx_payload;
    input integer desc_count;
    input [31:0] base_addr;
    input [31:0] payload_len;
    input [7:0] seed;
    integer desc_i;
    integer byte_i;
    reg [31:0] src_addr;
    begin
        for (desc_i = 0; desc_i < desc_count; desc_i = desc_i + 1) begin
            src_addr = base_addr + (desc_i * 32'h400);
            for (byte_i = 0; byte_i < payload_len; byte_i = byte_i + 1)
                `DMA_SYS_MEM_PATH[src_addr + byte_i] = seed ^ desc_i[7:0] ^ byte_i[7:0];
            write_tx_desc(TX_DESC_BASE + (desc_i * `DMA_TX_DESC_BYTES), payload_len, src_addr, desc_i + 1);
        end
    end
endtask

task push_frame_expectation;
    input integer ch;
    input [31:0] payload_src;
    input [31:0] payload_len;
    reg [31:0] dst_addr;
    begin
        if (frame_expected_count_q >= MAX_TRACKED_FRAMES)
            fail("frame expectation overflow");
        dst_addr = exp_rx_base[ch] + exp_rx_wr_ptr[ch];
        frame_len_q[frame_expected_count_q] = payload_len;
        frame_src_q[frame_expected_count_q] = payload_src;
        frame_dst_q[frame_expected_count_q] = dst_addr;
        frame_ch_q[frame_expected_count_q] = ch[3:0];
        frame_expected_count_q = frame_expected_count_q + 1;
        exp_rx_wr_ptr[ch] = exp_rx_wr_ptr[ch] + align64(payload_len);
        scenario_frame_count_q = scenario_frame_count_q + 1;
        if (exp_rx_cpl[ch])
            scenario_expected_cqe_q = scenario_expected_cqe_q + 1;
    end
endtask

task fill_pkt_payload;
    input [31:0] payload_src;
    input [31:0] payload_len;
    input [7:0] seed;
    integer byte_i;
    begin
        for (byte_i = 0; byte_i < payload_len; byte_i = byte_i + 1)
            pkt_mem[payload_src + byte_i] = seed ^ payload_src[7:0] ^ byte_i[7:0];
    end
endtask

task prepare_loopback_workload;
    input integer frame_count;
    input mixed_mode;
    input [31:0] fixed_payload_len;
    integer frame_i;
    integer byte_i;
    integer ch_i;
    reg [15:0] flow_id;
    reg [31:0] payload_len;
    reg [31:0] src_addr;
    reg [7:0] payload_byte;
    begin
        for (frame_i = 0; frame_i < frame_count; frame_i = frame_i + 1) begin
            ch_i = mixed_mode ? (frame_i % PERF_CHANNELS) : RX_CH_CPL;
            flow_id = mixed_mode ? (PERF_FLOW_BASE + ch_i[15:0]) : FLOW_ID_TX;
            payload_len = mixed_mode ? perf_size_for_index(frame_i) : fixed_payload_len;
            src_addr = TX_PAYLOAD_BASE + (frame_i * 32'd4096);
            for (byte_i = 0; byte_i < payload_len; byte_i = byte_i + 1) begin
                payload_byte = 8'h71 ^ frame_i[7:0] ^ byte_i[7:0];
                `DMA_SYS_MEM_PATH[src_addr + byte_i] = payload_byte;
                pkt_mem[src_addr + byte_i] = payload_byte;
            end
            write_tx_desc_flow(TX_DESC_BASE +
                               (frame_i * `DMA_TX_DESC_BYTES),
                               payload_len, src_addr, frame_i + 1, flow_id);
            push_frame_expectation(ch_i, src_addr, payload_len);
            tp_expected_payload_bytes_q =
                tp_expected_payload_bytes_q + payload_len;
        end
    end
endtask

task axis_send_frame_nobubble;
    input integer ch;
    input [15:0] flow_id;
    input [15:0] msg_id;
    input [31:0] payload_len;
    input [31:0] payload_src;
    input [31:0] frame_seq;
    integer total_beats;
    integer beat_idx;
    integer idx;
    integer guard;
    reg [511:0] beat;
    reg [511:0] header;
    begin
        total_beats = 1 + ((payload_len + 32'd63) >> 6);
        u_ref.ref_build_header(header, {4'h0, `DMA_TC_FC}, flow_id, msg_id,
                               payload_len, frame_seq, {32'h0, frame_seq}, 64'h0, payload_len);
        push_frame_expectation(ch, payload_src, payload_len);
        beat_idx = 0;
        beat = header;
        guard = 0;
        @(negedge clk);
        rx_axis_tdata <= beat;
        rx_axis_tvalid <= 1'b1;
        while (beat_idx < total_beats) begin
            @(posedge clk);
            if (rx_axis_tvalid && rx_axis_tready) begin
                guard = 0;
                beat_idx = beat_idx + 1;
                if (beat_idx == total_beats) begin
                    @(negedge clk);
                    rx_axis_tvalid <= 1'b0;
                    rx_axis_tdata <= 512'h0;
                end else begin
                    beat = 512'h0;
                    for (idx = 0; idx < 64; idx = idx + 1) begin
                        if ((((beat_idx - 1) * 64) + idx) < payload_len)
                            beat[idx*8 +: 8] = pkt_mem[payload_src + ((beat_idx - 1) * 64) + idx];
                    end
                    @(negedge clk);
                    rx_axis_tdata <= beat;
                end
            end else begin
                guard = guard + 1;
                if (guard > SCENARIO_TIMEOUT_CYCLES) begin
                    scenario_deadlock_q = 32'd1;
                    $display("Error: timeout sending frame scenario=%0s ch=%0d seq=%0d beat=%0d/%0d rx_state=%0d wr_state=%0d skid_count=%0d pay_busy=%0d cdc_busy=%0d writer_busy=%0d",
                             scenario_name_q, ch, frame_seq, beat_idx, total_beats,
                             u_dut.rx_state, u_dut.wr_state,
                             u_dut.g_rx_axis_skid.u_rx_axis_skid.count_q,
                             u_dut.pay_busy,
                             u_dut.async_bridge_busy,
                             u_dut.async_writer_busy);
                    $finish;
                end
            end
        end
    end
endtask

task compare_expected_rx_payloads;
    input integer sample_stride;
    integer frame_i;
    integer byte_i;
    integer start_mid;
    begin
        tp_payload_crc_q = 32'hffff_ffff;
        for (frame_i = 0; frame_i < frame_expected_count_q; frame_i = frame_i + 1) begin
            if (sample_stride <= 0 || frame_len_q[frame_i] <= 1024) begin
                for (byte_i = 0; byte_i < frame_len_q[frame_i]; byte_i = byte_i + 1) begin
                    if (`DMA_SYS_MEM_PATH[frame_dst_q[frame_i] + byte_i] !== pkt_mem[frame_src_q[frame_i] + byte_i]) begin
                        $display("Error: payload mismatch frame=%0d dst=%08x src=%08x byte=%0d got=%02x exp=%02x",
                                 frame_i,
                                 frame_dst_q[frame_i] + byte_i,
                                 frame_src_q[frame_i] + byte_i,
                                 byte_i,
                                 `DMA_SYS_MEM_PATH[frame_dst_q[frame_i] + byte_i],
                                 pkt_mem[frame_src_q[frame_i] + byte_i]);
                        $finish;
                    end
                    tp_payload_crc_q = crc32_byte(
                        tp_payload_crc_q,
                        `DMA_SYS_MEM_PATH[frame_dst_q[frame_i] + byte_i]);
                end
            end else begin
                for (byte_i = 0; byte_i < 64; byte_i = byte_i + 1) begin
                    if (`DMA_SYS_MEM_PATH[frame_dst_q[frame_i] + byte_i] !== pkt_mem[frame_src_q[frame_i] + byte_i]) begin
                        $display("Error: payload mismatch head frame=%0d byte=%0d", frame_i, byte_i);
                        $finish;
                    end
                end
                start_mid = 64;
                while (start_mid < (frame_len_q[frame_i] - 64)) begin
                    if (`DMA_SYS_MEM_PATH[frame_dst_q[frame_i] + start_mid] !== pkt_mem[frame_src_q[frame_i] + start_mid]) begin
                        $display("Error: payload mismatch sample frame=%0d byte=%0d", frame_i, start_mid);
                        $finish;
                    end
                    start_mid = start_mid + sample_stride;
                end
                for (byte_i = frame_len_q[frame_i] - 64; byte_i < frame_len_q[frame_i]; byte_i = byte_i + 1) begin
                    if (`DMA_SYS_MEM_PATH[frame_dst_q[frame_i] + byte_i] !== pkt_mem[frame_src_q[frame_i] + byte_i]) begin
                        $display("Error: payload mismatch tail frame=%0d byte=%0d", frame_i, byte_i);
                        $finish;
                    end
                end
            end
        end
        tp_payload_crc_q = tp_payload_crc_q ^ 32'hffff_ffff;
    end
endtask

task wait_global_idle;
    integer guard;
    reg [31:0] status;
    begin
        guard = 0;
        repeat (40) @(posedge clk);
        u_ps.axil_read(`DMA_REG_GLOBAL_STATUS, status);
        while ((status[1] || status[2] || status[4]) && (guard < SCENARIO_TIMEOUT_CYCLES)) begin
            repeat (10) @(posedge clk);
            guard = guard + 10;
            u_ps.axil_read(`DMA_REG_GLOBAL_STATUS, status);
        end
        if (guard >= SCENARIO_TIMEOUT_CYCLES) begin
            scenario_deadlock_q = 32'd1;
            $display("Error: timeout waiting global idle scenario=%0s status=%08x rx_state=%0d wr_state=%0d pay_busy=%0d cdc_busy=%0d writer_busy=%0d frame_valid=%0d pool_state=%0d pool_m_valid=%0d pool_m_ready=%0d",
                     scenario_name_q, status,
                     u_dut.rx_state,
                     u_dut.wr_state,
                     u_dut.pay_busy,
                     u_dut.async_bridge_busy,
                     u_dut.async_writer_busy,
                     u_dut.u_frame_shared_adapter.frame_valid_q,
                     u_dut.u_frame_shared_adapter.u_pool.rd_state,
                     u_dut.u_frame_shared_adapter.pool_m_valid,
                     u_dut.u_frame_shared_adapter.pool_m_ready);
            $finish;
        end
    end
endtask

task wait_for_cqe_count;
    input [31:0] expected;
    integer guard;
    begin
        guard = 0;
        while ((cq_cqe_completed_q < expected) && (guard < SCENARIO_TIMEOUT_CYCLES)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (guard >= SCENARIO_TIMEOUT_CYCLES) begin
            scenario_deadlock_q = 32'd1;
            $display("Error: timeout waiting cq count scenario=%0s got=%0d exp=%0d",
                     scenario_name_q, cq_cqe_completed_q, expected);
            $display("DMA_TP_TIMEOUT_STATE tx_fire=%0d rx_fire=%0d rx_frames_seen=%0d rx_payload_left=%0d rx_cqe=%0d tx_cqe=%0d rx_state=%0d wr_state=%0d pay_busy=%0d bridge_busy=%0d writer_busy=%0d pool_frame_valid=%0d pool_state=%0d pool_free=%0d",
                     tp_tx_axis_fire_q, tp_rx_axis_fire_q,
                     tp_rx_stream_frame_q,
                     tp_rx_stream_payload_beats_left_q,
                     tp_rx_cqe_done_q, tp_tx_cqe_done_q,
                     u_dut.rx_state, u_dut.wr_state, u_dut.pay_busy,
                     u_dut.async_bridge_busy, u_dut.async_writer_busy,
                     u_dut.u_frame_shared_adapter.frame_valid_q,
                     u_dut.u_frame_shared_adapter.u_pool.rd_state,
                     u_dut.u_frame_shared_adapter.u_pool.free_count);
            $finish;
        end
    end
endtask

task wait_for_cq_wr_ptr_value;
    input [31:0] expected;
    integer guard;
    reg [31:0] rd_value;
    begin
        guard = 0;
        u_ps.axil_read(`DMA_REG_CQ_WR_PTR, rd_value);
        while ((rd_value != expected) && (guard < SCENARIO_TIMEOUT_CYCLES)) begin
            repeat (5) @(posedge clk);
            guard = guard + 5;
            u_ps.axil_read(`DMA_REG_CQ_WR_PTR, rd_value);
        end
        if (guard >= SCENARIO_TIMEOUT_CYCLES) begin
            scenario_deadlock_q = 32'd1;
            $display("Error: timeout waiting cq wr ptr scenario=%0s got=%0d exp=%0d",
                     scenario_name_q, rd_value, expected);
            $finish;
        end
    end
endtask

task release_cq_rd_ptr_pattern;
    input integer releases;
    input integer interval_cycles;
    integer rel_i;
    reg [31:0] rd_ptr_value;
    begin
        rd_ptr_value = 32'h0;
        for (rel_i = 0; rel_i < releases; rel_i = rel_i + 1) begin
            repeat (interval_cycles) @(posedge clk);
            rd_ptr_value = rd_ptr_value + 1;
            u_ps.axil_write(`DMA_REG_CQ_RD_PTR, rd_ptr_value);
        end
    end
endtask

task run_scenario_t0;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd32);
        fill_pkt_payload(32'h0000_0000, 32'd128, 8'h10);
        fill_pkt_payload(32'h0000_0200, 32'd256, 8'h20);
        start_scenario("T0", 32'h20a22000);
        axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, 16'h1000, 32'd128, 32'h0000_0000, 32'd1);
        axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, 16'h1001, 32'd256, 32'h0000_0200, 32'd2);
        wait_for_cqe_count(32'd2);
        wait_global_idle();
        compare_expected_rx_payloads(0);
        finish_scenario("T0");
    end
endtask

task run_scenario_t1;
    integer frame_i;
    reg [31:0] src_base;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd64);
        start_scenario("T1", 32'h20a22001);
        for (frame_i = 0; frame_i < 32; frame_i = frame_i + 1) begin
            src_base = frame_i * 32'h0800;
            fill_pkt_payload(src_base, 32'd1024, 8'h31);
            axis_send_frame_nobubble(RX_CH_NOCPL, FLOW_ID_NOCPL, frame_i[15:0], 32'd1024, src_base, frame_i + 1);
        end
        wait_global_idle();
        compare_expected_rx_payloads(0);
        finish_scenario("T1");
    end
endtask

task run_scenario_t2;
    integer frame_i;
    reg [31:0] src_base;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd128);
        start_scenario("T2", 32'h20a22002);
        for (frame_i = 0; frame_i < 32; frame_i = frame_i + 1) begin
            src_base = frame_i * 32'h0800;
            fill_pkt_payload(src_base, 32'd1024, 8'h42);
            axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, frame_i[15:0], 32'd1024, src_base, frame_i + 1);
        end
        wait_for_cqe_count(32'd32);
        wait_global_idle();
        compare_expected_rx_payloads(0);
        finish_scenario("T2");
    end
endtask

task run_scenario_t3;
    integer frame_i;
    reg [31:0] src_base;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd512);
        start_scenario("T3", 32'h20a22003);
        for (frame_i = 0; frame_i < 256; frame_i = frame_i + 1) begin
            src_base = frame_i * 32'h0040;
            fill_pkt_payload(src_base, 32'd64, 8'h53);
            axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, frame_i[15:0], 32'd64, src_base, frame_i + 1);
        end
        wait_for_cqe_count(32'd256);
        wait_global_idle();
        compare_expected_rx_payloads(0);
        finish_scenario("T3");
    end
endtask

task run_scenario_t4;
    integer frame_i;
    reg [31:0] src_base;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd64);
        start_scenario("T4", 32'h20a22004);
        for (frame_i = 0; frame_i < 16; frame_i = frame_i + 1) begin
            src_base = frame_i * 32'h4000;
            fill_pkt_payload(src_base, 32'd4096, 8'h64);
            axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, frame_i[15:0], 32'd4096, src_base, frame_i + 1);
        end
        wait_for_cqe_count(32'd16);
        wait_global_idle();
        compare_expected_rx_payloads(512);
        finish_scenario("T4");
    end
endtask

task run_scenario_t5;
    integer frame_i;
    reg [31:0] src_base;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd128);
        start_scenario("T5", 32'h20a22005);
        stall_enable = 1'b1;
        stall_random_mode = 1'b0;
        stall_aw_mod = 8'd5;
        stall_w_mod = 8'd4;
        stall_b_mod = 8'd7;
        for (frame_i = 0; frame_i < 32; frame_i = frame_i + 1) begin
            src_base = frame_i * 32'h0400;
            fill_pkt_payload(src_base, 32'd512, 8'h75);
            axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, frame_i[15:0], 32'd512, src_base, frame_i + 1);
        end
        wait_for_cqe_count(32'd32);
        wait_global_idle();
        compare_expected_rx_payloads(0);
        stall_enable = 1'b0;
        finish_scenario("T5");
    end
endtask

task run_scenario_t6;
    integer frame_i;
    reg [31:0] src_base;
    reg [31:0] cq_wr_ptr_before_release;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd16);
        start_scenario("T6", 32'h20a22006);
        fork
            begin
                for (frame_i = 0; frame_i < 16; frame_i = frame_i + 1) begin
                    src_base = frame_i * 32'h0200;
                    fill_pkt_payload(src_base, 32'd256, 8'h86);
                    axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, frame_i[15:0], 32'd256, src_base, frame_i + 1);
                end
            end
            begin
                wait_for_cqe_count(32'd8);
                repeat (100) @(posedge clk);
                u_ps.axil_read(`DMA_REG_CQ_WR_PTR, cq_wr_ptr_before_release);
                if (cq_wr_ptr_before_release > 32'd15)
                    fail("T6 CQ_WR_PTR advanced beyond near-full boundary before release");
                release_cq_rd_ptr_pattern(16, 80);
            end
        join
        wait_for_cqe_count(32'd16);
        wait_global_idle();
        compare_expected_rx_payloads(0);
        finish_scenario("T6");
    end
endtask

task run_scenario_t7;
    integer frame_i;
    reg [31:0] src_base;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd256);
        config_tx_desc_queue();
        prepare_tx_payload(64, TX_PAYLOAD_BASE, 32'd256, 8'h97);
        start_scenario("T7", 32'h20a22007);
        fork
            begin
                start_tx_desc_queue(64);
            end
            begin
                for (frame_i = 0; frame_i < 64; frame_i = frame_i + 1) begin
                    src_base = frame_i * 32'h0200;
                    fill_pkt_payload(src_base, 32'd256, 8'h98);
                    axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL, frame_i[15:0], 32'd256, src_base, frame_i + 1);
                end
            end
        join
        wait_for_cqe_count(32'd128);
        wait_global_idle();
        compare_expected_rx_payloads(0);
        finish_scenario("T7");
    end
endtask

task run_scenario_t8;
    integer frame_i;
    integer desc_i;
    reg [31:0] src_base;
    reg [31:0] payload_len;
    reg [31:0] local_seed;
    reg [15:0] flow_id_sel;
    reg [31:0] tx_count;
    begin
        reset_dut();
        init_test_memories();
        config_default_env(32'd256);
        config_tx_desc_queue();
        start_scenario("T8", 32'h20a22008);
        stall_enable = 1'b1;
        stall_random_mode = 1'b1;
        local_seed = 32'h20a22008;
        tx_count = 16;
        for (desc_i = 0; desc_i < tx_count; desc_i = desc_i + 1)
            write_tx_desc(TX_DESC_BASE + (desc_i * `DMA_TX_DESC_BYTES), 32'd192,
                          TX_PAYLOAD_BASE + (desc_i * 32'h200), desc_i + 1);
        for (desc_i = 0; desc_i < tx_count; desc_i = desc_i + 1)
            u_hp0.preload_pattern(TX_PAYLOAD_BASE + (desc_i * 32'h200), 192, 8'ha0 + desc_i[7:0]);
        fork
            begin
                start_tx_desc_queue(tx_count);
            end
            begin
                for (frame_i = 0; frame_i < 48; frame_i = frame_i + 1) begin
                    local_seed = {local_seed[30:0], local_seed[31] ^ local_seed[21] ^ local_seed[1] ^ local_seed[0]};
                    payload_len = ((local_seed[10:0] % 32'd31) + 1) * 32'd64;
                    src_base = frame_i * 32'h1000;
                    fill_pkt_payload(src_base, payload_len, local_seed[7:0]);
                    flow_id_sel = local_seed[12] ? FLOW_ID_CPL : FLOW_ID_NOCPL;
                    axis_send_frame_nobubble((flow_id_sel == FLOW_ID_CPL) ? RX_CH_CPL : RX_CH_NOCPL,
                                             flow_id_sel, frame_i[15:0], payload_len, src_base, frame_i + 1);
                end
            end
        join
        wait_for_cqe_count(scenario_expected_cqe_q);
        wait_global_idle();
        compare_expected_rx_payloads(512);
        stall_enable = 1'b0;
        finish_scenario("T8");
    end
endtask

task verify_throughput_cq;
    integer cqe_i;
    reg [31:0] cqe_addr;
    reg [7:0] direction;
    reg [7:0] status_code;
    reg [7:0] channel_id;
    reg [15:0] flow_id;
    reg [31:0] payload_len;
    reg [31:0] payload_addr;
    reg [31:0] frame_seq;
    begin
        tp_cqe_rx_scanned_q = 0;
        tp_cqe_tx_scanned_q = 0;
        for (cqe_i = 0; cqe_i < scenario_expected_cqe_q;
             cqe_i = cqe_i + 1) begin
            cqe_addr = CQ_BASE + (cqe_i * `DMA_CQE_BYTES);
            if (sys_u32(cqe_addr + `DMA_CQE_MAGIC_OFF) !== `DMA_CQE_MAGIC)
                fail("CQE magic missing before owner scan");
            if (sys_u32(cqe_addr + `DMA_CQE_OWNER_OFF) === 32'h0)
                fail("CQE owner not published");
            direction = sys_u8(cqe_addr + `DMA_CQE_DIRECTION_OFF);
            status_code = sys_u8(cqe_addr + `DMA_CQE_STATUS_OFF);
            channel_id = sys_u8(cqe_addr + `DMA_CQE_CHANNEL_ID_OFF);
            flow_id = sys_u16(cqe_addr + `DMA_CQE_FLOW_ID_OFF);
            payload_len = sys_u32(cqe_addr + `DMA_CQE_LENGTH_OFF);
            payload_addr = sys_u32(cqe_addr + `DMA_CQE_ADDR_OFF);
            frame_seq = sys_u32(cqe_addr + `DMA_CQE_FRAME_SEQ_OFF);
            if (direction == `DMA_CQE_DIR_RX) begin
                if (status_code != `DMA_ST_FRAME_DONE)
                    fail("RX CQE status mismatch");
                if (tp_is_mixed_q) begin
                    if ((channel_id >= PERF_CHANNELS) ||
                        (flow_id != (PERF_FLOW_BASE + channel_id)))
                        fail("mixed RX CQE flow/channel mismatch");
                end else if (flow_id !=
                             (tp_is_loopback_q ? FLOW_ID_TX : FLOW_ID_CPL)) begin
                    fail("RX CQE flow mismatch");
                end
                tp_cqe_rx_scanned_q = tp_cqe_rx_scanned_q + 1;
            end else if (direction == `DMA_CQE_DIR_TX) begin
                if (status_code != `DMA_ST_TX_DONE)
                    fail("TX CQE status mismatch");
                if (!tp_is_loopback_q || channel_id != TX_CH)
                    fail("unexpected TX CQE");
                tp_cqe_tx_scanned_q = tp_cqe_tx_scanned_q + 1;
            end else begin
                fail("unknown CQE direction");
            end
            $display("DMA_TP_TRACE cqe=%0d dir=%0d ch=%0d flow=%04x len=%0d seq=%0d addr=%08x owner=1",
                     cqe_i, direction, channel_id, flow_id,
                     payload_len, frame_seq, payload_addr);
        end
        if (tp_cqe_rx_scanned_q != tp_frames_q)
            fail("RX CQE scan count mismatch");
        if (tp_is_loopback_q && tp_cqe_tx_scanned_q != tp_frames_q)
            fail("TX CQE scan count mismatch");
        if (!tp_is_loopback_q && tp_cqe_tx_scanned_q != 0)
            fail("RX-only point emitted TX CQE");
    end
endtask

task finish_throughput_point;
    integer ch_i;
    reg [63:0] hw_cycles;
    reg [63:0] steady_cycles;
    begin
        if (!tp_hw_started_q || !tp_hw_finished_q ||
            (tp_hw_end_cycle_q < tp_hw_start_cycle_q))
            fail("invalid hardware_end_to_end window");
        if (!tp_steady_started_q || !tp_steady_finished_q ||
            (tp_steady_end_cycle_q < tp_steady_start_cycle_q))
            fail("invalid datapath_steady_state window");
        if (tp_rx_payload_bytes_q != tp_expected_payload_bytes_q)
            fail("RX payload byte counter mismatch");
        if (tp_rx_cqe_done_q != tp_frames_q)
            fail("RX owner completion count mismatch");
        if (tp_is_loopback_q && tp_tx_cqe_done_q != tp_frames_q)
            fail("TX owner completion count mismatch");
        if (!tp_is_loopback_q && tp_tx_cqe_done_q != 0)
            fail("unexpected TX owner completion");

        hw_cycles = tp_hw_end_cycle_q - tp_hw_start_cycle_q + 1'b1;
        steady_cycles = tp_steady_end_cycle_q -
                        tp_steady_start_cycle_q + 1'b1;
        $display("DMA_TP_RAW_POINT status=UNVERIFIED case=%0s frames=%0d payload_bytes=%0d shared=%0d response_latency=%0d service_percent=%0d mem_phase_ns=%0d hw_cycles=%0d steady_cycles=%0d rx_axis_valid=%0d rx_axis_ready=%0d rx_axis_fire=%0d tx_axis_valid=%0d tx_axis_ready=%0d tx_axis_fire=%0d main_read_bytes=%0d rx_payload_write_bytes=%0d cq_bus_write_bytes=%0d main_ar_bursts=%0d main_aw_bursts=%0d rx_aw_bursts=%0d rx_peak_outstanding=%0d tx_peak_outstanding=%0d rx_input_stall=%0d cdc_payload_stall=%0d aw_stall=%0d w_stall=%0d b_stall=%0d ar_stall=%0d r_stall=%0d rx_cqe=%0d tx_cqe=%0d protocol_error=%0d",
                 tp_case_q, tp_frames_q, tp_expected_payload_bytes_q,
                 HP0_SHARED_SERVICE, HP0_RESPONSE_LATENCY,
                 HP0_SERVICE_PERCENT, MEM_PHASE_NS,
                 hw_cycles, steady_cycles,
                 tp_rx_axis_valid_q, tp_rx_axis_ready_q,
                 tp_rx_axis_fire_q, tp_tx_axis_valid_q,
                 tp_tx_axis_ready_q, tp_tx_axis_fire_q,
                 tp_main_read_bytes_q, tp_rx_payload_bytes_q,
                 tp_main_write_bytes_q, tp_main_ar_bursts_q,
                 tp_main_aw_bursts_q, tp_rx_aw_bursts_q,
                 tp_rx_peak_outstanding_q,
                 u_dut.u_tx_engine.pf_debug_peak_outstanding,
                 tp_rx_input_stall_q, tp_cdc_payload_stall_q,
                 tp_aw_stall_q, tp_w_stall_q, tp_b_stall_q,
                 tp_ar_stall_q, tp_r_stall_q,
                 tp_rx_cqe_done_q, tp_tx_cqe_done_q,
                 tp_protocol_error_q + u_hp0.debug_protocol_errors);
        if ((rx_frame_fail_q != 0) || (rx_frame_drop_q != 0) ||
            (scenario_deadlock_q != 0) || (tp_protocol_error_q != 0) ||
            (u_hp0.debug_protocol_errors != 0)) begin
            $display("DMA_TP_ERROR_COUNTS frame_fail=%0d frame_drop=%0d deadlock=%0d protocol=%0d hp0_protocol=%0d bridge_source=%0d bridge_mem=%0d serializer=%0d cq_rx_error=%0d cq_rx_full=%0d cq_tx_error=%0d cq_tx_full=%0d",
                     rx_frame_fail_q, rx_frame_drop_q, scenario_deadlock_q,
                     tp_protocol_error_q, u_hp0.debug_protocol_errors,
                     u_dut.async_bridge_protocol_error,
                     u_dut.async_mem_protocol_error,
                     u_dut.async_serializer_format_error,
                     u_dut.cq_single_rx_error, u_dut.cq_single_rx_full,
                     u_dut.cq_single_tx_error, u_dut.cq_single_tx_full);
            fail("error/drop/deadlock/protocol counter nonzero");
        end
        if (u_dut.cq_reserved_count != 0 || u_dut.async_bridge_busy ||
            u_dut.async_writer_busy ||
            (u_dut.frame_pool_free_count != `DMA_FRAME_POOL_BLOCK_NUM))
            fail("final ownership state not idle");
        if ((tp_frames_q == PERF_FRAME_COUNT) &&
            (tp_payload_bytes_q == 4096) &&
            (tp_rx_peak_outstanding_q != 4))
            fail("peak point did not observe four RX outstanding bursts");

        if (tp_is_mixed_q) begin
            for (ch_i = 0; ch_i < PERF_CHANNELS; ch_i = ch_i + 1) begin
                if (tp_flow_done_q[ch_i] != (tp_frames_q / PERF_CHANNELS))
                    fail("mixed-flow completion fairness mismatch");
                $display("DMA_TP_FLOW ch=%0d completions=%0d min_gap=%0d max_gap=%0d",
                         ch_i, tp_flow_done_q[ch_i],
                         (tp_flow_done_q[ch_i] <= 1) ? 0 : tp_flow_min_gap_q[ch_i],
                         tp_flow_max_gap_q[ch_i]);
            end
        end

        $display("DMA_TP_POINT case=%0s frames=%0d payload_bytes=%0d shared=%0d response_latency=%0d service_percent=%0d mem_phase_ns=%0d hw_start=%0d hw_end=%0d hw_cycles=%0d steady_start=%0d steady_end=%0d steady_cycles=%0d rx_axis_valid=%0d rx_axis_ready=%0d rx_axis_fire=%0d tx_axis_valid=%0d tx_axis_ready=%0d tx_axis_fire=%0d main_read_bytes=%0d rx_payload_write_bytes=%0d cq_bus_write_bytes=%0d main_ar_bursts=%0d main_aw_bursts=%0d rx_aw_bursts=%0d rx_peak_outstanding=%0d tx_peak_outstanding=%0d rx_input_stall=%0d cdc_payload_stall=%0d aw_stall=%0d w_stall=%0d b_stall=%0d ar_stall=%0d r_stall=%0d rx_cqe=%0d tx_cqe=%0d frame_fail=%0d frame_drop=%0d deadlock=%0d protocol_error=%0d payload_crc=%08x latency_count=%0d",
                 tp_case_q, tp_frames_q, tp_expected_payload_bytes_q,
                 HP0_SHARED_SERVICE, HP0_RESPONSE_LATENCY,
                 HP0_SERVICE_PERCENT, MEM_PHASE_NS,
                 tp_hw_start_cycle_q, tp_hw_end_cycle_q, hw_cycles,
                 tp_steady_start_cycle_q, tp_steady_end_cycle_q,
                 steady_cycles,
                 tp_rx_axis_valid_q, tp_rx_axis_ready_q, tp_rx_axis_fire_q,
                 tp_tx_axis_valid_q, tp_tx_axis_ready_q, tp_tx_axis_fire_q,
                 tp_main_read_bytes_q, tp_rx_payload_bytes_q,
                 tp_main_write_bytes_q, tp_main_ar_bursts_q,
                 tp_main_aw_bursts_q, tp_rx_aw_bursts_q,
                 tp_rx_peak_outstanding_q,
                 u_dut.u_tx_engine.pf_debug_peak_outstanding,
                 tp_rx_input_stall_q, tp_cdc_payload_stall_q,
                 tp_aw_stall_q, tp_w_stall_q, tp_b_stall_q,
                 tp_ar_stall_q, tp_r_stall_q,
                 tp_rx_cqe_done_q, tp_tx_cqe_done_q,
                 rx_frame_fail_q, rx_frame_drop_q, scenario_deadlock_q,
                 tp_protocol_error_q + u_hp0.debug_protocol_errors,
                 tp_payload_crc_q, tp_latency_count_q);
        $display("DMA_TP_BOUNDARY async64_interface_limit_B_per_cycle=8 sameclock512_claim_not_reused=1 hp0_model_not_board_measurement=1 seed=71 rx_contexts=16 tx_contexts=16 desc_workload=1024 desc_ring_capacity=2048 cq_entries=4096");
    end
endtask

task run_throughput_case;
    integer frame_i;
    integer payload_len;
    integer ch_i;
    reg [31:0] src_base;
    reg [15:0] flow_id;
    begin
        if ((tp_frames_q <= 0) || (tp_frames_q > PERF_FRAME_COUNT))
            fail("DMA_TP_FRAMES must be 1..1024");
        if (!((tp_payload_bytes_q == 64) ||
              (tp_payload_bytes_q == 128) ||
              (tp_payload_bytes_q == 256) ||
              (tp_payload_bytes_q == 1024) ||
              (tp_payload_bytes_q == 4096)))
            fail("DMA_TP_PAYLOAD_BYTES outside fixed sweep");

        tp_is_loopback_q = (tp_case_q == "loopback_peak") ||
                           (tp_case_q == "loopback_size") ||
                           (tp_case_q == "mixed16") ||
                           (tp_case_q == "hp0_sensitivity");
        tp_is_mixed_q = (tp_case_q == "mixed16");
        if (!tp_is_loopback_q &&
            !((tp_case_q == "rx_peak") || (tp_case_q == "rx_size")))
            fail("unknown DMA_TP_CASE");

        reset_dut();
        init_test_memories();
        config_throughput_env(tp_is_loopback_q, tp_is_mixed_q);
        if (tp_is_loopback_q)
            config_tx_desc_queue_throughput();
        start_scenario(tp_case_q, 32'd71);
        loopback_enable = tp_is_loopback_q;

        if (tp_is_loopback_q) begin
            prepare_loopback_workload(tp_frames_q, tp_is_mixed_q,
                                      tp_payload_bytes_q);
            start_tx_desc_queue_throughput(tp_frames_q);
        end else begin
            tp_expected_payload_bytes_q = tp_frames_q * tp_payload_bytes_q;
            for (frame_i = 0; frame_i < tp_frames_q;
                 frame_i = frame_i + 1) begin
                payload_len = tp_payload_bytes_q;
                src_base = frame_i * 32'd4096;
                fill_pkt_payload(src_base, payload_len,
                                 8'h71 ^ frame_i[7:0]);
                axis_send_frame_nobubble(RX_CH_CPL, FLOW_ID_CPL,
                                         frame_i[15:0], payload_len,
                                         src_base, frame_i + 1);
            end
        end

        wait_for_cqe_count(scenario_expected_cqe_q);
        wait_global_idle();
        compare_expected_rx_payloads(0);
        verify_throughput_cq();
        finish_throughput_point();
        finish_scenario(tp_case_q);
        $display("DMA_ASYNC64_END_TO_END_THROUGHPUT_PASS");
    end
endtask

always @(posedge mem_clk or negedge mem_rstn) begin
    if (!mem_rstn) begin
        tp_rx_peak_outstanding_q <= 8'd0;
    end else if (scenario_active &&
                 (u_dut.u_payload_writer_async64.outstanding_count_q >
                  tp_rx_peak_outstanding_q)) begin
        tp_rx_peak_outstanding_q <=
            u_dut.u_payload_writer_async64.outstanding_count_q;
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tp_global_cycle_q <= 64'd0;
        tp_rx_stream_frame_q <= 32'd0;
        tp_rx_stream_payload_beats_left_q <= 32'd0;
    end else begin
        tp_global_cycle_q <= tp_global_cycle_q + 1'b1;
        if (scenario_active) begin
            if (dut_rx_axis_tvalid)
                tp_rx_axis_valid_q <= tp_rx_axis_valid_q + 1'b1;
            if (dut_rx_axis_tready)
                tp_rx_axis_ready_q <= tp_rx_axis_ready_q + 1'b1;
            if (tx_axis_tvalid)
                tp_tx_axis_valid_q <= tp_tx_axis_valid_q + 1'b1;
            if (dut_tx_axis_tready)
                tp_tx_axis_ready_q <= tp_tx_axis_ready_q + 1'b1;
            if (dut_rx_axis_tvalid && !dut_rx_axis_tready)
                tp_rx_input_stall_q <= tp_rx_input_stall_q + 1'b1;
            if (tx_axis_tvalid && dut_tx_axis_tready)
                tp_tx_axis_fire_q <= tp_tx_axis_fire_q + 1'b1;

            if (dut_rx_axis_tvalid && dut_rx_axis_tready) begin
                tp_rx_axis_fire_q <= tp_rx_axis_fire_q + 1'b1;
                if (tp_rx_stream_payload_beats_left_q == 0) begin
                    if ((tp_rx_stream_frame_q >= frame_expected_count_q) ||
                        (dut_rx_axis_tdata[96 +: 32] !=
                         frame_len_q[tp_rx_stream_frame_q]))
                        tp_protocol_error_q <= tp_protocol_error_q + 1'b1;
                    if ((tp_rx_stream_frame_q < frame_expected_count_q) &&
                        (dut_rx_axis_tdata[64 +: 16] !=
                         exp_rx_flow[frame_ch_q[tp_rx_stream_frame_q]]))
                        tp_protocol_error_q <= tp_protocol_error_q + 1'b1;
                    if ((dut_rx_axis_tdata[128 +: 32] == 0) ||
                        (dut_rx_axis_tdata[128 +: 32] > tp_frames_q)) begin
                        tp_protocol_error_q <= tp_protocol_error_q + 1'b1;
                    end else begin
                        tp_frame_start_by_seq_q[
                            dut_rx_axis_tdata[128 +: 32] - 1'b1] <=
                            tp_global_cycle_q + 1'b1;
                    end
                    tp_rx_stream_payload_beats_left_q <=
                        (dut_rx_axis_tdata[96 +: 32] + 32'd63) >> 6;
                    tp_rx_stream_frame_q <= tp_rx_stream_frame_q + 1'b1;
                    if (!tp_is_loopback_q && !tp_hw_started_q) begin
                        tp_hw_started_q <= 1'b1;
                        tp_hw_start_cycle_q <= tp_global_cycle_q + 1'b1;
                    end
                end else begin
                    tp_rx_stream_payload_beats_left_q <=
                        tp_rx_stream_payload_beats_left_q - 1'b1;
                    if (!tp_steady_started_q) begin
                        tp_steady_started_q <= 1'b1;
                        tp_steady_start_cycle_q <= tp_global_cycle_q + 1'b1;
                    end
                end
            end

            if (tp_doorbell_pending_q && s_axil_bvalid && s_axil_bready) begin
                tp_doorbell_pending_q <= 1'b0;
                tp_hw_started_q <= 1'b1;
                tp_hw_start_cycle_q <= tp_global_cycle_q + 1'b1;
            end

            if (dut_m_axi_arvalid && dut_m_axi_arready)
                tp_main_ar_bursts_q <= tp_main_ar_bursts_q + 1'b1;
            if (dut_m_axi_rvalid && dut_m_axi_rready)
                tp_main_read_bytes_q <= tp_main_read_bytes_q + 8;
            if (dut_m_axi_awvalid && dut_m_axi_awready)
                tp_main_aw_bursts_q <= tp_main_aw_bursts_q + 1'b1;
            if (dut_m_axi_wvalid && dut_m_axi_wready)
                tp_main_write_bytes_q <=
                    tp_main_write_bytes_q + popcount8(dut_m_axi_wstrb);
            if (rx_mem_awvalid && rx_mem_awready)
                tp_rx_aw_bursts_q <= tp_rx_aw_bursts_q + 1'b1;
            if (rx_mem_wvalid && rx_mem_wready) begin
                tp_rx_payload_bytes_q <=
                    tp_rx_payload_bytes_q + popcount8(rx_mem_wstrb);
                if (!tp_steady_finished_q &&
                    ((tp_rx_payload_bytes_q + popcount8(rx_mem_wstrb)) ==
                     tp_expected_payload_bytes_q)) begin
                    tp_steady_finished_q <= 1'b1;
                    tp_steady_end_cycle_q <= tp_global_cycle_q + 1'b1;
                end
            end

            if (u_dut.async_bridge_payload_tvalid &&
                !u_dut.async_bridge_payload_tready)
                tp_cdc_payload_stall_q <= tp_cdc_payload_stall_q + 1'b1;
            if (rx_mem_awvalid && !rx_mem_awready)
                tp_aw_stall_q <= tp_aw_stall_q + 1'b1;
            if (rx_mem_wvalid && !rx_mem_wready)
                tp_w_stall_q <= tp_w_stall_q + 1'b1;
            if (rx_mem_bvalid && !rx_mem_bready)
                tp_b_stall_q <= tp_b_stall_q + 1'b1;
            if (dut_m_axi_arvalid && !dut_m_axi_arready)
                tp_ar_stall_q <= tp_ar_stall_q + 1'b1;
            if (dut_m_axi_rvalid && !dut_m_axi_rready)
                tp_r_stall_q <= tp_r_stall_q + 1'b1;

            if (u_dut.cq_single_rx_done) begin
                tp_rx_cqe_done_q <= tp_rx_cqe_done_q + 1'b1;
                if ((tp_rx_cqe_done_q + 1'b1) == tp_frames_q) begin
                    tp_hw_finished_q <= 1'b1;
                    tp_hw_end_cycle_q <= tp_global_cycle_q + 1'b1;
                end
                if ((u_dut.g_cq_single_writer.u_cq_single_writer.cmd_frame_seq_q == 0) ||
                    (u_dut.g_cq_single_writer.u_cq_single_writer.cmd_frame_seq_q >
                     tp_frames_q)) begin
                    tp_protocol_error_q <= tp_protocol_error_q + 1'b1;
                end else begin
                    tp_latency_cycles_tmp_q = tp_global_cycle_q + 1'b1 -
                        tp_frame_start_by_seq_q[
                            u_dut.g_cq_single_writer.u_cq_single_writer.cmd_frame_seq_q - 1'b1];
                    tp_latency_sample_q[tp_latency_count_q] <=
                        tp_latency_cycles_tmp_q;
                    tp_latency_count_q <= tp_latency_count_q + 1'b1;
                    $display("DMA_TP_LATENCY seq=%0d ch=%0d cycles=%0d",
                        u_dut.g_cq_single_writer.u_cq_single_writer.cmd_frame_seq_q,
                        u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q,
                        tp_latency_cycles_tmp_q);
                end
                if (u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q <
                    PERF_CHANNELS) begin
                    if (tp_flow_done_q[
                        u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q] != 0) begin
                        tp_latency_cycles_tmp_q = tp_global_cycle_q + 1'b1 -
                            tp_flow_last_done_q[
                                u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q];
                        if (tp_latency_cycles_tmp_q < tp_flow_min_gap_q[
                            u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q])
                            tp_flow_min_gap_q[
                                u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q] <=
                                tp_latency_cycles_tmp_q;
                        if (tp_latency_cycles_tmp_q > tp_flow_max_gap_q[
                            u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q])
                            tp_flow_max_gap_q[
                                u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q] <=
                                tp_latency_cycles_tmp_q;
                    end
                    tp_flow_done_q[
                        u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q] <=
                        tp_flow_done_q[
                            u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q] + 1'b1;
                    tp_flow_last_done_q[
                        u_dut.g_cq_single_writer.u_cq_single_writer.cmd_channel_id_q] <=
                        tp_global_cycle_q + 1'b1;
                end
            end
            if (u_dut.cq_single_tx_done)
                tp_tx_cqe_done_q <= tp_tx_cqe_done_q + 1'b1;
            if (u_dut.event_valid && u_dut.event_ch_valid) begin
                if (u_dut.event_status_code == `DMA_ST_FRAME_DONE)
                    rx_frame_done_q <= rx_frame_done_q + 1'b1;
                else if (u_dut.event_status_code != `DMA_ST_OK) begin
                    rx_frame_fail_q <= rx_frame_fail_q + 1'b1;
                    if (u_dut.event_status_code == `DMA_ST_DROP_NEW)
                        rx_frame_drop_q <= rx_frame_drop_q + 1'b1;
                end
            end
            if (u_dut.cq_single_rx_error || u_dut.cq_single_rx_full ||
                u_dut.cq_single_tx_error || u_dut.cq_single_tx_full ||
                (u_dut.async_bridge_protocol_error &&
                 !tp_prev_bridge_error_q) ||
                u_dut.async_mem_protocol_error ||
                u_dut.async_serializer_format_error)
                tp_protocol_error_q <= tp_protocol_error_q + 1'b1;
            if (u_dut.async_bridge_protocol_error &&
                !tp_prev_bridge_error_q) begin
                $display("DMA_TP_BRIDGE_ERROR cycle=%0d source_active=%0d payload_done=%0d s_cmd_valid=%0d s_cmd_ready=%0d s_payload_valid=%0d s_payload_ready=%0d s_payload_last=%0d s_cpl_valid=%0d s_cpl_ready=%0d reset_request=%0d",
                    tp_global_cycle_q + 1'b1,
                    u_dut.u_rx_payload_cdc_bridge.source_active_q,
                    u_dut.u_rx_payload_cdc_bridge.source_payload_done_q,
                    u_dut.pay_cmd_valid, u_dut.pay_cmd_ready,
                    u_dut.queue_wide_payload_tvalid,
                    u_dut.queue_wide_payload_tready,
                    u_dut.queue_wide_payload_tlast,
                    u_dut.pay_cpl_valid, u_dut.pay_cpl_ready,
                    u_dut.soft_reset_mem_request);
            end
            if (u_dut.u_rx_payload_cdc_bridge.source_payload_outside_frame &&
                !tp_bridge_cause_reported_q) begin
                $display("DMA_TP_BRIDGE_CAUSE cycle=%0d cause=source_payload_outside_frame source_active=%0d payload_done=%0d lookahead=%0d cmd_fire=%0d cpl_valid=%0d cpl_ready=%0d queue_pop=%0d payload_valid=%0d payload_ready=%0d payload_last=%0d payload_byte0=%02x source_is_frame=%0d selector_active=%0d frame_valid=%0d frame_seq=%0d frame_buf_valid=%0d frame_buf_last=%0d frame_pool_valid=%0d frame_pool_last=%0d frame_pool_ch=%0d stream_fifo_count=%0d stream_fifo_push=%0d stream_fifo_pop=%0d stream_issue=%0d stream_total=%0d",
                     tp_global_cycle_q + 1'b1,
                     u_dut.u_rx_payload_cdc_bridge.source_active_q,
                     u_dut.u_rx_payload_cdc_bridge.source_payload_done_q,
                     u_dut.u_rx_payload_cdc_bridge.ALLOW_SOURCE_PAYLOAD_LOOKAHEAD,
                     u_dut.u_rx_payload_cdc_bridge.s_cmd_fire,
                     u_dut.pay_cpl_valid,
                     u_dut.pay_cpl_ready,
                     u_dut.queue_pop,
                     u_dut.queue_wide_payload_tvalid,
                     u_dut.queue_wide_payload_tready,
                     u_dut.queue_wide_payload_tlast,
                     u_dut.queue_wide_payload_tdata[7:0],
                     u_dut.queue_active_is_frame,
                     u_dut.u_ingress_source_selector.active_q,
                     u_dut.u_frame_shared_adapter.frame_valid_q,
                     u_dut.u_frame_shared_adapter.frame_frame_seq_q,
                     u_dut.u_frame_shared_adapter.beat_buf_valid_q,
                     u_dut.u_frame_shared_adapter.beat_buf_last_q,
                     u_dut.u_frame_shared_adapter.pool_m_valid,
                     u_dut.u_frame_shared_adapter.pool_m_last,
                     u_dut.u_frame_shared_adapter.pool_m_ch_id,
                     u_dut.u_ingress_queue.wide_fifo_count_q,
                     u_dut.u_ingress_queue.wide_fifo_push,
                     u_dut.u_ingress_queue.wide_fifo_pop,
                     u_dut.u_ingress_queue.wide_issue_index_q,
                     u_dut.u_ingress_queue.wide_total_beats);
                tp_bridge_cause_reported_q <= 1'b1;
            end
            tp_prev_bridge_error_q <= u_dut.async_bridge_protocol_error;
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        scenario_cycles_q <= 64'd0;
        stall_cycle_count <= 32'd0;
        stall_lfsr <= 32'h1ace_beef;
        tx_req_waiting_q <= 1'b0;
        tx_req_accepted_q <= 1'b0;
        tx_req_start_cycle_q <= 64'd0;
        rx_req_waiting_q <= 1'b0;
        rx_req_start_cycle_q <= 64'd0;
        prev_tx_cqe_req_valid_q <= 1'b0;
        prev_wr_cqe_cmd_q <= 1'b0;
        prev_cq_single_rx_full_q <= 1'b0;
        prev_cq_single_tx_full_q <= 1'b0;
    end else begin
        if (scenario_active) begin
            scenario_cycles_q <= scenario_cycles_q + 1'b1;
            stall_cycle_count <= stall_cycle_count + 1'b1;
            stall_lfsr <= {stall_lfsr[30:0], stall_lfsr[31] ^ stall_lfsr[21] ^ stall_lfsr[1] ^ stall_lfsr[0]};

            if (rx_axis_tvalid)
                rx_tvalid_cycles_q <= rx_tvalid_cycles_q + 1'b1;
            if (rx_axis_tready)
                rx_tready_cycles_q <= rx_tready_cycles_q + 1'b1;
            if (rx_axis_tvalid && rx_axis_tready) begin
                rx_fire_cycles_q <= rx_fire_cycles_q + 1'b1;
                rx_accept_beats_q <= rx_accept_beats_q + 1'b1;
                rx_accept_bytes_q <= rx_accept_bytes_q + 64;
            end

            if (rx_mem_awvalid && rx_mem_awready)
                payload_aw_bursts_q <= payload_aw_bursts_q + 1'b1;
            if (rx_mem_wvalid && rx_mem_wready) begin
                payload_w_beats_q <= payload_w_beats_q + 1'b1;
                payload_write_bytes_q <= payload_write_bytes_q + popcount8(rx_mem_wstrb);
            end
            if (dut_m_axi_wvalid && dut_m_axi_wready)
                axi_w_fire_cycles_q <= axi_w_fire_cycles_q + 1'b1;
            if (u_dut.pay_rd_req)
                dbg_pay_rd_req_q <= dbg_pay_rd_req_q + 1'b1;
            if (u_dut.pay_rd_valid)
                dbg_pay_rd_valid_q <= dbg_pay_rd_valid_q + 1'b1;
            if (u_dut.stream_pay_rd_valid)
                dbg_stream_rd_valid_q <= dbg_stream_rd_valid_q + 1'b1;
            if (u_dut.frame_pay_rd_valid)
                dbg_frame_rd_valid_q <= dbg_frame_rd_valid_q + 1'b1;
            if (u_dut.u_frame_shared_adapter.pool_m_valid && u_dut.u_frame_shared_adapter.pool_m_ready)
                dbg_frame_pool_fire_q <= dbg_frame_pool_fire_q + 1'b1;
            if (dut_m_axi_wvalid && dut_m_axi_wready) begin
                dbg_w_run_q <= dbg_w_run_q + 1'b1;
                if ((dbg_w_run_q + 1'b1) > dbg_w_run_max_q)
                    dbg_w_run_max_q <= dbg_w_run_q + 1'b1;
            end else begin
                dbg_w_run_q <= 64'd0;
            end

            if ((u_dut.wr_state == WR_CQE_CMD) && !prev_wr_cqe_cmd_q)
                cq_rx_req_q <= cq_rx_req_q + 1'b1;
            if (u_dut.tx_cqe_req_valid && !prev_tx_cqe_req_valid_q)
                cq_tx_req_q <= cq_tx_req_q + 1'b1;
            if (u_dut.cq_single_rx_accept)
                cq_rx_accept_q <= cq_rx_accept_q + 1'b1;
            if (u_dut.cq_single_tx_accept)
                cq_tx_accept_q <= cq_tx_accept_q + 1'b1;
            if (u_dut.cq_single_busy)
                cq_busy_cycles_q <= cq_busy_cycles_q + 1'b1;
            if (u_dut.cq_single_commit_valid)
                cq_cqe_completed_q <= cq_cqe_completed_q + 1'b1;
            if (u_dut.cq_cmd_credit_count == 0)
                cq_credit_stall_cycles_q <= cq_credit_stall_cycles_q + 1'b1;

            case (u_dut.g_rx_axis_skid.u_rx_axis_skid.count_q)
            2'd0: skid_hist_0_q <= skid_hist_0_q + 1'b1;
            2'd1: skid_hist_1_q <= skid_hist_1_q + 1'b1;
            default: skid_hist_2_q <= skid_hist_2_q + 1'b1;
            endcase

            if (u_dut.rx_event_valid && (u_dut.rx_event_status_code == `DMA_ST_OK))
                rx_event_ok_q <= rx_event_ok_q + 1'b1;

            if (u_dut.event_valid && u_dut.event_ch_valid && (lat_count_pending_q > 0) &&
                (u_dut.event_status_code != `DMA_ST_OK)) begin
                lat_cycles_q = scenario_cycles_q + 1'b1 - lat_start_cycle_q[lat_head_q];
                if (u_dut.event_status_code == `DMA_ST_FRAME_DONE) begin
                    rx_frame_done_q <= rx_frame_done_q + 1'b1;
                    latency_sum_q <= latency_sum_q + lat_cycles_q;
                    latency_count_q <= latency_count_q + 1'b1;
                    if (latency_count_q == 0 || lat_cycles_q < latency_min_q)
                        latency_min_q <= lat_cycles_q;
                    if (lat_cycles_q > latency_max_q)
                        latency_max_q <= lat_cycles_q;
                end else begin
                    rx_frame_fail_q <= rx_frame_fail_q + 1'b1;
                    if (u_dut.event_status_code == `DMA_ST_DROP_NEW)
                        rx_frame_drop_q <= rx_frame_drop_q + 1'b1;
                end

                lat_head_q = lat_head_q + 1;
                if (lat_head_q >= MAX_TRACKED_FRAMES)
                    lat_head_q = 0;
                lat_count_pending_q = lat_count_pending_q - 1;
            end

            if (u_dut.tx_cqe_req_valid && !tx_req_waiting_q && !tx_req_accepted_q) begin
                tx_req_waiting_q <= 1'b1;
                tx_req_start_cycle_q <= scenario_cycles_q + 1'b1;
            end
            if (u_dut.cq_single_tx_accept) begin
                if (tx_req_waiting_q)
                    lat_cycles_q = scenario_cycles_q + 1'b1 - tx_req_start_cycle_q;
                else
                    lat_cycles_q = 64'd0;
                tx_req_lat_sum_q <= tx_req_lat_sum_q + lat_cycles_q;
                tx_req_lat_cnt_q <= tx_req_lat_cnt_q + 1'b1;
                if (lat_cycles_q > tx_req_lat_max_q)
                    tx_req_lat_max_q <= lat_cycles_q;
                tx_req_waiting_q <= 1'b0;
                tx_req_accepted_q <= 1'b1;
            end
            if (!u_dut.tx_cqe_req_valid)
                tx_req_accepted_q <= 1'b0;

            if ((u_dut.wr_state == WR_CQE_CMD) && !rx_req_waiting_q)
                rx_req_start_cycle_q <= scenario_cycles_q + 1'b1;
            if ((u_dut.wr_state == WR_CQE_CMD) && !rx_req_waiting_q)
                rx_req_waiting_q <= 1'b1;
            if (u_dut.cq_single_rx_accept) begin
                if (rx_req_waiting_q)
                    lat_cycles_q = scenario_cycles_q + 1'b1 - rx_req_start_cycle_q;
                else
                    lat_cycles_q = 64'd0;
                rx_req_lat_sum_q <= rx_req_lat_sum_q + lat_cycles_q;
                rx_req_lat_cnt_q <= rx_req_lat_cnt_q + 1'b1;
                if (lat_cycles_q > rx_req_lat_max_q)
                    rx_req_lat_max_q <= lat_cycles_q;
                rx_req_waiting_q <= 1'b0;
            end else if (rx_req_waiting_q && (u_dut.wr_state != WR_CQE_CMD))
                rx_req_waiting_q <= 1'b0;

            if (u_dut.cq_single_rx_full && !prev_cq_single_rx_full_q)
                cq_rx_full_q <= cq_rx_full_q + 1'b1;
            if (u_dut.cq_single_tx_full && !prev_cq_single_tx_full_q)
                cq_tx_full_q <= cq_tx_full_q + 1'b1;
        end

        prev_tx_cqe_req_valid_q <= u_dut.tx_cqe_req_valid;
        prev_wr_cqe_cmd_q <= (u_dut.wr_state == WR_CQE_CMD);
        prev_cq_single_rx_full_q <= u_dut.cq_single_rx_full;
        prev_cq_single_tx_full_q <= u_dut.cq_single_tx_full;
    end
end

initial begin
    clk = 1'b0;
    rstn = 1'b0;
    mem_rstn = 1'b0;
    rx_axis_tdata = 512'h0;
    rx_axis_tvalid = 1'b0;
    tx_axis_tready = 1'b1;
    loopback_enable = 1'b0;
    scenario_active = 1'b0;
    scenario_name_q = "IDLE";
    scenario_seed_q = 32'd71;
    tp_case_q = "rx_peak";
    tp_frames_q = PERF_FRAME_COUNT;
    tp_payload_bytes_q = 4096;
    if (!$value$plusargs("DMA_TP_CASE=%s", tp_case_q))
        tp_case_q = "rx_peak";
    if (!$value$plusargs("DMA_TP_FRAMES=%d", tp_frames_q))
        tp_frames_q = PERF_FRAME_COUNT;
    if (!$value$plusargs("DMA_TP_PAYLOAD_BYTES=%d", tp_payload_bytes_q))
        tp_payload_bytes_q = 4096;
    clear_scenario_metrics();
    run_throughput_case();
    $finish;
end

endmodule
