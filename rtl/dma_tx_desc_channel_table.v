`timescale 1ns/1ps
`include "dma_defs.vh"

module dma_tx_desc_channel_table #(
    parameter integer CH_W = 4
) (
    input                    clk,
    input                    rstn,
    input                    global_soft_reset,
    input      [`DMA_MAX_CH-1:0] tx_desc_ch_reset_mask,
    input      [`DMA_MAX_CH-1:0] tx_ch_busy_flat,

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

    input                    csr_rd_valid,
    output                   csr_rd_ready,
    input      [CH_W-1:0]    csr_rd_ch,
    input      [5:0]         csr_rd_off,
    output reg               csr_rvalid,
    output reg [31:0]        csr_rdata,
    output reg [1:0]         csr_rresp,

    output     [`DMA_MAX_CH-1:0] tx_desc_enable_flat,
    output     [`DMA_MAX_CH-1:0] tx_desc_ready_flat,

    input                    tx_desc_ctx_req,
    input      [CH_W-1:0]    tx_desc_ctx_ch,
    output reg               tx_desc_ctx_valid,
    output reg [31:0]        tx_desc_ctx_ctrl,
    output reg [31:0]        tx_desc_ctx_base_l,
    output reg [31:0]        tx_desc_ctx_base_h,
    output reg [31:0]        tx_desc_ctx_size,
    output reg [31:0]        tx_desc_ctx_rd_ptr,
    output reg [31:0]        tx_desc_ctx_wr_ptr,
    output reg [31:0]        tx_desc_ctx_status,
    output reg [31:0]        tx_desc_ctx_err_cnt,

    input                    tx_desc_active_valid,
    input      [CH_W-1:0]    tx_desc_active_ch,
    output reg               tx_desc_active_stop,

    input                    tx_desc_evt_valid,
    input      [CH_W-1:0]    tx_desc_evt_ch,
    input      [31:0]        tx_desc_evt_rd_ptr,
    input                    tx_desc_evt_update_rd_ptr,
    input      [7:0]         tx_desc_evt_status_code,
    input                    tx_desc_evt_update_status,
    input                    tx_desc_evt_inc_err,
    input                    tx_desc_evt_clear_busy,
    input                    tx_desc_evt_set_busy
);

localparam HAS_PER_CH_COUNTERS = (`DMA_ENABLE_PER_CH_COUNTERS != 0);
localparam HAS_DESC_STATUS_EVENT_LANES = (`DMA_ENABLE_TX_DESC_STATUS_EVENT_LANES != 0);
localparam CSR_WR_RSP_NONE    = 2'd0;
localparam CSR_WR_RSP_PROTECT = 2'd1;
localparam CSR_WR_RSP_RING    = 2'd2;
localparam [5:0] TX_DESC_CTRL_OFF   = `DMA_TX_DESC_CTRL;
localparam [5:0] TX_DESC_BASE_L_OFF = `DMA_TX_DESC_BASE_L;
localparam [5:0] TX_DESC_BASE_H_OFF = `DMA_TX_DESC_BASE_H;
localparam [5:0] TX_DESC_SIZE_OFF   = `DMA_TX_DESC_SIZE;
localparam [5:0] TX_DESC_RD_PTR_OFF = `DMA_TX_DESC_RD_PTR;
localparam [5:0] TX_DESC_WR_PTR_OFF = `DMA_TX_DESC_WR_PTR;
localparam [5:0] TX_DESC_STATUS_OFF = `DMA_TX_DESC_STATUS;
localparam [5:0] TX_DESC_ERR_CNT_OFF = `DMA_TX_DESC_ERR_CNT;

