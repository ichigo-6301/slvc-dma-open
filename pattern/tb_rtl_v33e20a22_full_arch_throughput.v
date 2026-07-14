`timescale 1ns/1ps
`include "dma_sim_def.vh"

module tb;

localparam integer RX_CH_CPL    = 0;
localparam integer RX_CH_NOCPL  = 1;
localparam integer TX_CH        = 0;
localparam integer MAX_TRACKED_FRAMES = 1024;
localparam integer MAX_TX_DESC  = 256;
localparam integer SCENARIO_TIMEOUT_CYCLES = 400000;

localparam [15:0] FLOW_ID_CPL   = 16'h2200;
localparam [15:0] FLOW_ID_NOCPL = 16'h2201;
localparam [15:0] FLOW_ID_TX    = 16'h2290;
localparam [15:0] STREAM_ID_TX  = 16'h3390;

localparam [31:0] RX0_BASE      = 32'h0010_0000;
localparam [31:0] RX1_BASE      = 32'h0018_0000;
localparam [31:0] RX_RING_SIZE  = 32'h0004_0000;
localparam [31:0] CQ_BASE       = 32'h0008_0000;
localparam [31:0] TX_PAYLOAD_BASE= 32'h0002_0000;
localparam [31:0] TX_DESC_BASE  = 32'h000a_0000;
localparam [31:0] TX_DESC_SIZE  = 32'd8192;

localparam [2:0] WR_IDLE        = 3'd0;
localparam [2:0] WR_CQE_CMD     = 3'd3;
localparam [2:0] CQ_ST_IDLE     = 3'd0;

