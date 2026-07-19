`timescale 1ns/1ps

// AXI4-Stream 双时钟 FIFO 包装层，把 data/valid/ready 的跨域交给 async FIFO，
// 保持每个 beat 的顺序和 backpressure 语义，不让源域 ready 直接观察目的域逻辑。
module dma_axis_async_fifo #(
    parameter integer DATA_WIDTH = 512,
    parameter integer DEPTH_LOG2 = 4,
    parameter integer READ_PIPELINE = 0
)(
    input                       s_clk,
    input                       s_rst_n,
    input      [DATA_WIDTH-1:0] s_tdata,
    input                       s_tvalid,
    output                      s_tready,

    input                       m_clk,
    input                       m_rst_n,
    output     [DATA_WIDTH-1:0] m_tdata,
    output                      m_tvalid,
    input                       m_tready
);

dma_async_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH_LOG2(DEPTH_LOG2),
    .READ_PIPELINE(READ_PIPELINE)
) u_fifo (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_data(s_tdata),
    .s_valid(s_tvalid),
    .s_ready(s_tready),
    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_data(m_tdata),
    .m_valid(m_tvalid),
    .m_ready(m_tready),
    .s_full(),
    .m_empty(),
    .s_level(),
    .m_level()
);

endmodule
