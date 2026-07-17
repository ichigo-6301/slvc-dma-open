`timescale 1ns/1ps

// Shared frame payload 的 RAM 叶节点，提供按 block/word 地址访问的同步存储。
// RAM 内容不承担 reset 语义；所有帧是否可见由 pool metadata、valid 和 free list
// 控制，避免为清空大容量数据阵列引入额外复位扇出。
module dma_frame_payload_ram #(
    parameter integer BLOCK_NUM = 64,
    parameter integer BLOCK_AW = 6,
    parameter integer DATA_W = 512,
    parameter integer KEEP_W = 64
)(
    input  wire                  clk,

    input  wire                  wr_en,
    input  wire [BLOCK_AW-1:0]   wr_addr,
    input  wire [DATA_W-1:0]     wr_data,
    input  wire [KEEP_W-1:0]     wr_keep,

    input  wire                  rd_en,
    input  wire [BLOCK_AW-1:0]   rd_addr,
    output reg  [DATA_W-1:0]     rd_data,
    output reg  [KEEP_W-1:0]     rd_keep
);

(* ram_style = "block" *) reg [DATA_W-1:0] payload_mem [0:BLOCK_NUM-1];
(* ram_style = "distributed" *) reg [KEEP_W-1:0] keep_mem [0:BLOCK_NUM-1];

always @(posedge clk) begin
    if (wr_en) begin
        payload_mem[wr_addr] <= wr_data;
        keep_mem[wr_addr] <= wr_keep;
    end

    if (rd_en) begin
        rd_data <= payload_mem[rd_addr];
        rd_keep <= keep_mem[rd_addr];
    end
end

endmodule
