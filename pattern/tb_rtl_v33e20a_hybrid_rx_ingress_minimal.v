`timescale 1ns/1ps
`include "dma_sim_def.vh"

`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
`define DMA_RX_DEDICATED_PAYLOAD_TB
`elsif DMA_RX_MEM_ASYNC_PROFILE
`define DMA_RX_DEDICATED_PAYLOAD_TB
`endif

module tb;

reg clk;
reg rstn;
reg clk_enable;
`ifdef DMA_RX_MEM_ASYNC_PROFILE
reg mem_clk;
reg mem_rstn;
reg mem_clk_enable;
`endif
reg [7:0] sys_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] ref_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] pkt_mem [0:`DMA_PKT_MEM_BYTES-1];

wire [511:0] rx_axis_tdata;
wire         rx_axis_tvalid;
wire         rx_axis_tready;

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

wire [31:0] m_axi_awaddr;
wire [7:0]  m_axi_awlen;
wire [2:0]  m_axi_awsize;
wire [1:0]  m_axi_awburst;
wire        m_axi_awvalid;
wire        m_axi_awready;
wire        m_axi_awready_raw;
wire [63:0] m_axi_wdata;
wire [7:0]  m_axi_wstrb;
wire        m_axi_wlast;
wire        m_axi_wvalid;
wire        m_axi_wready;
wire        m_axi_wready_raw;
wire [1:0]  m_axi_bresp;
wire        m_axi_bvalid;
wire        m_axi_bvalid_raw;
wire        m_axi_bready;
wire [31:0] m_axi_araddr;
wire [7:0]  m_axi_arlen;
wire [2:0]  m_axi_arsize;
wire [1:0]  m_axi_arburst;
wire        m_axi_arvalid;
wire        m_axi_arready;
wire [63:0] m_axi_rdata;
wire [1:0]  m_axi_rresp;
wire        m_axi_rlast;
wire        m_axi_rvalid;
wire        m_axi_rready;
wire        irq;
wire        ufc_tx_valid_tb;
reg         ufc_tx_ready_tb;
wire [7:0]  ufc_tx_opcode_tb;

`ifdef DMA_RX_DEDICATED_PAYLOAD_TB
wire [31:0]  m_axi_rx_payload_awaddr;
wire [7:0]   m_axi_rx_payload_awlen;
wire [2:0]   m_axi_rx_payload_awsize;
wire [1:0]   m_axi_rx_payload_awburst;
wire         m_axi_rx_payload_awvalid;
wire         m_axi_rx_payload_awready;
wire         m_axi_rx_payload_awready_raw;
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
wire [63:0]  m_axi_rx_payload_wdata;
wire [7:0]   m_axi_rx_payload_wstrb;
`else
wire [511:0] m_axi_rx_payload_wdata;
wire [63:0]  m_axi_rx_payload_wstrb;
`endif
wire         m_axi_rx_payload_wlast;
wire         m_axi_rx_payload_wvalid;
wire         m_axi_rx_payload_wready;
wire         m_axi_rx_payload_wready_raw;
wire [1:0]   m_axi_rx_payload_bresp;
wire         m_axi_rx_payload_bvalid;
wire         m_axi_rx_payload_bvalid_raw;
wire         m_axi_rx_payload_bready;
`endif

reg [511:0] header;
reg [511:0] hold_beat;
reg [31:0] rdata;
integer i;
integer observed_header_count;
integer observed_soft_reset_count;
reg cq_axi_aw_stall;
reg cq_axi_w_stall;
reg cq_axi_b_stall;
reg payload_axi_aw_stall;
reg payload_axi_w_stall;
reg payload_axi_b_stall;

assign m_axi_awready = m_axi_awready_raw && !cq_axi_aw_stall;
assign m_axi_wready = m_axi_wready_raw && !cq_axi_w_stall;
assign m_axi_bvalid = m_axi_bvalid_raw && !cq_axi_b_stall;
`ifdef DMA_RX_DEDICATED_PAYLOAD_TB
assign m_axi_rx_payload_awready = m_axi_rx_payload_awready_raw && !payload_axi_aw_stall;
assign m_axi_rx_payload_wready = m_axi_rx_payload_wready_raw && !payload_axi_w_stall;
assign m_axi_rx_payload_bvalid = m_axi_rx_payload_bvalid_raw && !payload_axi_b_stall;
`endif

`ifdef DMA_RX_DEDICATED_PAYLOAD_TB
integer wide_lengths [0:17];
integer wide_idx;
integer wide_len;
integer wide_aligned_len;
integer wide_ch_sel;
integer stress_offset [0:2];
reg [31:0] stress_dst [0:255];
reg [31:0] stress_src [0:255];
reg [31:0] stress_len [0:255];
`endif

