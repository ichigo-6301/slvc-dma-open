`timescale 1ns/1ps
`include "dma_defs.vh"

// 将 parser 产生的 flow/channel metadata 与通道寄存器快照匹配。
// 本模块只做 combinational 选择和合法性判断，不拥有 channel 表；表的更新由
// dma_rx_channel_table 完成，match 结果随后进入 RX admission pipeline。
module dma_rx_channel_match(
    input      [3:0]   traffic_class,
    input      [15:0]  flow_id,
    input      [15:0]  msg_id,
    input      [31:0]  payload_len,
    input      [`DMA_MAX_CH*32-1:0] rx_ctrl_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_cfg_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_size_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_max_len_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_wr_ptr_flat,
    output reg         match_valid,
    output reg [3:0]   match_ch,
    output reg [3:0]   match_policy,
    output reg [7:0]   reject_code,
    output reg         reject_drop
);

integer i;
reg [31:0] ctrl_i;
reg [31:0] cfg_i;
reg [31:0] size_i;
reg [31:0] max_len_i;
reg [31:0] wr_ptr_i;
reg [15:0] match_id;

function policy_supported;
    input [3:0] tc;
    input [3:0] policy;
    begin
        case (tc)
        `DMA_TC_CONT:
            policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                               (policy == `DMA_RX_POL_LINEAR_CAPTURE) ||
                               (policy == `DMA_RX_POL_RING_BUFFER);
        `DMA_TC_FC:
            policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                               (policy == `DMA_RX_POL_QUEUE_DROP_NEW) ||
                               (policy == `DMA_RX_POL_QUEUE_WITH_FC) ||
                               (policy == `DMA_RX_POL_QUEUE_LOSSLESS);
        `DMA_TC_AUX:
            policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                               (policy == `DMA_RX_POL_LINEAR_CAPTURE) ||
                               (policy == `DMA_RX_POL_MAILBOX) ||
                               (policy == `DMA_RX_POL_AUX_FIFO);
        default:
            policy_supported = 1'b0;
        endcase
    end
endfunction

function [31:0] align64;
    input [31:0] value;
    begin
        align64 = (value + 32'd63) & 32'hffff_ffc0;
    end
endfunction

always @(*) begin
    match_valid = 1'b0;
    match_ch = 4'hf;
    match_policy = 4'h0;
    reject_code = `DMA_ST_POLICY_REJECT;
    reject_drop = 1'b0;
    match_id = (traffic_class == `DMA_TC_AUX) ? msg_id : flow_id;

    for (i = 0; i < `DMA_MAX_CH; i = i + 1) begin
        ctrl_i = rx_ctrl_flat[i*32 +: 32];
        cfg_i = rx_cfg_flat[i*32 +: 32];
        size_i = rx_size_flat[i*32 +: 32];
        max_len_i = rx_max_len_flat[i*32 +: 32];
        wr_ptr_i = rx_wr_ptr_flat[i*32 +: 32];
        if (!match_valid && ctrl_i[`DMA_RX_CTRL_ENABLE] &&
            (cfg_i[3:0] == traffic_class) && (cfg_i[31:16] == match_id)) begin
            match_valid = 1'b1;
            match_ch = i[3:0];
            match_policy = cfg_i[7:4];
            if (!policy_supported(traffic_class, cfg_i[7:4])) begin
                reject_code = `DMA_ST_UNSUP_POLICY;
            end else if ((max_len_i != 0) && (payload_len > max_len_i)) begin
                reject_code = `DMA_ST_FRAME_TOO_BIG;
                reject_drop = 1'b1;
            end else if ((size_i != 0) &&
                         (traffic_class != `DMA_TC_FC) &&
                         (wr_ptr_i + align64(payload_len) > size_i) &&
                         (cfg_i[7:4] != `DMA_RX_POL_RING_BUFFER)) begin
                reject_code = `DMA_ST_BUFFER_FULL;
                reject_drop = 1'b1;
            end else begin
                reject_code = `DMA_ST_OK;
            end
        end
    end
end

endmodule
