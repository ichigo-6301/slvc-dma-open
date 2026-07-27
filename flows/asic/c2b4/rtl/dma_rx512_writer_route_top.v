`timescale 1ns/1ps

// Flow-only Target A wrapper. The fixed parameters are part of the A1
// implementation profile and do not change the production writer defaults.
module dma_rx512_writer_route_top (
    input               clk,
    input               rstn,
    input               soft_reset,

    input               cmd_valid,
    output              cmd_ready,
    input      [31:0]   cmd_addr,
    input      [31:0]   cmd_len,

    input               s_payload_tvalid,
    output              s_payload_tready,
    input      [511:0]  s_payload_tdata,
    input      [63:0]   s_payload_tkeep,
    input               s_payload_tlast,
    input      [7:0]    s_payload_level,

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
    output              busy
);

dma_axi_write_engine_512 #(
    .MAX_BURST_BEATS(16),
    .MAX_OUTSTANDING(4),
    .MAX_CMD_BYTES(4096),
    .USE_SOURCE_CREDIT(0)
) u_writer (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_addr(cmd_addr),
    .cmd_len(cmd_len),
    .s_payload_tvalid(s_payload_tvalid),
    .s_payload_tready(s_payload_tready),
    .s_payload_tdata(s_payload_tdata),
    .s_payload_tkeep(s_payload_tkeep),
    .s_payload_tlast(s_payload_tlast),
    .s_payload_level(s_payload_level),
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
    .cpl_valid(cpl_valid),
    .cpl_ready(cpl_ready),
    .cpl_error(cpl_error),
    .cpl_error_code(cpl_error_code),
    .busy(busy)
);

endmodule
