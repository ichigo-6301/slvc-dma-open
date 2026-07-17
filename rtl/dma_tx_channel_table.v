`timescale 1ns/1ps
`include "dma_defs.vh"

// TX channel 的 AXI-Lite 配置和运行时状态表。软件配置 source/base/length，
// TX engine 读取已锁存的 channel context；完成、错误和 frame counter 通过 event
// 写回，从而把 CSR 写路径与发送数据路径分开。
module dma_tx_channel_table #(
    parameter integer CH_W = 4
)(
    input                    clk,
    input                    rstn,
    input                    global_soft_reset,
    input                    csr_wr_valid,
    output                   csr_wr_ready,
    input      [CH_W-1:0]    csr_wr_ch,
    input      [5:0]         csr_wr_off,
    input      [31:0]        csr_wdata,
    input      [3:0]         csr_wstrb,
    output     [1:0]         csr_bresp,
    output reg               csr_wr_rsp_valid,
    output reg [1:0]         csr_wr_rsp_kind,
    output reg [7:0]         csr_wr_rsp_code,
    output reg               csr_global_err,
    output reg               csr_policy_irq,
    input                    csr_rd_valid,
    output                   csr_rd_ready,
    input      [CH_W-1:0]    csr_rd_ch,
    input      [5:0]         csr_rd_off,
    output reg               csr_rvalid,
    output reg [31:0]        csr_rdata,
    output reg [1:0]         csr_rresp,
    input                    tx_event_valid,
    input      [CH_W-1:0]    tx_event_ch,
    input      [7:0]         tx_event_status_code,
    input                    tx_event_inc_frame,
    input                    tx_event_inc_err,
    input                    tx_event_clear_start,
    input                    tx_event_clear_stop,
    input      [`DMA_MAX_CH-1:0] tx_ch_busy_flat,
    input      [`DMA_MAX_CH-1:0] tx_desc_enable_flat,
    output reg               irq_tx_completion,
    output reg               irq_axi_error,
    output     [`DMA_MAX_CH*32-1:0] tx_ctrl_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_cfg_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_base_l_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_base_h_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_len_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_status_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_user_flat
);

// CSR 请求和硬件事件分别进入表内状态机，避免同一周期软件写与完成事件互相覆盖。
localparam HAS_PER_CH_COUNTERS = (`DMA_ENABLE_PER_CH_COUNTERS != 0);
localparam HAS_USER_REGS = (`DMA_ENABLE_USER_REGS != 0);
localparam HAS_COUNTER_EVENT_LANES = (`DMA_ENABLE_TX_COUNTER_EVENT_LANES != 0);
localparam CSR_WR_RSP_NONE    = 2'd0;
localparam CSR_WR_RSP_PROTECT = 2'd1;

localparam [5:0] TX_CTRL_OFF      = `DMA_CH_CTRL;
localparam [5:0] TX_CFG_OFF       = `DMA_CH_CFG;
localparam [5:0] TX_BASE_L_OFF    = `DMA_CH_BASE_L;
localparam [5:0] TX_BASE_H_OFF    = `DMA_CH_BASE_H;
localparam [5:0] TX_LEN_OFF       = `DMA_TX_CH_LEN;
localparam [5:0] TX_STATUS_OFF    = `DMA_CH_STATUS;
localparam [5:0] TX_FRAME_CNT_OFF = `DMA_CH_FRAME_CNT;
localparam [5:0] TX_ERR_CNT_OFF   = `DMA_CH_ERR_CNT;
localparam [5:0] TX_USER_OFF      = `DMA_CH_USER;

reg [31:0] tx_ctrl      [0:`DMA_MAX_CH-1];
reg [31:0] tx_cfg       [0:`DMA_MAX_CH-1];
reg [31:0] tx_base_l    [0:`DMA_MAX_CH-1];
reg [31:0] tx_base_h    [0:`DMA_MAX_CH-1];
reg [31:0] tx_len       [0:`DMA_MAX_CH-1];
reg [31:0] tx_status    [0:`DMA_MAX_CH-1];
reg [31:0] tx_frame_cnt [0:`DMA_MAX_CH-1];
reg [31:0] tx_err_cnt   [0:`DMA_MAX_CH-1];
reg [31:0] tx_user      [0:`DMA_MAX_CH-1];
reg [31:0] tx_status_read_mirror [0:`DMA_MAX_CH-1];
reg [`DMA_MAX_CH-1:0] tx_ch_busy_q;
reg        tx_counter_evt_valid_q;
reg [CH_W-1:0] tx_counter_evt_ch_q;
reg        tx_counter_evt_inc_frame_q;
reg        tx_counter_evt_inc_err_q;
reg        tx_counter_csr_err_valid_q;
reg [CH_W-1:0] tx_counter_csr_err_ch_q;
reg        tx_counter_csr_err_set;
reg [CH_W-1:0] tx_counter_csr_err_set_ch;
(* keep = "true" *) reg [`DMA_MAX_CH-1:0] tx_counter_soft_reset_q;

integer i;
integer mirror_i;
integer cnt_i;
genvar gi;

assign csr_wr_ready = 1'b1;
assign csr_rd_ready = 1'b1;
assign csr_bresp = 2'b00;

generate
    for (gi = 0; gi < `DMA_MAX_CH; gi = gi + 1) begin : g_flatten
        assign tx_ctrl_flat[gi*32 +: 32] = tx_ctrl[gi];
        assign tx_cfg_flat[gi*32 +: 32] = tx_cfg[gi];
        assign tx_base_l_flat[gi*32 +: 32] = tx_base_l[gi];
        assign tx_base_h_flat[gi*32 +: 32] = tx_base_h[gi];
        assign tx_len_flat[gi*32 +: 32] = tx_len[gi];
        assign tx_status_flat[gi*32 +: 32] = tx_status[gi];
        assign tx_user_flat[gi*32 +: 32] = HAS_USER_REGS ? tx_user[gi] : 32'h0;
    end
