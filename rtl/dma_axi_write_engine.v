`timescale 1ns/1ps
`include "dma_defs.vh"

// RX payload/CQE 的 AXI4 写引擎。它把 frame word 流转换成受 4KB 边界和
// outstanding 限制约束的 burst，并分别跟踪 AW、W、B 的进度；写错误通过
// 完成事件返回上层，不能把已发出的事务静默丢掉。
module dma_axi_write_engine #(
    parameter integer INDEX_WIDTH = 9,
    parameter integer MAX_OUTSTANDING = `DMA_RX_WR_MAX_OUTSTANDING
)(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             cmd_valid,
    output            cmd_ready,
    input      [31:0] cmd_addr,
    input      [31:0] cmd_len,
    output reg        done,
    output reg        error,
    output reg        rd_req,
    output reg [INDEX_WIDTH-1:0] rd_index,
    input             rd_valid,
    input      [63:0] rd_data,
    output reg [31:0] m_axi_awaddr,
    output reg [7:0]  m_axi_awlen,
    output reg [2:0]  m_axi_awsize,
    output reg [1:0]  m_axi_awburst,
    output reg        m_axi_awvalid,
    input             m_axi_awready,
    output reg [63:0] m_axi_wdata,
    output reg [7:0]  m_axi_wstrb,
    output reg        m_axi_wlast,
    output reg        m_axi_wvalid,
    input             m_axi_wready,
    input      [1:0]  m_axi_bresp,
    input             m_axi_bvalid,
    output reg        m_axi_bready,
    output            busy
);

function integer clog2;
    input integer value;
    integer tmp;
    begin
        tmp = value - 1;
        clog2 = 0;
        while (tmp > 0) begin
            tmp = tmp >> 1;
            clog2 = clog2 + 1;
        end
    end
endfunction

// burst queue 记录已发出但尚未完成的写事务，深度略大于配置上限以容纳边界拆分。
localparam integer BURSTQ_USED_DEPTH = (MAX_OUTSTANDING < 2) ? 2 : (MAX_OUTSTANDING + 2);
localparam integer BURSTQ_AW = clog2(BURSTQ_USED_DEPTH);
localparam integer BURSTQ_DEPTH = (1 << BURSTQ_AW);
localparam integer MAX_BURST_BYTES = `DMA_MAX_BURST_LEN * 8;
localparam HAS_AW_PLAN_PIPELINE = (`DMA_ENABLE_AXI_WRITE_AW_PLAN_PIPELINE != 0);
localparam HAS_W_PREFETCH_FIFO = (`DMA_ENABLE_AXI_WRITE_W_PREFETCH_FIFO != 0);
localparam HAS_FRAME_SHARED_RD_REQ_QUEUE = (`DMA_ENABLE_FRAME_SHARED_RD_REQ_QUEUE != 0);
localparam integer W_PREFETCH_FIFO_DEPTH = 16;
localparam integer W_PREFETCH_FIFO_AW = clog2(W_PREFETCH_FIFO_DEPTH);
localparam [W_PREFETCH_FIFO_AW:0] W_PREFETCH_FIFO_DEPTH_C = W_PREFETCH_FIFO_DEPTH;
localparam [W_PREFETCH_FIFO_AW:0] W_PREFETCH_START_LEVEL_C = 8;
localparam [3:0] W_PREFETCH_RD_OUTSTANDING_LIMIT = 4'd4;
localparam [3:0] W_PREFETCH_BLOCK_START_OUTSTANDING_LIMIT = 4'd0;

reg                 active;
reg                 issue_blocked;
reg                 error_seen;
reg [31:0]          issue_addr;
reg [31:0]          issue_bytes_left;
reg [INDEX_WIDTH-1:0] next_word_index;
reg                 aw_plan_valid_q;
reg [31:0]          aw_plan_addr_q;
reg [7:0]           aw_plan_words_q;
reg [31:0]          aw_plan_bytes_q;

reg [7:0]           burst_words_q [0:BURSTQ_DEPTH-1];
reg [31:0]          burst_bytes_q [0:BURSTQ_DEPTH-1];
reg [BURSTQ_AW-1:0] burstq_wr_ptr;
reg [BURSTQ_AW-1:0] burstq_rd_ptr;
reg [BURSTQ_AW:0]   burstq_count;

reg                 w_active;
reg [7:0]           w_burst_words;
reg [31:0]          w_burst_bytes;
reg [7:0]           w_beat_index;
reg                 rd_waiting;
reg [63:0]          w_fifo_data [0:W_PREFETCH_FIFO_DEPTH-1];
reg [7:0]           w_fifo_strb [0:W_PREFETCH_FIFO_DEPTH-1];
reg                 w_fifo_last [0:W_PREFETCH_FIFO_DEPTH-1];
reg [W_PREFETCH_FIFO_AW-1:0] w_fifo_wr_ptr;
reg [W_PREFETCH_FIFO_AW-1:0] w_fifo_rd_ptr;
reg [W_PREFETCH_FIFO_AW:0]   w_fifo_count;
reg [63:0]          w_fifo_head_data_q;
reg [7:0]           w_fifo_head_strb_q;
reg                 w_fifo_head_last_q;
reg                 prefetch_active;
reg [7:0]           prefetch_burst_words;
reg [31:0]          prefetch_burst_bytes;
reg [7:0]           prefetch_issue_count;
reg [7:0]           prefetch_return_count;
reg [INDEX_WIDTH-1:0] prefetch_word_index;
reg [3:0]           prefetch_rd_outstanding_count;
reg                 prefetch_block_wait;
reg [3:0]           prefetch_block_wait_count;
reg                 prefetch_output_enabled;
reg [7:0]           w_pending_burst_count;

reg [7:0]           aw_pend_words;
reg [31:0]          aw_pend_bytes;
reg [7:0]           b_outstanding_count;

reg [7:0]           debug_outstanding_count;
reg [7:0]           debug_peak_outstanding;

reg [31:0]          burst_words_c;
reg [31:0]          words_to_4k_c;
reg [31:0]          burst_bytes_c;
reg [31:0]          bytes_this_beat_c;
reg [31:0]          prefetch_bytes_this_beat_c;

wire aw_push = m_axi_awvalid && m_axi_awready;
wire b_pop = m_axi_bvalid && m_axi_bready;
wire w_last_push = m_axi_wvalid && m_axi_wready && m_axi_wlast;
wire legacy_burstq_pop = !w_active && (burstq_count != 0) && !m_axi_wvalid && !rd_waiting && !aw_push;
wire prefetch_burstq_pop = !prefetch_active && (burstq_count != 0) && !aw_push;
wire burstq_pop = HAS_W_PREFETCH_FIFO ? prefetch_burstq_pop : legacy_burstq_pop;
wire [7:0] w_pending_slots = HAS_W_PREFETCH_FIFO ? w_pending_burst_count : (w_active ? 8'd1 : 8'd0);
wire [7:0] outstanding_slots = burstq_count + w_pending_slots + b_outstanding_count;
wire [31:0] bytes_to_4k_fast_c = 32'd4096 - {20'h0, issue_addr[11:0]};
wire [31:0] words_to_4k_fast_c = bytes_to_4k_fast_c >> 3;
wire [31:0] bytes_to_4k_aligned_fast_c =
    (words_to_4k_fast_c == 0) ? 32'd8 : (words_to_4k_fast_c << 3);
wire [31:0] aw_pend_limit_bytes_fast_c =
    (bytes_to_4k_aligned_fast_c < MAX_BURST_BYTES) ? bytes_to_4k_aligned_fast_c : MAX_BURST_BYTES;
wire [31:0] aw_pend_bytes_fast_c =
    (issue_bytes_left < aw_pend_limit_bytes_fast_c) ? issue_bytes_left : aw_pend_limit_bytes_fast_c;
wire aw_plan_busy = HAS_AW_PLAN_PIPELINE && aw_plan_valid_q;
wire can_make_aw_plan = HAS_AW_PLAN_PIPELINE &&
    active && !issue_blocked && !error_seen &&
    !aw_plan_valid_q && !m_axi_awvalid &&
    (issue_bytes_left != 0);
wire can_issue_aw_plan = HAS_AW_PLAN_PIPELINE &&
    aw_plan_valid_q && !m_axi_awvalid &&
    active && !issue_blocked && !error_seen &&
    (outstanding_slots < MAX_OUTSTANDING) &&
    (burstq_count < BURSTQ_DEPTH-1);
wire prefetch_resp = HAS_W_PREFETCH_FIFO && (prefetch_rd_outstanding_count != 0) && rd_valid;
wire [3:0] prefetch_outstanding_after_resp =
    prefetch_rd_outstanding_count - {3'b000, prefetch_resp};
wire prefetch_block_wait_resp =
    prefetch_resp && prefetch_block_wait && (prefetch_block_wait_count != 0);
wire [3:0] prefetch_block_wait_count_after_resp =
    prefetch_block_wait_count - {3'b000, prefetch_block_wait_resp};
wire prefetch_block_wait_after_resp =
    prefetch_block_wait && !(prefetch_block_wait_resp && (prefetch_block_wait_count <= 4'd1));
wire prefetch_block_wait_guard =
    !HAS_FRAME_SHARED_RD_REQ_QUEUE && prefetch_block_wait_after_resp;
wire prefetch_active_after_resp =
    prefetch_active && !(prefetch_resp && (prefetch_return_count == (prefetch_burst_words - 1'b1)));
wire prefetch_final_drain_after_resp =
    !prefetch_active_after_resp &&
    (prefetch_outstanding_after_resp == 0) &&
    (w_pending_burst_count != 0) &&
    (issue_bytes_left == 0) &&
    !m_axi_awvalid &&
    !aw_plan_busy &&
    (burstq_count == 0);
wire prefetch_w_reg_ready = HAS_W_PREFETCH_FIFO && (!m_axi_wvalid || m_axi_wready);
wire prefetch_output_take = HAS_W_PREFETCH_FIFO && prefetch_output_enabled && prefetch_w_reg_ready;
wire prefetch_fifo_pop = prefetch_output_take && (w_fifo_count != 0);
wire prefetch_resp_to_output = 1'b0;
wire prefetch_fifo_push = prefetch_resp && !prefetch_resp_to_output;
wire [W_PREFETCH_FIFO_AW-1:0] w_fifo_rd_ptr_next = w_fifo_rd_ptr + 1'b1;
wire [W_PREFETCH_FIFO_AW:0] w_fifo_count_after_io =
    w_fifo_count +
    {{W_PREFETCH_FIFO_AW{1'b0}}, prefetch_fifo_push} -
    {{W_PREFETCH_FIFO_AW{1'b0}}, prefetch_fifo_pop};
wire prefetch_output_start =
    !prefetch_output_enabled &&
    ((w_fifo_count_after_io >= W_PREFETCH_START_LEVEL_C) || prefetch_final_drain_after_resp);
wire prefetch_output_stop =
    prefetch_output_enabled &&
    !prefetch_final_drain_after_resp &&
    ((prefetch_fifo_pop && (w_fifo_count_after_io == 0)) ||
     ((w_fifo_count == 0) && prefetch_fifo_push));
wire [W_PREFETCH_FIFO_AW:0] prefetch_reserved_after_resp =
    w_fifo_count_after_io + {{(W_PREFETCH_FIFO_AW-3){1'b0}}, prefetch_outstanding_after_resp};
wire prefetch_next_is_block_start = (prefetch_word_index[2:0] == 3'b000);
wire prefetch_block_start_safe =
    HAS_FRAME_SHARED_RD_REQ_QUEUE ||
    !prefetch_next_is_block_start ||
    (!prefetch_block_wait_guard &&
     (prefetch_outstanding_after_resp <= W_PREFETCH_BLOCK_START_OUTSTANDING_LIMIT));
wire prefetch_can_issue = HAS_W_PREFETCH_FIFO &&
    prefetch_active &&
    (prefetch_issue_count < prefetch_burst_words) &&
    !prefetch_block_wait_guard &&
    prefetch_block_start_safe &&
    (prefetch_outstanding_after_resp < W_PREFETCH_RD_OUTSTANDING_LIMIT) &&
    (prefetch_reserved_after_resp < W_PREFETCH_FIFO_DEPTH_C);
wire prefetch_start_can_issue = HAS_W_PREFETCH_FIFO &&
    burstq_pop &&
    (burst_words_q[burstq_rd_ptr] != 0) &&
    !prefetch_block_wait_guard &&
    prefetch_block_start_safe &&
    (prefetch_outstanding_after_resp < W_PREFETCH_RD_OUTSTANDING_LIMIT) &&
    (prefetch_reserved_after_resp < W_PREFETCH_FIFO_DEPTH_C);
wire write_path_idle = HAS_W_PREFETCH_FIFO ?
    (!prefetch_active && (prefetch_rd_outstanding_count == 0) && (w_fifo_count == 0) && (w_pending_burst_count == 0)) :
    (!w_active && !rd_waiting);

assign cmd_ready = !busy;
assign busy = active || m_axi_awvalid || aw_plan_busy || m_axi_wvalid ||
              (HAS_W_PREFETCH_FIFO ?
                  (prefetch_active || (prefetch_rd_outstanding_count != 0) || (w_fifo_count != 0) || (w_pending_burst_count != 0)) :
                  (rd_waiting || w_active)) ||
              (burstq_count != 0) || (b_outstanding_count != 0);

initial begin
    if (`DMA_MAX_BURST_LEN > 256)
        $fatal(1, "DMA_MAX_BURST_LEN must be <= 256");
    if (`DMA_MAX_BURST_LEN != 16)
        $fatal(1, "DMA baseline expects DMA_MAX_BURST_LEN default 16");
    if (MAX_OUTSTANDING < 1)
        $fatal(1, "RX write MAX_OUTSTANDING must be >= 1");
end

function [7:0] wstrb_for_bytes;
    input [31:0] bytes;
    begin
        case (bytes)
        32'd0: wstrb_for_bytes = 8'h00;
        32'd1: wstrb_for_bytes = 8'h01;
        32'd2: wstrb_for_bytes = 8'h03;
        32'd3: wstrb_for_bytes = 8'h07;
        32'd4: wstrb_for_bytes = 8'h0f;
        32'd5: wstrb_for_bytes = 8'h1f;
        32'd6: wstrb_for_bytes = 8'h3f;
        32'd7: wstrb_for_bytes = 8'h7f;
        default: wstrb_for_bytes = 8'hff;
        endcase
    end
endfunction

always @(*) begin
    burst_words_c = (issue_bytes_left + 32'd7) >> 3;
    if (burst_words_c > `DMA_MAX_BURST_LEN)
        burst_words_c = `DMA_MAX_BURST_LEN;
    words_to_4k_c = (32'd4096 - {20'h0, issue_addr[11:0]}) >> 3;
    if (words_to_4k_c == 0)
        words_to_4k_c = 32'd1;
    if (burst_words_c > words_to_4k_c)
        burst_words_c = words_to_4k_c;
    if (burst_words_c == 0)
        burst_words_c = 32'd1;
    burst_bytes_c = burst_words_c << 3;
    if (issue_bytes_left < burst_bytes_c)
        burst_bytes_c = issue_bytes_left;

    bytes_this_beat_c = 32'h0;
    if (w_active && (w_burst_bytes > {21'h0, w_beat_index, 3'b000})) begin
        bytes_this_beat_c = w_burst_bytes - {21'h0, w_beat_index, 3'b000};
        if (bytes_this_beat_c > 8)
            bytes_this_beat_c = 8;
    end

    prefetch_bytes_this_beat_c = 32'h0;
    if (prefetch_active && (prefetch_burst_bytes > {21'h0, prefetch_return_count, 3'b000})) begin
        prefetch_bytes_this_beat_c = prefetch_burst_bytes - {21'h0, prefetch_return_count, 3'b000};
        if (prefetch_bytes_this_beat_c > 8)
            prefetch_bytes_this_beat_c = 8;
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        active <= 1'b0;
        issue_blocked <= 1'b0;
        error_seen <= 1'b0;
        issue_addr <= 32'h0;
        issue_bytes_left <= 32'h0;
        next_word_index <= {INDEX_WIDTH{1'b0}};
        aw_plan_valid_q <= 1'b0;
        aw_plan_addr_q <= 32'h0;
        aw_plan_words_q <= 8'h0;
        aw_plan_bytes_q <= 32'h0;
        burstq_wr_ptr <= {BURSTQ_AW{1'b0}};
        burstq_rd_ptr <= {BURSTQ_AW{1'b0}};
        burstq_count <= {(BURSTQ_AW+1){1'b0}};
        w_active <= 1'b0;
        w_burst_words <= 8'h0;
        w_burst_bytes <= 32'h0;
        w_beat_index <= 8'h0;
        rd_waiting <= 1'b0;
        w_fifo_wr_ptr <= {W_PREFETCH_FIFO_AW{1'b0}};
        w_fifo_rd_ptr <= {W_PREFETCH_FIFO_AW{1'b0}};
        w_fifo_count <= {(W_PREFETCH_FIFO_AW+1){1'b0}};
        prefetch_active <= 1'b0;
        prefetch_burst_words <= 8'h0;
        prefetch_burst_bytes <= 32'h0;
        prefetch_issue_count <= 8'h0;
        prefetch_return_count <= 8'h0;
        prefetch_word_index <= {INDEX_WIDTH{1'b0}};
        prefetch_rd_outstanding_count <= 4'h0;
        prefetch_block_wait <= 1'b0;
        prefetch_block_wait_count <= 4'h0;
        prefetch_output_enabled <= 1'b0;
        w_pending_burst_count <= 8'h0;
        aw_pend_words <= 8'h0;
        aw_pend_bytes <= 32'h0;
        b_outstanding_count <= 8'h0;
        debug_outstanding_count <= 8'h0;
        debug_peak_outstanding <= 8'h0;
        done <= 1'b0;
        error <= 1'b0;
        rd_req <= 1'b0;
        rd_index <= {INDEX_WIDTH{1'b0}};
        m_axi_awaddr <= 32'h0;
        m_axi_awlen <= 8'h0;
        m_axi_awsize <= 3'd3;
        m_axi_awburst <= 2'b01;
        m_axi_awvalid <= 1'b0;
        if (!rstn) begin
            m_axi_wdata <= 64'h0;
            m_axi_wstrb <= 8'h0;
            m_axi_wlast <= 1'b0;
        end
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
    end else if (soft_reset) begin
        active <= 1'b0;
        issue_blocked <= 1'b0;
        error_seen <= 1'b0;
        issue_addr <= 32'h0;
        issue_bytes_left <= 32'h0;
        next_word_index <= {INDEX_WIDTH{1'b0}};
        aw_plan_valid_q <= 1'b0;
        aw_plan_addr_q <= 32'h0;
        aw_plan_words_q <= 8'h0;
        aw_plan_bytes_q <= 32'h0;
        burstq_wr_ptr <= {BURSTQ_AW{1'b0}};
        burstq_rd_ptr <= {BURSTQ_AW{1'b0}};
        burstq_count <= {(BURSTQ_AW+1){1'b0}};
        w_active <= 1'b0;
        w_burst_words <= 8'h0;
        w_burst_bytes <= 32'h0;
        w_beat_index <= 8'h0;
        rd_waiting <= 1'b0;
        w_fifo_wr_ptr <= {W_PREFETCH_FIFO_AW{1'b0}};
        w_fifo_rd_ptr <= {W_PREFETCH_FIFO_AW{1'b0}};
        w_fifo_count <= {(W_PREFETCH_FIFO_AW+1){1'b0}};
        prefetch_active <= 1'b0;
        prefetch_burst_words <= 8'h0;
        prefetch_burst_bytes <= 32'h0;
        prefetch_issue_count <= 8'h0;
        prefetch_return_count <= 8'h0;
        prefetch_word_index <= {INDEX_WIDTH{1'b0}};
        prefetch_rd_outstanding_count <= 4'h0;
        prefetch_block_wait <= 1'b0;
        prefetch_block_wait_count <= 4'h0;
        prefetch_output_enabled <= 1'b0;
        w_pending_burst_count <= 8'h0;
        aw_pend_words <= 8'h0;
        aw_pend_bytes <= 32'h0;
        b_outstanding_count <= 8'h0;
        debug_outstanding_count <= 8'h0;
        debug_peak_outstanding <= 8'h0;
        done <= 1'b0;
        error <= 1'b0;
        rd_req <= 1'b0;
        rd_index <= {INDEX_WIDTH{1'b0}};
        m_axi_awaddr <= 32'h0;
        m_axi_awlen <= 8'h0;
        m_axi_awsize <= 3'd3;
        m_axi_awburst <= 2'b01;
        m_axi_awvalid <= 1'b0;
        if (!rstn) begin
            m_axi_wdata <= 64'h0;
            m_axi_wstrb <= 8'h0;
            m_axi_wlast <= 1'b0;
        end
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
    end else begin
        done <= 1'b0;
        error <= 1'b0;
        rd_req <= 1'b0;
        m_axi_bready <= busy;

        if (cmd_valid && cmd_ready) begin
            if (cmd_len == 0) begin
                done <= 1'b1;
            end else begin
                active <= 1'b1;
                issue_blocked <= 1'b0;
                error_seen <= 1'b0;
                issue_addr <= cmd_addr;
                issue_bytes_left <= cmd_len;
                next_word_index <= {INDEX_WIDTH{1'b0}};
                aw_plan_valid_q <= 1'b0;
                aw_plan_addr_q <= 32'h0;
                aw_plan_words_q <= 8'h0;
                aw_plan_bytes_q <= 32'h0;
                burstq_wr_ptr <= {BURSTQ_AW{1'b0}};
                burstq_rd_ptr <= {BURSTQ_AW{1'b0}};
                burstq_count <= {(BURSTQ_AW+1){1'b0}};
                w_active <= 1'b0;
                w_burst_words <= 8'h0;
                w_burst_bytes <= 32'h0;
                w_beat_index <= 8'h0;
                rd_waiting <= 1'b0;
                w_fifo_wr_ptr <= {W_PREFETCH_FIFO_AW{1'b0}};
                w_fifo_rd_ptr <= {W_PREFETCH_FIFO_AW{1'b0}};
                w_fifo_count <= {(W_PREFETCH_FIFO_AW+1){1'b0}};
                prefetch_active <= 1'b0;
                prefetch_burst_words <= 8'h0;
                prefetch_burst_bytes <= 32'h0;
                prefetch_issue_count <= 8'h0;
                prefetch_return_count <= 8'h0;
                prefetch_word_index <= {INDEX_WIDTH{1'b0}};
                prefetch_rd_outstanding_count <= 4'h0;
                prefetch_block_wait <= 1'b0;
                prefetch_block_wait_count <= 4'h0;
                prefetch_output_enabled <= 1'b0;
                w_pending_burst_count <= 8'h0;
                m_axi_awvalid <= 1'b0;
                m_axi_wvalid <= 1'b0;
                m_axi_wlast <= 1'b0;
                debug_outstanding_count <= 8'h0;
                debug_peak_outstanding <= 8'h0;
            end
        end

        if (can_make_aw_plan) begin
            aw_plan_valid_q <= 1'b1;
            aw_plan_addr_q <= issue_addr;
            aw_plan_words_q <= burst_words_c[7:0];
            aw_plan_bytes_q <= aw_pend_bytes_fast_c;
        end

        if (HAS_AW_PLAN_PIPELINE) begin
            if (can_issue_aw_plan) begin
                m_axi_awaddr <= aw_plan_addr_q;
                m_axi_awlen <= aw_plan_words_q - 1'b1;
                m_axi_awsize <= 3'd3;
                m_axi_awburst <= 2'b01;
                m_axi_awvalid <= 1'b1;
                aw_pend_words <= aw_plan_words_q;
                aw_pend_bytes <= aw_plan_bytes_q;
                aw_plan_valid_q <= 1'b0;
            end
        end else if (active && !issue_blocked && !m_axi_awvalid &&
                     (issue_bytes_left != 0) &&
                     (outstanding_slots < MAX_OUTSTANDING) &&
                     (burstq_count < BURSTQ_DEPTH-1)) begin
            m_axi_awaddr <= issue_addr;
            m_axi_awlen <= burst_words_c[7:0] - 1'b1;
            m_axi_awsize <= 3'd3;
            m_axi_awburst <= 2'b01;
            m_axi_awvalid <= 1'b1;
            aw_pend_words <= burst_words_c[7:0];
            aw_pend_bytes <= aw_pend_bytes_fast_c;
        end

        if (aw_push) begin
            m_axi_awvalid <= 1'b0;
            burst_words_q[burstq_wr_ptr] <= aw_pend_words;
            burst_bytes_q[burstq_wr_ptr] <= aw_pend_bytes;
            issue_addr <= issue_addr + (aw_pend_words << 3);
            if (issue_bytes_left > aw_pend_bytes)
                issue_bytes_left <= issue_bytes_left - aw_pend_bytes;
            else
                issue_bytes_left <= 32'h0;
        end

        if (burstq_pop) begin
            if (HAS_W_PREFETCH_FIFO) begin
                prefetch_active <= 1'b1;
                prefetch_burst_words <= burst_words_q[burstq_rd_ptr];
                prefetch_burst_bytes <= burst_bytes_q[burstq_rd_ptr];
                prefetch_issue_count <= 8'h0;
                prefetch_return_count <= 8'h0;
            end else begin
                w_active <= 1'b1;
                w_burst_words <= burst_words_q[burstq_rd_ptr];
                w_burst_bytes <= burst_bytes_q[burstq_rd_ptr];
                w_beat_index <= 8'h0;
            end
        end

        if (aw_push)
            burstq_wr_ptr <= burstq_wr_ptr + 1'b1;
        if (burstq_pop)
            burstq_rd_ptr <= burstq_rd_ptr + 1'b1;
        case ({aw_push, burstq_pop})
        2'b10: burstq_count <= burstq_count + 1'b1;
        2'b01: burstq_count <= burstq_count - 1'b1;
        default: begin end
        endcase

        if (HAS_W_PREFETCH_FIFO) begin
            if (prefetch_resp) begin
                if (prefetch_return_count == (prefetch_burst_words - 1'b1)) begin
                    prefetch_active <= 1'b0;
                    prefetch_return_count <= 8'h0;
                end else begin
                    prefetch_return_count <= prefetch_return_count + 1'b1;
                end
            end

            if (prefetch_fifo_push) begin
                w_fifo_data[w_fifo_wr_ptr] <= rd_data;
                w_fifo_strb[w_fifo_wr_ptr] <= wstrb_for_bytes(prefetch_bytes_this_beat_c);
                w_fifo_last[w_fifo_wr_ptr] <= (prefetch_return_count == (prefetch_burst_words - 1'b1));
                w_fifo_wr_ptr <= w_fifo_wr_ptr + 1'b1;
            end
            if (prefetch_fifo_pop && (w_fifo_count > 1)) begin
                w_fifo_head_data_q <= w_fifo_data[w_fifo_rd_ptr_next];
                w_fifo_head_strb_q <= w_fifo_strb[w_fifo_rd_ptr_next];
                w_fifo_head_last_q <= w_fifo_last[w_fifo_rd_ptr_next];
            end else if (prefetch_fifo_push &&
                         ((w_fifo_count == 0) ||
                          (prefetch_fifo_pop && (w_fifo_count == 1)))) begin
                w_fifo_head_data_q <= rd_data;
                w_fifo_head_strb_q <= wstrb_for_bytes(prefetch_bytes_this_beat_c);
                w_fifo_head_last_q <= (prefetch_return_count == (prefetch_burst_words - 1'b1));
            end
            if (prefetch_fifo_pop)
                w_fifo_rd_ptr <= w_fifo_rd_ptr + 1'b1;
            w_fifo_count <= w_fifo_count_after_io;

            if (prefetch_w_reg_ready) begin
                if (prefetch_output_enabled && (w_fifo_count != 0)) begin
                    m_axi_wdata <= w_fifo_head_data_q;
                    m_axi_wstrb <= w_fifo_head_strb_q;
                    m_axi_wlast <= w_fifo_head_last_q;
                    m_axi_wvalid <= 1'b1;
                end else begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast <= 1'b0;
                end
            end
            if (prefetch_output_start)
                prefetch_output_enabled <= 1'b1;
            else if (prefetch_output_stop)
                prefetch_output_enabled <= 1'b0;

            if (prefetch_start_can_issue || prefetch_can_issue) begin
                rd_req <= 1'b1;
                rd_waiting <= 1'b0;
                rd_index <= prefetch_word_index;
                prefetch_word_index <= prefetch_word_index + 1'b1;
                prefetch_issue_count <= prefetch_start_can_issue ? 8'd1 : (prefetch_issue_count + 1'b1);
                prefetch_rd_outstanding_count <= prefetch_outstanding_after_resp + 1'b1;
                if (prefetch_next_is_block_start) begin
                    prefetch_block_wait <= 1'b1;
                    prefetch_block_wait_count <= prefetch_outstanding_after_resp + 1'b1;
                end else begin
                    prefetch_block_wait <= prefetch_block_wait_after_resp;
                    prefetch_block_wait_count <= prefetch_block_wait_count_after_resp;
                end
            end else begin
                prefetch_rd_outstanding_count <= prefetch_outstanding_after_resp;
                prefetch_block_wait <= prefetch_block_wait_after_resp;
                prefetch_block_wait_count <= prefetch_block_wait_count_after_resp;
            end
        end else begin
            if (w_active && !rd_waiting && !m_axi_wvalid) begin
                rd_req <= 1'b1;
                rd_waiting <= 1'b1;
                rd_index <= next_word_index + w_beat_index;
            end

            if (rd_waiting && rd_valid) begin
                rd_waiting <= 1'b0;
                m_axi_wdata <= rd_data;
                m_axi_wstrb <= wstrb_for_bytes(bytes_this_beat_c);
                m_axi_wlast <= (w_beat_index == (w_burst_words - 1'b1));
                m_axi_wvalid <= 1'b1;
            end

            if (m_axi_wvalid && m_axi_wready) begin
                m_axi_wvalid <= 1'b0;
                if (m_axi_wlast) begin
                    m_axi_wlast <= 1'b0;
                    next_word_index <= next_word_index + w_burst_words;
                    w_active <= 1'b0;
                end else begin
                    w_beat_index <= w_beat_index + 1'b1;
                end
            end
        end

        if (b_pop) begin
            if (m_axi_bresp != 2'b00) begin
                error_seen <= 1'b1;
                issue_blocked <= 1'b1;
                if (HAS_AW_PLAN_PIPELINE) begin
                    aw_plan_valid_q <= 1'b0;
                    aw_plan_addr_q <= 32'h0;
                    aw_plan_words_q <= 8'h0;
                    aw_plan_bytes_q <= 32'h0;
                    if (!m_axi_awvalid)
                        m_axi_awvalid <= 1'b0;
                end
            end
        end

        if (HAS_W_PREFETCH_FIFO) begin
            case ({burstq_pop, w_last_push})
            2'b10: begin
                w_pending_burst_count <= w_pending_burst_count + 1'b1;
            end
            2'b01: begin
                if (w_pending_burst_count != 0)
                    w_pending_burst_count <= w_pending_burst_count - 1'b1;
            end
            default: begin
            end
            endcase
        end

        case ({w_last_push, b_pop})
        2'b10: begin
            b_outstanding_count <= b_outstanding_count + 1'b1;
        end
        2'b01: begin
            if (b_outstanding_count != 0) begin
                b_outstanding_count <= b_outstanding_count - 1'b1;
            end
        end
        default: begin
        end
        endcase

        debug_outstanding_count <= outstanding_slots;
        if (outstanding_slots > debug_peak_outstanding)
            debug_peak_outstanding <= outstanding_slots;

        if (active && !error_seen &&
            (issue_bytes_left == 0) &&
            !m_axi_awvalid &&
            !aw_plan_busy &&
            (burstq_count == 0) &&
            write_path_idle &&
            !m_axi_wvalid &&
            (b_outstanding_count == 0)) begin
            active <= 1'b0;
            done <= 1'b1;
        end else if (active && error_seen &&
                     !m_axi_awvalid &&
                     !aw_plan_busy &&
                     (burstq_count == 0) &&
                     write_path_idle &&
                     !m_axi_wvalid &&
                     (b_outstanding_count == 0)) begin
            active <= 1'b0;
            done <= 1'b1;
            error <= 1'b1;
        end
    end
end

endmodule