reg [31:0] tx_desc_ctrl    [0:`DMA_MAX_CH-1];
reg [31:0] tx_desc_base_l  [0:`DMA_MAX_CH-1];
reg [31:0] tx_desc_base_h  [0:`DMA_MAX_CH-1];
reg [31:0] tx_desc_size    [0:`DMA_MAX_CH-1];
reg [31:0] tx_desc_rd_ptr  [0:`DMA_MAX_CH-1];
reg [31:0] tx_desc_wr_ptr  [0:`DMA_MAX_CH-1];
reg [31:0] tx_desc_status  [0:`DMA_MAX_CH-1];
reg [31:0] tx_desc_err_cnt [0:`DMA_MAX_CH-1];
reg [`DMA_MAX_CH-1:0] tx_ch_busy_flat_q;
reg        csr_cmd_valid_q;
reg [CH_W-1:0] csr_cmd_ch_q;
reg [5:0]  csr_cmd_off_q;
reg [31:0] csr_cmd_wdata_q;
reg [3:0]  csr_cmd_wstrb_q;
reg        csr_cmd_busy_q;
reg        csr_rd_pending_q;
reg [CH_W-1:0] csr_rd_ch_q;
reg [5:0]  csr_rd_off_q;
reg        tx_desc_ctx_pending_q;
reg        tx_desc_ctx_seen_q;
reg [CH_W-1:0] tx_desc_ctx_ch_q;
reg        tx_desc_status_csr_evt_valid_q;
reg [CH_W-1:0] tx_desc_status_csr_evt_ch_q;
reg [7:0]  tx_desc_status_csr_evt_code_q;
reg        tx_desc_status_csr_evt_busy_q;
reg        tx_desc_status_csr_evt_empty_q;
reg        tx_desc_status_desc_evt_valid_q;
reg [CH_W-1:0] tx_desc_status_desc_evt_ch_q;
reg [7:0]  tx_desc_status_desc_evt_code_q;
reg        tx_desc_status_desc_evt_busy_q;
reg        tx_desc_status_desc_evt_empty_q;
reg        tx_desc_err_cnt_csr_evt_valid_q;
reg [CH_W-1:0] tx_desc_err_cnt_csr_evt_ch_q;
reg        tx_desc_err_cnt_desc_evt_valid_q;
reg [CH_W-1:0] tx_desc_err_cnt_desc_evt_ch_q;
reg        tx_desc_err_input_valid_q;
reg [CH_W-1:0] tx_desc_err_input_ch_q;
reg        tx_desc_wr_pending_q;
reg        tx_desc_wr_pending_ok_q;
reg [CH_W-1:0] tx_desc_wr_pending_ch_q;
reg [31:0] tx_desc_wr_pending_ptr_q;
reg [7:0]  tx_desc_wr_pending_code_q;
reg [1:0]  tx_desc_wr_pending_kind_q;

integer i;
genvar gi;

wire [`DMA_MAX_CH-1:0] tx_ch_busy_status_flat =
    HAS_DESC_STATUS_EVENT_LANES ? tx_ch_busy_flat_q : tx_ch_busy_flat;

assign csr_wr_ready = !csr_cmd_valid_q && !tx_desc_wr_pending_q;
assign csr_rd_ready = !csr_rd_pending_q && !csr_rvalid;
assign csr_bresp = 2'b00;