endgenerate

function [31:0] maybe_counter_data;
    input [31:0] data;
    begin
        maybe_counter_data = HAS_PER_CH_COUNTERS ? data : 32'h0;
    end
endfunction

function [31:0] maybe_user_data;
    input [31:0] data;
    begin
        maybe_user_data = HAS_USER_REGS ? data : 32'h0;
    end
endfunction

function [31:0] read_tx_reg;
    input [CH_W-1:0] ch;
    input [5:0]      off;
    begin
        read_tx_reg = 32'h0;
        case (off)
        TX_CTRL_OFF:      read_tx_reg = tx_ctrl[ch];
        TX_CFG_OFF:       read_tx_reg = tx_cfg[ch];
        TX_BASE_L_OFF:    read_tx_reg = tx_base_l[ch];
        TX_BASE_H_OFF:    read_tx_reg = tx_base_h[ch];
        TX_LEN_OFF:       read_tx_reg = tx_len[ch];
        TX_STATUS_OFF:    read_tx_reg = tx_status_read_mirror[ch];
        TX_FRAME_CNT_OFF: read_tx_reg = maybe_counter_data(tx_frame_cnt[ch]);
        TX_ERR_CNT_OFF:   read_tx_reg = maybe_counter_data(tx_err_cnt[ch]);
        TX_USER_OFF:      read_tx_reg = maybe_user_data(tx_user[ch]);
        default:          read_tx_reg = 32'h0;
        endcase
    end
endfunction

task reset_all_channels;
    integer ch;
    begin
        for (ch = 0; ch < `DMA_MAX_CH; ch = ch + 1) begin
            tx_ctrl[ch] = 32'h0;
            tx_cfg[ch] = 32'h0;
            tx_base_l[ch] = 32'h0;
            tx_base_h[ch] = 32'h0;
            tx_len[ch] = 32'h0;
            tx_status[ch] = 32'h1;
            tx_frame_cnt[ch] = 32'h0;
            tx_err_cnt[ch] = 32'h0;
            tx_user[ch] = 32'h0;
            tx_status_read_mirror[ch] = 32'h1;
        end
    end
endtask

task soft_reset_all_channel_state;
    integer ch;
    begin
        for (ch = 0; ch < `DMA_MAX_CH; ch = ch + 1) begin
            tx_ctrl[ch] = 32'h0;
            tx_cfg[ch] = 32'h0;
            tx_base_l[ch] = 32'h0;
            tx_base_h[ch] = 32'h0;
            tx_len[ch] = 32'h0;
            tx_status[ch] = 32'h1;
            tx_user[ch] = 32'h0;
            tx_status_read_mirror[ch] = 32'h1;
        end
    end
endtask

