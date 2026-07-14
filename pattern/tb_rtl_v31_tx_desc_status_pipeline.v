`timescale 1ns/1ps
`include "dma_sim_def.vh"

module tb;
reg clk;
reg rstn;
reg [7:0] sys_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] ref_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] pkt_mem [0:`DMA_PKT_MEM_BYTES-1];

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

wire [511:0] tx_axis_tdata;
wire         tx_axis_tvalid;
wire         tx_axis_tready;
wire [511:0] rx_axis_tdata;
wire         rx_axis_tvalid;
wire         rx_axis_tready;
wire         irq;
wire [31:0] loop_tx_beats;
wire [31:0] loop_rx_beats;

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

reg [31:0] rd;
reg [7:0]  cqe_ch;
reg [15:0] cqe_flow;
reg [31:0] cqe_len;
reg [31:0] cqe_addr;
integer i;

localparam integer RX_CH = 0;
localparam integer TX_CH = 0;
localparam [15:0] TEST_FLOW_ID = 16'h0044;
localparam [15:0] TEST_STREAM_ID = 16'h00A1;
localparam [31:0] TX_PAYLOAD_BASE = 32'h0000_2800;
localparam [31:0] RX_PAYLOAD_BASE = 32'h0001_2000;
localparam [31:0] RX_RING_SIZE    = 32'h0000_4000;
localparam [31:0] DESC_BASE       = 32'h0007_4000;
localparam [31:0] DESC_SIZE       = 32'd256;
localparam [31:0] CQ_BASE         = 32'h0008_4000;
localparam [31:0] CQ_SIZE         = 32'd16;
localparam [31:0] PAYLOAD_LEN     = 32'd128;
localparam [11:0] TX0             = `DMA_TX_CH_BASE + (TX_CH * `DMA_CH_STRIDE);
localparam [11:0] RX0             = `DMA_RX_CH_BASE + (RX_CH * `DMA_CH_STRIDE);
localparam [11:0] TXD0            = `DMA_TX_DESC_CH_BASE + (TX_CH * `DMA_CH_STRIDE);

ps_axil_bfm u_ps(
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .irq(irq), .clk(clk), .rstn(rstn)
);

axi_ddr_mem_model u_ddr(
    .aclk(clk), .arstn(rstn),
    .awaddr(m_axi_awaddr), .awlen(m_axi_awlen), .awsize(m_axi_awsize), .awburst(m_axi_awburst),
    .awvalid(m_axi_awvalid), .awready(m_axi_awready),
    .wdata(m_axi_wdata), .wstrb(m_axi_wstrb), .wlast(m_axi_wlast), .wvalid(m_axi_wvalid), .wready(m_axi_wready),
    .bresp(m_axi_bresp), .bvalid(m_axi_bvalid), .bready(m_axi_bready),
    .araddr(m_axi_araddr), .arlen(m_axi_arlen), .arsize(m_axi_arsize), .arburst(m_axi_arburst),
    .arvalid(m_axi_arvalid), .arready(m_axi_arready),
    .rdata(m_axi_rdata), .rresp(m_axi_rresp), .rlast(m_axi_rlast), .rvalid(m_axi_rvalid), .rready(m_axi_rready)
);

axis_loopback_bfm u_loop(
    .clk(clk), .rstn(rstn),
    .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tready(tx_axis_tready),
    .rx_axis_tdata(rx_axis_tdata), .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tready(rx_axis_tready),
    .tx_beat_count(loop_tx_beats), .rx_beat_count(loop_rx_beats)
);

ufc_msg_monitor u_ufc(
    .clk(clk), .rstn(rstn),
    .ufc_tx_valid(ufc_tx_valid), .ufc_tx_ready(ufc_tx_ready),
    .ufc_tx_opcode(ufc_tx_opcode), .ufc_tx_flow_id(ufc_tx_flow_id),
    .ufc_tx_arg0(ufc_tx_arg0), .ufc_tx_arg1(ufc_tx_arg1),
    .ufc_rx_valid(ufc_rx_valid), .ufc_rx_ready(ufc_rx_ready),
    .ufc_rx_opcode(ufc_rx_opcode), .ufc_rx_flow_id(ufc_rx_flow_id),
    .ufc_rx_arg0(ufc_rx_arg0), .ufc_rx_arg1(ufc_rx_arg1),
    .pause_count(), .resume_count(), .last_opcode(), .last_flow_id(),
    .last_arg0(), .last_arg1()
);

frame_dma_wrapper u_dut(
    .aclk(clk), .aresetn(rstn),
    .tx_axis_aclk(clk), .tx_axis_aresetn(rstn),
    .rx_axis_tdata(rx_axis_tdata), .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tready(rx_axis_tready),
    .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tready(tx_axis_tready),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
    .ufc_tx_valid(ufc_tx_valid), .ufc_tx_ready(ufc_tx_ready), .ufc_tx_opcode(ufc_tx_opcode),
    .ufc_tx_flow_id(ufc_tx_flow_id), .ufc_tx_arg0(ufc_tx_arg0), .ufc_tx_arg1(ufc_tx_arg1),
    .ufc_rx_valid(ufc_rx_valid), .ufc_rx_ready(ufc_rx_ready), .ufc_rx_opcode(ufc_rx_opcode),
    .ufc_rx_flow_id(ufc_rx_flow_id), .ufc_rx_arg0(ufc_rx_arg0), .ufc_rx_arg1(ufc_rx_arg1),
    .irq(irq)
);

always #5 clk = ~clk;

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

task fill_payload;
    input [31:0] addr;
    input [31:0] len;
    input [7:0] seed;
    integer j;
    begin
        for (j = 0; j < len; j = j + 1)
            `DMA_SYS_MEM_PATH[addr + j] = seed ^ j[7:0];
    end
endtask

task write_desc_raw;
    input [31:0] desc_addr;
    input [31:0] ctrl;
    input [15:0] channel_id;
    input [15:0] stream_id;
    input [31:0] payload_len;
    input [31:0] src_addr_lo;
    input [31:0] src_addr_hi;
    input [31:0] seq;
    integer j;
    begin
        for (j = 0; j < `DMA_TX_DESC_BYTES; j = j + 1)
            `DMA_SYS_MEM_PATH[desc_addr + j] = 8'h0;
        put_u32(desc_addr + `DMA_TX_DESC_CTRL_OFF, ctrl);
        put_u32(desc_addr + `DMA_TX_DESC_CH_STREAM_OFF, {stream_id, channel_id});
        put_u32(desc_addr + `DMA_TX_DESC_LEN_OFF, payload_len);
        put_u32(desc_addr + `DMA_TX_DESC_ADDR_LO_OFF, src_addr_lo);
        put_u32(desc_addr + `DMA_TX_DESC_ADDR_HI_OFF, src_addr_hi);
        put_u32(desc_addr + `DMA_TX_DESC_SEQ_OFF, seq);
        put_u32(desc_addr + `DMA_TX_DESC_SAMPLE_OFF, 32'h1000_0000 | seq[15:0]);
    end
endtask

task reset_dut;
    begin
        rstn = 1'b0;
        u_ddr.set_read_error_addr(1'b0, 32'h0);
        repeat (8) @(posedge clk);
        rstn = 1'b1;
        repeat (20) @(posedge clk);
    end
endtask

task common_config;
    begin
        u_ddr.clear_all();
        fill_payload(TX_PAYLOAD_BASE, 32'd4096, 8'h5A);
        u_ps.axil_write(`DMA_REG_IRQ_MASK, 32'hffff_ffff);
        u_ps.dma_config_cq(CQ_BASE, CQ_SIZE);
        u_ps.dma_config_rx_channel(RX_CH, RX_PAYLOAD_BASE, RX_RING_SIZE, 32'd4096,
                                   TEST_FLOW_ID, `DMA_RX_POL_QUEUE_WITH_FC,
                                   32'd2048, 32'd1024);
        u_ps.axil_write(TX0 + `DMA_CH_CFG, {TEST_FLOW_ID, 4'h0, 4'h0, `DMA_TX_POL_SINGLE_SHOT, `DMA_TC_FC});
        u_ps.axil_write(TX0 + `DMA_TX_CH_LEN, 32'd4096);
        u_ps.axil_write(TXD0 + `DMA_TX_DESC_BASE_L, DESC_BASE);
        u_ps.axil_write(TXD0 + `DMA_TX_DESC_SIZE, DESC_SIZE);
        u_ps.dma_global_enable(1'b1, 1'b1, 1'b1, 1'b1);
        u_ps.axil_write(TX0 + `DMA_CH_CTRL,
            (1 << `DMA_TX_CTRL_ENABLE) | (1 << `DMA_TX_CTRL_CPL_EN) | (1 << `DMA_TX_CTRL_IRQ_EN));
    end
endtask

task start_desc;
    input [31:0] wr_ptr;
    begin
        u_ps.axil_write(TXD0 + `DMA_TX_DESC_WR_PTR, wr_ptr);
        u_ps.axil_write(TXD0 + `DMA_TX_DESC_CTRL,
            (1 << `DMA_TX_DESC_CTRL_ENABLE) | (1 << `DMA_TX_DESC_CTRL_START) | (1 << `DMA_TX_DESC_CTRL_IRQ_EN));
    end
endtask

task read_desc_triplet;
    output [31:0] rd_ptr;
    output [31:0] status;
    output [31:0] err_cnt;
    begin
        u_ps.axil_read(TXD0 + `DMA_TX_DESC_RD_PTR, rd_ptr);
        u_ps.axil_read(TXD0 + `DMA_TX_DESC_STATUS, status);
        u_ps.axil_read(TXD0 + `DMA_TX_DESC_ERR_CNT, err_cnt);
    end
endtask

task expect_desc_readback;
    input [31:0] exp_rd_ptr;
    input [7:0]  exp_status;
    input [31:0] exp_err_cnt;
    integer poll;
    reg [31:0] status;
    reg [31:0] err_cnt;
    begin
        poll = 0;
        rd = 32'hffff_ffff;
        while ((rd !== exp_rd_ptr) && (poll < 50000)) begin
            u_ps.axil_read(TXD0 + `DMA_TX_DESC_RD_PTR, rd);
            if (rd !== exp_rd_ptr) begin
                @(posedge clk);
                poll = poll + 1;
            end
        end
        if (poll >= 50000) begin
            $display("Error: timeout waiting DESC_RD_PTR exp=%08x got=%08x", exp_rd_ptr, rd);
            $finish;
        end

        read_desc_triplet(rd, status, err_cnt);
        if (rd !== exp_rd_ptr) begin
            $display("Error: DESC_RD_PTR mismatch exp=%08x got=%08x", exp_rd_ptr, rd);
            $finish;
        end
        if (status[23:16] !== exp_status) begin
            $display("Error: DESC_STATUS code mismatch exp=%02x got=%08x", exp_status, status);
            $finish;
        end
        if (err_cnt !== exp_err_cnt) begin
            $display("Error: DESC_ERR_CNT mismatch exp=%0d got=%0d", exp_err_cnt, err_cnt);
            $finish;
        end
    end
endtask

task check_cqe;
    input [7:0] exp_dir;
    input [7:0] exp_status;
    input [7:0] exp_ch;
    input [15:0] exp_flow;
    input [31:0] exp_len;
    input [31:0] exp_addr;
    begin
        u_ps.dma_poll_cq_detail(exp_dir, exp_status, cqe_ch, cqe_flow, cqe_len, cqe_addr);
        if ((cqe_ch !== exp_ch) || (cqe_flow !== exp_flow) ||
            (cqe_len !== exp_len) || (cqe_addr !== exp_addr)) begin
            $display("Error: CQE mismatch dir=%02x status=%02x ch=%0d/%0d flow=%04x/%04x len=%0d/%0d addr=%08x/%08x",
                     exp_dir, exp_status, cqe_ch, exp_ch, cqe_flow, exp_flow, cqe_len, exp_len, cqe_addr, exp_addr);
            $finish;
        end
    end
endtask

task compare_payload;
    input [31:0] src_addr;
    input [31:0] dst_addr;
    input [31:0] len;
    integer j;
    begin
        for (j = 0; j < len; j = j + 1) begin
            if (`DMA_SYS_MEM_PATH[src_addr + j] !== `DMA_SYS_MEM_PATH[dst_addr + j]) begin
                $display("Error: payload mismatch idx=%0d exp=%02x got=%02x",
                         j, `DMA_SYS_MEM_PATH[src_addr + j], `DMA_SYS_MEM_PATH[dst_addr + j]);
                $finish;
            end
        end
    end
endtask

task run_descriptor_success_case;
    begin
        $display("CASE descriptor_success_readback");
        reset_dut();
        common_config();
        write_desc_raw(DESC_BASE, (1 << `DMA_TX_DESC_OWNER_VALID),
                       TEST_FLOW_ID, TEST_STREAM_ID, PAYLOAD_LEN, TX_PAYLOAD_BASE, 32'h0, 32'h11);
        start_desc(32'd64);
        expect_desc_readback(32'd64, `DMA_ST_TX_DONE, 32'd0);
        check_cqe(`DMA_CQE_DIR_TX, `DMA_ST_TX_DONE, TX_CH[7:0], TEST_FLOW_ID, PAYLOAD_LEN, TX_PAYLOAD_BASE);
    end
endtask

task run_owner_error_case;
    begin
        $display("CASE descriptor_owner_error_readback");
        reset_dut();
        common_config();
        write_desc_raw(DESC_BASE, 32'h0,
                       TEST_FLOW_ID, TEST_STREAM_ID, 32'd64, TX_PAYLOAD_BASE, 32'h0, 32'h22);
        start_desc(32'd64);
        expect_desc_readback(32'd64, `DMA_ST_TX_DESC_OWNER_ERR, 32'd1);
        check_cqe(`DMA_CQE_DIR_TX, `DMA_ST_TX_DESC_OWNER_ERR, TX_CH[7:0], TEST_FLOW_ID, 32'd64, TX_PAYLOAD_BASE);
    end
endtask

task run_payload_read_error_case;
    begin
        $display("CASE descriptor_payload_read_error_readback");
        reset_dut();
        common_config();
        write_desc_raw(DESC_BASE, (1 << `DMA_TX_DESC_OWNER_VALID),
                       TEST_FLOW_ID, TEST_STREAM_ID, 32'd64, TX_PAYLOAD_BASE, 32'h0, 32'h33);
        u_ddr.set_read_error_addr(1'b1, TX_PAYLOAD_BASE);
        start_desc(32'd64);
        expect_desc_readback(32'd64, `DMA_ST_AXI_READ_ERR, 32'd1);
        check_cqe(`DMA_CQE_DIR_TX, `DMA_ST_AXI_READ_ERR, TX_CH[7:0], TEST_FLOW_ID, 32'd64, TX_PAYLOAD_BASE);
    end
endtask

task run_single_shot_compat_case;
    begin
        $display("CASE single_shot_compat");
        reset_dut();
        u_ddr.clear_all();
        fill_payload(TX_PAYLOAD_BASE, 32'd4096, 8'h5A);
        u_ps.axil_write(`DMA_REG_IRQ_MASK, 32'hffff_ffff);
        u_ps.dma_config_cq(CQ_BASE, CQ_SIZE);
        u_ps.dma_config_rx_channel(RX_CH, RX_PAYLOAD_BASE, RX_RING_SIZE, 32'd4096,
                                   TEST_FLOW_ID, `DMA_RX_POL_QUEUE_WITH_FC,
                                   32'd2048, 32'd1024);
        u_ps.dma_config_tx_channel(TX_CH, TX_PAYLOAD_BASE + 32'd512, 32'd256, TEST_FLOW_ID, `DMA_TC_FC, `DMA_TX_POL_SINGLE_SHOT);
        u_ps.dma_global_enable(1'b1, 1'b1, 1'b1, 1'b1);
        u_ps.dma_start_tx(TX_CH);
        check_cqe(`DMA_CQE_DIR_TX, `DMA_ST_TX_DONE, TX_CH[7:0], TEST_FLOW_ID, 32'd256, TX_PAYLOAD_BASE + 32'd512);
        check_cqe(`DMA_CQE_DIR_RX, `DMA_ST_FRAME_DONE, RX_CH[7:0], TEST_FLOW_ID, 32'd256, RX_PAYLOAD_BASE);
        compare_payload(TX_PAYLOAD_BASE + 32'd512, RX_PAYLOAD_BASE, 32'd256);
    end
endtask

initial begin
    clk = 1'b0;
    rstn = 1'b0;
    for (i = 0; i < `DMA_SIM_MEM_BYTES; i = i + 1) begin
        sys_mem[i] = 8'h0;
        ref_mem[i] = 8'h0;
    end

    run_descriptor_success_case();
    run_owner_error_case();
    run_payload_read_error_case();
    run_single_shot_compat_case();

    $display("SUMMARY: v31 TX descriptor status pipeline PASS");
    $finish;
end

endmodule
