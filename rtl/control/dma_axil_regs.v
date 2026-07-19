`timescale 1ns/1ps
`include "dma_defs.vh"

// AXI4-Lite 控制面：按 global、TX channel、RX channel 和 descriptor region 解码 CSR。
// 读请求先采样地址/区域再抓取状态，写请求先完成保护与 ring-pointer 检查；硬件
// event 和 soft reset 以本地控制状态输出，避免 AXI-Lite valid 与数据面直接耦合。
module dma_axil_regs #(
    parameter integer TX_RD_MAX_OUTSTANDING = `DMA_TX_RD_MAX_OUTSTANDING,
    parameter integer RX_WR_MAX_OUTSTANDING = `DMA_RX_WR_MAX_OUTSTANDING,
    parameter integer DEFER_BUSY_SOFT_RESET = 0
)(
    input             clk,
    input             rstn,
    input      [31:0] s_axil_awaddr,
    input             s_axil_awvalid,
    output            s_axil_awready,
    input      [31:0] s_axil_wdata,
    input      [3:0]  s_axil_wstrb,
    input             s_axil_wvalid,
    output            s_axil_wready,
    output reg [1:0]  s_axil_bresp,
    output reg        s_axil_bvalid,
    input             s_axil_bready,
    input      [31:0] s_axil_araddr,
    input             s_axil_arvalid,
    output            s_axil_arready,
    output reg [31:0] s_axil_rdata,
    output reg [1:0]  s_axil_rresp,
    output reg        s_axil_rvalid,
    input             s_axil_rready,
    input             core_busy,
    input             axi_busy,
    input             event_valid,
    input             event_ch_valid,
    input      [3:0]  event_ch,
    input      [7:0]  event_status_code,
    input      [31:0] event_aligned_len,
    input      [31:0] event_next_wr_ptr,
    input             event_inc_frame,
    input             event_inc_drop,
    input             event_inc_err,
    input             event_update_wr_ptr,
    input      [15:0] event_irq_mask,
    input             event_global_header_err,
    input             fc_status_valid,
    input      [3:0]  fc_status_ch,
    input             fc_status_pause,
    input             fc_status_low,
    input             fc_status_full,
    input             fc_status_afull,
    input             fc_status_ovf,
    input             cq_commit_valid,
    input      [31:0] cq_next_ptr,
    input      [`DMA_MAX_CH-1:0] rx_ch_busy_flat,
    input      [`DMA_MAX_CH-1:0] tx_ch_busy_flat,
    input      [`DMA_MAX_CH-1:0] tx_desc_enable_flat,
    input             tx_event_valid,
    input      [3:0]  tx_event_ch,
    input      [7:0]  tx_event_status_code,
    input             tx_event_inc_frame,
    input             tx_event_inc_err,
    input             tx_event_clear_start,
    input             tx_event_clear_stop,
    input             tx_desc_event_valid,
    input      [3:0]  tx_desc_event_ch,
    input      [31:0] tx_desc_event_rd_ptr,
    input      [7:0]  tx_desc_event_status_code,
    input             tx_desc_event_inc_err,
    output            tx_csr_wr_valid,
    input             tx_csr_wr_ready,
    output     [3:0]  tx_csr_wr_ch,
    output     [5:0]  tx_csr_wr_off,
    output     [31:0] tx_csr_wdata,
    output     [3:0]  tx_csr_wstrb,
    input      [1:0]  tx_csr_bresp,
    input             tx_csr_wr_rsp_valid,
    input      [1:0]  tx_csr_wr_rsp_kind,
    input      [7:0]  tx_csr_wr_rsp_code,
    input             tx_csr_global_err,
    input             tx_csr_policy_irq,
    output            tx_csr_rd_valid,
    input             tx_csr_rd_ready,
    output     [3:0]  tx_csr_rd_ch,
    output     [5:0]  tx_csr_rd_off,
    input             tx_csr_rvalid,
    input      [31:0] tx_csr_rdata,
    input      [1:0]  tx_csr_rresp,
    input             tx_tbl_irq_tx_completion,
    input             tx_tbl_irq_axi_error,
    output            tx_desc_csr_wr_valid,
    input             tx_desc_csr_wr_ready,
    output     [3:0]  tx_desc_csr_wr_ch,
    output     [5:0]  tx_desc_csr_wr_off,
    output     [31:0] tx_desc_csr_wdata,
    output     [3:0]  tx_desc_csr_wstrb,
    input      [1:0]  tx_desc_csr_bresp,
    input             tx_desc_csr_wr_rsp_valid,
    input      [1:0]  tx_desc_csr_wr_rsp_kind,
    input      [7:0]  tx_desc_csr_wr_rsp_code,
    output            tx_desc_csr_rd_valid,
    input             tx_desc_csr_rd_ready,
    output     [3:0]  tx_desc_csr_rd_ch,
    output     [5:0]  tx_desc_csr_rd_off,
    input             tx_desc_csr_rvalid,
    input      [31:0] tx_desc_csr_rdata,
    input      [1:0]  tx_desc_csr_rresp,
    output            rx_csr_wr_valid,
    input             rx_csr_wr_ready,
    output     [3:0]  rx_csr_wr_ch,
    output     [5:0]  rx_csr_wr_off,
    output     [31:0] rx_csr_wdata,
    output     [3:0]  rx_csr_wstrb,
    input      [1:0]  rx_csr_bresp,
    input             rx_csr_wr_rsp_valid,
    input      [1:0]  rx_csr_wr_rsp_kind,
    input      [7:0]  rx_csr_wr_rsp_code,
    output            rx_csr_rd_valid,
    input             rx_csr_rd_ready,
    output     [3:0]  rx_csr_rd_ch,
    output     [5:0]  rx_csr_rd_off,
    input             rx_csr_rvalid,
    input      [31:0] rx_csr_rdata,
    input      [1:0]  rx_csr_rresp,
    output            global_enable,
    output            rx_enable,
    output            tx_enable,
    output            irq_enable,
    output     [31:0] cq_base_l,
    output     [31:0] cq_base_h,
    output     [31:0] cq_size,
    output     [31:0] cq_wr_ptr,
    output     [31:0] cq_rd_ptr,
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
    output     [`DMA_MAX_CH*32-1:0] rx_user_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_ctrl_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_cfg_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_base_l_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_base_h_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_len_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_status_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_user_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_desc_ctrl_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_desc_base_l_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_desc_base_h_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_desc_size_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_desc_rd_ptr_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_desc_wr_ptr_flat,
    output     [`DMA_MAX_CH*32-1:0] tx_desc_status_flat,
    output            ufc_enable,
    output reg        ufc_tx_start,
    output reg [7:0]  ufc_tx_opcode_cfg,
    output reg [15:0] ufc_tx_flow_id_cfg,
    output reg [31:0] ufc_tx_arg0_cfg,
    output reg [31:0] ufc_tx_arg1_cfg,
    output reg        ufc_tx_clear_done,
    output reg        ufc_tx_clear_busy_reject,
    input             ufc_tx_busy,
    input             ufc_tx_done,
    input             ufc_tx_busy_reject,
    input             ufc_tx_done_event,
    output reg        ufc_rx_clear_pending,
    output reg        ufc_rx_clear_overrun,
    input             ufc_rx_pending,
    input             ufc_rx_overrun,
    input      [7:0]  ufc_rx_opcode,
    input      [15:0] ufc_rx_flow_id,
    input      [31:0] ufc_rx_arg0,
    input      [31:0] ufc_rx_arg1,
    input             ufc_rx_msg_event,
    output reg        soft_reset_pulse,
    output reg        ch_reset_pulse,
    output reg [3:0]  ch_reset_ch,
    output             irq
);

// 读写各自拥有阶段化 FSM，响应保持到 AXI-Lite ready，允许软件侧增加若干周期。
localparam RD_IDLE   = 3'd0;
localparam RD_DECODE = 3'd1;
localparam RD_SAMPLE = 3'd2;
localparam RD_FETCH  = 3'd3;
localparam RD_RESP   = 3'd4;

localparam WR_IDLE   = 3'd0;
localparam WR_DECODE = 3'd1;
localparam WR_EXEC   = 3'd2;
localparam WR_EXEC2  = 3'd3;
localparam WR_RESP   = 3'd4;

localparam RD_REGION_GLOBAL   = 3'd0;
localparam RD_REGION_TX_CH    = 3'd1;
localparam RD_REGION_RX_CH    = 3'd2;
localparam RD_REGION_TX_DESC  = 3'd3;
localparam RD_REGION_RESERVED = 3'd4;

localparam HAS_DEBUG_STATUS = (`DMA_ENABLE_DEBUG_STATUS != 0);
localparam CSR_WR_RSP_NONE    = 2'd0;
localparam CSR_WR_RSP_PROTECT = 2'd1;
localparam CSR_WR_RSP_RING    = 2'd2;

reg [31:0] global_ctrl_r;
reg [31:0] global_status_sticky;
reg [31:0] irq_status;
reg [31:0] irq_mask;
reg [31:0] cq_base_l_r;
reg [31:0] cq_base_h_r;
reg [31:0] cq_size_r;
reg [31:0] cq_wr_ptr_r;
reg [31:0] cq_rd_ptr_r;
reg [31:0] intr_coal_cnt;
reg [31:0] intr_coal_timer;
reg [31:0] global_drop_cnt;
reg [31:0] global_err_cnt;

reg [2:0]  wr_state;
reg        wr_aw_seen;
reg        wr_w_seen;
reg [11:0] wr_addr_q;
reg [31:0] wr_data_q;
reg [3:0]  wr_strb_q;
reg [2:0]  wr_region_q;
reg [3:0]  wr_ch_q;
reg [11:0] wr_ch_off_q;
reg [11:0] wr_global_off_q;
reg [2:0]  rd_state;
reg [11:0] rd_addr_q;
reg [2:0]  rd_region_q;
reg [3:0]  rd_ch_q;
reg [11:0] rd_ch_off_q;
reg [11:0] rd_global_off_q;
reg [31:0] rd_data_pipe;
reg [1:0]  rd_global_group_q;
reg [31:0] rd_global_bank0_q;
reg [31:0] rd_global_bank1_q;
reg [31:0] rd_global_bank2_q;
reg [31:0] rd_global_bank3_q;
reg        rd_table_req_sent_q;

reg        core_busy_q;
reg        axi_busy_q;
reg        soft_reset_pending_q;
reg        ufc_tx_busy_q;
reg        ufc_tx_done_q;
reg        ufc_tx_busy_reject_q;
reg        ufc_rx_pending_q;
reg        ufc_rx_overrun_q;
reg [7:0]  ufc_rx_opcode_q;
reg [15:0] ufc_rx_flow_id_q;
reg [31:0] ufc_rx_arg0_q;
reg [31:0] ufc_rx_arg1_q;

reg [31:0] feature_status_mirror;
reg [31:0] global_status_mirror;
reg [31:0] debug_state_mirror;
reg [31:0] ufc_tx_status_mirror;
reg [31:0] ufc_rx_status_mirror;

reg        ev_cap_valid;
reg        ev_cap_ch_valid;
reg [3:0]  ev_cap_ch;
reg [7:0]  ev_cap_status_code;
reg [31:0] ev_cap_aligned_len;
reg [31:0] ev_cap_next_wr_ptr;
reg        ev_cap_inc_frame;
reg        ev_cap_inc_drop;
reg        ev_cap_inc_err;
reg        ev_cap_update_wr_ptr;
reg [15:0] ev_cap_irq_mask;
reg        ev_cap_global_header_err;

assign s_axil_arready = (rd_state == RD_IDLE);
assign s_axil_awready = (wr_state == WR_IDLE) && !wr_aw_seen;
assign s_axil_wready  = (wr_state == WR_IDLE) && !wr_w_seen;
assign tx_csr_wr_valid = (wr_state == WR_EXEC) && (wr_region_q == RD_REGION_TX_CH);
assign tx_csr_wr_ch = wr_ch_q;
assign tx_csr_wr_off = wr_ch_off_q[5:0];
assign tx_csr_wdata = wr_data_q;
assign tx_csr_wstrb = wr_strb_q;
assign tx_csr_rd_valid = (rd_state == RD_FETCH) && (rd_region_q == RD_REGION_TX_CH);
assign tx_csr_rd_ch = rd_ch_q;
assign tx_csr_rd_off = rd_ch_off_q[5:0];
assign tx_desc_csr_wr_valid = (wr_state == WR_EXEC) && (wr_region_q == RD_REGION_TX_DESC);
assign tx_desc_csr_wr_ch = wr_ch_q;
assign tx_desc_csr_wr_off = wr_ch_off_q[5:0];
assign tx_desc_csr_wdata = wr_data_q;
assign tx_desc_csr_wstrb = wr_strb_q;
assign tx_desc_csr_rd_valid = (rd_state == RD_FETCH) &&
                              (rd_region_q == RD_REGION_TX_DESC) &&
                              !rd_table_req_sent_q;
assign tx_desc_csr_rd_ch = rd_ch_q;
assign tx_desc_csr_rd_off = rd_ch_off_q[5:0];
assign rx_csr_wr_valid = (wr_state == WR_EXEC) && (wr_region_q == RD_REGION_RX_CH);
assign rx_csr_wr_ch = wr_ch_q;
assign rx_csr_wr_off = wr_ch_off_q[5:0];
assign rx_csr_wdata = wr_data_q;
assign rx_csr_wstrb = wr_strb_q;
assign rx_csr_rd_valid = (rd_state == RD_FETCH) && (rd_region_q == RD_REGION_RX_CH);
assign rx_csr_rd_ch = rd_ch_q;
assign rx_csr_rd_off = rd_ch_off_q[5:0];
assign rx_ctrl_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_cfg_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_base_l_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_base_h_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_size_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_max_len_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_wr_ptr_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_rd_ptr_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_used_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_high_wm_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_low_wm_flat = {(`DMA_MAX_CH*32){1'b0}};
assign rx_user_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_desc_ctrl_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_desc_base_l_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_desc_base_h_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_desc_size_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_desc_rd_ptr_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_desc_wr_ptr_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_desc_status_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_ctrl_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_cfg_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_base_l_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_base_h_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_len_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_status_flat = {(`DMA_MAX_CH*32){1'b0}};
assign tx_user_flat = {(`DMA_MAX_CH*32){1'b0}};

function [31:0] maybe_debug_data;
    input [31:0] data;
    begin
        maybe_debug_data = HAS_DEBUG_STATUS ? data : 32'h0;
    end
endfunction

assign global_enable = global_ctrl_r[`DMA_GCTRL_GLOBAL_EN];
assign rx_enable = global_ctrl_r[`DMA_GCTRL_RX_EN];
assign tx_enable = global_ctrl_r[`DMA_GCTRL_TX_EN];
assign irq_enable = global_ctrl_r[`DMA_GCTRL_IRQ_EN];
assign ufc_enable = global_ctrl_r[`DMA_GCTRL_UFC_EN];
assign cq_base_l = cq_base_l_r;
assign cq_base_h = cq_base_h_r;
assign cq_size = cq_size_r;
assign cq_wr_ptr = cq_wr_ptr_r;
assign cq_rd_ptr = cq_rd_ptr_r;
assign irq = irq_enable && (|(irq_status & irq_mask));

task reset_regs;
    begin
        global_ctrl_r = 32'h0;
        global_status_sticky = 32'h0;
        irq_status = 32'h0;
        irq_mask = 32'h0;
        cq_base_l_r = 32'h0;
        cq_base_h_r = 32'h0;
        cq_size_r = 32'h0;
        cq_wr_ptr_r = 32'h0;
        cq_rd_ptr_r = 32'h0;
        intr_coal_cnt = 32'h1;
        intr_coal_timer = 32'h0;
        global_drop_cnt = 32'h0;
        global_err_cnt = 32'h0;
        ufc_tx_start = 1'b0;
        ufc_tx_opcode_cfg = 8'h0;
        ufc_tx_flow_id_cfg = 16'h0;
        ufc_tx_arg0_cfg = 32'h0;
        ufc_tx_arg1_cfg = 32'h0;
        ufc_tx_clear_done = 1'b0;
        ufc_tx_clear_busy_reject = 1'b0;
        ufc_rx_clear_pending = 1'b0;
        ufc_rx_clear_overrun = 1'b0;
    end
endtask

task decode_write_addr;
    input [11:0] off;
    output [2:0] region;
    output [3:0] ch;
    output [11:0] ch_off;
    output [11:0] global_off;
    integer ch_int;
    begin
        region = RD_REGION_RESERVED;
        ch = 4'h0;
        ch_off = 12'h0;
        global_off = off;
        if (off < `DMA_TX_CH_BASE) begin
            region = RD_REGION_GLOBAL;
            global_off = off;
        end else if ((off >= `DMA_TX_CH_BASE) &&
                     (off < (`DMA_TX_CH_BASE + (`DMA_TX_CH_NUM * `DMA_CH_STRIDE)))) begin
            ch_int = (off - `DMA_TX_CH_BASE) >> 6;
            region = RD_REGION_TX_CH;
            ch = ch_int[3:0];
            ch_off = off - `DMA_TX_CH_BASE - (ch_int << 6);
        end else if ((off >= `DMA_RX_CH_BASE) &&
                     (off < (`DMA_RX_CH_BASE + (`DMA_MAX_CH * `DMA_CH_STRIDE)))) begin
            ch_int = (off - `DMA_RX_CH_BASE) >> 6;
            region = RD_REGION_RX_CH;
            ch = ch_int[3:0];
            ch_off = off - `DMA_RX_CH_BASE - (ch_int << 6);
        end else if ((off >= `DMA_TX_DESC_CH_BASE) &&
                     (off < (`DMA_TX_DESC_CH_BASE + (`DMA_TX_CH_NUM * `DMA_CH_STRIDE)))) begin
            ch_int = (off - `DMA_TX_DESC_CH_BASE) >> 6;
            region = RD_REGION_TX_DESC;
            ch = ch_int[3:0];
            ch_off = off - `DMA_TX_DESC_CH_BASE - (ch_int << 6);
        end
    end
endtask

task execute_global_write;
    input [11:0] off;
    input [31:0] data;
    begin
        case (off)
        `DMA_REG_GLOBAL_CTRL: begin
            if (data[`DMA_GCTRL_SOFT_RESET]) begin
                if (DEFER_BUSY_SOFT_RESET) begin
                    soft_reset_pending_q <= 1'b1;
                end else if (core_busy_q) begin
                    global_status_sticky[`DMA_GSTATUS_RESET_REJECTED] = 1'b1;
                    global_err_cnt = global_err_cnt + 1'b1;
                    irq_status[`DMA_IRQ_POLICY_REJECT] = 1'b1;
                end else begin
                    reset_regs();
                    soft_reset_pulse = 1'b1;
                end
            end else begin
                global_ctrl_r = (global_ctrl_r & 32'hffff_fc00) | (data & 32'h0000_001f);
                if (data[`DMA_GCTRL_CLR_STATUS])
                    global_status_sticky = 32'h0;
            end
        end
        `DMA_REG_IRQ_STATUS: irq_status = irq_status & ~data;
        `DMA_REG_IRQ_MASK: irq_mask = data;
        `DMA_REG_CQ_BASE_L: cq_base_l_r = data;
        `DMA_REG_CQ_BASE_H: cq_base_h_r = data;
        `DMA_REG_CQ_SIZE: cq_size_r = data;
        `DMA_REG_CQ_RD_PTR: cq_rd_ptr_r = data;
        `DMA_REG_INTR_COAL_CNT: intr_coal_cnt = data;
        `DMA_REG_INTR_COAL_TMR: intr_coal_timer = data;
        `DMA_REG_SOFT_RESET: if (data[0]) begin
            if (DEFER_BUSY_SOFT_RESET) begin
                soft_reset_pending_q <= 1'b1;
            end else if (core_busy_q) begin
                global_status_sticky[`DMA_GSTATUS_RESET_REJECTED] = 1'b1;
                global_err_cnt = global_err_cnt + 1'b1;
                irq_status[`DMA_IRQ_POLICY_REJECT] = 1'b1;
            end else begin
                reset_regs();
                soft_reset_pulse = 1'b1;
            end
        end
        `DMA_REG_UFC_TX_CTRL: begin
            ufc_tx_start = data[`DMA_UFC_TX_START];
            ufc_tx_clear_done = data[`DMA_UFC_TX_DONE];
            ufc_tx_clear_busy_reject = data[`DMA_UFC_TX_BUSY_REJ];
        end
        `DMA_REG_UFC_TX_OPCODE: ufc_tx_opcode_cfg = data[7:0];
        `DMA_REG_UFC_TX_FLOWID: ufc_tx_flow_id_cfg = data[15:0];
        `DMA_REG_UFC_TX_ARG0: ufc_tx_arg0_cfg = data;
        `DMA_REG_UFC_TX_ARG1: ufc_tx_arg1_cfg = data;
        `DMA_REG_UFC_RX_STATUS: begin
            ufc_rx_clear_pending = data[`DMA_UFC_RX_PENDING];
            ufc_rx_clear_overrun = data[`DMA_UFC_RX_OVERRUN];
        end
        `DMA_REG_IP_ID,
        `DMA_REG_VERSION,
        `DMA_REG_GLOBAL_STATUS,
        `DMA_REG_RX_CH_NUM,
        `DMA_REG_TX_CH_NUM,
        `DMA_REG_CQ_WR_PTR,
        `DMA_REG_DROP_CNT,
        `DMA_REG_ERR_CNT,
        `DMA_REG_DEBUG_STATE,
        `DMA_REG_FEATURE,
        `DMA_REG_UFC_RX_OPCODE,
        `DMA_REG_UFC_RX_FLOWID,
        `DMA_REG_UFC_RX_ARG0,
        `DMA_REG_UFC_RX_ARG1: ;
        default: begin
            global_status_sticky[`DMA_GSTATUS_ILLEGAL_REG] = 1'b1;
            global_err_cnt = global_err_cnt + 1'b1;
            irq_status[`DMA_IRQ_POLICY_REJECT] = 1'b1;
        end
        endcase
    end
endtask

task execute_write_cmd;
    begin
        case (wr_region_q)
        RD_REGION_GLOBAL: execute_global_write(wr_global_off_q, wr_data_q);
        RD_REGION_TX_CH: begin end
        RD_REGION_RX_CH: begin end
        RD_REGION_TX_DESC: begin end
        default: begin
            global_status_sticky[`DMA_GSTATUS_ILLEGAL_REG] = 1'b1;
            global_err_cnt = global_err_cnt + 1'b1;
            irq_status[`DMA_IRQ_POLICY_REJECT] = 1'b1;
        end
        endcase
    end
endtask

task decode_read_addr;
    input [11:0] off;
    output [2:0] region;
    output [3:0] ch;
    output [11:0] ch_off;
    output [11:0] global_off;
    integer ch_calc;
    begin
        region = RD_REGION_RESERVED;
        ch = 4'h0;
        ch_off = 12'h0;
        global_off = off;
        if (off < `DMA_TX_CH_BASE) begin
            region = RD_REGION_GLOBAL;
        end else if ((off >= `DMA_TX_CH_BASE) &&
                     (off < (`DMA_TX_CH_BASE + (`DMA_TX_CH_NUM * `DMA_CH_STRIDE)))) begin
            region = RD_REGION_TX_CH;
            ch_calc = (off - `DMA_TX_CH_BASE) >> 6;
            ch = ch_calc[3:0];
            ch_off = off - `DMA_TX_CH_BASE - (ch_calc << 6);
        end else if ((off >= `DMA_RX_CH_BASE) &&
                     (off < (`DMA_RX_CH_BASE + (`DMA_MAX_CH * `DMA_CH_STRIDE)))) begin
            region = RD_REGION_RX_CH;
            ch_calc = (off - `DMA_RX_CH_BASE) >> 6;
            ch = ch_calc[3:0];
            ch_off = off - `DMA_RX_CH_BASE - (ch_calc << 6);
        end else if ((off >= `DMA_TX_DESC_CH_BASE) &&
                     (off < (`DMA_TX_DESC_CH_BASE + (`DMA_TX_CH_NUM * `DMA_CH_STRIDE)))) begin
            region = RD_REGION_TX_DESC;
            ch_calc = (off - `DMA_TX_DESC_CH_BASE) >> 6;
            ch = ch_calc[3:0];
            ch_off = off - `DMA_TX_DESC_CH_BASE - (ch_calc << 6);
        end
    end
endtask

task fetch_read_data_sampled;
    input [2:0] region;
    input [11:0] ch_off;
    input [11:0] global_off;
    output [31:0] data;
    begin
        data = 32'h0;
        case (region)
        RD_REGION_GLOBAL: begin
            case (global_off)
            `DMA_REG_IP_ID: data = `DMA_IP_ID;
            `DMA_REG_VERSION: data = `DMA_VERSION;
            `DMA_REG_GLOBAL_CTRL: data = global_ctrl_r;
            `DMA_REG_GLOBAL_STATUS: data = global_status_mirror;
            `DMA_REG_IRQ_STATUS: data = irq_status;
            `DMA_REG_IRQ_MASK: data = irq_mask;
            `DMA_REG_RX_CH_NUM: data = `DMA_RX_CH_NUM;
            `DMA_REG_TX_CH_NUM: data = `DMA_TX_CH_NUM;
            `DMA_REG_CQ_BASE_L: data = cq_base_l_r;
            `DMA_REG_CQ_BASE_H: data = cq_base_h_r;
            `DMA_REG_CQ_SIZE: data = cq_size_r;
            `DMA_REG_CQ_WR_PTR: data = cq_wr_ptr_r;
            `DMA_REG_CQ_RD_PTR: data = cq_rd_ptr_r;
            `DMA_REG_INTR_COAL_CNT: data = intr_coal_cnt;
            `DMA_REG_INTR_COAL_TMR: data = intr_coal_timer;
            `DMA_REG_DROP_CNT: data = global_drop_cnt;
            `DMA_REG_ERR_CNT: data = global_err_cnt;
            `DMA_REG_DEBUG_STATE: data = maybe_debug_data(debug_state_mirror);
            `DMA_REG_FEATURE: data = feature_status_mirror;
            `DMA_REG_UFC_TX_CTRL: data = ufc_tx_status_mirror;
            `DMA_REG_UFC_TX_OPCODE: data = {24'h0, ufc_tx_opcode_cfg};
            `DMA_REG_UFC_TX_FLOWID: data = {16'h0, ufc_tx_flow_id_cfg};
            `DMA_REG_UFC_TX_ARG0: data = ufc_tx_arg0_cfg;
            `DMA_REG_UFC_TX_ARG1: data = ufc_tx_arg1_cfg;
            `DMA_REG_UFC_RX_STATUS: data = ufc_rx_status_mirror;
            `DMA_REG_UFC_RX_OPCODE: data = {24'h0, ufc_rx_opcode_q};
            `DMA_REG_UFC_RX_FLOWID: data = {16'h0, ufc_rx_flow_id_q};
            `DMA_REG_UFC_RX_ARG0: data = ufc_rx_arg0_q;
            `DMA_REG_UFC_RX_ARG1: data = ufc_rx_arg1_q;
            default: data = 32'h0;
            endcase
        end
        RD_REGION_TX_CH: begin
            case (ch_off)
            `DMA_CH_CTRL,
            `DMA_CH_CFG,
            `DMA_CH_BASE_L,
            `DMA_CH_BASE_H,
            `DMA_TX_CH_LEN,
            `DMA_CH_STATUS,
            `DMA_CH_FRAME_CNT,
            `DMA_CH_ERR_CNT,
            `DMA_CH_USER: data = tx_csr_rdata;
            default: data = 32'h0;
            endcase
        end
        RD_REGION_RX_CH: begin
            data = rx_csr_rdata;
        end
        RD_REGION_TX_DESC: begin
            data = tx_desc_csr_rdata;
        end
        default: data = 32'h0;
        endcase
    end
endtask

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        core_busy_q <= 1'b0;
        axi_busy_q <= 1'b0;
        ufc_tx_busy_q <= 1'b0;
        ufc_tx_done_q <= 1'b0;
        ufc_tx_busy_reject_q <= 1'b0;
        ufc_rx_pending_q <= 1'b0;
        ufc_rx_overrun_q <= 1'b0;
        ufc_rx_opcode_q <= 8'h0;
        ufc_rx_flow_id_q <= 16'h0;
        ufc_rx_arg0_q <= 32'h0;
        ufc_rx_arg1_q <= 32'h0;
        feature_status_mirror <= 32'h0;
        global_status_mirror <= 32'h1;
        debug_state_mirror <= 32'h0;
        ufc_tx_status_mirror <= 32'h0;
        ufc_rx_status_mirror <= 32'h0;
    end else begin
        core_busy_q <= core_busy;
        axi_busy_q <= axi_busy;
        ufc_tx_busy_q <= ufc_tx_busy;
        ufc_tx_done_q <= ufc_tx_done;
        ufc_tx_busy_reject_q <= ufc_tx_busy_reject;
        ufc_rx_pending_q <= ufc_rx_pending;
        ufc_rx_overrun_q <= ufc_rx_overrun;
        ufc_rx_opcode_q <= ufc_rx_opcode;
        ufc_rx_flow_id_q <= ufc_rx_flow_id;
        ufc_rx_arg0_q <= ufc_rx_arg0;
        ufc_rx_arg1_q <= ufc_rx_arg1;

        feature_status_mirror <= 32'h0;
        feature_status_mirror[`DMA_FEATURE_RX] <= 1'b1;
        feature_status_mirror[`DMA_FEATURE_TX] <= 1'b1;
        feature_status_mirror[`DMA_FEATURE_UFC] <= 1'b1;
        feature_status_mirror[`DMA_FEATURE_DESC_Q] <= 1'b1;
        feature_status_mirror[`DMA_FEATURE_MULTI_OUT] <= ((TX_RD_MAX_OUTSTANDING > 1) || (RX_WR_MAX_OUTSTANDING > 1));
        feature_status_mirror[`DMA_FEATURE_PER_CH_FIFO] <= 1'b1;
        feature_status_mirror[`DMA_FEATURE_FC_PER_CH_INGRESS] <= 1'b1;
        feature_status_mirror[`DMA_FEATURE_FC_DDR_RING] <= 1'b1;
        feature_status_mirror[`DMA_FEATURE_SPLIT_FRAME_WRITE] <= 1'b0;

        global_status_mirror <= global_status_sticky;
        global_status_mirror[0] <= !core_busy_q;
        global_status_mirror[1] <= core_busy_q;
        global_status_mirror[2] <= core_busy_q;
        global_status_mirror[4] <= axi_busy_q;
        global_status_mirror[5] <= (cq_size_r != 0) &&
            (((cq_wr_ptr_r + 1 >= cq_size_r) ? 32'h0 : (cq_wr_ptr_r + 1)) == cq_rd_ptr_r);
        global_status_mirror[6] <= |(irq_status & irq_mask);
        if (HAS_DEBUG_STATUS)
            debug_state_mirror <= {30'h0, axi_busy_q, core_busy_q};
        else
            debug_state_mirror <= 32'h0;

        ufc_tx_status_mirror <= 32'h0;
        ufc_tx_status_mirror[`DMA_UFC_TX_BUSY] <= ufc_tx_busy_q;
        ufc_tx_status_mirror[`DMA_UFC_TX_DONE] <= ufc_tx_done_q;
        ufc_tx_status_mirror[`DMA_UFC_TX_BUSY_REJ] <= ufc_tx_busy_reject_q;
        ufc_rx_status_mirror <= 32'h0;
        ufc_rx_status_mirror[`DMA_UFC_RX_PENDING] <= ufc_rx_pending_q;
        ufc_rx_status_mirror[`DMA_UFC_RX_OVERRUN] <= ufc_rx_overrun_q;
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        s_axil_bresp <= 2'b00;
        s_axil_bvalid <= 1'b0;
        s_axil_rdata <= 32'h0;
        s_axil_rresp <= 2'b00;
        s_axil_rvalid <= 1'b0;
        wr_state <= WR_IDLE;
        wr_aw_seen <= 1'b0;
        wr_w_seen <= 1'b0;
        wr_addr_q <= 12'h0;
        wr_data_q <= 32'h0;
        wr_strb_q <= 4'h0;
        wr_region_q <= RD_REGION_RESERVED;
        wr_ch_q <= 4'h0;
        wr_ch_off_q <= 12'h0;
        wr_global_off_q <= 12'h0;
        rd_state <= RD_IDLE;
        rd_addr_q <= 12'h0;
        rd_region_q <= RD_REGION_RESERVED;
        rd_ch_q <= 4'h0;
        rd_ch_off_q <= 12'h0;
        rd_global_off_q <= 12'h0;
        rd_data_pipe <= 32'h0;
        rd_table_req_sent_q <= 1'b0;
        ev_cap_valid <= 1'b0;
        ev_cap_ch_valid <= 1'b0;
        ev_cap_ch <= 4'h0;
        ev_cap_status_code <= 8'h0;
        ev_cap_aligned_len <= 32'h0;
        ev_cap_next_wr_ptr <= 32'h0;
        ev_cap_inc_frame <= 1'b0;
        ev_cap_inc_drop <= 1'b0;
        ev_cap_inc_err <= 1'b0;
        ev_cap_update_wr_ptr <= 1'b0;
        ev_cap_irq_mask <= 16'h0;
        ev_cap_global_header_err <= 1'b0;
        soft_reset_pulse = 1'b0;
        soft_reset_pending_q <= 1'b0;
        ch_reset_pulse = 1'b0;
        ch_reset_ch <= 4'h0;
        reset_regs();
    end else begin
        soft_reset_pulse = 1'b0;
        ch_reset_pulse = 1'b0;
        ch_reset_ch <= 4'h0;
        ufc_tx_start = 1'b0;
        ufc_tx_clear_done = 1'b0;
        ufc_tx_clear_busy_reject = 1'b0;
        ufc_rx_clear_pending = 1'b0;
        ufc_rx_clear_overrun = 1'b0;

        if (DEFER_BUSY_SOFT_RESET && soft_reset_pending_q && !core_busy_q) begin
            reset_regs();
            soft_reset_pulse = 1'b1;
            soft_reset_pending_q <= 1'b0;
        end

        case (wr_state)
        WR_IDLE: begin
            if (!wr_aw_seen && s_axil_awvalid && s_axil_awready) begin
                wr_addr_q <= s_axil_awaddr[11:0];
                wr_aw_seen <= 1'b1;
            end
            if (!wr_w_seen && s_axil_wvalid && s_axil_wready) begin
                wr_data_q <= s_axil_wdata;
                wr_strb_q <= s_axil_wstrb;
                wr_w_seen <= 1'b1;
            end
            if ((wr_aw_seen || (s_axil_awvalid && s_axil_awready)) &&
                (wr_w_seen || (s_axil_wvalid && s_axil_wready))) begin
                wr_state <= WR_DECODE;
            end
        end
        WR_DECODE: begin
            decode_write_addr(wr_addr_q, wr_region_q, wr_ch_q, wr_ch_off_q, wr_global_off_q);
            wr_state <= WR_EXEC;
        end
        WR_EXEC: begin
            execute_write_cmd();
            if ((wr_region_q == RD_REGION_TX_CH) && !tx_csr_wr_ready)
                wr_state <= WR_EXEC;
            else if ((wr_region_q == RD_REGION_RX_CH) && !rx_csr_wr_ready)
                wr_state <= WR_EXEC;
            else if ((wr_region_q == RD_REGION_TX_DESC) && !tx_desc_csr_wr_ready)
                wr_state <= WR_EXEC;
            else
                wr_state <= WR_EXEC2;
        end
        WR_EXEC2: begin
            if ((wr_region_q == RD_REGION_TX_CH) && tx_csr_wr_rsp_valid) begin
                if (tx_csr_global_err)
                    global_err_cnt <= global_err_cnt + 1'b1;
                if (tx_csr_policy_irq)
                    irq_status[`DMA_IRQ_POLICY_REJECT] <= 1'b1;
                wr_state <= WR_RESP;
            end
            if ((wr_region_q == RD_REGION_TX_DESC) && tx_desc_csr_wr_rsp_valid) begin
                if ((tx_desc_csr_wr_rsp_kind == CSR_WR_RSP_PROTECT) ||
                    (tx_desc_csr_wr_rsp_kind == CSR_WR_RSP_RING)) begin
                    global_err_cnt <= global_err_cnt + 1'b1;
                    irq_status[`DMA_IRQ_POLICY_REJECT] <= 1'b1;
                end
                wr_state <= WR_RESP;
            end
            if ((wr_region_q == RD_REGION_RX_CH) && rx_csr_wr_rsp_valid) begin
                if (rx_csr_wr_rsp_kind == CSR_WR_RSP_PROTECT) begin
                    global_err_cnt <= global_err_cnt + 1'b1;
                    irq_status[`DMA_IRQ_POLICY_REJECT] <= 1'b1;
                end
                wr_state <= WR_RESP;
            end
            if ((wr_region_q == RD_REGION_GLOBAL) || (wr_region_q == RD_REGION_RESERVED))
                wr_state <= WR_RESP;
        end
        WR_RESP: begin
            if (!s_axil_bvalid) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp <= 2'b00;
            end else if (s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
                wr_aw_seen <= 1'b0;
                wr_w_seen <= 1'b0;
                wr_state <= WR_IDLE;
            end
        end
        default: begin
            s_axil_bvalid <= 1'b0;
            wr_aw_seen <= 1'b0;
            wr_w_seen <= 1'b0;
            wr_state <= WR_IDLE;
        end
        endcase

        case (rd_state)
        RD_IDLE: begin
            s_axil_rvalid <= 1'b0;
            rd_table_req_sent_q <= 1'b0;
            if (s_axil_arvalid && s_axil_arready) begin
                rd_addr_q <= s_axil_araddr[11:0];
                rd_state <= RD_DECODE;
            end
        end
        RD_DECODE: begin
            decode_read_addr(rd_addr_q, rd_region_q, rd_ch_q, rd_ch_off_q, rd_global_off_q);
            rd_state <= RD_SAMPLE;
        end
        RD_SAMPLE: begin
            if (rd_region_q == RD_REGION_GLOBAL) begin
                rd_global_group_q <= rd_global_off_q[6:5];
                case (rd_global_off_q[4:2])
                3'd0: begin
                    rd_global_bank0_q <= `DMA_IP_ID;
                    rd_global_bank1_q <= cq_base_l_r;
                    rd_global_bank2_q <= global_drop_cnt;
                    rd_global_bank3_q <= ufc_tx_arg1_cfg;
                end
                3'd1: begin
                    rd_global_bank0_q <= `DMA_VERSION;
                    rd_global_bank1_q <= cq_base_h_r;
                    rd_global_bank2_q <= global_err_cnt;
                    rd_global_bank3_q <= ufc_rx_status_mirror;
                end
                3'd2: begin
                    rd_global_bank0_q <= global_ctrl_r;
                    rd_global_bank1_q <= cq_size_r;
                    rd_global_bank2_q <= maybe_debug_data(debug_state_mirror);
                    rd_global_bank3_q <= {24'h0, ufc_rx_opcode_q};
                end
                3'd3: begin
                    rd_global_bank0_q <= global_status_mirror;
                    rd_global_bank1_q <= cq_wr_ptr_r;
                    rd_global_bank2_q <= feature_status_mirror;
                    rd_global_bank3_q <= {16'h0, ufc_rx_flow_id_q};
                end
                3'd4: begin
                    rd_global_bank0_q <= irq_status;
                    rd_global_bank1_q <= cq_rd_ptr_r;
                    rd_global_bank2_q <= ufc_tx_status_mirror;
                    rd_global_bank3_q <= ufc_rx_arg0_q;
                end
                3'd5: begin
                    rd_global_bank0_q <= irq_mask;
                    rd_global_bank1_q <= intr_coal_cnt;
                    rd_global_bank2_q <= {24'h0, ufc_tx_opcode_cfg};
                    rd_global_bank3_q <= ufc_rx_arg1_q;
                end
                3'd6: begin
                    rd_global_bank0_q <= `DMA_RX_CH_NUM;
                    rd_global_bank1_q <= intr_coal_timer;
                    rd_global_bank2_q <= {16'h0, ufc_tx_flow_id_cfg};
                    rd_global_bank3_q <= 32'h0;
                end
                default: begin
                    rd_global_bank0_q <= `DMA_TX_CH_NUM;
                    rd_global_bank1_q <= 32'h0;
                    rd_global_bank2_q <= ufc_tx_arg0_cfg;
                    rd_global_bank3_q <= 32'h0;
                end
                endcase
            end
            rd_state <= RD_FETCH;
        end
        RD_FETCH: begin
            if (rd_region_q == RD_REGION_TX_DESC) begin
                if (!rd_table_req_sent_q) begin
                    if (tx_desc_csr_rd_ready)
                        rd_table_req_sent_q <= 1'b1;
                end else if (tx_desc_csr_rvalid) begin
                    rd_data_pipe <= tx_desc_csr_rdata;
                    rd_table_req_sent_q <= 1'b0;
                    rd_state <= RD_RESP;
                end
            end else if (rd_region_q == RD_REGION_TX_CH) begin
                if (!rd_table_req_sent_q) begin
                    if (tx_csr_rd_ready)
                        rd_table_req_sent_q <= 1'b1;
                end else if (tx_csr_rvalid) begin
                    rd_data_pipe <= tx_csr_rdata;
                    rd_table_req_sent_q <= 1'b0;
                    rd_state <= RD_RESP;
                end
            end else if (rd_region_q == RD_REGION_RX_CH) begin
                if (!rd_table_req_sent_q) begin
                    if (rx_csr_rd_ready)
                        rd_table_req_sent_q <= 1'b1;
                end else if (rx_csr_rvalid) begin
                    rd_data_pipe <= rx_csr_rdata;
                    rd_table_req_sent_q <= 1'b0;
                    rd_state <= RD_RESP;
                end
            end else if (rd_region_q == RD_REGION_GLOBAL) begin
                case (rd_global_group_q)
                2'd0: rd_data_pipe <= rd_global_bank0_q;
                2'd1: rd_data_pipe <= rd_global_bank1_q;
                2'd2: rd_data_pipe <= rd_global_bank2_q;
                default: rd_data_pipe <= rd_global_bank3_q;
                endcase
                rd_state <= RD_RESP;
            end else begin
                rd_data_pipe <= 32'h0;
                rd_state <= RD_RESP;
            end
        end
        RD_RESP: begin
            if (!s_axil_rvalid) begin
                s_axil_rdata <= rd_data_pipe;
                s_axil_rresp <= 2'b00;
                s_axil_rvalid <= 1'b1;
            end else if (s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
                rd_state <= RD_IDLE;
            end
        end
        default: begin
            s_axil_rvalid <= 1'b0;
            rd_state <= RD_IDLE;
        end
        endcase

        if (soft_reset_pulse) begin
            ev_cap_valid <= 1'b0;
            ev_cap_ch_valid <= 1'b0;
            ev_cap_ch <= 4'h0;
            ev_cap_status_code <= 8'h0;
            ev_cap_aligned_len <= 32'h0;
            ev_cap_next_wr_ptr <= 32'h0;
            ev_cap_inc_frame <= 1'b0;
            ev_cap_inc_drop <= 1'b0;
            ev_cap_inc_err <= 1'b0;
            ev_cap_update_wr_ptr <= 1'b0;
            ev_cap_irq_mask <= 16'h0;
            ev_cap_global_header_err <= 1'b0;
        end else begin
            ev_cap_valid <= event_valid;
            ev_cap_ch_valid <= event_ch_valid;
            ev_cap_ch <= event_ch;
            ev_cap_status_code <= event_status_code;
            ev_cap_aligned_len <= event_aligned_len;
            ev_cap_next_wr_ptr <= event_next_wr_ptr;
            ev_cap_inc_frame <= event_inc_frame;
            ev_cap_inc_drop <= event_inc_drop;
            ev_cap_inc_err <= event_inc_err;
            ev_cap_update_wr_ptr <= event_update_wr_ptr;
            ev_cap_irq_mask <= event_irq_mask;
            ev_cap_global_header_err <= event_global_header_err;

            if (ev_cap_valid) begin
                irq_status <= irq_status | {16'h0, ev_cap_irq_mask};
                if (ev_cap_global_header_err)
                    global_status_sticky[10] <= 1'b1;
                if (ev_cap_inc_drop) begin
                    global_drop_cnt <= global_drop_cnt + 1'b1;
                end
                if (ev_cap_inc_err) begin
                    global_err_cnt <= global_err_cnt + 1'b1;
                end
            end
        end

        if (tx_tbl_irq_tx_completion)
            irq_status[`DMA_IRQ_TX_COMPLETION] <= 1'b1;
        if (tx_tbl_irq_axi_error)
            irq_status[`DMA_IRQ_AXI_ERROR] <= 1'b1;

        if (cq_commit_valid)
            cq_wr_ptr_r <= cq_next_ptr;

        if (ufc_tx_done_event)
            irq_status[`DMA_IRQ_UFC_TX_DONE] <= 1'b1;
        if (ufc_rx_msg_event)
            irq_status[`DMA_IRQ_UFC_RX] <= 1'b1;
    end
end

endmodule
