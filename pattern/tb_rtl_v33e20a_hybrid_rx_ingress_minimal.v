`timescale 1ns/1ps
`include "dma_sim_def.vh"

module tb;

reg clk;
reg rstn;
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
wire [63:0] m_axi_wdata;
wire [7:0]  m_axi_wstrb;
wire        m_axi_wlast;
wire        m_axi_wvalid;
wire        m_axi_wready;
wire [1:0]  m_axi_bresp;
wire        m_axi_bvalid;
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

`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
wire [31:0]  m_axi_rx_payload_awaddr;
wire [7:0]   m_axi_rx_payload_awlen;
wire [2:0]   m_axi_rx_payload_awsize;
wire [1:0]   m_axi_rx_payload_awburst;
wire         m_axi_rx_payload_awvalid;
wire         m_axi_rx_payload_awready;
wire [511:0] m_axi_rx_payload_wdata;
wire [63:0]  m_axi_rx_payload_wstrb;
wire         m_axi_rx_payload_wlast;
wire         m_axi_rx_payload_wvalid;
wire         m_axi_rx_payload_wready;
wire [1:0]   m_axi_rx_payload_bresp;
wire         m_axi_rx_payload_bvalid;
wire         m_axi_rx_payload_bready;
`endif

reg [511:0] header;
reg [511:0] hold_beat;
reg [31:0] rdata;
integer i;

`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
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
    .awvalid(m_axi_awvalid),
    .awready(m_axi_awready),
    .wdata(m_axi_wdata),
    .wstrb(m_axi_wstrb),
    .wlast(m_axi_wlast),
    .wvalid(m_axi_wvalid),
    .wready(m_axi_wready),
    .bresp(m_axi_bresp),
    .bvalid(m_axi_bvalid),
    .bready(m_axi_bready),
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

`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
axi512_write_slave_model #(
    .RANDOM_STALL(1),
    .RANDOM_SEED(32'h5120_2301)
) u_wide_mem (
    .aclk(clk),
    .arstn(rstn),
    .awaddr(m_axi_rx_payload_awaddr),
    .awlen(m_axi_rx_payload_awlen),
    .awsize(m_axi_rx_payload_awsize),
    .awburst(m_axi_rx_payload_awburst),
    .awvalid(m_axi_rx_payload_awvalid),
    .awready(m_axi_rx_payload_awready),
    .wdata(m_axi_rx_payload_wdata),
    .wstrb(m_axi_rx_payload_wstrb),
    .wlast(m_axi_rx_payload_wlast),
    .wvalid(m_axi_rx_payload_wvalid),
    .wready(m_axi_rx_payload_wready),
    .bresp(m_axi_rx_payload_bresp),
    .bvalid(m_axi_rx_payload_bvalid),
    .bready(m_axi_rx_payload_bready)
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
    .ufc_tx_valid(),
    .ufc_tx_ready(1'b1),
    .ufc_tx_opcode(),
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
`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
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

always #5 clk = ~clk;

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
        rstn = 1'b0;
        repeat (12) @(posedge clk);
        rstn = 1'b1;
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
        if (guard != 0) begin
            $display("Error: no-drop oversized FRAME_SHARED payload was not backpressured");
            $finish;
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

`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
task run_t10_wide_directed_lengths;
    reg [15:0] flow_sel;
    reg [31:0] base_sel;
    begin
        $display("WIDE512_INTEGRATION T10 directed_lengths");
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
        $display("WIDE512_INTEGRATION T11 mixed_source_stress frames=256");
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

initial begin
    clk = 1'b0;
    rstn = 1'b0;
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
`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
    run_t10_wide_directed_lengths();
    run_t11_wide_mixed_stress();
`endif

`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE
    $display("PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256");
`else
    $display("OK: dma RTL v33e20a hybrid RX ingress minimal directed test passed.");
`endif
    repeat (10) @(posedge clk);
    $finish;
end

endmodule