localparam [3:0] CH_FRAME0 = 4'd0;
localparam [3:0] CH_FRAME1 = 4'd1;
localparam [3:0] CH_STREAM = 4'd2;
localparam [15:0] FLOW_FRAME0 = 16'h0020;
localparam [15:0] FLOW_FRAME1 = 16'h0021;
localparam [15:0] FLOW_STREAM = 16'h0022;
localparam [31:0] BASE_FRAME0 = 32'h0018_0000;
localparam [31:0] BASE_FRAME1 = 32'h0018_4000;
localparam [31:0] BASE_STREAM = 32'h0018_8000;
localparam [15:0] EXPECTED_POOL_FREE = `DMA_FRAME_POOL_BLOCK_NUM;

dma_ref_model u_ref();

axi_lite_master_model u_axil(
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
    .clk(clk),
    .rstn(rstn)
);

rx_axis_bfm u_rx_axis(
    .rx_axis_tdata(rx_axis_tdata),
    .rx_axis_tvalid(rx_axis_tvalid),
    .rx_axis_tready(rx_axis_tready),
    .clk(clk),
    .rstn(rstn)
);

axi64_slave_model u_mem(
    .aclk(clk),
    .arstn(rstn),
    .awaddr(m_axi_awaddr),
    .awlen(m_axi_awlen),
    .awsize(m_axi_awsize),
    .awburst(m_axi_awburst),
    .awvalid(m_axi_awvalid && !cq_axi_aw_stall),
    .awready(m_axi_awready_raw),
    .wdata(m_axi_wdata),
    .wstrb(m_axi_wstrb),
    .wlast(m_axi_wlast),
    .wvalid(m_axi_wvalid && !cq_axi_w_stall),
    .wready(m_axi_wready_raw),
    .bresp(m_axi_bresp),
    .bvalid(m_axi_bvalid_raw),
    .bready(m_axi_bready && !cq_axi_b_stall),
    .araddr(m_axi_araddr),
    .arlen(m_axi_arlen),
    .arsize(m_axi_arsize),
    .arburst(m_axi_arburst),
    .arvalid(m_axi_arvalid),
    .arready(m_axi_arready),
    .rdata(m_axi_rdata),
    .rresp(m_axi_rresp),
    .rlast(m_axi_rlast),
    .rvalid(m_axi_rvalid),
    .rready(m_axi_rready)
);

`ifdef DMA_RX_MEM_ASYNC64_PROFILE
  axi64_slave_model #(
    .RANDOM_STALL(1),
    .RANDOM_SEED(32'h6400_2301)
) u_payload_mem (
    .aclk(mem_clk),
    .arstn(mem_rstn),
    .awaddr(m_axi_rx_payload_awaddr),
    .awlen(m_axi_rx_payload_awlen),
    .awsize(m_axi_rx_payload_awsize),
    .awburst(m_axi_rx_payload_awburst),
    .awvalid(m_axi_rx_payload_awvalid && !payload_axi_aw_stall),
    .awready(m_axi_rx_payload_awready_raw),
    .wdata(m_axi_rx_payload_wdata),
    .wstrb(m_axi_rx_payload_wstrb),
    .wlast(m_axi_rx_payload_wlast),
    .wvalid(m_axi_rx_payload_wvalid && !payload_axi_w_stall),
    .wready(m_axi_rx_payload_wready_raw),
    .bresp(m_axi_rx_payload_bresp),
    .bvalid(m_axi_rx_payload_bvalid_raw),
    .bready(m_axi_rx_payload_bready && !payload_axi_b_stall),
    .araddr(32'h0),
    .arlen(8'h0),
    .arsize(3'd3),
    .arburst(2'b01),
    .arvalid(1'b0),
    .arready(),
    .rdata(),
    .rresp(),
    .rlast(),
    .rvalid(),
    .rready(1'b0)
);
`elsif DMA_RX_DEDICATED_PAYLOAD_TB
axi512_write_slave_model #(
    .RANDOM_STALL(1),
    .RANDOM_SEED(32'h5120_2301)
) u_wide_mem (
`ifdef DMA_RX_MEM_ASYNC_PROFILE
    .aclk(mem_clk),
    .arstn(mem_rstn),
`else
    .aclk(clk),
    .arstn(rstn),
`endif
    .awaddr(m_axi_rx_payload_awaddr),
    .awlen(m_axi_rx_payload_awlen),
    .awsize(m_axi_rx_payload_awsize),
    .awburst(m_axi_rx_payload_awburst),
    .awvalid(m_axi_rx_payload_awvalid && !payload_axi_aw_stall),
    .awready(m_axi_rx_payload_awready_raw),
    .wdata(m_axi_rx_payload_wdata),
    .wstrb(m_axi_rx_payload_wstrb),
    .wlast(m_axi_rx_payload_wlast),
    .wvalid(m_axi_rx_payload_wvalid && !payload_axi_w_stall),
    .wready(m_axi_rx_payload_wready_raw),
    .bresp(m_axi_rx_payload_bresp),
    .bvalid(m_axi_rx_payload_bvalid_raw),
    .bready(m_axi_rx_payload_bready && !payload_axi_b_stall)
);
`endif

frame_dma_rx_top u_dut(
    .aclk(clk),
    .aresetn(rstn),
    .tx_axis_aclk(clk),
    .tx_axis_aresetn(rstn),
    .rx_axis_tdata(rx_axis_tdata),
    .rx_axis_tvalid(rx_axis_tvalid),
    .rx_axis_tready(rx_axis_tready),
    .tx_axis_tdata(),
    .tx_axis_tvalid(),
    .tx_axis_tready(1'b1),
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
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .ufc_tx_valid(ufc_tx_valid_tb),
    .ufc_tx_ready(ufc_tx_ready_tb),
    .ufc_tx_opcode(ufc_tx_opcode_tb),
    .ufc_tx_flow_id(),
    .ufc_tx_arg0(),
    .ufc_tx_arg1(),
    .ufc_rx_valid(1'b0),
    .ufc_rx_ready(),
    .ufc_rx_opcode(8'h0),
    .ufc_rx_flow_id(16'h0),
    .ufc_rx_arg0(32'h0),
    .ufc_rx_arg1(32'h0),
    .irq(irq)
`ifdef DMA_RX_MEM_ASYNC_PROFILE
    ,.mem_clk(mem_clk)
    ,.mem_aresetn(mem_rstn)
`endif
`ifdef DMA_RX_DEDICATED_PAYLOAD_TB
    ,.m_axi_rx_payload_awaddr(m_axi_rx_payload_awaddr)
    ,.m_axi_rx_payload_awlen(m_axi_rx_payload_awlen)
    ,.m_axi_rx_payload_awsize(m_axi_rx_payload_awsize)
    ,.m_axi_rx_payload_awburst(m_axi_rx_payload_awburst)
    ,.m_axi_rx_payload_awvalid(m_axi_rx_payload_awvalid)
    ,.m_axi_rx_payload_awready(m_axi_rx_payload_awready)
    ,.m_axi_rx_payload_wdata(m_axi_rx_payload_wdata)
    ,.m_axi_rx_payload_wstrb(m_axi_rx_payload_wstrb)
    ,.m_axi_rx_payload_wlast(m_axi_rx_payload_wlast)
    ,.m_axi_rx_payload_wvalid(m_axi_rx_payload_wvalid)
    ,.m_axi_rx_payload_wready(m_axi_rx_payload_wready)
    ,.m_axi_rx_payload_bresp(m_axi_rx_payload_bresp)
    ,.m_axi_rx_payload_bvalid(m_axi_rx_payload_bvalid)
    ,.m_axi_rx_payload_bready(m_axi_rx_payload_bready)
`endif
);

always #5 if (clk_enable) clk = ~clk;
`ifdef DMA_RX_MEM_ASYNC_PROFILE
always #3.5 if (mem_clk_enable) mem_clk = ~mem_clk;
`endif

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        observed_header_count <= 0;
        observed_soft_reset_count <= 0;
    end else begin
        if (u_dut.header_fire)
            observed_header_count <= observed_header_count + 1;
        if (u_dut.core_soft_reset)
            observed_soft_reset_count <= observed_soft_reset_count + 1;
    end
end

function [31:0] ch_base;
    input [3:0] ch;
    begin
        ch_base = `DMA_RX_CH_BASE + (ch * `DMA_CH_STRIDE);
    end
endfunction

task clear_mem;
    integer idx;
    begin
        for (idx = 0; idx < `DMA_SIM_MEM_BYTES; idx = idx + 1) begin
            sys_mem[idx] = 8'h0;
            ref_mem[idx] = 8'h0;
        end
        for (idx = 0; idx < `DMA_PKT_MEM_BYTES; idx = idx + 1)
            pkt_mem[idx] = idx[7:0] ^ 8'h5a;
    end
endtask

task reset_dut;
    begin
        cq_axi_aw_stall = 1'b0;
        cq_axi_w_stall = 1'b0;
        cq_axi_b_stall = 1'b0;
        payload_axi_aw_stall = 1'b0;
        payload_axi_w_stall = 1'b0;
        payload_axi_b_stall = 1'b0;
        ufc_tx_ready_tb = 1'b1;
        rstn = 1'b0;
`ifdef DMA_RX_MEM_ASYNC_PROFILE
        mem_rstn = 1'b0;
`endif
        repeat (12) @(posedge clk);
        rstn = 1'b1;
`ifdef DMA_RX_MEM_ASYNC_PROFILE
        repeat (4) @(posedge mem_clk);
        mem_rstn = 1'b1;
`endif
        repeat (10) @(posedge clk);
    end
endtask

task config_rx_ch;
    input [3:0] ch;
    input [15:0] flow_id;
    input [3:0] policy;
    input [31:0] base;
    input [31:0] size;
    input [31:0] max_len;
    begin
        u_axil.axil_write(ch_base(ch) + `DMA_CH_CFG,
                          {flow_id, 4'h0, 4'h0, policy, `DMA_TC_FC}, 4'hf);
        u_axil.axil_write(ch_base(ch) + `DMA_CH_BASE_L, base, 4'hf);
        u_axil.axil_write(ch_base(ch) + `DMA_CH_SIZE, size, 4'hf);
        u_axil.axil_write(ch_base(ch) + `DMA_CH_MAX_LEN, max_len, 4'hf);
        u_axil.axil_write(ch_base(ch) + `DMA_RX_CH_HIGH_WM, size - 32'd64, 4'hf);
        u_axil.axil_write(ch_base(ch) + `DMA_RX_CH_LOW_WM, 32'd64, 4'hf);
        u_axil.axil_write(ch_base(ch) + `DMA_CH_CTRL,
                          (1 << `DMA_RX_CTRL_ENABLE) |
                          (1 << `DMA_RX_CTRL_IRQ_EN) |
                          (1 << `DMA_RX_CTRL_FC_EN), 4'hf);
    end
endtask

task configure_default;
    input [3:0] ch1_policy;
    begin
        u_axil.axil_write(`DMA_REG_IRQ_MASK, 32'hffff_ffff, 4'hf);
        config_rx_ch(CH_FRAME0, FLOW_FRAME0, `DMA_RX_POL_QUEUE_WITH_FC,
                     BASE_FRAME0, 32'd16384, 32'd8192);
        config_rx_ch(CH_FRAME1, FLOW_FRAME1, ch1_policy,
                     BASE_FRAME1, 32'd16384, 32'd8192);
        config_rx_ch(CH_STREAM, FLOW_STREAM, `DMA_RX_POL_QUEUE_WITH_FC,
                     BASE_STREAM, 32'd16384, 32'd8192);
        u_axil.axil_write(`DMA_REG_GLOBAL_CTRL,
                          (1 << `DMA_GCTRL_GLOBAL_EN) |
                          (1 << `DMA_GCTRL_RX_EN) |
                          (1 << `DMA_GCTRL_IRQ_EN), 4'hf);
    end
endtask

task fresh_config;
    input [3:0] ch1_policy;
    begin
        clear_mem();
        reset_dut();
        configure_default(ch1_policy);
    end
endtask

task build_fc_header;
    input [15:0] flow_id;
    input [31:0] len;
    input [31:0] seq;
    begin
        u_ref.ref_build_header(header, {4'h0, `DMA_TC_FC}, flow_id, 16'h0,
                               len, seq, 64'h2020_0000 + seq, 64'h0, len);
    end
endtask

task send_fc;
    input [15:0] flow_id;
    input [31:0] len;
    input [31:0] src;
    input [31:0] seq;
    begin
        build_fc_header(flow_id, len, seq);
        u_rx_axis.send_frame(header, src, len);
    end
endtask

task wait_idle;
    integer poll;
    begin
        poll = 0;
        u_axil.axil_read(`DMA_REG_GLOBAL_STATUS, rdata);
        while ((rdata[1] || rdata[2] || rdata[4]) && poll < 50000) begin
            repeat (10) @(posedge clk);
            u_axil.axil_read(`DMA_REG_GLOBAL_STATUS, rdata);
            poll = poll + 1;
        end
        if (poll >= 50000) begin
            $display("Error: timeout waiting idle status=%08x rx_state=%0d wr_state=%0d frame_free=%0d alloc=%0d",
                     rdata, u_dut.rx_state, u_dut.wr_state,
                     u_dut.frame_pool_free_count, u_dut.frame_pool_alloc_count);
            $finish;
        end
    end
endtask

task expect_reg;
    input [31:0] addr;
    input [31:0] exp;
    begin
        u_axil.axil_read(addr, rdata);
        if (rdata !== exp) begin
            $display("Error: reg mismatch addr=%08x got=%08x exp=%08x", addr, rdata, exp);
            $finish;
        end
    end
endtask

task expect_status_code;
    input [3:0] ch;
    input [7:0] exp;
    begin
        u_axil.axil_read(ch_base(ch) + `DMA_CH_STATUS, rdata);
        if (rdata[23:16] !== exp) begin
            $display("Error: status mismatch ch=%0d got=%02x exp=%02x full=%08x",
                     ch, rdata[23:16], exp, rdata);
            $finish;
        end
    end
endtask

task check_payload;
    input [31:0] dst;
    input [31:0] src;
    input [31:0] len;
    integer k;
    begin
        for (k = 0; k < len; k = k + 1) begin
            if (sys_mem[dst+k] !== pkt_mem[src+k]) begin
                $display("Error: payload mismatch dst=%08x got=%02x exp=%02x",
                         dst+k, sys_mem[dst+k], pkt_mem[src+k]);
                $finish;
            end
        end
    end
endtask

task expect_zero;
    input [31:0] dst;
    input [31:0] len;
    integer k;
    begin
        for (k = 0; k < len; k = k + 1) begin
            if (sys_mem[dst+k] !== 8'h0) begin
                $display("Error: unexpected DDR write dst=%08x value=%02x", dst+k, sys_mem[dst+k]);
                $finish;
            end
        end
    end
endtask

task expect_pool_released;
    begin
        if (u_dut.frame_pool_free_count !== EXPECTED_POOL_FREE) begin
            $display("Error: shared pool not released free=%0d alloc=%0d leak=%0d",
                     u_dut.frame_pool_free_count,
                     u_dut.frame_pool_alloc_count,
                     u_dut.frame_pool_leak_check_error);
            $finish;
        end
        if (u_dut.frame_pool_leak_check_error) begin
            $display("Error: shared pool leak_check_error set");
            $finish;
        end
    end
endtask

task hold_payload_and_expect_backpressure;
    integer guard;
    integer idx;
    begin
        hold_beat = 512'h0;
        for (idx = 0; idx < 64; idx = idx + 1)
            hold_beat[idx*8 +: 8] = pkt_mem[32'h6000 + idx];
        @(negedge clk);
        force u_rx_axis.rx_axis_tdata = hold_beat;
        force u_rx_axis.rx_axis_tvalid = 1'b1;
        guard = 0;
        repeat (40) begin
            @(posedge clk);
            if (rx_axis_tready)
                guard = guard + 1;
        end
        if (`DMA_ENABLE_RX_AXIS_SKID != 0) begin
            if (guard != 4) begin
                $display("Error: elastic FIFO credit bound mismatch accepted=%0d expected=4", guard);
                $finish;
            end
        end else begin
            if (guard != 0) begin
                $display("Error: no-drop oversized FRAME_SHARED payload was not backpressured");
                $finish;
            end
        end
        release u_rx_axis.rx_axis_tdata;
        release u_rx_axis.rx_axis_tvalid;
        u_rx_axis.rx_axis_tdata = 512'h0;
        u_rx_axis.rx_axis_tvalid = 1'b0;
        @(negedge clk);
    end
endtask

task run_t0_reset;
    begin
        $display("E20A_CASE T0 reset");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        wait_idle();
        expect_pool_released();
    end
endtask

task run_t1_stream_reserved_smoke;
    begin
        $display("E20A_CASE T1 stream_reserved_smoke");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_STREAM, 32'd64, 32'h0000, 32'd1);
        wait_idle();
        expect_reg(ch_base(CH_STREAM) + `DMA_RX_CH_WR_PTR, 32'd64);
        check_payload(BASE_STREAM, 32'h0000, 32'd64);
        expect_pool_released();
    end
endtask

task run_t2_frame_shared_single;
    begin
        $display("E20A_CASE T2 frame_shared_single");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_FRAME0, 32'd96, 32'h0100, 32'd2);
        wait_idle();
        expect_reg(ch_base(CH_FRAME0) + `DMA_RX_CH_WR_PTR, 32'd128);
        check_payload(BASE_FRAME0, 32'h0100, 32'd96);
        expect_pool_released();
    end
endtask

task run_t3_frame_shared_two_frames;
    begin
        $display("E20A_CASE T3 frame_shared_two_frames");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_FRAME0, 32'd64, 32'h0200, 32'd3);
        wait_idle();
        send_fc(FLOW_FRAME0, 32'd128, 32'h0300, 32'd4);
        wait_idle();
        expect_reg(ch_base(CH_FRAME0) + `DMA_RX_CH_WR_PTR, 32'd192);
        check_payload(BASE_FRAME0, 32'h0200, 32'd64);
        check_payload(BASE_FRAME0 + 32'd64, 32'h0300, 32'd128);
        expect_pool_released();
    end
endtask

task run_t4_mixed_stream_frame;
    begin
        $display("E20A_CASE T4 mixed_stream_frame");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_FRAME0, 32'd128, 32'h0400, 32'd5);
        send_fc(FLOW_STREAM, 32'd64, 32'h0500, 32'd6);
        wait_idle();
        check_payload(BASE_FRAME0, 32'h0400, 32'd128);
        check_payload(BASE_STREAM, 32'h0500, 32'd64);
        expect_pool_released();
    end
endtask

task run_t5_stream_priority;
    begin
        $display("E20A_CASE T5 stream_priority");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_STREAM, 32'd128, 32'h0600, 32'd7);
        send_fc(FLOW_FRAME1, 32'd128, 32'h0700, 32'd8);
        wait_idle();
        check_payload(BASE_STREAM, 32'h0600, 32'd128);
        check_payload(BASE_FRAME1, 32'h0700, 32'd128);
        expect_pool_released();
    end
endtask

task run_t6_frame_pool_full_nodrop;
    begin
        $display("E20A_CASE T6 frame_pool_full_nodrop");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        build_fc_header(FLOW_FRAME0, 32'd8192, 32'd9);
        u_rx_axis.send_beat(header);
        hold_payload_and_expect_backpressure();
        reset_dut();
        configure_default(`DMA_RX_POL_QUEUE_WITH_FC);
        wait_idle();
        expect_pool_released();
    end
endtask

task run_t7_frame_pool_drop;
    begin
        $display("E20A_CASE T7 frame_pool_drop");
        fresh_config(`DMA_RX_POL_QUEUE_DROP_NEW);
        send_fc(FLOW_FRAME1, 32'd8192, 32'h1000, 32'd10);
        wait_idle();
        expect_reg(ch_base(CH_FRAME1) + `DMA_RX_CH_WR_PTR, 32'd0);
        expect_zero(BASE_FRAME1, 32'd256);
        expect_status_code(CH_FRAME1, `DMA_ST_DROP_NEW);
        expect_pool_released();
    end
endtask

task run_t8_disabled_channel;
    begin
        $display("E20A_CASE T8 disabled_channel");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_STREAM, 32'd96, 32'h2000, 32'd11);
        wait_idle();
        expect_reg(ch_base(CH_STREAM) + `DMA_RX_CH_WR_PTR, 32'd128);
        check_payload(BASE_STREAM, 32'h2000, 32'd96);
        expect_pool_released();
    end
endtask

task run_t9_reset_recovery;
    begin
        $display("E20A_CASE T9 reset_recovery");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        build_fc_header(FLOW_FRAME0, 32'd8192, 32'd12);
        u_rx_axis.send_beat(header);
        hold_payload_and_expect_backpressure();
        reset_dut();
        configure_default(`DMA_RX_POL_QUEUE_WITH_FC);
        wait_idle();
        expect_pool_released();
    end
endtask

`ifdef DMA_RX_DEDICATED_PAYLOAD_TB
task run_t10_wide_directed_lengths;
    reg [15:0] flow_sel;
    reg [31:0] base_sel;
    begin
        $display("RX_PAYLOAD_INTEGRATION T10 directed_lengths");
        wide_lengths[0] = 1;
        wide_lengths[1] = 7;
        wide_lengths[2] = 8;
        wide_lengths[3] = 31;
        wide_lengths[4] = 63;
        wide_lengths[5] = 64;
        wide_lengths[6] = 65;
        wide_lengths[7] = 127;
        wide_lengths[8] = 128;
        wide_lengths[9] = 255;
        wide_lengths[10] = 256;
        wide_lengths[11] = 511;
        wide_lengths[12] = 512;
        wide_lengths[13] = 1023;
        wide_lengths[14] = 1024;
        wide_lengths[15] = 2048;
        wide_lengths[16] = 4095;
        wide_lengths[17] = 4096;

        for (wide_idx = 0; wide_idx < 18; wide_idx = wide_idx + 1) begin
            fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
            wide_ch_sel = wide_idx % 3;
            if (wide_ch_sel == 0) begin
                flow_sel = FLOW_FRAME0;
                base_sel = BASE_FRAME0;
            end else if (wide_ch_sel == 1) begin
                flow_sel = FLOW_FRAME1;
                base_sel = BASE_FRAME1;
            end else begin
                flow_sel = FLOW_STREAM;
                base_sel = BASE_STREAM;
            end
            wide_len = wide_lengths[wide_idx];
            send_fc(flow_sel, wide_len, 32'h0001_0000 + wide_idx * 32'h1200,
                    32'h100 + wide_idx);
            wait_idle();
            check_payload(base_sel, 32'h0001_0000 + wide_idx * 32'h1200, wide_len);
            expect_pool_released();
        end
    end
endtask

task run_t11_wide_mixed_stress;
    reg [15:0] flow_sel;
    reg [31:0] base_sel;
    integer frame_idx;
    begin
        $display("RX_PAYLOAD_INTEGRATION T11 mixed_source_stress frames=256");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        stress_offset[0] = 0;
        stress_offset[1] = 0;
        stress_offset[2] = 0;
        for (frame_idx = 0; frame_idx < 256; frame_idx = frame_idx + 1) begin
            wide_ch_sel = frame_idx % 3;
            wide_len = ((frame_idx * 73) % 255) + 1;
            wide_aligned_len = (wide_len + 63) & 32'hffff_ffc0;
            if (wide_ch_sel == 0) begin
                flow_sel = FLOW_FRAME0;
                base_sel = BASE_FRAME0;
            end else if (wide_ch_sel == 1) begin
                flow_sel = FLOW_FRAME1;
                base_sel = BASE_FRAME1;
            end else begin
                flow_sel = FLOW_STREAM;
                base_sel = BASE_STREAM;
            end
            stress_dst[frame_idx] = base_sel + stress_offset[wide_ch_sel];
            stress_src[frame_idx] = 32'h0000_8000 + frame_idx * 32'h400;
            stress_len[frame_idx] = wide_len;
            stress_offset[wide_ch_sel] = stress_offset[wide_ch_sel] + wide_aligned_len;
            send_fc(flow_sel, wide_len, stress_src[frame_idx], 32'h400 + frame_idx);
        end
        wait_idle();
        for (frame_idx = 0; frame_idx < 256; frame_idx = frame_idx + 1)
            check_payload(stress_dst[frame_idx], stress_src[frame_idx], stress_len[frame_idx]);
        expect_pool_released();
    end
endtask

`endif

`ifdef DMA_RX_MEM_ASYNC_PROFILE
task run_t12_async_soft_reset_drain;
    integer reset_guard;
    begin
        $display("RX_PAYLOAD_INTEGRATION T12 active_soft_reset_drain");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        fork
            send_fc(FLOW_FRAME0, 32'd4096, 32'h0003_0000, 32'h700);
            begin
                wait (u_dut.pay_busy && (u_dut.wr_state == 3'd2));
                repeat (3) @(posedge clk);
                u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
                reset_guard = 0;
                while (!u_dut.core_soft_reset && (reset_guard < 50000)) begin
                    @(posedge clk);
                    reset_guard = reset_guard + 1;
                end
                if (reset_guard >= 50000) begin
                    $display("Error: deferred async soft reset never completed quiesce=%0d drain=%0d mem_req=%0d mem_done=%0d core_work=%0d",
                             u_dut.soft_reset_quiesce, u_dut.soft_reset_drain_done,
                             u_dut.soft_reset_mem_request_sent_q,
                             u_dut.soft_reset_mem_reset_done, u_dut.core_work_busy);
                    $display("  rx=%0d wr=%0d release=%0d ingress=%0d pay=%0d cq=%0d tx=%0d tx_idle=%0d ufc_busy=%0d ufc_valid=%0d drop_pending=%0d",
                             u_dut.rx_state, u_dut.wr_state, u_dut.release_service_busy,
                             u_dut.ingress_work_busy, u_dut.pay_busy, u_dut.cq_work_busy,
                             u_dut.tx_busy, u_dut.tx_drain_idle, u_dut.ufc_tx_busy,
                             u_dut.ufc_tx_valid, u_dut.frame_drop_pending);
                    $display("  cq_reserved=%0d cq_dec_pending=%0d cq_credit=%0d reserve_evt=%0d return_evt=%0d bridge_busy=%0d writer_busy=%0d",
                             u_dut.cq_reserved_count, u_dut.cq_reserve_dec_pending_cnt,
                             u_dut.cq_cmd_credit_count,
                             u_dut.cq_cmd_credit_reserve_evt_q,
                             u_dut.cq_cmd_credit_return_evt_q,
                             u_dut.async_bridge_busy, u_dut.async_writer_busy);
                    $finish;
                end
                if (u_dut.pay_busy || (u_dut.wr_state != 3'd0)) begin
                    $display("Error: async soft reset fired before payload drain busy=%0d wr_state=%0d",
                             u_dut.pay_busy, u_dut.wr_state);
                    $finish;
                end
            end
        join

        repeat (12) @(posedge clk);
        check_payload(BASE_FRAME0, 32'h0003_0000, 32'd4096);
        if (u_dut.async_bridge_protocol_error || u_dut.pay_cpl_valid ||
            u_dut.async_writer_busy) begin
            $display("Error: async soft reset left stale backend state protocol=%0d cpl=%0d writer=%0d",
                     u_dut.async_bridge_protocol_error, u_dut.pay_cpl_valid,
                     u_dut.async_writer_busy);
            $finish;
        end

        configure_default(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_STREAM, 32'd65, 32'h0003_2000, 32'h701);
        wait_idle();
        check_payload(BASE_STREAM, 32'h0003_2000, 32'd65);
        expect_pool_released();
    end
endtask

task wait_soft_reset_commit;
    input integer max_cycles;
    integer reset_guard;
    begin
        reset_guard = 0;
        while (!u_dut.core_soft_reset && (reset_guard < max_cycles)) begin
            @(posedge clk);
            reset_guard = reset_guard + 1;
        end
        if (reset_guard >= max_cycles) begin
            $display("Error: bounded soft reset timeout quiesce=%0d drain=%0d mem_req=%0d mem_done=%0d core_work=%0d",
                     u_dut.soft_reset_quiesce, u_dut.soft_reset_drain_done,
                     u_dut.soft_reset_mem_request_sent_q,
                     u_dut.soft_reset_mem_reset_done, u_dut.core_work_busy);
            $display("  rx=%0d wr=%0d ingress=%0d pay=%0d cq=%0d tx=%0d tx_idle=%0d ufc=%0d/%0d reserved=%0d credit=%0d bridge=%0d writer=%0d aw=%0d/%0d w=%0d/%0d b=%0d/%0d",
                     u_dut.rx_state, u_dut.wr_state, u_dut.ingress_work_busy,
                     u_dut.pay_busy, u_dut.cq_work_busy, u_dut.tx_busy,
                     u_dut.tx_drain_idle, u_dut.ufc_tx_busy, u_dut.ufc_tx_valid,
                     u_dut.cq_reserved_count, u_dut.cq_cmd_credit_count,
                     u_dut.async_bridge_busy, u_dut.async_writer_busy,
                     m_axi_rx_payload_awvalid, m_axi_rx_payload_awready,
                     m_axi_rx_payload_wvalid, m_axi_rx_payload_wready,
                     m_axi_rx_payload_bvalid, m_axi_rx_payload_bready);
            $finish;
        end
    end
endtask

task release_payload_axi_forces;
    begin
        payload_axi_aw_stall = 1'b0;
        payload_axi_w_stall = 1'b0;
        payload_axi_b_stall = 1'b0;
    end
endtask

task run_t13_async_collect_quiesce;
    integer headers_at_quiesce;
    integer reset_guard;
    reg first_frame_done;
    reg stop_pending_header;
    reg [511:0] pending_header;
    begin
        $display("RX_PAYLOAD_QUIESCE T13 collect_and_continuous_rx");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        first_frame_done = 1'b0;
        stop_pending_header = 1'b0;

        fork
            begin
                send_fc(FLOW_FRAME0, 32'd4096, 32'h0003_4000, 32'h710);
                first_frame_done = 1'b1;
            end
            begin
                wait (first_frame_done);
                build_fc_header(FLOW_FRAME1, 32'd4096, 32'h711);
                pending_header = header;
                @(negedge clk);
                u_rx_axis.rx_axis_tdata = pending_header;
                u_rx_axis.rx_axis_tvalid = 1'b1;
                while (!stop_pending_header)
                    @(posedge clk);
                @(negedge clk);
                u_rx_axis.rx_axis_tvalid = 1'b0;
                u_rx_axis.rx_axis_tdata = 512'h0;
            end
            begin
                wait (u_dut.rx_state == 4'd9);
                repeat (8) @(posedge clk);
                u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
                wait (u_dut.soft_reset_quiesce);
                headers_at_quiesce = observed_header_count;
                wait_soft_reset_commit(100000);
                if (observed_header_count != headers_at_quiesce) begin
                    $display("Error: quiesce accepted a new RX header before reset expected=%0d actual=%0d",
                             headers_at_quiesce, observed_header_count);
                    $finish;
                end
                stop_pending_header = 1'b1;
            end
        join

        repeat (12) @(posedge clk);
        check_payload(BASE_FRAME0, 32'h0003_4000, 32'd4096);
        if (u_dut.async_bridge_protocol_error || u_dut.pay_cpl_valid) begin
            $display("Error: collect quiesce left stale CDC state protocol=%0d cpl=%0d",
                     u_dut.async_bridge_protocol_error, u_dut.pay_cpl_valid);
            $finish;
        end

        configure_default(`DMA_RX_POL_QUEUE_WITH_FC);
        send_fc(FLOW_STREAM, 32'd65, 32'h0003_8000, 32'h712);
        wait_idle();
        check_payload(BASE_STREAM, 32'h0003_8000, 32'd65);
        if (u_dut.async_source_cpl_tag != 8'h00) begin
            $display("Error: first post-reset CDC completion tag was not epoch zero tag=%0d",
                     u_dut.async_source_cpl_tag);
            $finish;
        end
    end
endtask

task run_t14_async_multi_queue_backpressure;
    integer reset_count_before;
    begin
        $display("RX_PAYLOAD_QUIESCE T14 fixed_shared_aw_w_b_drain");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        payload_axi_aw_stall = 1'b1;
        payload_axi_w_stall = 1'b1;
        payload_axi_b_stall = 1'b1;

        send_fc(FLOW_FRAME0, 32'd512, 32'h0003_a000, 32'h720);
        send_fc(FLOW_FRAME1, 32'd512, 32'h0003_b000, 32'h721);
        send_fc(FLOW_STREAM, 32'd512, 32'h0003_c000, 32'h722);
        if (!u_dut.ingress_work_busy) begin
            $display("Error: multi-queue reset setup did not retain committed ingress work");
            $finish;
        end

        reset_count_before = observed_soft_reset_count;
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        wait (u_dut.soft_reset_quiesce);
        repeat (20) @(posedge clk);
        if (observed_soft_reset_count != reset_count_before) begin
            $display("Error: reset completed while payload AW was backpressured");
            $finish;
        end

        payload_axi_aw_stall = 1'b0;
        wait (m_axi_rx_payload_wvalid);
        repeat (12) @(posedge mem_clk);
        payload_axi_w_stall = 1'b0;
        repeat (40) @(posedge mem_clk);
        if (u_dut.core_soft_reset) begin
            $display("Error: reset completed before payload B responses drained");
            $finish;
        end
        payload_axi_b_stall = 1'b0;
        wait_soft_reset_commit(100000);
        release_payload_axi_forces();
        repeat (12) @(posedge clk);
        check_payload(BASE_FRAME0, 32'h0003_a000, 32'd512);
        check_payload(BASE_FRAME1, 32'h0003_b000, 32'd512);
        check_payload(BASE_STREAM, 32'h0003_c000, 32'd512);
    end
endtask

task run_t15_async_cq_backpressure;
    integer reset_count_before;
    begin
        $display("RX_PAYLOAD_QUIESCE T15 completion_cq_aw_w_b_drain");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        u_axil.axil_write(`DMA_REG_CQ_BASE_L, 32'h001c_0000, 4'hf);
        u_axil.axil_write(`DMA_REG_CQ_SIZE, 32'd16, 4'hf);
        u_axil.axil_write(`DMA_REG_CQ_RD_PTR, 32'h0, 4'hf);
        u_axil.axil_write(ch_base(CH_FRAME0) + `DMA_CH_CTRL,
                          (1 << `DMA_RX_CTRL_ENABLE) |
                          (1 << `DMA_RX_CTRL_IRQ_EN) |
                          (1 << `DMA_RX_CTRL_FC_EN) |
                          (1 << `DMA_RX_CTRL_CPL_EN), 4'hf);

        cq_axi_aw_stall = 1'b1;
        cq_axi_w_stall = 1'b1;
        cq_axi_b_stall = 1'b1;
        send_fc(FLOW_FRAME0, 32'd513, 32'h0003_d000, 32'h730);
        wait (u_dut.cq_single_busy || (u_dut.wr_state == 3'd3));
        reset_count_before = observed_soft_reset_count;
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        wait (u_dut.soft_reset_quiesce);
        repeat (20) @(posedge clk);
        if (observed_soft_reset_count != reset_count_before) begin
            $display("Error: reset completed while CQ AW was backpressured");
            $finish;
        end
        cq_axi_aw_stall = 1'b0;
        wait (m_axi_wvalid);
        repeat (10) @(posedge clk);
        cq_axi_w_stall = 1'b0;
        repeat (30) @(posedge clk);
        cq_axi_b_stall = 1'b0;
        wait_soft_reset_commit(100000);
        cq_axi_aw_stall = 1'b0;
        cq_axi_w_stall = 1'b0;
        cq_axi_b_stall = 1'b0;
        repeat (12) @(posedge clk);
        check_payload(BASE_FRAME0, 32'h0003_d000, 32'd513);
    end
endtask

task run_t16_async_clock_stop_and_repeat;
    integer reset_count_before;
    begin
        $display("RX_PAYLOAD_QUIESCE T16 clock_stops_and_repeated_requests");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        @(negedge mem_clk);
        mem_clk_enable = 1'b0;
        reset_count_before = observed_soft_reset_count;
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        wait (u_dut.soft_reset_quiesce);
        repeat (40) @(posedge clk);
        if (observed_soft_reset_count != reset_count_before ||
            u_dut.soft_reset_mem_reset_done) begin
            $display("Error: reset completed while mem_clk was stopped");
            $finish;
        end
        u_axil.axil_read(`DMA_REG_DEBUG_STATE, rdata);
        if (!rdata[2] || !rdata[3]) begin
            $display("Error: pending/quiescing debug status missing while mem_clk stopped debug=%08x", rdata);
            $finish;
        end
        mem_clk_enable = 1'b1;
        wait_soft_reset_commit(100000);
        repeat (3) @(posedge clk);
        if (observed_soft_reset_count != (reset_count_before + 1)) begin
            $display("Error: repeated pending reset requests produced count=%0d expected=%0d",
                     observed_soft_reset_count, reset_count_before + 1);
            $finish;
        end

        configure_default(`DMA_RX_POL_QUEUE_WITH_FC);
        reset_count_before = observed_soft_reset_count;
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        wait (u_dut.soft_reset_quiesce_q);
        @(negedge clk);
        clk_enable = 1'b0;
        #200;
        if (observed_soft_reset_count != reset_count_before) begin
            $display("Error: reset completed while aclk was stopped");
            $finish;
        end
        clk_enable = 1'b1;
        wait_soft_reset_commit(100000);
        repeat (3) @(posedge clk);
        if (observed_soft_reset_count != (reset_count_before + 1)) begin
            $display("Error: aclk-stop reset did not complete exactly once");
            $finish;
        end

        reset_count_before = observed_soft_reset_count;
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        wait_soft_reset_commit(100000);
        repeat (3) @(posedge clk);
        if (observed_soft_reset_count != (reset_count_before + 1)) begin
            $display("Error: reset request at completion boundary did not form one new epoch");
            $finish;
        end
    end
endtask

task run_t17_async_ufc_quiesce;
    integer reset_count_before;
    begin
        $display("RX_PAYLOAD_QUIESCE T17 ufc_existing_drain_and_new_launch_block");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        ufc_tx_ready_tb = 1'b0;
        u_axil.axil_write(`DMA_REG_GLOBAL_CTRL,
                          (1 << `DMA_GCTRL_GLOBAL_EN) |
                          (1 << `DMA_GCTRL_RX_EN) |
                          (1 << `DMA_GCTRL_UFC_EN), 4'hf);
        u_axil.axil_write(`DMA_REG_UFC_TX_OPCODE, 32'h5a, 4'hf);
        @(negedge clk);
        force u_dut.ufc_tx_start = 1'b1;
        @(posedge clk);
        #1;
        release u_dut.ufc_tx_start;
        wait (ufc_tx_valid_tb && u_dut.ufc_tx_busy);
        reset_count_before = observed_soft_reset_count;
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        wait (u_dut.soft_reset_quiesce);
        @(negedge clk);
        force u_dut.ufc_tx_start = 1'b1;
        @(posedge clk);
        #1;
        release u_dut.ufc_tx_start;
        repeat (20) @(posedge clk);
        if (!ufc_tx_valid_tb || (observed_soft_reset_count != reset_count_before)) begin
            $display("Error: quiesce dropped the accepted UFC or completed reset before UFC drain");
            $finish;
        end
        ufc_tx_ready_tb = 1'b1;
        wait_soft_reset_commit(100000);
        repeat (4) @(posedge clk);
        if (ufc_tx_valid_tb || u_dut.ufc_tx_busy) begin
            $display("Error: UFC state remained visible after bounded soft reset");
            $finish;
        end
    end
endtask

task run_t18_async_buffered_header_drain;
    integer quiesce_guard;
    begin
        $display("RX_PAYLOAD_QUIESCE T18 buffered_header_drain");
        fresh_config(`DMA_RX_POL_QUEUE_WITH_FC);
        force u_dut.release_service_busy = 1'b1;
        send_fc(FLOW_STREAM, 32'd65, 32'h0003_e000, 32'h740);
        $display("RX_PAYLOAD_QUIESCE T18 buffered count=%0d state=%0d",
                 u_dut.g_rx_axis_skid.u_rx_axis_skid.count_q, u_dut.rx_state);
        if ((u_dut.rx_state != 4'd0) || !u_dut.rx_front_tvalid) begin
            $display("Error: buffered-header setup failed state=%0d front_valid=%0d",
                     u_dut.rx_state, u_dut.rx_front_tvalid);
            $finish;
        end
        u_axil.axil_write(`DMA_REG_SOFT_RESET, 32'h1, 4'hf);
        quiesce_guard = 0;
        while (!u_dut.soft_reset_quiesce && (quiesce_guard < 1000)) begin
            @(posedge clk);
            quiesce_guard = quiesce_guard + 1;
        end
        if (quiesce_guard >= 1000) begin
            $display("Error: buffered-header reset request did not enter quiesce");
            $finish;
        end
        $display("RX_PAYLOAD_QUIESCE T18 quiesce_entered");
        repeat (8) @(posedge clk);
        if (!u_dut.rx_front_tvalid || u_dut.core_soft_reset) begin
            $display("Error: buffered frame was reset before release service drained");
            $finish;
        end
        release u_dut.release_service_busy;
        $display("RX_PAYLOAD_QUIESCE T18 release_service_resumed");
        wait_soft_reset_commit(100000);
        $display("RX_PAYLOAD_QUIESCE T18 reset_committed");
        repeat (12) @(posedge clk);
        check_payload(BASE_STREAM, 32'h0003_e000, 32'd65);
        if (u_dut.rx_front_tvalid || u_dut.async_bridge_protocol_error) begin
            $display("Error: buffered-header drain left stale state front=%0d protocol=%0d",
                     u_dut.rx_front_tvalid, u_dut.async_bridge_protocol_error);
            $finish;
        end
    end
endtask
`endif

initial begin
    clk = 1'b0;
    rstn = 1'b0;
    clk_enable = 1'b1;
    cq_axi_aw_stall = 1'b0;
    cq_axi_w_stall = 1'b0;
    cq_axi_b_stall = 1'b0;
    payload_axi_aw_stall = 1'b0;
    payload_axi_w_stall = 1'b0;
    payload_axi_b_stall = 1'b0;
    ufc_tx_ready_tb = 1'b1;
`ifdef DMA_RX_MEM_ASYNC_PROFILE
    mem_clk = 1'b0;
    mem_rstn = 1'b0;
    mem_clk_enable = 1'b1;
`endif
    clear_mem();

    run_t0_reset();
    run_t1_stream_reserved_smoke();
    run_t2_frame_shared_single();
    run_t3_frame_shared_two_frames();
    run_t4_mixed_stream_frame();
    run_t5_stream_priority();
    run_t6_frame_pool_full_nodrop();
    run_t7_frame_pool_drop();
    run_t8_disabled_channel();
    run_t9_reset_recovery();
`ifdef DMA_RX_DEDICATED_PAYLOAD_TB
    run_t10_wide_directed_lengths();
    run_t11_wide_mixed_stress();
`endif
`ifdef DMA_RX_MEM_ASYNC_PROFILE
    run_t12_async_soft_reset_drain();
    run_t13_async_collect_quiesce();
    run_t14_async_multi_queue_backpressure();
    run_t15_async_cq_backpressure();
    run_t16_async_clock_stop_and_repeat();
    run_t17_async_ufc_quiesce();
    run_t18_async_buffered_header_drain();
    $display("PASS tb_rtl_rx_payload_soft_reset_quiesce scenarios=collect,multi_queue,aw_w_b,cq,clock_stop,repeat,ufc,buffered_header");
`endif

`ifdef DMA_RX_MEM_ASYNC64_PROFILE
    $display("PASS tb_rtl_rx_mem_async64_integration directed_lengths=18 mixed_frames=256 soft_reset_drain=1");
`elsif DMA_RX_MEM_ASYNC512_PROFILE
    $display("PASS tb_rtl_rx_mem_async512_integration directed_lengths=18 mixed_frames=256 soft_reset_drain=1");
`elsif DMA_RX_WIDE_PAYLOAD_PROFILE
    $display("PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256");
`else
    $display("OK: dma RTL v33e20a hybrid RX ingress minimal directed test passed.");
`endif
    repeat (10) @(posedge clk);
    $finish;
end

endmodule

`ifdef DMA_RX_DEDICATED_PAYLOAD_TB
`undef DMA_RX_DEDICATED_PAYLOAD_TB
`endif
