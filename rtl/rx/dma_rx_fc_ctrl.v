`timescale 1ns/1ps
`include "dma_defs.vh"

// RX flow-control 控制器。它根据各通道 used/high/low watermark 产生 pause/resume
// 事件，并把控制消息与 ingress enqueue 的时序解耦；pause 是链路侧策略事件，
// 不是 AXI4-Stream tready 的端到端替代品。
module dma_rx_fc_ctrl(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             enable,
    input             ufc_enable,
    input      [31:0] queue_used_bytes,
    input      [`DMA_MAX_CH*32-1:0] rx_ctrl_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_cfg_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_size_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_used_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_high_wm_flat,
    input      [`DMA_MAX_CH*32-1:0] rx_low_wm_flat,

    input             enq_valid,
    input      [3:0]  enq_ch,
    input      [3:0]  enq_policy,
    input      [15:0] enq_flow_id,
    input      [31:0] enq_aligned_len,
    input      [31:0] enq_rx_ctrl,
    input      [31:0] enq_high_wm,
    input      [31:0] enq_low_wm,

    output reg        core_tx_valid,
    input             core_tx_ready,
    output reg [7:0]  core_tx_opcode,
    output reg [15:0] core_tx_flow_id,
    output reg [31:0] core_tx_arg0,
    output reg [31:0] core_tx_arg1,
    output     [`DMA_MAX_CH-1:0] pause_active_flat,
    input             ch_reset_valid,
    input      [3:0]  ch_reset_ch,

    output reg        resume_scan_req_valid,
    output reg [3:0]  resume_scan_req_ch,
    input             resume_scan_rsp_valid,
    input      [3:0]  resume_scan_rsp_ch,
    input      [31:0] resume_scan_rsp_used,
    input      [31:0] resume_scan_rsp_low_wm,
    input      [31:0] resume_scan_rsp_size,
    input      [15:0] resume_scan_rsp_flow_id,

    output reg        status_valid,
    output reg [3:0]  status_ch,
    output reg        status_pause,
    output reg        status_low,
    output reg        status_irq
);

reg pause_active [0:`DMA_MAX_CH-1];
reg pause_pending [0:`DMA_MAX_CH-1];
reg [15:0] pause_pending_flow [0:`DMA_MAX_CH-1];
reg [31:0] pause_pending_used [0:`DMA_MAX_CH-1];
reg pause_pending_found;
reg [3:0] pause_pending_ch;
reg                   resume_calc_valid_q;
reg [3:0]             resume_calc_ch_q;
reg [15:0]            resume_calc_flow_id_q;
reg [31:0]            resume_free_q;
reg [3:0]             resume_scan_ch_q;
reg                   resume_scan_wait_q;
reg                   enq_pipe_valid_q;
reg [3:0]             enq_pipe_ch_q;
reg [15:0]            enq_pipe_flow_id_q;
reg                   enq_pipe_fc_enabled_q;
reg [31:0]            enq_pipe_used_after_q;
reg [31:0]            enq_pipe_high_wm_q;
integer i;
genvar gi;

generate
    for (gi = 0; gi < `DMA_MAX_CH; gi = gi + 1) begin : g_pause_flat
        assign pause_active_flat[gi] = pause_active[gi];
    end
endgenerate

wire enq_fc_enabled = enable && ufc_enable && enq_valid &&
                      enq_rx_ctrl[`DMA_RX_CTRL_FC_EN];
wire [31:0] used_after_enq = queue_used_bytes + enq_aligned_len;
wire [31:0] high_wm_eff = (enq_high_wm == 0) ? 32'd4096 : enq_high_wm;
wire pipe_should_pause = enable && ufc_enable && enq_pipe_valid_q &&
                         enq_pipe_fc_enabled_q && !pause_active[enq_pipe_ch_q] &&
                         (enq_pipe_used_after_q >= enq_pipe_high_wm_q);
wire should_pause = (`DMA_ENABLE_RX_FC_ENQ_PIPELINE != 0) ?
                    pipe_should_pause :
                    (enq_fc_enabled && !pause_active[enq_ch] &&
                     (used_after_enq >= high_wm_eff));
wire [3:0] should_pause_ch = (`DMA_ENABLE_RX_FC_ENQ_PIPELINE != 0) ?
                             enq_pipe_ch_q : enq_ch;
wire [15:0] should_pause_flow_id = (`DMA_ENABLE_RX_FC_ENQ_PIPELINE != 0) ?
                                   enq_pipe_flow_id_q : enq_flow_id;
wire [31:0] should_pause_used = (`DMA_ENABLE_RX_FC_ENQ_PIPELINE != 0) ?
                                 enq_pipe_used_after_q : used_after_enq;
wire ch_reset_fire = (ch_reset_valid === 1'b1);
wire resume_pipe_busy = resume_scan_wait_q || resume_calc_valid_q;

function [31:0] effective_low_wm;
    input [31:0] low_wm;
    begin
        effective_low_wm = (low_wm == 0) ? 32'd1024 : low_wm;
    end
endfunction

always @(*) begin
    pause_pending_found = 1'b0;
    pause_pending_ch = 4'h0;
    for (i = 0; i < `DMA_MAX_CH; i = i + 1) begin
        if (!pause_pending_found && pause_pending[i]) begin
            pause_pending_found = 1'b1;
            pause_pending_ch = i[3:0];
        end
    end

end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (i = 0; i < `DMA_MAX_CH; i = i + 1) begin
            pause_active[i] <= 1'b0;
            pause_pending[i] <= 1'b0;
            pause_pending_flow[i] <= 16'h0;
            pause_pending_used[i] <= 32'h0;
        end
        resume_calc_valid_q <= 1'b0;
        resume_calc_ch_q <= 4'h0;
        resume_calc_flow_id_q <= 16'h0;
        resume_free_q <= 32'h0;
        resume_scan_ch_q <= 4'h0;
        resume_scan_wait_q <= 1'b0;
        resume_scan_req_valid <= 1'b0;
        resume_scan_req_ch <= 4'h0;
        enq_pipe_valid_q <= 1'b0;
        enq_pipe_ch_q <= 4'h0;
        enq_pipe_flow_id_q <= 16'h0;
        enq_pipe_fc_enabled_q <= 1'b0;
        enq_pipe_used_after_q <= 32'h0;
        enq_pipe_high_wm_q <= 32'h0;
        core_tx_valid <= 1'b0;
        core_tx_opcode <= 8'h0;
        core_tx_flow_id <= 16'h0;
        core_tx_arg0 <= 32'h0;
        core_tx_arg1 <= 32'h0;
        status_valid <= 1'b0;
        status_ch <= 4'h0;
        status_pause <= 1'b0;
        status_low <= 1'b0;
        status_irq <= 1'b0;
    end else if (soft_reset) begin
        for (i = 0; i < `DMA_MAX_CH; i = i + 1) begin
            pause_active[i] <= 1'b0;
            pause_pending[i] <= 1'b0;
            pause_pending_flow[i] <= 16'h0;
            pause_pending_used[i] <= 32'h0;
        end
        resume_calc_valid_q <= 1'b0;
        resume_calc_ch_q <= 4'h0;
        resume_calc_flow_id_q <= 16'h0;
        resume_free_q <= 32'h0;
        resume_scan_ch_q <= 4'h0;
        resume_scan_wait_q <= 1'b0;
        resume_scan_req_valid <= 1'b0;
        resume_scan_req_ch <= 4'h0;
        enq_pipe_valid_q <= 1'b0;
        enq_pipe_ch_q <= 4'h0;
        enq_pipe_flow_id_q <= 16'h0;
        enq_pipe_fc_enabled_q <= 1'b0;
        enq_pipe_used_after_q <= 32'h0;
        enq_pipe_high_wm_q <= 32'h0;
        core_tx_valid <= 1'b0;
        core_tx_opcode <= 8'h0;
        core_tx_flow_id <= 16'h0;
        core_tx_arg0 <= 32'h0;
        core_tx_arg1 <= 32'h0;
        status_valid <= 1'b0;
        status_ch <= 4'h0;
        status_pause <= 1'b0;
        status_low <= 1'b0;
        status_irq <= 1'b0;
    end else begin
        resume_scan_req_valid <= 1'b0;
        if (`DMA_ENABLE_RX_FC_ENQ_PIPELINE != 0) begin
            enq_pipe_valid_q <= enq_valid;
            enq_pipe_ch_q <= enq_ch;
            enq_pipe_flow_id_q <= enq_flow_id;
            enq_pipe_fc_enabled_q <= enq_rx_ctrl[`DMA_RX_CTRL_FC_EN];
            enq_pipe_used_after_q <= used_after_enq;
            enq_pipe_high_wm_q <= high_wm_eff;
        end else begin
            enq_pipe_valid_q <= 1'b0;
            enq_pipe_ch_q <= 4'h0;
            enq_pipe_flow_id_q <= 16'h0;
            enq_pipe_fc_enabled_q <= 1'b0;
            enq_pipe_used_after_q <= 32'h0;
            enq_pipe_high_wm_q <= 32'h0;
        end
        status_valid <= 1'b0;
        status_irq <= 1'b0;

        if (!enable || !ufc_enable) begin
            for (i = 0; i < `DMA_MAX_CH; i = i + 1) begin
                pause_active[i] <= 1'b0;
                pause_pending[i] <= 1'b0;
            end
            resume_calc_valid_q <= 1'b0;
            resume_calc_ch_q <= 4'h0;
            resume_calc_flow_id_q <= 16'h0;
            resume_free_q <= 32'h0;
            resume_scan_wait_q <= 1'b0;
            resume_scan_req_valid <= 1'b0;
            enq_pipe_valid_q <= 1'b0;
            core_tx_valid <= 1'b0;
        end else begin
            if (ch_reset_fire) begin
                pause_active[ch_reset_ch] <= 1'b0;
                pause_pending[ch_reset_ch] <= 1'b0;
                if (resume_calc_valid_q && (resume_calc_ch_q == ch_reset_ch))
                    resume_calc_valid_q <= 1'b0;
                if (enq_pipe_valid_q && (enq_pipe_ch_q == ch_reset_ch))
                    enq_pipe_valid_q <= 1'b0;
            end

            if (core_tx_valid && core_tx_ready)
                core_tx_valid <= 1'b0;

            if (should_pause) begin
                pause_active[should_pause_ch] <= 1'b1;
                pause_pending[should_pause_ch] <= 1'b1;
                pause_pending_flow[should_pause_ch] <= should_pause_flow_id;
                pause_pending_used[should_pause_ch] <= should_pause_used;
                status_valid <= 1'b1;
                status_ch <= should_pause_ch;
                status_pause <= 1'b1;
                status_low <= 1'b0;
                status_irq <= 1'b1;
            end

            if (!core_tx_valid && pause_pending_found) begin
                pause_pending[pause_pending_ch] <= 1'b0;
                core_tx_valid <= 1'b1;
                core_tx_opcode <= `DMA_UFC_OP_PAUSE;
                core_tx_flow_id <= pause_pending_flow[pause_pending_ch];
                core_tx_arg0 <= (32'h1 << `DMA_UFC_PAUSE_DDR_HIGH);
                core_tx_arg1 <= pause_pending_used[pause_pending_ch];
            end else if (resume_calc_valid_q && !core_tx_valid && !pause_pending_found) begin
                if (!(ch_reset_fire && (resume_calc_ch_q == ch_reset_ch)) &&
                    pause_active[resume_calc_ch_q]) begin
                    pause_active[resume_calc_ch_q] <= 1'b0;
                    core_tx_valid <= 1'b1;
                    core_tx_opcode <= `DMA_UFC_OP_RESUME;
                    core_tx_flow_id <= resume_calc_flow_id_q;
                    core_tx_arg0 <= (32'h1 << `DMA_UFC_RESUME_DDR_LOW);
                    core_tx_arg1 <= resume_free_q;
                    status_valid <= 1'b1;
                    status_ch <= resume_calc_ch_q;
                    status_pause <= 1'b0;
                    status_low <= 1'b1;
                end
                resume_calc_valid_q <= 1'b0;
            end else if (resume_scan_rsp_valid) begin
                resume_scan_wait_q <= 1'b0;
                if (!(ch_reset_fire && (resume_scan_rsp_ch == ch_reset_ch)) &&
                    pause_active[resume_scan_rsp_ch] &&
                    (resume_scan_rsp_used <= effective_low_wm(resume_scan_rsp_low_wm))) begin
                    resume_calc_valid_q <= 1'b1;
                    resume_calc_ch_q <= resume_scan_rsp_ch;
                    resume_calc_flow_id_q <= resume_scan_rsp_flow_id;
                    resume_free_q <= (resume_scan_rsp_size > resume_scan_rsp_used) ?
                                     (resume_scan_rsp_size - resume_scan_rsp_used) : 32'h0;
                end
            end else if (!resume_pipe_busy && !core_tx_valid && !pause_pending_found) begin
                resume_scan_req_valid <= 1'b1;
                resume_scan_req_ch <= resume_scan_ch_q;
                resume_scan_wait_q <= 1'b1;
                resume_scan_ch_q <= (resume_scan_ch_q == `DMA_MAX_CH-1) ?
                                    4'h0 : resume_scan_ch_q + 1'b1;
            end
        end
    end
end

endmodule