reg clk;
reg rstn;
reg [7:0] sys_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] ref_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] pkt_mem [0:`DMA_PKT_MEM_BYTES-1];

reg [511:0] rx_axis_tdata;
reg         rx_axis_tvalid;
wire        rx_axis_tready;

wire [511:0] tx_axis_tdata;
wire         tx_axis_tvalid;
reg          tx_axis_tready;

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

reg [31:0] exp_rx_base [0:1];
reg [31:0] exp_rx_wr_ptr [0:1];
reg [31:0] exp_rx_flow [0:1];
reg        exp_rx_cpl [0:1];

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

axi_ddr_mem_model u_ddr(
    .aclk(clk),
    .arstn(rstn),
    .awaddr(mem_m_axi_awaddr),
    .awlen(mem_m_axi_awlen),
    .awsize(mem_m_axi_awsize),
    .awburst(mem_m_axi_awburst),
    .awvalid(mem_m_axi_awvalid),
    .awready(mem_m_axi_awready),
    .wdata(mem_m_axi_wdata),
    .wstrb(mem_m_axi_wstrb),
    .wlast(mem_m_axi_wlast),
    .wvalid(mem_m_axi_wvalid),
    .wready(mem_m_axi_wready),
    .bresp(mem_m_axi_bresp),
    .bvalid(mem_m_axi_bvalid),
    .bready(mem_m_axi_bready),
    .araddr(mem_m_axi_araddr),
    .arlen(mem_m_axi_arlen),
    .arsize(mem_m_axi_arsize),
    .arburst(mem_m_axi_arburst),
    .arvalid(mem_m_axi_arvalid),
    .arready(mem_m_axi_arready),
    .rdata(mem_m_axi_rdata),
    .rresp(mem_m_axi_rresp),
    .rlast(mem_m_axi_rlast),
    .rvalid(mem_m_axi_rvalid),
    .rready(mem_m_axi_rready)
);

frame_dma_rx_top u_dut(
    .aclk(clk),
    .aresetn(rstn),
    .tx_axis_aclk(clk),
    .tx_axis_aresetn(rstn),
    .rx_axis_tdata(rx_axis_tdata),
    .rx_axis_tvalid(rx_axis_tvalid),
    .rx_axis_tready(rx_axis_tready),
    .tx_axis_tdata(tx_axis_tdata),
    .tx_axis_tvalid(tx_axis_tvalid),
    .tx_axis_tready(tx_axis_tready),
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
    .irq(irq)
);

assign ufc_tx_ready = 1'b1;
assign ufc_rx_valid = 1'b0;
assign ufc_rx_opcode = 8'h0;
assign ufc_rx_flow_id = 16'h0;
assign ufc_rx_arg0 = 32'h0;
assign ufc_rx_arg1 = 32'h0;

always #5 clk = ~clk;

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
        u_ddr.clear_all();
        for (idx = 0; idx < `DMA_PKT_MEM_BYTES; idx = idx + 1)
            pkt_mem[idx] = 8'h0;
        for (idx = 0; idx < `DMA_SIM_MEM_BYTES; idx = idx + 1)
            ref_mem[idx] = 8'h0;
    end
endtask

task reset_dut;
    begin
        rstn = 1'b0;
        rx_axis_tdata = 512'h0;
        rx_axis_tvalid = 1'b0;
        tx_axis_tready = 1'b1;
        stall_enable = 1'b0;
        stall_random_mode = 1'b0;
        stall_aw_mod = 8'd0;
        stall_w_mod = 8'd0;
        stall_b_mod = 8'd0;
        stall_lfsr = 32'h1ace_beef;
        stall_cycle_count = 32'h0;
        repeat (12) @(posedge clk);
        rstn = 1'b1;
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
                if (lat_count_pending_q >= MAX_TRACKED_FRAMES)
                    fail("latency queue overflow");
                if (beat_idx == 0) begin
                    lat_start_cycle_q[lat_tail_q] = scenario_cycles_q + 1'b1;
                    lat_payload_len_q[lat_tail_q] = payload_len;
                    lat_ch_q[lat_tail_q] = ch[3:0];
                    lat_tail_q = lat_tail_q + 1;
                    if (lat_tail_q >= MAX_TRACKED_FRAMES)
                        lat_tail_q = 0;
                    lat_count_pending_q = lat_count_pending_q + 1;
                end
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
                    $display("Error: timeout sending frame scenario=%0s ch=%0d seq=%0d beat=%0d/%0d rx_state=%0d wr_state=%0d skid_count=%0d pay_busy=%0d pref_active=%0d pref_issue=%0d pref_return=%0d pref_out=%0d pref_block_wait=%0d w_fifo_count=%0d w_pending_bursts=%0d rd_req=%0d rd_valid=%0d",
                             scenario_name_q, ch, frame_seq, beat_idx, total_beats,
                             u_dut.rx_state, u_dut.wr_state,
                             u_dut.g_rx_axis_skid.u_rx_axis_skid.count_q,
                             u_dut.pay_busy,
                             u_dut.u_payload_writer.prefetch_active,
                             u_dut.u_payload_writer.prefetch_issue_count,
                             u_dut.u_payload_writer.prefetch_return_count,
                             u_dut.u_payload_writer.prefetch_rd_outstanding_count,
                             u_dut.u_payload_writer.prefetch_block_wait,
                             u_dut.u_payload_writer.w_fifo_count,
                             u_dut.u_payload_writer.w_pending_burst_count,
                             u_dut.pay_rd_req,
                             u_dut.pay_rd_valid);
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
            $display("Error: timeout waiting global idle scenario=%0s status=%08x rx_state=%0d wr_state=%0d pay_busy=%0d pref_active=%0d pref_issue=%0d pref_return=%0d pref_out=%0d w_fifo_count=%0d w_pending_bursts=%0d frame_valid=%0d pending_rd=%0d pending_idx=%0d beat_block=%0d beat_valid=%0d pool_state=%0d pool_drain_rem=%0d pool_sel_cnt=%0d pool_m_valid=%0d pool_m_ready=%0d pool_m_last=%0d",
                     scenario_name_q, status,
                     u_dut.rx_state,
                     u_dut.wr_state,
                     u_dut.pay_busy,
                     u_dut.u_payload_writer.prefetch_active,
                     u_dut.u_payload_writer.prefetch_issue_count,
                     u_dut.u_payload_writer.prefetch_return_count,
                     u_dut.u_payload_writer.prefetch_rd_outstanding_count,
                     u_dut.u_payload_writer.w_fifo_count,
                     u_dut.u_payload_writer.w_pending_burst_count,
                     u_dut.u_frame_shared_adapter.frame_valid_q,
                     u_dut.u_frame_shared_adapter.pending_rd_q,
                     u_dut.u_frame_shared_adapter.pending_rd_index_q,
                     u_dut.u_frame_shared_adapter.beat_block_q,
                     u_dut.u_frame_shared_adapter.beat_buf_valid_q,
                     u_dut.u_frame_shared_adapter.u_pool.rd_state,
                     u_dut.u_frame_shared_adapter.u_pool.drain_remaining,
                     u_dut.u_frame_shared_adapter.u_pool.selected_meta_count_q,
                     u_dut.u_frame_shared_adapter.pool_m_valid,
                     u_dut.u_frame_shared_adapter.pool_m_ready,
                     u_dut.u_frame_shared_adapter.pool_m_last);
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
            u_ddr.preload_pattern(TX_PAYLOAD_BASE + (desc_i * 32'h200), 192, 8'ha0 + desc_i[7:0]);
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

            if (u_dut.pay_awvalid && u_dut.pay_awready)
                payload_aw_bursts_q <= payload_aw_bursts_q + 1'b1;
            if (u_dut.pay_wvalid && u_dut.pay_wready) begin
                payload_w_beats_q <= payload_w_beats_q + 1'b1;
                payload_write_bytes_q <= payload_write_bytes_q + popcount8(u_dut.pay_wstrb);
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
    rx_axis_tdata = 512'h0;
    rx_axis_tvalid = 1'b0;
    tx_axis_tready = 1'b1;
    scenario_active = 1'b0;
    scenario_name_q = "IDLE";
    scenario_seed_q = 32'h20a22000;
    single_scenario_q = -1;
    if (!$value$plusargs("E20A22_SCENARIO=%d", single_scenario_q))
        single_scenario_q = -1;
    clear_scenario_metrics();
    init_test_memories();

    if (single_scenario_q < 0 || single_scenario_q == 0) run_scenario_t0();
    if (single_scenario_q < 0 || single_scenario_q == 1) run_scenario_t1();
    if (single_scenario_q < 0 || single_scenario_q == 2) run_scenario_t2();
    if (single_scenario_q < 0 || single_scenario_q == 3) run_scenario_t3();
    if (single_scenario_q < 0 || single_scenario_q == 4) run_scenario_t4();
    if (single_scenario_q < 0 || single_scenario_q == 5) run_scenario_t5();
    if (single_scenario_q < 0 || single_scenario_q == 6) run_scenario_t6();
    if (single_scenario_q < 0 || single_scenario_q == 7) run_scenario_t7();
    if (single_scenario_q < 0 || single_scenario_q == 8) run_scenario_t8();

    $display("E20A22_FULL_ARCH_THROUGHPUT_PASS");
    $finish;
end

endmodule
