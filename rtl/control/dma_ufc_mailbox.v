`timescale 1ns/1ps
`include "dma_defs.vh"

// UFC 控制消息 mailbox：接收侧只在本地 pending 未占用时接收一条消息，发送侧
// 通过 core_tx_ready 与链路 ready 解耦。它承载控制消息，不承担 payload 数据流控。
module dma_ufc_mailbox(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             quiesce,
    input             enable,

    input             tx_start,
    input      [7:0]  tx_cfg_opcode,
    input      [15:0] tx_cfg_flow_id,
    input      [31:0] tx_cfg_arg0,
    input      [31:0] tx_cfg_arg1,
    input             tx_clear_done,
    input             tx_clear_busy_reject,
    output reg        tx_busy,
    output reg        tx_done,
    output reg        tx_busy_reject,
    output reg        tx_done_pulse,

    input             core_tx_valid,
    output            core_tx_ready,
    input      [7:0]  core_tx_opcode,
    input      [15:0] core_tx_flow_id,
    input      [31:0] core_tx_arg0,
    input      [31:0] core_tx_arg1,

    output reg        ufc_tx_valid,
    input             ufc_tx_ready,
    output reg [7:0]  ufc_tx_opcode,
    output reg [15:0] ufc_tx_flow_id,
    output reg [31:0] ufc_tx_arg0,
    output reg [31:0] ufc_tx_arg1,

    input             ufc_rx_valid,
    output            ufc_rx_ready,
    input      [7:0]  ufc_rx_opcode,
    input      [15:0] ufc_rx_flow_id,
    input      [31:0] ufc_rx_arg0,
    input      [31:0] ufc_rx_arg1,
    input             rx_clear_pending,
    input             rx_clear_overrun,
    output reg        rx_pending,
    output reg        rx_overrun,
    output reg [7:0]  rx_msg_opcode,
    output reg [15:0] rx_msg_flow_id,
    output reg [31:0] rx_msg_arg0,
    output reg [31:0] rx_msg_arg1,
    output reg        rx_msg_pulse
);

reg tx_ps_active;

assign ufc_rx_ready = enable && !quiesce && !rx_pending;
assign core_tx_ready = enable && !quiesce && !ufc_tx_valid && !tx_busy;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tx_busy <= 1'b0;
        tx_done <= 1'b0;
        tx_busy_reject <= 1'b0;
        tx_done_pulse <= 1'b0;
        ufc_tx_valid <= 1'b0;
        tx_ps_active <= 1'b0;
        ufc_tx_opcode <= 8'h0;
        ufc_tx_flow_id <= 16'h0;
        ufc_tx_arg0 <= 32'h0;
        ufc_tx_arg1 <= 32'h0;
        rx_pending <= 1'b0;
        rx_overrun <= 1'b0;
        rx_msg_opcode <= 8'h0;
        rx_msg_flow_id <= 16'h0;
        rx_msg_arg0 <= 32'h0;
        rx_msg_arg1 <= 32'h0;
        rx_msg_pulse <= 1'b0;
    end else if (soft_reset) begin
        tx_busy <= 1'b0;
        tx_done <= 1'b0;
        tx_busy_reject <= 1'b0;
        tx_done_pulse <= 1'b0;
        ufc_tx_valid <= 1'b0;
        tx_ps_active <= 1'b0;
        ufc_tx_opcode <= 8'h0;
        ufc_tx_flow_id <= 16'h0;
        ufc_tx_arg0 <= 32'h0;
        ufc_tx_arg1 <= 32'h0;
        rx_pending <= 1'b0;
        rx_overrun <= 1'b0;
        rx_msg_opcode <= 8'h0;
        rx_msg_flow_id <= 16'h0;
        rx_msg_arg0 <= 32'h0;
        rx_msg_arg1 <= 32'h0;
        rx_msg_pulse <= 1'b0;
    end else begin
        tx_done_pulse <= 1'b0;
        rx_msg_pulse <= 1'b0;

        if (tx_clear_done)
            tx_done <= 1'b0;
        if (tx_clear_busy_reject)
            tx_busy_reject <= 1'b0;
        if (rx_clear_overrun)
            rx_overrun <= 1'b0;
        if (rx_clear_pending)
            rx_pending <= 1'b0;

        if (!enable) begin
            tx_busy <= 1'b0;
            ufc_tx_valid <= 1'b0;
            tx_ps_active <= 1'b0;
        end else begin
            if (core_tx_valid && core_tx_ready) begin
                ufc_tx_valid <= 1'b1;
                tx_ps_active <= 1'b0;
                ufc_tx_opcode <= core_tx_opcode;
                ufc_tx_flow_id <= core_tx_flow_id;
                ufc_tx_arg0 <= core_tx_arg0;
                ufc_tx_arg1 <= core_tx_arg1;
            end else if (tx_start && !quiesce) begin
                if (tx_busy || ufc_tx_valid) begin
                    tx_busy_reject <= 1'b1;
                end else begin
                    tx_busy <= 1'b1;
                    ufc_tx_valid <= 1'b1;
                    tx_ps_active <= 1'b1;
                    ufc_tx_opcode <= tx_cfg_opcode;
                    ufc_tx_flow_id <= tx_cfg_flow_id;
                    ufc_tx_arg0 <= tx_cfg_arg0;
                    ufc_tx_arg1 <= tx_cfg_arg1;
                end
            end

            if (ufc_tx_valid && ufc_tx_ready) begin
                ufc_tx_valid <= 1'b0;
                tx_busy <= 1'b0;
                if (tx_ps_active) begin
                    tx_done <= 1'b1;
                    tx_done_pulse <= 1'b1;
                end
                tx_ps_active <= 1'b0;
            end
        end

        if (enable && !quiesce && ufc_rx_valid) begin
            if (!rx_pending) begin
                rx_pending <= 1'b1;
                rx_msg_opcode <= ufc_rx_opcode;
                rx_msg_flow_id <= ufc_rx_flow_id;
                rx_msg_arg0 <= ufc_rx_arg0;
                rx_msg_arg1 <= ufc_rx_arg1;
                rx_msg_pulse <= 1'b1;
            end else begin
                rx_overrun <= 1'b1;
            end
        end
    end
end

endmodule
