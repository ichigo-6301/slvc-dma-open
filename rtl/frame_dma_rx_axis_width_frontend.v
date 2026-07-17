`timescale 1ns/1ps
`include "dma_defs.vh"

// 可选外部 RX 宽度 frontend：接受 64/128/256/512-bit AXIS，并聚合到固定 512-bit
// Core。它是接口适配层，不代表 native DMA Core 已经完成对应宽度的独立验证。
module frame_dma_rx_axis_width_frontend #(
    parameter integer EXT_AXIS_DATA_WIDTH = `DMA_EXT_AXIS_DATA_WIDTH,
    parameter integer CORE_AXIS_DATA_WIDTH = 512,
    parameter integer TX_RD_MAX_OUTSTANDING = `DMA_TX_RD_MAX_OUTSTANDING,
    parameter integer RX_WR_MAX_OUTSTANDING = `DMA_RX_WR_MAX_OUTSTANDING
)(
    input                                 aclk,
    input                                 aresetn,
    input                                 tx_axis_aclk,
    input                                 tx_axis_aresetn,
    input      [EXT_AXIS_DATA_WIDTH-1:0]  s_axis_tdata,
    input                                 s_axis_tvalid,
    output                                s_axis_tready,
    output     [511:0]                    tx_axis_tdata,
    output                                tx_axis_tvalid,
    input                                 tx_axis_tready,
    input      [31:0]                     s_axil_awaddr,
    input                                 s_axil_awvalid,
    output                                s_axil_awready,
    input      [31:0]                     s_axil_wdata,
    input      [3:0]                      s_axil_wstrb,
    input                                 s_axil_wvalid,
    output                                s_axil_wready,
    output     [1:0]                      s_axil_bresp,
    output                                s_axil_bvalid,
    input                                 s_axil_bready,
    input      [31:0]                     s_axil_araddr,
    input                                 s_axil_arvalid,
    output                                s_axil_arready,
    output     [31:0]                     s_axil_rdata,
    output     [1:0]                      s_axil_rresp,
    output                                s_axil_rvalid,
    input                                 s_axil_rready,
    output     [31:0]                     m_axi_awaddr,
    output     [7:0]                      m_axi_awlen,
    output     [2:0]                      m_axi_awsize,
    output     [1:0]                      m_axi_awburst,
    output                                m_axi_awvalid,
    input                                 m_axi_awready,
    output     [63:0]                     m_axi_wdata,
    output     [7:0]                      m_axi_wstrb,
    output                                m_axi_wlast,
    output                                m_axi_wvalid,
    input                                 m_axi_wready,
    input      [1:0]                      m_axi_bresp,
    input                                 m_axi_bvalid,
    output                                m_axi_bready,
    output     [31:0]                     m_axi_araddr,
    output     [7:0]                      m_axi_arlen,
    output     [2:0]                      m_axi_arsize,
    output     [1:0]                      m_axi_arburst,
    output                                m_axi_arvalid,
    input                                 m_axi_arready,
    input      [63:0]                     m_axi_rdata,
    input      [1:0]                      m_axi_rresp,
    input                                 m_axi_rlast,
    input                                 m_axi_rvalid,
    output                                m_axi_rready,
    output                                ufc_tx_valid,
    input                                 ufc_tx_ready,
    output     [7:0]                      ufc_tx_opcode,
    output     [15:0]                     ufc_tx_flow_id,
    output     [31:0]                     ufc_tx_arg0,
    output     [31:0]                     ufc_tx_arg1,
    input                                 ufc_rx_valid,
    output                                ufc_rx_ready,
    input      [7:0]                      ufc_rx_opcode,
    input      [15:0]                     ufc_rx_flow_id,
    input      [31:0]                     ufc_rx_arg0,
    input      [31:0]                     ufc_rx_arg1,
    output                                irq
);

wire [CORE_AXIS_DATA_WIDTH-1:0] core_rx_axis_tdata;
wire                            core_rx_axis_tvalid;
wire                            core_rx_axis_tready;

initial begin
    if (CORE_AXIS_DATA_WIDTH != 512)
        $fatal(1, "frame_dma_rx_axis_width_frontend requires CORE_AXIS_DATA_WIDTH=512");
    if (!((EXT_AXIS_DATA_WIDTH == 64) || (EXT_AXIS_DATA_WIDTH == 128) ||
          (EXT_AXIS_DATA_WIDTH == 256) || (EXT_AXIS_DATA_WIDTH == 512)))
        $fatal(1, "EXT_AXIS_DATA_WIDTH must be 64/128/256/512");
end

dma_axis_width_pack_512 #(
    .EXT_AXIS_DATA_WIDTH(EXT_AXIS_DATA_WIDTH),
    .CORE_AXIS_DATA_WIDTH(CORE_AXIS_DATA_WIDTH)
) u_axis_width_pack_512 (
    .clk(aclk),
    .rstn(aresetn),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(core_rx_axis_tdata),
    .m_axis_tvalid(core_rx_axis_tvalid),
    .m_axis_tready(core_rx_axis_tready)
);

frame_dma_rx_top #(
    .TX_RD_MAX_OUTSTANDING(TX_RD_MAX_OUTSTANDING),
    .RX_WR_MAX_OUTSTANDING(RX_WR_MAX_OUTSTANDING)
) u_core (
    .aclk(aclk),
    .aresetn(aresetn),
    .tx_axis_aclk(tx_axis_aclk),
    .tx_axis_aresetn(tx_axis_aresetn),
    .rx_axis_tdata(core_rx_axis_tdata),
    .rx_axis_tvalid(core_rx_axis_tvalid),
    .rx_axis_tready(core_rx_axis_tready),
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

endmodule
