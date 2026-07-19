`timescale 1ns/1ps

// UFC/control message 的双时钟 FIFO。opcode、channel_id 和两个参数先打包成单一
// payload 再跨域，避免字段分别同步造成消息撕裂；消息边界由 FIFO entry 保证。
module dma_ctrl_msg_async_fifo #(
    parameter integer DEPTH_LOG2 = 3
)(
    input         s_clk,
    input         s_rst_n,
    input         s_valid,
    output        s_ready,
    input  [7:0]  s_opcode,
    input  [15:0] s_channel_id,
    input  [31:0] s_arg0,
    input  [31:0] s_arg1,

    input         m_clk,
    input         m_rst_n,
    output        m_valid,
    input         m_ready,
    output [7:0]  m_opcode,
    output [15:0] m_channel_id,
    output [31:0] m_arg0,
    output [31:0] m_arg1
);

wire [87:0] s_payload;
wire [87:0] m_payload;

assign s_payload = {s_arg1, s_arg0, s_channel_id, s_opcode};
assign {m_arg1, m_arg0, m_channel_id, m_opcode} = m_payload;

dma_async_fifo #(
    .DATA_WIDTH(88),
    .DEPTH_LOG2(DEPTH_LOG2)
) u_fifo (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_data(s_payload),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_data(m_payload),
    .m_valid(m_valid),
    .m_ready(m_ready),
    .s_full(),
    .m_empty(),
    .s_level(),
    .m_level()
);

endmodule