task set_tx_status_code;
    input [CH_W-1:0] ch;
    input [7:0]      code;
    begin
        tx_status[ch][`DMA_TX_STATUS_IDLE] = !tx_ch_busy_q[ch];
        tx_status[ch][`DMA_TX_STATUS_BUSY] = tx_ch_busy_q[ch];
        tx_status[ch][`DMA_TX_STATUS_ENABLED] = tx_ctrl[ch][`DMA_TX_CTRL_ENABLE];
        tx_status[ch][23:16] = code;
        if (code == `DMA_ST_TX_DONE)
            tx_status[ch][`DMA_TX_STATUS_DONE] = 1'b1;
        if (code == `DMA_ST_AXI_READ_ERR)
            tx_status[ch][`DMA_TX_STATUS_READ_ERR] = 1'b1;
        if (code == `DMA_ST_TX_UNDERFLOW)
            tx_status[ch][`DMA_TX_STATUS_UNDERFLOW] = 1'b1;
        if (code == `DMA_ST_TX_STOPPED)
            tx_status[ch][`DMA_TX_STATUS_ABORTED] = 1'b1;
        if (code == `DMA_ST_TX_CQ_BLOCKED || code == `DMA_ST_CQ_FULL)
            tx_status[ch][`DMA_TX_STATUS_CQ_BLOCKED] = 1'b1;
        tx_status[ch][31:24] = {4'h0, ch};
    end
endtask

task post_tx_protect_error;
    input [CH_W-1:0] ch;
    input [7:0]      code;
    begin
        set_tx_status_code(ch, code);
        if (HAS_PER_CH_COUNTERS && HAS_COUNTER_EVENT_LANES) begin
            tx_counter_csr_err_set = 1'b1;
            tx_counter_csr_err_set_ch = ch;
        end else if (HAS_PER_CH_COUNTERS) begin
            tx_err_cnt[ch] = tx_err_cnt[ch] + 1'b1;
        end
        csr_wr_rsp_kind = CSR_WR_RSP_PROTECT;
        csr_wr_rsp_code = code;
        csr_global_err = 1'b1;
        csr_policy_irq = 1'b1;
    end
endtask

task execute_write;
    input [CH_W-1:0] ch;
    input [5:0]      off;
    input [31:0]     data;
    begin
        case (off)
        TX_CTRL_OFF: begin
            if (data[`DMA_TX_CTRL_CLR_STAT])
                tx_status[ch] = 32'h1;
            if (tx_ctrl[ch][`DMA_TX_CTRL_ENABLE] || tx_ch_busy_q[ch]) begin
                tx_ctrl[ch][`DMA_TX_CTRL_CPL_EN] = data[`DMA_TX_CTRL_CPL_EN];
                tx_ctrl[ch][`DMA_TX_CTRL_IRQ_EN] = data[`DMA_TX_CTRL_IRQ_EN];
                if (data[`DMA_TX_CTRL_START] && tx_ctrl[ch][`DMA_TX_CTRL_ENABLE] && !tx_ch_busy_q[ch]) begin
                    if (tx_desc_enable_flat[ch])
                        post_tx_protect_error(ch, `DMA_ST_UNSUPPORTED_FEATURE);
                    else
                        tx_ctrl[ch][`DMA_TX_CTRL_START] = 1'b1;
                end
                if (data[`DMA_TX_CTRL_STOP])
                    tx_ctrl[ch][`DMA_TX_CTRL_STOP] = 1'b1;
            end else begin
                tx_ctrl[ch] = data & ((32'h1 << `DMA_TX_CTRL_ENABLE) |
                                      (32'h1 << `DMA_TX_CTRL_CPL_EN) |
                                      (32'h1 << `DMA_TX_CTRL_IRQ_EN));
                if (data[`DMA_TX_CTRL_START] && data[`DMA_TX_CTRL_ENABLE]) begin
                    if (tx_desc_enable_flat[ch])
                        post_tx_protect_error(ch, `DMA_ST_UNSUPPORTED_FEATURE);
                    else
                        tx_ctrl[ch][`DMA_TX_CTRL_START] = 1'b1;
                end
            end
            tx_status[ch][`DMA_TX_STATUS_ENABLED] = tx_ctrl[ch][`DMA_TX_CTRL_ENABLE];
        end
        TX_CFG_OFF:    if (!tx_ctrl[ch][`DMA_TX_CTRL_ENABLE] && !tx_ch_busy_q[ch]) tx_cfg[ch] = data; else post_tx_protect_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        TX_BASE_L_OFF: if (!tx_ctrl[ch][`DMA_TX_CTRL_ENABLE] && !tx_ch_busy_q[ch]) tx_base_l[ch] = data; else post_tx_protect_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        TX_BASE_H_OFF: if (!tx_ctrl[ch][`DMA_TX_CTRL_ENABLE] && !tx_ch_busy_q[ch]) tx_base_h[ch] = data; else post_tx_protect_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        TX_LEN_OFF:    if (!tx_ctrl[ch][`DMA_TX_CTRL_ENABLE] && !tx_ch_busy_q[ch]) tx_len[ch] = data; else post_tx_protect_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        TX_USER_OFF: begin
            if (HAS_USER_REGS) begin
                if (!tx_ctrl[ch][`DMA_TX_CTRL_ENABLE] && !tx_ch_busy_q[ch])
                    tx_user[ch] = data;
                else
                    post_tx_protect_error(ch, `DMA_ST_CFG_PROTECT_ERR);
            end
        end
        TX_STATUS_OFF,
        TX_FRAME_CNT_OFF,
        TX_ERR_CNT_OFF: begin
        end
        default: post_tx_protect_error(ch, `DMA_ST_ILLEGAL_REG_WRITE);
        endcase
    end
endtask

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        csr_rvalid <= 1'b0;
        csr_rdata <= 32'h0;
        csr_rresp <= 2'b00;
    end else if (global_soft_reset) begin
        csr_rvalid <= 1'b0;
        csr_rdata <= 32'h0;
        csr_rresp <= 2'b00;
    end else begin
        csr_rvalid <= csr_rd_valid;
        if (csr_rd_valid)
            csr_rdata <= read_tx_reg(csr_rd_ch, csr_rd_off);
        csr_rresp <= 2'b00;
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tx_ch_busy_q <= {`DMA_MAX_CH{1'b0}};
        csr_wr_rsp_valid <= 1'b0;
        csr_wr_rsp_kind = CSR_WR_RSP_NONE;
        csr_wr_rsp_code = 8'h0;
        csr_global_err = 1'b0;
        csr_policy_irq = 1'b0;
        irq_tx_completion <= 1'b0;
        irq_axi_error <= 1'b0;
        tx_counter_evt_valid_q <= 1'b0;
        tx_counter_evt_ch_q <= {CH_W{1'b0}};
        tx_counter_evt_inc_frame_q <= 1'b0;
        tx_counter_evt_inc_err_q <= 1'b0;
        tx_counter_csr_err_valid_q <= 1'b0;
        tx_counter_csr_err_ch_q <= {CH_W{1'b0}};
        tx_counter_csr_err_set = 1'b0;
        tx_counter_csr_err_set_ch = {CH_W{1'b0}};
        tx_counter_soft_reset_q <= {`DMA_MAX_CH{1'b0}};
        reset_all_channels();
    end else begin
        tx_counter_soft_reset_q <= {`DMA_MAX_CH{global_soft_reset}};
        tx_ch_busy_q <= tx_ch_busy_flat;
        csr_wr_rsp_valid <= 1'b0;
        csr_wr_rsp_kind = CSR_WR_RSP_NONE;
        csr_wr_rsp_code = 8'h0;
        csr_global_err = 1'b0;
        csr_policy_irq = 1'b0;
        irq_tx_completion <= 1'b0;
        irq_axi_error <= 1'b0;
        tx_counter_csr_err_set = 1'b0;
        tx_counter_csr_err_set_ch = {CH_W{1'b0}};

        if (global_soft_reset) begin
            tx_counter_evt_valid_q <= 1'b0;
            tx_counter_evt_ch_q <= {CH_W{1'b0}};
            tx_counter_evt_inc_frame_q <= 1'b0;
            tx_counter_evt_inc_err_q <= 1'b0;
            tx_counter_csr_err_valid_q <= 1'b0;
            tx_counter_csr_err_ch_q <= {CH_W{1'b0}};
            soft_reset_all_channel_state();
        end else begin
            if (HAS_PER_CH_COUNTERS) begin
                for (cnt_i = 0; cnt_i < `DMA_MAX_CH; cnt_i = cnt_i + 1) begin
                    if (tx_counter_soft_reset_q[cnt_i]) begin
                        tx_frame_cnt[cnt_i] = 32'h0;
                        tx_err_cnt[cnt_i] = 32'h0;
                    end else if (HAS_COUNTER_EVENT_LANES) begin
                        if (tx_counter_evt_valid_q &&
                            (tx_counter_evt_ch_q == cnt_i[CH_W-1:0]) &&
                            tx_counter_evt_inc_frame_q)
                            tx_frame_cnt[cnt_i] = tx_frame_cnt[cnt_i] + 1'b1;
                        case ({
                            tx_counter_evt_valid_q &&
                            (tx_counter_evt_ch_q == cnt_i[CH_W-1:0]) &&
                            tx_counter_evt_inc_err_q,
                            tx_counter_csr_err_valid_q &&
                            (tx_counter_csr_err_ch_q == cnt_i[CH_W-1:0])
                        })
                        2'b11: tx_err_cnt[cnt_i] = tx_err_cnt[cnt_i] + 32'd2;
                        2'b10,
                        2'b01: tx_err_cnt[cnt_i] = tx_err_cnt[cnt_i] + 1'b1;
                        default: ;
                        endcase
                    end
                end
            end

            for (mirror_i = 0; mirror_i < `DMA_MAX_CH; mirror_i = mirror_i + 1) begin
                tx_status_read_mirror[mirror_i] = tx_status[mirror_i];
                tx_status_read_mirror[mirror_i][`DMA_TX_STATUS_IDLE] = !tx_ch_busy_q[mirror_i];
                tx_status_read_mirror[mirror_i][`DMA_TX_STATUS_BUSY] = tx_ch_busy_q[mirror_i];
                tx_status_read_mirror[mirror_i][`DMA_TX_STATUS_ENABLED] = tx_ctrl[mirror_i][`DMA_TX_CTRL_ENABLE];
            end

            if (csr_wr_valid) begin
                csr_wr_rsp_valid <= 1'b1;
                execute_write(csr_wr_ch, csr_wr_off, csr_wdata);
            end

            if (tx_event_valid) begin
                set_tx_status_code(tx_event_ch, tx_event_status_code);
                if (HAS_PER_CH_COUNTERS && !HAS_COUNTER_EVENT_LANES && tx_event_inc_frame)
                    tx_frame_cnt[tx_event_ch] = tx_frame_cnt[tx_event_ch] + 1'b1;
                if (HAS_PER_CH_COUNTERS && !HAS_COUNTER_EVENT_LANES && tx_event_inc_err)
                    tx_err_cnt[tx_event_ch] = tx_err_cnt[tx_event_ch] + 1'b1;
                if (tx_event_clear_start)
                    tx_ctrl[tx_event_ch][`DMA_TX_CTRL_START] = 1'b0;
                if (tx_event_clear_stop)
                    tx_ctrl[tx_event_ch][`DMA_TX_CTRL_STOP] = 1'b0;
                tx_status[tx_event_ch][`DMA_TX_STATUS_BUSY] = tx_ch_busy_q[tx_event_ch];
                tx_status[tx_event_ch][`DMA_TX_STATUS_IDLE] = !tx_ch_busy_q[tx_event_ch];
                tx_status[tx_event_ch][`DMA_TX_STATUS_ENABLED] = tx_ctrl[tx_event_ch][`DMA_TX_CTRL_ENABLE];
                if (tx_ctrl[tx_event_ch][`DMA_TX_CTRL_IRQ_EN])
                    irq_tx_completion <= 1'b1;
                if (tx_event_status_code == `DMA_ST_AXI_READ_ERR)
                    irq_axi_error <= 1'b1;
            end

            if (HAS_COUNTER_EVENT_LANES) begin
                tx_counter_evt_valid_q <= HAS_PER_CH_COUNTERS &&
                                          tx_event_valid &&
                                          (tx_event_inc_frame || tx_event_inc_err);
                tx_counter_evt_ch_q <= tx_event_ch;
                tx_counter_evt_inc_frame_q <= tx_event_inc_frame;
                tx_counter_evt_inc_err_q <= tx_event_inc_err;
                tx_counter_csr_err_valid_q <= HAS_PER_CH_COUNTERS && tx_counter_csr_err_set;
                tx_counter_csr_err_ch_q <= tx_counter_csr_err_set_ch;
            end else begin
                tx_counter_evt_valid_q <= 1'b0;
                tx_counter_evt_ch_q <= {CH_W{1'b0}};
                tx_counter_evt_inc_frame_q <= 1'b0;
                tx_counter_evt_inc_err_q <= 1'b0;
                tx_counter_csr_err_valid_q <= 1'b0;
                tx_counter_csr_err_ch_q <= {CH_W{1'b0}};
            end
        end
    end
end

endmodule