generate
    for (gi = 0; gi < `DMA_MAX_CH; gi = gi + 1) begin : g_summary
        if (gi < `DMA_TX_CH_NUM) begin : g_active
            assign tx_desc_enable_flat[gi] = tx_desc_ctrl[gi][`DMA_TX_DESC_CTRL_ENABLE];
            assign tx_desc_ready_flat[gi] =
                tx_desc_ctrl[gi][`DMA_TX_DESC_CTRL_ENABLE] &&
                tx_desc_ctrl[gi][`DMA_TX_DESC_CTRL_START] &&
                (tx_desc_rd_ptr[gi] != tx_desc_wr_ptr[gi]);
        end else begin : g_inactive
            assign tx_desc_enable_flat[gi] = 1'b0;
            assign tx_desc_ready_flat[gi] = 1'b0;
        end
    end
endgenerate

function [31:0] maybe_counter_data;
    input [31:0] data;
    begin
        maybe_counter_data = HAS_PER_CH_COUNTERS ? data : 32'h0;
    end
endfunction

function [31:0] build_tx_desc_status;
    input [31:0] cur_status;
    input [3:0]  ch;
    input [7:0]  code;
    input        busy_bit;
    input        empty_bit;
    reg [31:0]   next_status;
    begin
        next_status = cur_status;
        next_status[`DMA_TX_DESC_STATUS_IDLE] = !busy_bit;
        next_status[`DMA_TX_DESC_STATUS_BUSY] = busy_bit;
        next_status[`DMA_TX_DESC_STATUS_EMPTY] = empty_bit;
        next_status[23:16] = code;
        if (code == `DMA_ST_TX_DESC_FETCH_ERR)
            next_status[`DMA_TX_DESC_STATUS_FETCH_ERR] = 1'b1;
        if (code == `DMA_ST_TX_DESC_OWNER_ERR)
            next_status[`DMA_TX_DESC_STATUS_OWNER_ERR] = 1'b1;
        if (code == `DMA_ST_TX_DESC_LEN_ERR)
            next_status[`DMA_TX_DESC_STATUS_LEN_ERR] = 1'b1;
        if (code == `DMA_ST_TX_DESC_ADDR_ERR)
            next_status[`DMA_TX_DESC_STATUS_ADDR_ERR] = 1'b1;
        if (code == `DMA_ST_TX_DESC_RING_ERR)
            next_status[`DMA_TX_DESC_STATUS_RING_ERR] = 1'b1;
        if (code == `DMA_ST_AXI_READ_ERR)
            next_status[`DMA_TX_DESC_STATUS_PAYLOAD_READ_ERR] = 1'b1;
        if (code == `DMA_ST_TX_STOPPED)
            next_status[`DMA_TX_DESC_STATUS_STOPPED] = 1'b1;
        next_status[31:24] = {4'h0, ch};
        build_tx_desc_status = next_status;
    end
endfunction

function [31:0] build_tx_desc_read_status;
    input [CH_W-1:0] ch;
    begin
        build_tx_desc_read_status = build_tx_desc_status(
            tx_desc_status[ch],
            ch[3:0],
            tx_desc_status[ch][23:16],
            tx_ch_busy_status_flat[ch],
            (tx_desc_rd_ptr[ch] == tx_desc_wr_ptr[ch])
        );
    end
endfunction

function [31:0] read_desc_reg;
    input [CH_W-1:0] ch;
    input [5:0]      off;
    begin
        read_desc_reg = 32'h0;
        case (off)
        TX_DESC_CTRL_OFF:    read_desc_reg = tx_desc_ctrl[ch];
        TX_DESC_BASE_L_OFF:  read_desc_reg = tx_desc_base_l[ch];
        TX_DESC_BASE_H_OFF:  read_desc_reg = tx_desc_base_h[ch];
        TX_DESC_SIZE_OFF:    read_desc_reg = tx_desc_size[ch];
        TX_DESC_RD_PTR_OFF:  read_desc_reg = tx_desc_rd_ptr[ch];
        TX_DESC_WR_PTR_OFF:  read_desc_reg = tx_desc_wr_ptr[ch];
        TX_DESC_STATUS_OFF:  read_desc_reg = build_tx_desc_read_status(ch);
        TX_DESC_ERR_CNT_OFF: read_desc_reg = maybe_counter_data(tx_desc_err_cnt[ch]);
        default:             read_desc_reg = 32'h0;
        endcase
    end
endfunction

function [31:0] next_desc_ctrl;
    input [31:0] cur_ctrl;
    input [31:0] wr_data;
    input        busy_at_accept;
    reg [31:0]   next_ctrl;
    begin
        next_ctrl = cur_ctrl;
        next_ctrl[`DMA_TX_DESC_CTRL_IRQ_EN] = wr_data[`DMA_TX_DESC_CTRL_IRQ_EN];
        if (!busy_at_accept) begin
            next_ctrl[`DMA_TX_DESC_CTRL_ENABLE] = wr_data[`DMA_TX_DESC_CTRL_ENABLE];
            next_ctrl[`DMA_TX_DESC_CTRL_START] = wr_data[`DMA_TX_DESC_CTRL_START];
        end else if (wr_data[`DMA_TX_DESC_CTRL_STOP]) begin
            next_ctrl[`DMA_TX_DESC_CTRL_STOP] = 1'b1;
        end
        next_desc_ctrl = next_ctrl;
    end
endfunction

task reset_all_channels;
    integer ch;
    begin
        for (ch = 0; ch < `DMA_MAX_CH; ch = ch + 1) begin
            tx_desc_ctrl[ch] <= 32'h0;
            tx_desc_base_l[ch] <= 32'h0;
            tx_desc_base_h[ch] <= 32'h0;
            tx_desc_size[ch] <= 32'h0;
            tx_desc_rd_ptr[ch] <= 32'h0;
            tx_desc_wr_ptr[ch] <= 32'h0;
            tx_desc_status[ch] <= 32'h5;
            tx_desc_err_cnt[ch] <= 32'h0;
        end
    end
endtask

task reset_one_channel;
    input integer ch;
    begin
        tx_desc_ctrl[ch] <= 32'h0;
        tx_desc_rd_ptr[ch] <= 32'h0;
        tx_desc_wr_ptr[ch] <= 32'h0;
        tx_desc_status[ch] <= 32'h5;
        tx_desc_err_cnt[ch] <= 32'h0;
    end
endtask

task update_csr_status;
    input [CH_W-1:0] ch;
    input [7:0]      code;
    input            busy_bit;
    input            empty_bit;
    begin
        if (HAS_DESC_STATUS_EVENT_LANES) begin
            tx_desc_status_csr_evt_valid_q <= 1'b1;
            tx_desc_status_csr_evt_ch_q <= ch;
            tx_desc_status_csr_evt_code_q <= code;
            tx_desc_status_csr_evt_busy_q <= busy_bit;
            tx_desc_status_csr_evt_empty_q <= empty_bit;
        end else begin
            tx_desc_status[ch] <= build_tx_desc_status(
                tx_desc_status[ch],
                ch[3:0],
                code,
                busy_bit,
                empty_bit
            );
        end
    end
endtask

task update_desc_status;
    input [CH_W-1:0] ch;
    input [7:0]      code;
    input            busy_bit;
    input            empty_bit;
    begin
        if (HAS_DESC_STATUS_EVENT_LANES) begin
            tx_desc_status_desc_evt_valid_q <= 1'b1;
            tx_desc_status_desc_evt_ch_q <= ch;
            tx_desc_status_desc_evt_code_q <= code;
            tx_desc_status_desc_evt_busy_q <= busy_bit;
            tx_desc_status_desc_evt_empty_q <= empty_bit;
        end else begin
            tx_desc_status[ch] <= build_tx_desc_status(
                tx_desc_status[ch],
                ch[3:0],
                code,
                busy_bit,
                empty_bit
            );
        end
    end
endtask

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        csr_wr_rsp_valid <= 1'b0;
        csr_wr_rsp_kind <= CSR_WR_RSP_NONE;
        csr_wr_rsp_code <= 8'h0;
        csr_rvalid <= 1'b0;
        csr_rdata <= 32'h0;
        csr_rresp <= 2'b00;
        csr_cmd_valid_q <= 1'b0;
        csr_cmd_ch_q <= {CH_W{1'b0}};
        csr_cmd_off_q <= 6'h0;
        csr_cmd_wdata_q <= 32'h0;
        csr_cmd_wstrb_q <= 4'h0;
        csr_cmd_busy_q <= 1'b0;
        csr_rd_pending_q <= 1'b0;
        csr_rd_ch_q <= {CH_W{1'b0}};
        csr_rd_off_q <= 6'h0;
        tx_desc_ctx_pending_q <= 1'b0;
        tx_desc_ctx_seen_q <= 1'b0;
        tx_desc_ctx_ch_q <= {CH_W{1'b0}};
        tx_desc_ctx_valid <= 1'b0;
        tx_desc_ctx_ctrl <= 32'h0;
        tx_desc_ctx_base_l <= 32'h0;
        tx_desc_ctx_base_h <= 32'h0;
        tx_desc_ctx_size <= 32'h0;
        tx_desc_ctx_rd_ptr <= 32'h0;
        tx_desc_ctx_wr_ptr <= 32'h0;
        tx_desc_ctx_status <= 32'h0;
        tx_desc_ctx_err_cnt <= 32'h0;
        tx_desc_active_stop <= 1'b0;
        tx_ch_busy_flat_q <= {`DMA_MAX_CH{1'b0}};
        tx_desc_status_csr_evt_valid_q <= 1'b0;
        tx_desc_status_csr_evt_ch_q <= {CH_W{1'b0}};
        tx_desc_status_csr_evt_code_q <= 8'h0;
        tx_desc_status_csr_evt_busy_q <= 1'b0;
        tx_desc_status_csr_evt_empty_q <= 1'b0;
        tx_desc_status_desc_evt_valid_q <= 1'b0;
        tx_desc_status_desc_evt_ch_q <= {CH_W{1'b0}};
        tx_desc_status_desc_evt_code_q <= 8'h0;
        tx_desc_status_desc_evt_busy_q <= 1'b0;
        tx_desc_status_desc_evt_empty_q <= 1'b0;
        tx_desc_err_cnt_csr_evt_valid_q <= 1'b0;
        tx_desc_err_cnt_csr_evt_ch_q <= {CH_W{1'b0}};
        tx_desc_err_cnt_desc_evt_valid_q <= 1'b0;
        tx_desc_err_cnt_desc_evt_ch_q <= {CH_W{1'b0}};
        tx_desc_err_input_valid_q <= 1'b0;
        tx_desc_err_input_ch_q <= {CH_W{1'b0}};
        tx_desc_wr_pending_q <= 1'b0;
        tx_desc_wr_pending_ok_q <= 1'b0;
        tx_desc_wr_pending_ch_q <= {CH_W{1'b0}};
        tx_desc_wr_pending_ptr_q <= 32'h0;
        tx_desc_wr_pending_code_q <= 8'h0;
        tx_desc_wr_pending_kind_q <= CSR_WR_RSP_NONE;
        reset_all_channels();
    end else begin
        csr_wr_rsp_valid <= 1'b0;
        csr_wr_rsp_kind <= CSR_WR_RSP_NONE;
        csr_wr_rsp_code <= 8'h0;

        if (global_soft_reset) begin
            csr_rvalid <= 1'b0;
            csr_rdata <= 32'h0;
            csr_rresp <= 2'b00;
            csr_cmd_valid_q <= 1'b0;
            csr_cmd_ch_q <= {CH_W{1'b0}};
            csr_cmd_off_q <= 6'h0;
            csr_cmd_wdata_q <= 32'h0;
            csr_cmd_wstrb_q <= 4'h0;
            csr_cmd_busy_q <= 1'b0;
            csr_rd_pending_q <= 1'b0;
            csr_rd_ch_q <= {CH_W{1'b0}};
            csr_rd_off_q <= 6'h0;
            tx_desc_ctx_pending_q <= 1'b0;
            tx_desc_ctx_seen_q <= 1'b0;
            tx_desc_ctx_ch_q <= {CH_W{1'b0}};
            tx_desc_ctx_valid <= 1'b0;
            tx_desc_ctx_ctrl <= 32'h0;
            tx_desc_ctx_base_l <= 32'h0;
            tx_desc_ctx_base_h <= 32'h0;
            tx_desc_ctx_size <= 32'h0;
            tx_desc_ctx_rd_ptr <= 32'h0;
            tx_desc_ctx_wr_ptr <= 32'h0;
            tx_desc_ctx_status <= 32'h0;
            tx_desc_ctx_err_cnt <= 32'h0;
            tx_desc_active_stop <= 1'b0;
            tx_ch_busy_flat_q <= {`DMA_MAX_CH{1'b0}};
            tx_desc_status_csr_evt_valid_q <= 1'b0;
            tx_desc_status_csr_evt_ch_q <= {CH_W{1'b0}};
            tx_desc_status_csr_evt_code_q <= 8'h0;
            tx_desc_status_csr_evt_busy_q <= 1'b0;
            tx_desc_status_csr_evt_empty_q <= 1'b0;
            tx_desc_status_desc_evt_valid_q <= 1'b0;
            tx_desc_status_desc_evt_ch_q <= {CH_W{1'b0}};
            tx_desc_status_desc_evt_code_q <= 8'h0;
            tx_desc_status_desc_evt_busy_q <= 1'b0;
            tx_desc_status_desc_evt_empty_q <= 1'b0;
            tx_desc_err_cnt_csr_evt_valid_q <= 1'b0;
            tx_desc_err_cnt_csr_evt_ch_q <= {CH_W{1'b0}};
            tx_desc_err_cnt_desc_evt_valid_q <= 1'b0;
            tx_desc_err_cnt_desc_evt_ch_q <= {CH_W{1'b0}};
            tx_desc_err_input_valid_q <= 1'b0;
            tx_desc_err_input_ch_q <= {CH_W{1'b0}};
            tx_desc_wr_pending_q <= 1'b0;
            tx_desc_wr_pending_ok_q <= 1'b0;
            tx_desc_wr_pending_ch_q <= {CH_W{1'b0}};
            tx_desc_wr_pending_ptr_q <= 32'h0;
            tx_desc_wr_pending_code_q <= 8'h0;
            tx_desc_wr_pending_kind_q <= CSR_WR_RSP_NONE;
            reset_all_channels();
        end else begin
            csr_rvalid <= 1'b0;
            csr_rresp <= 2'b00;
            tx_desc_ctx_valid <= 1'b0;
            tx_desc_active_stop <= tx_desc_active_valid &&
                                   tx_desc_ctrl[tx_desc_active_ch][`DMA_TX_DESC_CTRL_STOP];

            for (i = 0; i < `DMA_MAX_CH; i = i + 1) begin
                if (tx_desc_ch_reset_mask[i]) begin
                    reset_one_channel(i);
                    if (tx_desc_err_cnt_csr_evt_valid_q &&
                        (tx_desc_err_cnt_csr_evt_ch_q == i[CH_W-1:0]))
                        tx_desc_err_cnt_csr_evt_valid_q <= 1'b0;
                    if (tx_desc_err_cnt_desc_evt_valid_q &&
                        (tx_desc_err_cnt_desc_evt_ch_q == i[CH_W-1:0]))
                        tx_desc_err_cnt_desc_evt_valid_q <= 1'b0;
                    if (tx_desc_err_input_valid_q &&
                        (tx_desc_err_input_ch_q == i[CH_W-1:0]))
                        tx_desc_err_input_valid_q <= 1'b0;
                end
            end

            tx_ch_busy_flat_q <= tx_ch_busy_flat;

            if (csr_rd_pending_q) begin
                csr_rvalid <= 1'b1;
                csr_rdata <= read_desc_reg(csr_rd_ch_q, csr_rd_off_q);
                csr_rresp <= 2'b00;
                csr_rd_pending_q <= 1'b0;
            end
            if (csr_rd_valid && csr_rd_ready) begin
                csr_rd_pending_q <= 1'b1;
                csr_rd_ch_q <= csr_rd_ch;
                csr_rd_off_q <= csr_rd_off;
            end

            if (tx_desc_ctx_pending_q) begin
                tx_desc_ctx_valid <= 1'b1;
                tx_desc_ctx_ctrl <= tx_desc_ctrl[tx_desc_ctx_ch_q];
                tx_desc_ctx_base_l <= tx_desc_base_l[tx_desc_ctx_ch_q];
                tx_desc_ctx_base_h <= tx_desc_base_h[tx_desc_ctx_ch_q];
                tx_desc_ctx_size <= tx_desc_size[tx_desc_ctx_ch_q];
                tx_desc_ctx_rd_ptr <= tx_desc_rd_ptr[tx_desc_ctx_ch_q];
                tx_desc_ctx_wr_ptr <= tx_desc_wr_ptr[tx_desc_ctx_ch_q];
                tx_desc_ctx_status <= build_tx_desc_read_status(tx_desc_ctx_ch_q);
                tx_desc_ctx_err_cnt <= maybe_counter_data(tx_desc_err_cnt[tx_desc_ctx_ch_q]);
                tx_desc_ctx_pending_q <= 1'b0;
            end
            if (!tx_desc_ctx_req) begin
                tx_desc_ctx_seen_q <= 1'b0;
            end else if (!tx_desc_ctx_seen_q && !tx_desc_ctx_pending_q) begin
                tx_desc_ctx_pending_q <= 1'b1;
                tx_desc_ctx_ch_q <= tx_desc_ctx_ch;
                tx_desc_ctx_seen_q <= 1'b1;
            end
            if (HAS_DESC_STATUS_EVENT_LANES) begin
                for (i = 0; i < `DMA_MAX_CH; i = i + 1) begin
                    if (!tx_desc_ch_reset_mask[i]) begin
                        if (tx_desc_status_csr_evt_valid_q &&
                            (tx_desc_status_csr_evt_ch_q == i[CH_W-1:0])) begin
                            tx_desc_status[i] <= build_tx_desc_status(
                                tx_desc_status[i],
                                i[3:0],
                                tx_desc_status_csr_evt_code_q,
                                tx_desc_status_csr_evt_busy_q,
                                tx_desc_status_csr_evt_empty_q
                            );
                        end
                        if (tx_desc_status_desc_evt_valid_q &&
                            (tx_desc_status_desc_evt_ch_q == i[CH_W-1:0])) begin
                            tx_desc_status[i] <= build_tx_desc_status(
                                tx_desc_status[i],
                                i[3:0],
                                tx_desc_status_desc_evt_code_q,
                                tx_desc_status_desc_evt_busy_q,
                                tx_desc_status_desc_evt_empty_q
                            );
                        end
                    end
                end
            end
            tx_desc_status_csr_evt_valid_q <= 1'b0;
            tx_desc_status_desc_evt_valid_q <= 1'b0;

            if (HAS_PER_CH_COUNTERS) begin
                if (tx_desc_err_cnt_csr_evt_valid_q &&
                    !tx_desc_ch_reset_mask[tx_desc_err_cnt_csr_evt_ch_q]) begin
                    tx_desc_err_cnt[tx_desc_err_cnt_csr_evt_ch_q] <=
                        tx_desc_err_cnt[tx_desc_err_cnt_csr_evt_ch_q] + 1'b1;
                end
                if (tx_desc_err_cnt_desc_evt_valid_q &&
                    !tx_desc_ch_reset_mask[tx_desc_err_cnt_desc_evt_ch_q] &&
                    !(tx_desc_err_cnt_csr_evt_valid_q &&
                      (tx_desc_err_cnt_csr_evt_ch_q == tx_desc_err_cnt_desc_evt_ch_q) &&
                      !tx_desc_ch_reset_mask[tx_desc_err_cnt_csr_evt_ch_q])) begin
                    tx_desc_err_cnt[tx_desc_err_cnt_desc_evt_ch_q] <=
                        tx_desc_err_cnt[tx_desc_err_cnt_desc_evt_ch_q] + 1'b1;
                end
            end
            tx_desc_err_cnt_csr_evt_valid_q <= 1'b0;
            tx_desc_err_cnt_desc_evt_valid_q <= tx_desc_err_input_valid_q;
            tx_desc_err_cnt_desc_evt_ch_q <= tx_desc_err_input_ch_q;
            tx_desc_err_input_valid_q <= 1'b0;
            tx_desc_err_input_ch_q <= {CH_W{1'b0}};

            if (tx_desc_wr_pending_q) begin
                csr_wr_rsp_valid <= 1'b1;
                tx_desc_wr_pending_q <= 1'b0;
                if (tx_desc_wr_pending_ok_q) begin
                    tx_desc_wr_ptr[tx_desc_wr_pending_ch_q] <= tx_desc_wr_pending_ptr_q;
                    update_csr_status(
                        tx_desc_wr_pending_ch_q,
                        tx_desc_status[tx_desc_wr_pending_ch_q][23:16],
                        1'b0,
                        (tx_desc_rd_ptr[tx_desc_wr_pending_ch_q] == tx_desc_wr_pending_ptr_q)
                    );
                end else if (tx_desc_wr_pending_kind_q == CSR_WR_RSP_RING) begin
                    update_csr_status(
                        tx_desc_wr_pending_ch_q,
                        tx_desc_wr_pending_code_q,
                        1'b0,
                        (tx_desc_rd_ptr[tx_desc_wr_pending_ch_q] ==
                         tx_desc_wr_ptr[tx_desc_wr_pending_ch_q])
                    );
                    if (HAS_PER_CH_COUNTERS &&
                        !tx_desc_ch_reset_mask[tx_desc_wr_pending_ch_q]) begin
                        tx_desc_err_cnt_csr_evt_valid_q <= 1'b1;
                        tx_desc_err_cnt_csr_evt_ch_q <= tx_desc_wr_pending_ch_q;
                    end
                    csr_wr_rsp_kind <= CSR_WR_RSP_RING;
                    csr_wr_rsp_code <= tx_desc_wr_pending_code_q;
                end else begin
                    csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
                    csr_wr_rsp_code <= tx_desc_wr_pending_code_q;
                end
            end

            if (csr_cmd_valid_q) begin
                csr_wr_rsp_valid <= (csr_cmd_off_q != TX_DESC_WR_PTR_OFF);
                csr_cmd_valid_q <= 1'b0;
                case (csr_cmd_off_q)
                TX_DESC_CTRL_OFF: begin
                    if (csr_cmd_wdata_q[`DMA_TX_DESC_CTRL_RESET]) begin
                        if (csr_cmd_busy_q) begin
                            csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
                            csr_wr_rsp_code <= `DMA_ST_CFG_PROTECT_ERR;
                        end else begin
                            reset_one_channel(csr_cmd_ch_q);
                        end
                    end else begin
                        tx_desc_ctrl[csr_cmd_ch_q] <= next_desc_ctrl(
                            tx_desc_ctrl[csr_cmd_ch_q], csr_cmd_wdata_q, csr_cmd_busy_q);
                        update_csr_status(
                            csr_cmd_ch_q,
                            tx_desc_status[csr_cmd_ch_q][23:16],
                            csr_cmd_busy_q,
                            (tx_desc_rd_ptr[csr_cmd_ch_q] == tx_desc_wr_ptr[csr_cmd_ch_q])
                        );
                    end
                end
                TX_DESC_BASE_L_OFF: begin
                    if (!tx_desc_ctrl[csr_cmd_ch_q][`DMA_TX_DESC_CTRL_ENABLE] && !csr_cmd_busy_q) begin
                        if (csr_cmd_wdata_q[5:0] == 6'h0)
                            tx_desc_base_l[csr_cmd_ch_q] <= csr_cmd_wdata_q;
                        else begin
                            update_csr_status(
                                csr_cmd_ch_q,
                                `DMA_ST_TX_DESC_RING_ERR,
                                csr_cmd_busy_q,
                                (tx_desc_rd_ptr[csr_cmd_ch_q] == tx_desc_wr_ptr[csr_cmd_ch_q])
                            );
                            if (HAS_PER_CH_COUNTERS && !tx_desc_ch_reset_mask[csr_cmd_ch_q]) begin
                                tx_desc_err_cnt_csr_evt_valid_q <= 1'b1;
                                tx_desc_err_cnt_csr_evt_ch_q <= csr_cmd_ch_q;
                            end
                            csr_wr_rsp_kind <= CSR_WR_RSP_RING;
                            csr_wr_rsp_code <= `DMA_ST_TX_DESC_RING_ERR;
                        end
                    end else begin
                        csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
                        csr_wr_rsp_code <= `DMA_ST_CFG_PROTECT_ERR;
                    end
                end
                TX_DESC_BASE_H_OFF: begin
                    if (!tx_desc_ctrl[csr_cmd_ch_q][`DMA_TX_DESC_CTRL_ENABLE] && !csr_cmd_busy_q) begin
                        if (csr_cmd_wdata_q == 32'h0)
                            tx_desc_base_h[csr_cmd_ch_q] <= csr_cmd_wdata_q;
                        else begin
                            update_csr_status(
                                csr_cmd_ch_q,
                                `DMA_ST_TX_DESC_RING_ERR,
                                csr_cmd_busy_q,
                                (tx_desc_rd_ptr[csr_cmd_ch_q] == tx_desc_wr_ptr[csr_cmd_ch_q])
                            );
                            if (HAS_PER_CH_COUNTERS && !tx_desc_ch_reset_mask[csr_cmd_ch_q]) begin
                                tx_desc_err_cnt_csr_evt_valid_q <= 1'b1;
                                tx_desc_err_cnt_csr_evt_ch_q <= csr_cmd_ch_q;
                            end
                            csr_wr_rsp_kind <= CSR_WR_RSP_RING;
                            csr_wr_rsp_code <= `DMA_ST_TX_DESC_RING_ERR;
                        end
                    end else begin
                        csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
                        csr_wr_rsp_code <= `DMA_ST_CFG_PROTECT_ERR;
                    end
                end
                TX_DESC_SIZE_OFF: begin
                    if (!tx_desc_ctrl[csr_cmd_ch_q][`DMA_TX_DESC_CTRL_ENABLE] && !csr_cmd_busy_q) begin
                        if ((csr_cmd_wdata_q != 32'h0) && (csr_cmd_wdata_q[5:0] == 6'h0))
                            tx_desc_size[csr_cmd_ch_q] <= csr_cmd_wdata_q;
                        else begin
                            update_csr_status(
                                csr_cmd_ch_q,
                                `DMA_ST_TX_DESC_RING_ERR,
                                csr_cmd_busy_q,
                                (tx_desc_rd_ptr[csr_cmd_ch_q] == tx_desc_wr_ptr[csr_cmd_ch_q])
                            );
                            if (HAS_PER_CH_COUNTERS && !tx_desc_ch_reset_mask[csr_cmd_ch_q]) begin
                                tx_desc_err_cnt_csr_evt_valid_q <= 1'b1;
                                tx_desc_err_cnt_csr_evt_ch_q <= csr_cmd_ch_q;
                            end
                            csr_wr_rsp_kind <= CSR_WR_RSP_RING;
                            csr_wr_rsp_code <= `DMA_ST_TX_DESC_RING_ERR;
                        end
                    end else begin
                        csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
                        csr_wr_rsp_code <= `DMA_ST_CFG_PROTECT_ERR;
                    end
                end
                TX_DESC_WR_PTR_OFF: begin
                    tx_desc_wr_pending_q <= 1'b1;
                    tx_desc_wr_pending_ch_q <= csr_cmd_ch_q;
                    tx_desc_wr_pending_ptr_q <= csr_cmd_wdata_q;
                    if (!tx_desc_ctrl[csr_cmd_ch_q][`DMA_TX_DESC_CTRL_ENABLE] && !csr_cmd_busy_q &&
                        (tx_desc_size[csr_cmd_ch_q] != 32'h0) &&
                        (csr_cmd_wdata_q[5:0] == 6'h0) &&
                        (csr_cmd_wdata_q < tx_desc_size[csr_cmd_ch_q])) begin
                        tx_desc_wr_pending_ok_q <= 1'b1;
                        tx_desc_wr_pending_code_q <= 8'h0;
                        tx_desc_wr_pending_kind_q <= CSR_WR_RSP_NONE;
                    end else if (!tx_desc_ctrl[csr_cmd_ch_q][`DMA_TX_DESC_CTRL_ENABLE] &&
                                 !csr_cmd_busy_q) begin
                        tx_desc_wr_pending_ok_q <= 1'b0;
                        tx_desc_wr_pending_code_q <= `DMA_ST_TX_DESC_RING_ERR;
                        tx_desc_wr_pending_kind_q <= CSR_WR_RSP_RING;
                    end else begin
                        tx_desc_wr_pending_ok_q <= 1'b0;
                        tx_desc_wr_pending_code_q <= `DMA_ST_CFG_PROTECT_ERR;
                        tx_desc_wr_pending_kind_q <= CSR_WR_RSP_PROTECT;
                    end
                end
                TX_DESC_RD_PTR_OFF,
                TX_DESC_STATUS_OFF,
                TX_DESC_ERR_CNT_OFF: begin
                end
                default: begin
                    csr_wr_rsp_kind <= CSR_WR_RSP_PROTECT;
                    csr_wr_rsp_code <= `DMA_ST_ILLEGAL_REG_WRITE;
                end
                endcase
            end

            if (tx_desc_evt_valid) begin
                if (tx_desc_evt_update_rd_ptr)
                    tx_desc_rd_ptr[tx_desc_evt_ch] <= tx_desc_evt_rd_ptr;
                if (tx_desc_evt_update_status) begin
                    update_desc_status(
                        tx_desc_evt_ch,
                        tx_desc_evt_status_code,
                        tx_desc_evt_set_busy && !tx_desc_evt_clear_busy,
                        ((tx_desc_evt_update_rd_ptr ? tx_desc_evt_rd_ptr : tx_desc_rd_ptr[tx_desc_evt_ch]) ==
                         tx_desc_wr_ptr[tx_desc_evt_ch])
                    );
                    if (tx_desc_evt_status_code == `DMA_ST_TX_STOPPED) begin
                        tx_desc_ctrl[tx_desc_evt_ch] <=
                            tx_desc_ctrl[tx_desc_evt_ch] &
                            ~((32'h1 << `DMA_TX_DESC_CTRL_START) |
                              (32'h1 << `DMA_TX_DESC_CTRL_STOP));
                    end
                end
                if (HAS_PER_CH_COUNTERS && tx_desc_evt_inc_err && !tx_desc_ch_reset_mask[tx_desc_evt_ch]) begin
                    tx_desc_err_input_valid_q <= 1'b1;
                    tx_desc_err_input_ch_q <= tx_desc_evt_ch;
                end
            end

            if (csr_wr_valid && csr_wr_ready) begin
                csr_cmd_valid_q <= 1'b1;
                csr_cmd_ch_q <= csr_wr_ch;
                csr_cmd_off_q <= csr_wr_off;
                csr_cmd_wdata_q <= csr_wdata;
                csr_cmd_wstrb_q <= csr_wstrb;
                csr_cmd_busy_q <= tx_ch_busy_flat[csr_wr_ch];
            end
        end
    end
end

endmodule
