`timescale 1ns/1ps
`include "dma_defs.vh"

module dma_rx_channel_table #(
    parameter integer CH_W = 4
) (
    input                    clk,
    input                    rstn,
    input                    global_soft_reset,
    input      [`DMA_MAX_CH-1:0] rx_ch_busy_flat,

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
    output reg               ch_reset_pulse,
    output reg [CH_W-1:0]    ch_reset_ch,
    input                    resume_scan_req_valid,
    input      [CH_W-1:0]    resume_scan_req_ch,
    output reg               resume_scan_rsp_valid,
    output reg [CH_W-1:0]    resume_scan_rsp_ch,
    output reg [31:0]        resume_scan_rsp_used,
    output reg [31:0]        resume_scan_rsp_low_wm,
    output reg [31:0]        resume_scan_rsp_size,
    output reg [15:0]        resume_scan_rsp_flow_id,
    output                   consumer_release_valid,
    input                    consumer_release_ready,
    output     [CH_W-1:0]    consumer_release_ch,
    output     [31:0]        consumer_release_delta,
    output     [31:0]        consumer_release_ptr,

    input                    csr_rd_valid,
    output                   csr_rd_ready,
    input      [CH_W-1:0]    csr_rd_ch,
    input      [5:0]         csr_rd_off,
    output reg               csr_rvalid,
    output reg [31:0]        csr_rdata,
    output reg [1:0]         csr_rresp,

    input                    event_valid,
    input                    event_ch_valid,
    input      [CH_W-1:0]    event_ch,
    input      [7:0]         event_status_code,
    input      [31:0]        event_aligned_len,
    input      [31:0]        event_next_wr_ptr,
    input                    event_inc_frame,
    input                    event_inc_drop,
    input                    event_inc_err,
    input                    event_update_wr_ptr,

    input                    fc_status_valid,
    input      [CH_W-1:0]    fc_status_ch,
    input                    fc_status_pause,
    input                    fc_status_low,
    input                    fc_status_full,
    input                    fc_status_afull,
    input                    fc_status_ovf,

    output     [`DMA_MAX_CH*32-1:0] rx_ctrl_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_cfg_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_base_l_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_base_h_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_size_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_max_len_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_wr_ptr_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_rd_ptr_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_used_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_high_wm_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_low_wm_flat,
    output     [`DMA_MAX_CH*32-1:0] rx_user_flat
);

localparam HAS_PER_CH_COUNTERS = (`DMA_ENABLE_PER_CH_COUNTERS != 0);
localparam HAS_USER_REGS = (`DMA_ENABLE_USER_REGS != 0);
localparam HAS_COUNTER_EVENT_LANES = (`DMA_ENABLE_RX_COUNTER_EVENT_LANES != 0);
localparam CSR_WR_RSP_NONE    = 2'd0;
localparam CSR_WR_RSP_PROTECT = 2'd1;
localparam [1:0] RDPTR_IDLE   = 2'd0;
localparam [1:0] RDPTR_CALC   = 2'd1;
localparam [1:0] RDPTR_COMMIT = 2'd2;
localparam [1:0] RDPTR_RESP   = 2'd3;

localparam [5:0] RX_CTRL_OFF      = `DMA_CH_CTRL;
localparam [5:0] RX_CFG_OFF       = `DMA_CH_CFG;
localparam [5:0] RX_BASE_L_OFF    = `DMA_CH_BASE_L;
localparam [5:0] RX_BASE_H_OFF    = `DMA_CH_BASE_H;
localparam [5:0] RX_SIZE_OFF      = `DMA_CH_SIZE;
localparam [5:0] RX_MAX_LEN_OFF   = `DMA_CH_MAX_LEN;
localparam [5:0] RX_WR_PTR_OFF    = `DMA_RX_CH_WR_PTR;
localparam [5:0] RX_RD_PTR_OFF    = `DMA_RX_CH_RD_PTR;
localparam [5:0] RX_USED_OFF      = `DMA_CH_USED;
localparam [5:0] RX_HIGH_WM_OFF   = `DMA_RX_CH_HIGH_WM;
localparam [5:0] RX_LOW_WM_OFF    = `DMA_RX_CH_LOW_WM;
localparam [5:0] RX_STATUS_OFF    = `DMA_CH_STATUS;
localparam [5:0] RX_FRAME_CNT_OFF = `DMA_CH_FRAME_CNT;
localparam [5:0] RX_DROP_CNT_OFF  = `DMA_CH_DROP_CNT;
localparam [5:0] RX_ERR_CNT_OFF   = `DMA_CH_ERR_CNT;
localparam [5:0] RX_USER_OFF      = `DMA_CH_USER;

reg [31:0] rx_ctrl      [0:`DMA_MAX_CH-1];
reg [31:0] rx_cfg       [0:`DMA_MAX_CH-1];
reg [31:0] rx_base_l    [0:`DMA_MAX_CH-1];
reg [31:0] rx_base_h    [0:`DMA_MAX_CH-1];
reg [31:0] rx_size      [0:`DMA_MAX_CH-1];
reg [31:0] rx_max_len   [0:`DMA_MAX_CH-1];
reg [31:0] rx_wr_ptr    [0:`DMA_MAX_CH-1];
reg [31:0] rx_rd_ptr    [0:`DMA_MAX_CH-1];
reg [31:0] rx_used      [0:`DMA_MAX_CH-1];
reg [31:0] rx_high_wm   [0:`DMA_MAX_CH-1];
reg [31:0] rx_low_wm    [0:`DMA_MAX_CH-1];
reg [31:0] rx_status    [0:`DMA_MAX_CH-1];
reg [31:0] rx_frame_cnt [0:`DMA_MAX_CH-1];
reg [31:0] rx_drop_cnt  [0:`DMA_MAX_CH-1];
reg [31:0] rx_err_cnt   [0:`DMA_MAX_CH-1];
reg [31:0] rx_user      [0:`DMA_MAX_CH-1];
reg [31:0] rx_status_read_mirror [0:`DMA_MAX_CH-1];

reg [`DMA_MAX_CH-1:0] rx_ch_busy_q;

reg                  event_pipe_valid;
reg                  event_pipe_ch_valid;
reg [CH_W-1:0]       event_pipe_ch;
reg [7:0]            event_pipe_status_code;
reg [31:0]           event_pipe_aligned_len;
reg [31:0]           event_pipe_next_wr_ptr;
reg                  event_pipe_inc_frame;
reg                  event_pipe_inc_drop;
reg                  event_pipe_inc_err;
reg                  event_pipe_update_wr_ptr;
reg                  rx_cnt_evt_valid_q;
reg [CH_W-1:0]       rx_cnt_evt_ch_q;
reg                  rx_cnt_evt_inc_frame_q;
reg                  rx_cnt_evt_inc_drop_q;
reg                  rx_cnt_evt_inc_err_q;

reg                  csr_err_cnt_evt_valid_q;
reg [CH_W-1:0]       csr_err_cnt_evt_ch_q;
reg                  csr_err_cnt_commit_valid_q;
reg [CH_W-1:0]       csr_err_cnt_commit_ch_q;
reg                  csr_err_cnt_evt_set;
reg [CH_W-1:0]       csr_err_cnt_evt_set_ch;
reg                  used_evt_valid_q;
reg [CH_W-1:0]       used_evt_ch_q;
reg [31:0]           used_evt_delta_q;
reg                  used_rdptr_valid_q;
reg                  consumer_release_valid_q;
reg [CH_W-1:0]       used_rdptr_ch_q;
reg [31:0]           used_rdptr_delta_q;
reg [31:0]           used_rdptr_ptr_q;
reg                  used_clear_valid_q;
reg [CH_W-1:0]       used_clear_ch_q;
reg                  used_commit_rsp_valid_q;
reg                  used_commit_rsp_is_rdptr_q;
reg                  used_commit_rsp_is_ch_reset_q;
reg [CH_W-1:0]       used_commit_rsp_ch_q;
reg [1:0]            used_commit_rsp_kind_q;
reg [7:0]            used_commit_rsp_code_q;
reg [1:0]            rdptr_state_q;
reg [CH_W-1:0]       rdptr_ch_q;
reg [31:0]           rdptr_new_ptr_q;
reg [31:0]           rdptr_old_ptr_q;
reg [31:0]           rdptr_size_q;
reg [31:0]           rdptr_used_q;
reg [CH_W-1:0]       rdptr_calc_ch_q;
reg [31:0]           rdptr_calc_new_ptr_q;
reg [31:0]           rdptr_release_delta_q;
reg [31:0]           rdptr_used_snapshot_q;
reg                  rdptr_error_q;
reg [7:0]            rdptr_error_code_q;
wire csr_ch_reset_accept = (rdptr_state_q == RDPTR_IDLE) &&
                           csr_wr_valid && csr_wr_ready &&
                           (csr_wr_off == RX_CTRL_OFF) &&
                           csr_wdata[`DMA_RX_CTRL_CH_RESET] &&
                           !rx_ch_busy_q[csr_wr_ch];

integer i;
integer mirror_i;
integer used_i;
integer cnt_i;
reg [31:0] used_next;
reg        used_commit_hit;
reg        used_clear_hit;
genvar gi;

assign csr_wr_ready = (rdptr_state_q == RDPTR_IDLE) &&
                      !used_commit_rsp_valid_q && !consumer_release_valid_q;
assign csr_rd_ready = 1'b1;
assign csr_bresp = 2'b00;
assign consumer_release_valid = consumer_release_valid_q;
assign consumer_release_ch = used_rdptr_ch_q;
assign consumer_release_delta = used_rdptr_delta_q;
assign consumer_release_ptr = used_rdptr_ptr_q;

generate
    for (gi = 0; gi < `DMA_MAX_CH; gi = gi + 1) begin : g_flatten
        assign rx_ctrl_flat[gi*32 +: 32] = rx_ctrl[gi];
        assign rx_cfg_flat[gi*32 +: 32] = rx_cfg[gi];
        assign rx_base_l_flat[gi*32 +: 32] = rx_base_l[gi];
        assign rx_base_h_flat[gi*32 +: 32] = rx_base_h[gi];
        assign rx_size_flat[gi*32 +: 32] = rx_size[gi];
        assign rx_max_len_flat[gi*32 +: 32] = rx_max_len[gi];
        assign rx_wr_ptr_flat[gi*32 +: 32] = rx_wr_ptr[gi];
        assign rx_rd_ptr_flat[gi*32 +: 32] = rx_rd_ptr[gi];
        assign rx_used_flat[gi*32 +: 32] = rx_used[gi];
        assign rx_high_wm_flat[gi*32 +: 32] = rx_high_wm[gi];
        assign rx_low_wm_flat[gi*32 +: 32] = rx_low_wm[gi];
        assign rx_user_flat[gi*32 +: 32] = HAS_USER_REGS ? rx_user[gi] : 32'h0;
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

function [31:0] read_rx_reg;
    input [CH_W-1:0] ch;
    input [5:0]      off;
    begin
        read_rx_reg = 32'h0;
        case (off)
        RX_CTRL_OFF:      read_rx_reg = rx_ctrl[ch];
        RX_CFG_OFF:       read_rx_reg = rx_cfg[ch];
        RX_BASE_L_OFF:    read_rx_reg = rx_base_l[ch];
        RX_BASE_H_OFF:    read_rx_reg = rx_base_h[ch];
        RX_SIZE_OFF:      read_rx_reg = rx_size[ch];
        RX_MAX_LEN_OFF:   read_rx_reg = rx_max_len[ch];
        RX_WR_PTR_OFF:    read_rx_reg = rx_wr_ptr[ch];
        RX_RD_PTR_OFF:    read_rx_reg = rx_rd_ptr[ch];
        RX_USED_OFF:      read_rx_reg = rx_used[ch];
        RX_HIGH_WM_OFF:   read_rx_reg = rx_high_wm[ch];
        RX_LOW_WM_OFF:    read_rx_reg = rx_low_wm[ch];
        RX_STATUS_OFF:    read_rx_reg = rx_status_read_mirror[ch];
        RX_FRAME_CNT_OFF: read_rx_reg = maybe_counter_data(rx_frame_cnt[ch]);
        RX_DROP_CNT_OFF:  read_rx_reg = maybe_counter_data(rx_drop_cnt[ch]);
        RX_ERR_CNT_OFF:   read_rx_reg = maybe_counter_data(rx_err_cnt[ch]);
        RX_USER_OFF:      read_rx_reg = maybe_user_data(rx_user[ch]);
        default:          read_rx_reg = 32'h0;
        endcase
    end
endfunction

task reset_all_channels;
    integer ch;
    begin
        for (ch = 0; ch < `DMA_MAX_CH; ch = ch + 1) begin
            rx_ctrl[ch] = 32'h0;
            rx_cfg[ch] = 32'h0;
            rx_base_l[ch] = 32'h0;
            rx_base_h[ch] = 32'h0;
            rx_size[ch] = 32'h0;
            rx_max_len[ch] = 32'h0;
            rx_wr_ptr[ch] = 32'h0;
            rx_rd_ptr[ch] = 32'h0;
            rx_used[ch] = 32'h0;
            rx_high_wm[ch] = 32'h0;
            rx_low_wm[ch] = 32'h0;
            rx_status[ch] = 32'h1;
            rx_frame_cnt[ch] = 32'h0;
            rx_drop_cnt[ch] = 32'h0;
            rx_err_cnt[ch] = 32'h0;
            rx_user[ch] = 32'h0;
            rx_status_read_mirror[ch] = 32'h1;
        end
    end
endtask

task reset_one_channel_no_used;
    input integer ch;
    begin
        rx_ctrl[ch] = 32'h0;
        rx_status[ch] = 32'h1;
        rx_frame_cnt[ch] = 32'h0;
        rx_drop_cnt[ch] = 32'h0;
        rx_err_cnt[ch] = 32'h0;
        rx_wr_ptr[ch] = 32'h0;
        rx_rd_ptr[ch] = 32'h0;
    end
endtask

task set_rx_status_code;
    input [CH_W-1:0] ch;
    input [7:0]      code;
    begin
        rx_status[ch][`DMA_RX_STATUS_IDLE] = 1'b1;
        rx_status[ch][`DMA_RX_STATUS_BUSY] = 1'b0;
        rx_status[ch][`DMA_RX_STATUS_ENABLED] = rx_ctrl[ch][`DMA_RX_CTRL_ENABLE];
        rx_status[ch][23:16] = code;
        if (code == `DMA_ST_POLICY_REJECT)
            rx_status[ch][`DMA_RX_STATUS_POLICY] = 1'b1;
        if (code == `DMA_ST_CFG_PROTECT_ERR ||
            code == `DMA_ST_ILLEGAL_REG_WRITE ||
            code == `DMA_ST_UNSUPPORTED_FEATURE ||
            code == `DMA_ST_ILLEGAL_PARAM)
            rx_status[ch][`DMA_RX_STATUS_POLICY] = 1'b1;
        if (code == `DMA_ST_CQ_FULL)
            rx_status[ch][`DMA_RX_STATUS_CQ] = 1'b1;
        if (code == `DMA_ST_BUFFER_FULL || code == `DMA_ST_FRAME_TOO_BIG ||
            code == `DMA_ST_OVERFLOW || code == `DMA_ST_DDR_QUEUE_FULL ||
            code == `DMA_ST_WRAP_NOT_ALLOWED || code == `DMA_ST_LOSSLESS_OVF)
            rx_status[ch][`DMA_RX_STATUS_OVF] = 1'b1;
        if (code == `DMA_ST_DROP || code == `DMA_ST_DROP_NEW ||
            code == `DMA_ST_DROP_CQ_FULL || code == `DMA_ST_BUFFER_FULL)
            rx_status[ch][`DMA_RX_STATUS_DROP] = 1'b1;
        if (code == `DMA_ST_INGRESS_FULL || code == `DMA_ST_INGRESS_META_FULL)
            rx_status[ch][`DMA_RX_STATUS_ING_FULL] = 1'b1;
        if (code == `DMA_ST_PAUSE_VIOL)
            rx_status[ch][`DMA_RX_STATUS_PAUSE_VIOL] = 1'b1;
    end
endtask

task post_write_error;
    input [CH_W-1:0] ch;
    input [7:0]      code;
    begin
        set_rx_status_code(ch, code);
        if (HAS_PER_CH_COUNTERS)
            csr_err_cnt_evt_set = 1'b1;
        csr_err_cnt_evt_set_ch = ch;
        csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
        csr_wr_rsp_code <= code;
    end
endtask

task execute_write;
    input [CH_W-1:0] ch;
    input [5:0]      off;
    input [31:0]     data;
    begin
        case (off)
        RX_CTRL_OFF: begin
            if (data[`DMA_RX_CTRL_CLR_STAT])
                rx_status[ch] = 32'h1;
            if (data[`DMA_RX_CTRL_CH_RESET]) begin
                if (rx_ch_busy_q[ch]) begin
                    post_write_error(ch, `DMA_ST_CFG_PROTECT_ERR);
                end
            end else begin
                if (rx_ctrl[ch][`DMA_RX_CTRL_ENABLE] || rx_ch_busy_q[ch]) begin
                    rx_ctrl[ch][`DMA_RX_CTRL_CPL_EN] = data[`DMA_RX_CTRL_CPL_EN];
                    rx_ctrl[ch][`DMA_RX_CTRL_IRQ_EN] = data[`DMA_RX_CTRL_IRQ_EN];
                end else begin
                    rx_ctrl[ch] = data & 32'h0000_085d;
                end
            end
            rx_status[ch][`DMA_RX_STATUS_ENABLED] = rx_ctrl[ch][`DMA_RX_CTRL_ENABLE];
        end
        RX_CFG_OFF:     if (!rx_ctrl[ch][`DMA_RX_CTRL_ENABLE] && !rx_ch_busy_q[ch]) rx_cfg[ch] = data; else post_write_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        RX_BASE_L_OFF:  if (!rx_ctrl[ch][`DMA_RX_CTRL_ENABLE] && !rx_ch_busy_q[ch]) rx_base_l[ch] = data; else post_write_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        RX_BASE_H_OFF:  if (!rx_ctrl[ch][`DMA_RX_CTRL_ENABLE] && !rx_ch_busy_q[ch]) rx_base_h[ch] = data; else post_write_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        RX_SIZE_OFF:    if (!rx_ctrl[ch][`DMA_RX_CTRL_ENABLE] && !rx_ch_busy_q[ch]) rx_size[ch] = data; else post_write_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        RX_MAX_LEN_OFF: if (!rx_ctrl[ch][`DMA_RX_CTRL_ENABLE] && !rx_ch_busy_q[ch]) rx_max_len[ch] = data; else post_write_error(ch, `DMA_ST_CFG_PROTECT_ERR);
        RX_HIGH_WM_OFF: rx_high_wm[ch] = data;
        RX_LOW_WM_OFF:  rx_low_wm[ch] = data;
        RX_USER_OFF: begin
            if (HAS_USER_REGS) begin
                if (!rx_ctrl[ch][`DMA_RX_CTRL_ENABLE] && !rx_ch_busy_q[ch])
                    rx_user[ch] = data;
                else
                    post_write_error(ch, `DMA_ST_CFG_PROTECT_ERR);
            end
        end
        RX_WR_PTR_OFF,
        RX_RD_PTR_OFF,
        RX_USED_OFF,
        RX_STATUS_OFF,
        RX_FRAME_CNT_OFF,
        RX_DROP_CNT_OFF,
        RX_ERR_CNT_OFF: ;
        default: post_write_error(ch, `DMA_ST_ILLEGAL_REG_WRITE);
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
            csr_rdata <= read_rx_reg(csr_rd_ch, csr_rd_off);
        csr_rresp <= 2'b00;
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        rx_ch_busy_q <= {`DMA_MAX_CH{1'b0}};
        event_pipe_valid <= 1'b0;
        event_pipe_ch_valid <= 1'b0;
        event_pipe_ch <= {CH_W{1'b0}};
        event_pipe_status_code <= 8'h0;
        event_pipe_aligned_len <= 32'h0;
        event_pipe_next_wr_ptr <= 32'h0;
        event_pipe_inc_frame <= 1'b0;
        event_pipe_inc_drop <= 1'b0;
        event_pipe_inc_err <= 1'b0;
        event_pipe_update_wr_ptr <= 1'b0;
        rx_cnt_evt_valid_q <= 1'b0;
        rx_cnt_evt_ch_q <= {CH_W{1'b0}};
        rx_cnt_evt_inc_frame_q <= 1'b0;
        rx_cnt_evt_inc_drop_q <= 1'b0;
        rx_cnt_evt_inc_err_q <= 1'b0;
        csr_wr_rsp_valid <= 1'b0;
        csr_wr_rsp_kind <= CSR_WR_RSP_NONE;
        csr_wr_rsp_code <= 8'h0;
        ch_reset_pulse <= 1'b0;
        ch_reset_ch <= {CH_W{1'b0}};
        resume_scan_rsp_valid <= 1'b0;
        resume_scan_rsp_ch <= {CH_W{1'b0}};
        resume_scan_rsp_used <= 32'h0;
        resume_scan_rsp_low_wm <= 32'h0;
        resume_scan_rsp_size <= 32'h0;
        resume_scan_rsp_flow_id <= 16'h0;
        csr_err_cnt_evt_valid_q <= 1'b0;
        csr_err_cnt_evt_ch_q <= {CH_W{1'b0}};
        csr_err_cnt_commit_valid_q <= 1'b0;
        csr_err_cnt_commit_ch_q <= {CH_W{1'b0}};
        used_evt_valid_q <= 1'b0;
        used_evt_ch_q <= {CH_W{1'b0}};
        used_evt_delta_q <= 32'h0;
        used_rdptr_valid_q <= 1'b0;
        consumer_release_valid_q <= 1'b0;
        used_rdptr_ch_q <= {CH_W{1'b0}};
        used_rdptr_delta_q <= 32'h0;
        used_rdptr_ptr_q <= 32'h0;
        used_clear_valid_q <= 1'b0;
        used_clear_ch_q <= {CH_W{1'b0}};
        used_commit_rsp_valid_q <= 1'b0;
        used_commit_rsp_is_rdptr_q <= 1'b0;
        used_commit_rsp_is_ch_reset_q <= 1'b0;
        used_commit_rsp_ch_q <= {CH_W{1'b0}};
        used_commit_rsp_kind_q <= CSR_WR_RSP_NONE;
        used_commit_rsp_code_q <= 8'h0;
        rdptr_state_q <= RDPTR_IDLE;
        rdptr_ch_q <= {CH_W{1'b0}};
        rdptr_new_ptr_q <= 32'h0;
        rdptr_old_ptr_q <= 32'h0;
        rdptr_size_q <= 32'h0;
        rdptr_used_q <= 32'h0;
        rdptr_calc_ch_q <= {CH_W{1'b0}};
        rdptr_calc_new_ptr_q <= 32'h0;
        rdptr_release_delta_q <= 32'h0;
        rdptr_used_snapshot_q <= 32'h0;
        rdptr_error_q <= 1'b0;
        rdptr_error_code_q <= 8'h0;
        reset_all_channels();
    end else begin
        rx_ch_busy_q <= rx_ch_busy_flat;
        csr_wr_rsp_valid <= 1'b0;
        csr_wr_rsp_kind <= CSR_WR_RSP_NONE;
        csr_wr_rsp_code <= 8'h0;
        ch_reset_pulse <= 1'b0;
        ch_reset_ch <= {CH_W{1'b0}};
        csr_err_cnt_evt_set = 1'b0;
        csr_err_cnt_evt_set_ch = {CH_W{1'b0}};
        used_rdptr_valid_q <= 1'b0;
        if (consumer_release_valid_q && consumer_release_ready)
            consumer_release_valid_q <= 1'b0;
        used_clear_valid_q <= 1'b0;
        used_clear_ch_q <= {CH_W{1'b0}};
        used_commit_rsp_valid_q <= 1'b0;
        used_commit_rsp_is_rdptr_q <= 1'b0;
        used_commit_rsp_is_ch_reset_q <= 1'b0;
        used_commit_rsp_ch_q <= {CH_W{1'b0}};
        used_commit_rsp_kind_q <= CSR_WR_RSP_NONE;
        used_commit_rsp_code_q <= 8'h0;

        if (global_soft_reset) begin
            resume_scan_rsp_valid <= 1'b0;
            resume_scan_rsp_ch <= {CH_W{1'b0}};
            resume_scan_rsp_used <= 32'h0;
            resume_scan_rsp_low_wm <= 32'h0;
            resume_scan_rsp_size <= 32'h0;
            resume_scan_rsp_flow_id <= 16'h0;
            event_pipe_valid <= 1'b0;
            event_pipe_ch_valid <= 1'b0;
            event_pipe_ch <= {CH_W{1'b0}};
            event_pipe_status_code <= 8'h0;
            event_pipe_aligned_len <= 32'h0;
            event_pipe_next_wr_ptr <= 32'h0;
            event_pipe_inc_frame <= 1'b0;
            event_pipe_inc_drop <= 1'b0;
            event_pipe_inc_err <= 1'b0;
            event_pipe_update_wr_ptr <= 1'b0;
            rx_cnt_evt_valid_q <= 1'b0;
            rx_cnt_evt_ch_q <= {CH_W{1'b0}};
            rx_cnt_evt_inc_frame_q <= 1'b0;
            rx_cnt_evt_inc_drop_q <= 1'b0;
            rx_cnt_evt_inc_err_q <= 1'b0;
            csr_err_cnt_evt_valid_q <= 1'b0;
            csr_err_cnt_evt_ch_q <= {CH_W{1'b0}};
            csr_err_cnt_commit_valid_q <= 1'b0;
            csr_err_cnt_commit_ch_q <= {CH_W{1'b0}};
            used_evt_valid_q <= 1'b0;
            used_evt_ch_q <= {CH_W{1'b0}};
            used_evt_delta_q <= 32'h0;
            used_rdptr_valid_q <= 1'b0;
            consumer_release_valid_q <= 1'b0;
            used_rdptr_ch_q <= {CH_W{1'b0}};
            used_rdptr_delta_q <= 32'h0;
            used_rdptr_ptr_q <= 32'h0;
            used_clear_valid_q <= 1'b0;
            used_clear_ch_q <= {CH_W{1'b0}};
            used_commit_rsp_valid_q <= 1'b0;
            used_commit_rsp_is_rdptr_q <= 1'b0;
            used_commit_rsp_is_ch_reset_q <= 1'b0;
            used_commit_rsp_ch_q <= {CH_W{1'b0}};
            used_commit_rsp_kind_q <= CSR_WR_RSP_NONE;
            used_commit_rsp_code_q <= 8'h0;
            rdptr_state_q <= RDPTR_IDLE;
            rdptr_ch_q <= {CH_W{1'b0}};
            rdptr_new_ptr_q <= 32'h0;
            rdptr_old_ptr_q <= 32'h0;
            rdptr_size_q <= 32'h0;
            rdptr_used_q <= 32'h0;
            rdptr_calc_ch_q <= {CH_W{1'b0}};
            rdptr_calc_new_ptr_q <= 32'h0;
            rdptr_release_delta_q <= 32'h0;
            rdptr_used_snapshot_q <= 32'h0;
            rdptr_error_q <= 1'b0;
            rdptr_error_code_q <= 8'h0;
            reset_all_channels();
        end else begin
            resume_scan_rsp_valid <= resume_scan_req_valid;
            if (resume_scan_req_valid) begin
                resume_scan_rsp_ch <= resume_scan_req_ch;
                resume_scan_rsp_used <= rx_used[resume_scan_req_ch];
                resume_scan_rsp_low_wm <= rx_low_wm[resume_scan_req_ch];
                resume_scan_rsp_size <= rx_size[resume_scan_req_ch];
                resume_scan_rsp_flow_id <= rx_cfg[resume_scan_req_ch][31:16];
            end
            for (mirror_i = 0; mirror_i < `DMA_MAX_CH; mirror_i = mirror_i + 1) begin
                rx_status_read_mirror[mirror_i] = rx_status[mirror_i];
                rx_status_read_mirror[mirror_i][`DMA_RX_STATUS_IDLE] = !rx_ch_busy_q[mirror_i];
                rx_status_read_mirror[mirror_i][`DMA_RX_STATUS_BUSY] = rx_ch_busy_q[mirror_i];
                rx_status_read_mirror[mirror_i][`DMA_RX_STATUS_ENABLED] = rx_ctrl[mirror_i][`DMA_RX_CTRL_ENABLE];
            end

            if (used_commit_rsp_valid_q) begin
                csr_wr_rsp_valid <= 1'b1;
                csr_wr_rsp_kind <= used_commit_rsp_kind_q;
                csr_wr_rsp_code <= used_commit_rsp_code_q;
                if (used_commit_rsp_is_ch_reset_q) begin
                    ch_reset_pulse <= 1'b1;
                    ch_reset_ch <= used_commit_rsp_ch_q;
                end
            end

            event_pipe_valid <= event_valid;
            event_pipe_ch_valid <= event_ch_valid;
            event_pipe_ch <= event_ch;
            event_pipe_status_code <= event_status_code;
            event_pipe_aligned_len <= event_aligned_len;
            event_pipe_next_wr_ptr <= event_next_wr_ptr;
            event_pipe_inc_frame <= event_inc_frame;
            event_pipe_inc_drop <= event_inc_drop;
            event_pipe_inc_err <= event_inc_err;
            event_pipe_update_wr_ptr <= event_update_wr_ptr;
            used_evt_valid_q <= event_pipe_valid && event_pipe_ch_valid && event_pipe_update_wr_ptr;
            used_evt_ch_q <= event_pipe_ch;
            used_evt_delta_q <= event_pipe_aligned_len;

            // Centralize all runtime rx_used changes through registered requests.
            for (used_i = 0; used_i < `DMA_MAX_CH; used_i = used_i + 1) begin
                used_next = rx_used[used_i];
                used_commit_hit = 1'b0;
                used_clear_hit = used_clear_valid_q && (used_clear_ch_q == used_i[CH_W-1:0]);
                if (used_clear_hit) begin
                    used_next = 32'h0;
                    used_commit_hit = 1'b1;
                end
                if (used_evt_valid_q && (used_evt_ch_q == used_i[CH_W-1:0])) begin
                    used_next = used_next + used_evt_delta_q;
                    used_commit_hit = 1'b1;
                end
                if (used_rdptr_valid_q && (used_rdptr_ch_q == used_i[CH_W-1:0]) && !used_clear_hit) begin
                    used_next = used_next - used_rdptr_delta_q;
                    used_commit_hit = 1'b1;
                end
                if (used_commit_hit)
                    rx_used[used_i] <= used_next;
            end

            if (HAS_PER_CH_COUNTERS && HAS_COUNTER_EVENT_LANES) begin
                for (cnt_i = 0; cnt_i < `DMA_MAX_CH; cnt_i = cnt_i + 1) begin
                    if (rx_cnt_evt_valid_q &&
                        (rx_cnt_evt_ch_q == cnt_i[CH_W-1:0]) &&
                        !(used_clear_valid_q && (used_clear_ch_q == cnt_i[CH_W-1:0])) &&
                        !(csr_ch_reset_accept && (csr_wr_ch == cnt_i[CH_W-1:0]))) begin
                        if (rx_cnt_evt_inc_frame_q)
                            rx_frame_cnt[cnt_i] = rx_frame_cnt[cnt_i] + 1'b1;
                        if (rx_cnt_evt_inc_drop_q)
                            rx_drop_cnt[cnt_i] = rx_drop_cnt[cnt_i] + 1'b1;
                    end
                    case ({
                        rx_cnt_evt_valid_q && rx_cnt_evt_inc_err_q &&
                        (rx_cnt_evt_ch_q == cnt_i[CH_W-1:0]) &&
                        !(used_clear_valid_q && (used_clear_ch_q == cnt_i[CH_W-1:0])) &&
                        !(csr_ch_reset_accept && (csr_wr_ch == cnt_i[CH_W-1:0])),
                        csr_err_cnt_commit_valid_q &&
                        (csr_err_cnt_commit_ch_q == cnt_i[CH_W-1:0])
                    })
                    2'b11: rx_err_cnt[cnt_i] = rx_err_cnt[cnt_i] + 32'd2;
                    2'b10,
                    2'b01: rx_err_cnt[cnt_i] = rx_err_cnt[cnt_i] + 1'b1;
                    default: ;
                    endcase
                end
            end else begin
                if (HAS_PER_CH_COUNTERS && csr_err_cnt_evt_valid_q)
                    rx_err_cnt[csr_err_cnt_evt_ch_q] = rx_err_cnt[csr_err_cnt_evt_ch_q] + 1'b1;

                if (HAS_PER_CH_COUNTERS &&
                    rx_cnt_evt_valid_q &&
                    !(used_clear_valid_q && (used_clear_ch_q == rx_cnt_evt_ch_q)) &&
                    !(csr_ch_reset_accept && (csr_wr_ch == rx_cnt_evt_ch_q))) begin
                    if (rx_cnt_evt_inc_frame_q)
                        rx_frame_cnt[rx_cnt_evt_ch_q] = rx_frame_cnt[rx_cnt_evt_ch_q] + 1'b1;
                    if (rx_cnt_evt_inc_drop_q)
                        rx_drop_cnt[rx_cnt_evt_ch_q] = rx_drop_cnt[rx_cnt_evt_ch_q] + 1'b1;
                    if (rx_cnt_evt_inc_err_q)
                        rx_err_cnt[rx_cnt_evt_ch_q] = rx_err_cnt[rx_cnt_evt_ch_q] + 1'b1;
                end
            end

            if (rdptr_state_q == RDPTR_CALC) begin
                rdptr_calc_ch_q <= rdptr_ch_q;
                rdptr_calc_new_ptr_q <= rdptr_new_ptr_q;
                rdptr_used_snapshot_q <= rdptr_used_q;
                if ((rdptr_size_q == 32'h0) || (rdptr_new_ptr_q >= rdptr_size_q) || (rdptr_new_ptr_q[5:0] != 6'h0)) begin
                    rdptr_release_delta_q <= 32'h0;
                    rdptr_error_q <= 1'b1;
                    rdptr_error_code_q <= `DMA_ST_RD_PTR_ERR;
                end else if (rdptr_new_ptr_q >= rdptr_old_ptr_q) begin
                    rdptr_release_delta_q <= rdptr_new_ptr_q - rdptr_old_ptr_q;
                    rdptr_error_q <= ((rdptr_new_ptr_q - rdptr_old_ptr_q) > rdptr_used_q);
                    rdptr_error_code_q <= `DMA_ST_RD_PTR_ERR;
                end else begin
                    rdptr_release_delta_q <= rdptr_size_q - rdptr_old_ptr_q + rdptr_new_ptr_q;
                    rdptr_error_q <= ((rdptr_size_q - rdptr_old_ptr_q + rdptr_new_ptr_q) > rdptr_used_q);
                    rdptr_error_code_q <= `DMA_ST_RD_PTR_ERR;
                end
                rdptr_state_q <= RDPTR_COMMIT;
            end

            if ((rdptr_state_q == RDPTR_IDLE) && csr_wr_valid && csr_wr_ready) begin
                if (csr_wr_off == RX_RD_PTR_OFF) begin
                    rdptr_ch_q <= csr_wr_ch;
                    rdptr_new_ptr_q <= csr_wdata;
                    rdptr_old_ptr_q <= rx_rd_ptr[csr_wr_ch];
                    rdptr_size_q <= rx_size[csr_wr_ch];
                    rdptr_used_q <= rx_used[csr_wr_ch];
                    rdptr_state_q <= RDPTR_CALC;
                end else if ((csr_wr_off == RX_CTRL_OFF) &&
                             csr_wdata[`DMA_RX_CTRL_CH_RESET] &&
                             !rx_ch_busy_q[csr_wr_ch]) begin
                    reset_one_channel_no_used(csr_wr_ch);
                    used_clear_valid_q <= 1'b1;
                    used_clear_ch_q <= csr_wr_ch;
                    used_commit_rsp_valid_q <= 1'b1;
                    used_commit_rsp_is_rdptr_q <= 1'b0;
                    used_commit_rsp_is_ch_reset_q <= 1'b1;
                    used_commit_rsp_ch_q <= csr_wr_ch;
                    used_commit_rsp_kind_q <= CSR_WR_RSP_NONE;
                    used_commit_rsp_code_q <= 8'h0;
                end else begin
                    csr_wr_rsp_valid <= 1'b1;
                    execute_write(csr_wr_ch, csr_wr_off, csr_wdata);
                end
            end

            if (event_pipe_valid && event_pipe_ch_valid) begin
                set_rx_status_code(event_pipe_ch, event_pipe_status_code);
                rx_cnt_evt_valid_q <= HAS_PER_CH_COUNTERS &&
                                      !((used_clear_valid_q && (used_clear_ch_q == event_pipe_ch)) ||
                                        (csr_ch_reset_accept && (csr_wr_ch == event_pipe_ch))) &&
                                      (event_pipe_inc_frame || event_pipe_inc_drop || event_pipe_inc_err);
                rx_cnt_evt_ch_q <= event_pipe_ch;
                rx_cnt_evt_inc_frame_q <= event_pipe_inc_frame;
                rx_cnt_evt_inc_drop_q <= event_pipe_inc_drop;
                rx_cnt_evt_inc_err_q <= event_pipe_inc_err;
                if (event_pipe_update_wr_ptr)
                    rx_wr_ptr[event_pipe_ch] = event_pipe_next_wr_ptr;
            end else begin
                rx_cnt_evt_valid_q <= 1'b0;
                rx_cnt_evt_inc_frame_q <= 1'b0;
                rx_cnt_evt_inc_drop_q <= 1'b0;
                rx_cnt_evt_inc_err_q <= 1'b0;
            end

            if (rdptr_state_q == RDPTR_COMMIT) begin
                if (rdptr_error_q) begin
                    csr_wr_rsp_valid <= 1'b1;
                    set_rx_status_code(rdptr_calc_ch_q, rdptr_error_code_q);
                    if (HAS_PER_CH_COUNTERS)
                        csr_err_cnt_evt_set = 1'b1;
                    csr_err_cnt_evt_set_ch = rdptr_calc_ch_q;
                    csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
                    csr_wr_rsp_code <= rdptr_error_code_q;
                    rdptr_state_q <= RDPTR_IDLE;
                end else begin
                    rx_rd_ptr[rdptr_calc_ch_q] = rdptr_calc_new_ptr_q;
                    used_rdptr_valid_q <= 1'b1;
                    consumer_release_valid_q <= 1'b1;
                    used_rdptr_ch_q <= rdptr_calc_ch_q;
                    used_rdptr_delta_q <= rdptr_release_delta_q;
                    used_rdptr_ptr_q <= rdptr_calc_new_ptr_q;
                    used_commit_rsp_valid_q <= 1'b1;
                    used_commit_rsp_is_rdptr_q <= 1'b1;
                    used_commit_rsp_is_ch_reset_q <= 1'b0;
                    used_commit_rsp_ch_q <= rdptr_calc_ch_q;
                    used_commit_rsp_kind_q <= CSR_WR_RSP_NONE;
                    used_commit_rsp_code_q <= 8'h0;
                    rdptr_state_q <= RDPTR_RESP;
                end
            end else if (rdptr_state_q == RDPTR_RESP) begin
                rdptr_state_q <= RDPTR_IDLE;
            end

            csr_err_cnt_evt_valid_q <= csr_err_cnt_evt_set;
            csr_err_cnt_evt_ch_q <= csr_err_cnt_evt_set_ch;
            if (HAS_COUNTER_EVENT_LANES) begin
                csr_err_cnt_commit_valid_q <= csr_err_cnt_evt_valid_q;
                csr_err_cnt_commit_ch_q <= csr_err_cnt_evt_ch_q;
            end else begin
                csr_err_cnt_commit_valid_q <= 1'b0;
                csr_err_cnt_commit_ch_q <= {CH_W{1'b0}};
            end

            if (fc_status_valid) begin
                rx_status[fc_status_ch][`DMA_RX_STATUS_PAUSE] = fc_status_pause;
                rx_status[fc_status_ch][`DMA_RX_STATUS_LOW] = fc_status_low;
                rx_status[fc_status_ch][`DMA_RX_STATUS_DDR_FULL] = fc_status_full;
                rx_status[fc_status_ch][`DMA_RX_STATUS_DDR_AFULL] = fc_status_afull;
                if (fc_status_ovf)
                    rx_status[fc_status_ch][`DMA_RX_STATUS_OVF] = 1'b1;
            end
        end
    end
end

endmodule
