`timescale 1ns/1ps

module slvc_carrier_cdc_adapter #(
    parameter integer SL_DATA_WIDTH = 512,
    parameter integer AXIS_FIFO_DEPTH_LOG2 = 4,
    parameter integer CTRL_FIFO_DEPTH_LOG2 = 3
)(
    input                           carrier_rx_clk,
    input                           carrier_rx_rst_n,
    input      [SL_DATA_WIDTH-1:0]  carrier_rx_tdata,
    input                           carrier_rx_tvalid,
    output                          carrier_rx_tready,

    input                           carrier_tx_clk,
    input                           carrier_tx_rst_n,
    output     [SL_DATA_WIDTH-1:0]  carrier_tx_tdata,
    output                          carrier_tx_tvalid,
    input                           carrier_tx_tready,

    input                           carrier_ctrl_rx_clk,
    input                           carrier_ctrl_rx_rst_n,
    input                           carrier_ctrl_rx_valid,
    output                          carrier_ctrl_rx_ready,
    input      [7:0]                carrier_ctrl_rx_opcode,
    input      [15:0]               carrier_ctrl_rx_channel_id,
    input      [31:0]               carrier_ctrl_rx_arg0,
    input      [31:0]               carrier_ctrl_rx_arg1,

    input                           carrier_ctrl_tx_clk,
    input                           carrier_ctrl_tx_rst_n,
    output                          carrier_ctrl_tx_valid,
    input                           carrier_ctrl_tx_ready,
    output     [7:0]                carrier_ctrl_tx_opcode,
    output     [15:0]               carrier_ctrl_tx_channel_id,
    output     [31:0]               carrier_ctrl_tx_arg0,
    output     [31:0]               carrier_ctrl_tx_arg1,

    input                           dma_clk,
    input                           dma_rst_n,
    output     [SL_DATA_WIDTH-1:0]  dma_sl_rx_tdata,
    output                          dma_sl_rx_tvalid,
    input                           dma_sl_rx_tready,
    input      [SL_DATA_WIDTH-1:0]  dma_sl_tx_tdata,
    input                           dma_sl_tx_tvalid,
    output                          dma_sl_tx_tready,

    output                          dma_ctrl_rx_valid,
    input                           dma_ctrl_rx_ready,
    output     [7:0]                dma_ctrl_rx_opcode,
    output     [15:0]               dma_ctrl_rx_channel_id,
    output     [31:0]               dma_ctrl_rx_arg0,
    output     [31:0]               dma_ctrl_rx_arg1,

    input                           dma_ctrl_tx_valid,
    output                          dma_ctrl_tx_ready,
    input      [7:0]                dma_ctrl_tx_opcode,
    input      [15:0]               dma_ctrl_tx_channel_id,
    input      [31:0]               dma_ctrl_tx_arg0,
    input      [31:0]               dma_ctrl_tx_arg1
);

dma_axis_async_fifo #(
    .DATA_WIDTH(SL_DATA_WIDTH),
    .DEPTH_LOG2(AXIS_FIFO_DEPTH_LOG2)
) u_rx_data_fifo (
    .s_clk(carrier_rx_clk),
    .s_rst_n(carrier_rx_rst_n),
    .s_tdata(carrier_rx_tdata),
    .s_tvalid(carrier_rx_tvalid),
    .s_tready(carrier_rx_tready),
    .m_clk(dma_clk),
    .m_rst_n(dma_rst_n),
    .m_tdata(dma_sl_rx_tdata),
    .m_tvalid(dma_sl_rx_tvalid),
    .m_tready(dma_sl_rx_tready)
);

dma_axis_async_fifo #(
    .DATA_WIDTH(SL_DATA_WIDTH),
    .DEPTH_LOG2(AXIS_FIFO_DEPTH_LOG2),
    .READ_PIPELINE(1)
) u_tx_data_fifo (
    .s_clk(dma_clk),
    .s_rst_n(dma_rst_n),
    .s_tdata(dma_sl_tx_tdata),
    .s_tvalid(dma_sl_tx_tvalid),
    .s_tready(dma_sl_tx_tready),
    .m_clk(carrier_tx_clk),
    .m_rst_n(carrier_tx_rst_n),
    .m_tdata(carrier_tx_tdata),
    .m_tvalid(carrier_tx_tvalid),
    .m_tready(carrier_tx_tready)
);

dma_ctrl_msg_async_fifo #(
    .DEPTH_LOG2(CTRL_FIFO_DEPTH_LOG2)
) u_ctrl_rx_fifo (
    .s_clk(carrier_ctrl_rx_clk),
    .s_rst_n(carrier_ctrl_rx_rst_n),
    .s_valid(carrier_ctrl_rx_valid),
    .s_ready(carrier_ctrl_rx_ready),
    .s_opcode(carrier_ctrl_rx_opcode),
    .s_channel_id(carrier_ctrl_rx_channel_id),
    .s_arg0(carrier_ctrl_rx_arg0),
    .s_arg1(carrier_ctrl_rx_arg1),
    .m_clk(dma_clk),
    .m_rst_n(dma_rst_n),
    .m_valid(dma_ctrl_rx_valid),
    .m_ready(dma_ctrl_rx_ready),
    .m_opcode(dma_ctrl_rx_opcode),
    .m_channel_id(dma_ctrl_rx_channel_id),
    .m_arg0(dma_ctrl_rx_arg0),
    .m_arg1(dma_ctrl_rx_arg1)
);

dma_ctrl_msg_async_fifo #(
    .DEPTH_LOG2(CTRL_FIFO_DEPTH_LOG2)
) u_ctrl_tx_fifo (
    .s_clk(dma_clk),
    .s_rst_n(dma_rst_n),
    .s_valid(dma_ctrl_tx_valid),
    .s_ready(dma_ctrl_tx_ready),
    .s_opcode(dma_ctrl_tx_opcode),
    .s_channel_id(dma_ctrl_tx_channel_id),
    .s_arg0(dma_ctrl_tx_arg0),
    .s_arg1(dma_ctrl_tx_arg1),
    .m_clk(carrier_ctrl_tx_clk),
    .m_rst_n(carrier_ctrl_tx_rst_n),
    .m_valid(carrier_ctrl_tx_valid),
    .m_ready(carrier_ctrl_tx_ready),
    .m_opcode(carrier_ctrl_tx_opcode),
    .m_channel_id(carrier_ctrl_tx_channel_id),
    .m_arg0(carrier_ctrl_tx_arg0),
    .m_arg1(carrier_ctrl_tx_arg1)
);

endmodule
