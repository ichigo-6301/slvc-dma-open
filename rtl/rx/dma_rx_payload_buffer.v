`timescale 1ns/1ps
`include "dma_defs.vh"

// 旧式 per-channel payload 缓冲，按 64-bit word 组织并由上层提供读索引。
// 它保留用于兼容路径；共享 frame pool 开启时，主数据路径由 pool/adapter 承担。
module dma_rx_payload_buffer(
    input             clk,
    input             rstn,
    input             start,
    input      [31:0] payload_len,
    input      [511:0] in_tdata,
    input             in_tvalid,
    output            in_tready,
    output reg        done,
    output     [63:0] rd_data,
    input      [8:0]  rd_index
);

localparam MAX_WORDS = 512;

reg [63:0] mem [0:MAX_WORDS-1];
reg [8:0]  wr_word_base;
reg [8:0]  beats_needed;
reg [8:0]  beats_seen;
reg        active;

assign in_tready = active && !done;
assign rd_data = mem[rd_index];

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        wr_word_base <= 9'h0;
        beats_needed <= 9'h0;
        beats_seen <= 9'h0;
        active <= 1'b0;
        done <= 1'b0;
    end else begin
        if (start) begin
            wr_word_base <= 9'h0;
            beats_needed <= (payload_len + 32'd63) >> 6;
            beats_seen <= 9'h0;
            done <= (payload_len == 0);
            active <= (payload_len != 0);
        end else if (in_tvalid && in_tready) begin
            mem[wr_word_base + 0] <= in_tdata[  0 +: 64];
            mem[wr_word_base + 1] <= in_tdata[ 64 +: 64];
            mem[wr_word_base + 2] <= in_tdata[128 +: 64];
            mem[wr_word_base + 3] <= in_tdata[192 +: 64];
            mem[wr_word_base + 4] <= in_tdata[256 +: 64];
            mem[wr_word_base + 5] <= in_tdata[320 +: 64];
            mem[wr_word_base + 6] <= in_tdata[384 +: 64];
            mem[wr_word_base + 7] <= in_tdata[448 +: 64];
            wr_word_base <= wr_word_base + 9'd8;
            beats_seen <= beats_seen + 1'b1;
            if ((beats_seen + 1'b1) >= beats_needed) begin
                done <= 1'b1;
                active <= 1'b0;
            end
        end
    end
end

endmodule
