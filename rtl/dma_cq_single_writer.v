`timescale 1ns/1ps
`include "dma_defs.vh"

// RX/TX CQ 请求的共享串行 writer。它先在本地 shadow pointer 上检查 ring 空间，
// 再一次只接受一个来源，最后把完成后的 pointer/commit 事件返回 Core；因此多个
// producer 不会同时发布同一个 CQ slot。
module dma_cq_single_writer(
    input             clk,
    input             rstn,
    input             soft_reset,

    input      [31:0] cq_base_l,
    input      [31:0] cq_size,
    input      [31:0] cq_rd_ptr,
    input      [31:0] cq_wr_ptr_sync,

    input             rx_req_valid,
    output            rx_req_accept,
    input      [3:0]  rx_ch,
    input      [3:0]  rx_tc,
    input      [3:0]  rx_policy,
    input      [15:0] rx_flow_id,
    input      [15:0] rx_msg_id,
    input      [31:0] rx_payload_addr,
    input      [31:0] rx_payload_len,
    input      [31:0] rx_aligned_len,
    input      [63:0] rx_timestamp,
    input      [31:0] rx_frame_seq,
    input      [31:0] rx_sample_count,
    input      [15:0] rx_cqe_flags,
    output reg        rx_done,
    output reg        rx_error,
    output reg        rx_full,

    input             tx_req_valid,
    output            tx_req_accept,
    input      [3:0]  tx_ch,
    input      [3:0]  tx_tc,
    input      [3:0]  tx_policy,
    input      [15:0] tx_flow_id,
    input      [15:0] tx_msg_id,
    input      [31:0] tx_payload_addr,
    input      [31:0] tx_payload_len,
    input      [31:0] tx_aligned_len,
    input      [31:0] tx_frame_seq,
    input      [7:0]  tx_status_code,
    input      [15:0] tx_cqe_flags,
    output reg        tx_done,
    output reg        tx_error,
    output reg        tx_full,

    output reg        cq_commit_valid,
    output reg [31:0] cq_commit_ptr,

    output     [31:0] m_axi_awaddr,
    output     [7:0]  m_axi_awlen,
    output     [2:0]  m_axi_awsize,
    output     [1:0]  m_axi_awburst,
    output            m_axi_awvalid,
    input             m_axi_awready,
    output     [63:0] m_axi_wdata,
    output     [7:0]  m_axi_wstrb,
    output            m_axi_wlast,
    output            m_axi_wvalid,
    input             m_axi_wready,
    input      [1:0]  m_axi_bresp,
    input             m_axi_bvalid,
    output            m_axi_bready,
    output            busy
);

// 请求选择、空间检查、启动和等待分阶段进行，避免 AXI backpressure 改写 shadow state。
localparam ST_IDLE  = 3'd0;
localparam ST_NEXT  = 3'd1;
localparam ST_CHECK = 3'd2;
localparam ST_START = 3'd3;
localparam ST_WAIT  = 3'd4;

reg [2:0] state;
reg cmd_is_tx_q;
reg [31:0] wr_ptr_shadow_q;
reg [31:0] wr_ptr_q;
reg [31:0] rd_ptr_q;
reg [31:0] size_q;
reg [31:0] next_ptr_q;
reg [31:0] cmd_addr_q;
reg [7:0]  cmd_status_code_q;
reg [3:0]  cmd_tc_q;
reg [3:0]  cmd_policy_q;
reg [7:0]  cmd_channel_id_q;
reg [7:0]  cmd_direction_q;
reg [15:0] cmd_cqe_flags_q;
reg [15:0] cmd_flow_id_q;
reg [15:0] cmd_msg_id_q;
reg [31:0] cmd_payload_addr_q;
reg [31:0] cmd_payload_len_q;
reg [31:0] cmd_aligned_len_q;
reg [63:0] cmd_timestamp_q;
reg [31:0] cmd_frame_seq_q;
reg [31:0] cmd_sample_count_q;

wire writer_done;
wire writer_error;
wire writer_busy;
wire writer_start = (state == ST_START);
wire idle_accept_rx = (state == ST_IDLE) && rx_req_valid;
wire idle_accept_tx = (state == ST_IDLE) && !rx_req_valid && tx_req_valid;

assign rx_req_accept = idle_accept_rx;
assign tx_req_accept = idle_accept_tx;
assign busy = (state != ST_IDLE) || writer_busy;

dma_cq_writer u_writer(
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .start(writer_start),
    .ready(),
    .cqe_addr(cmd_addr_q),
    .status_code(cmd_status_code_q),
    .traffic_class(cmd_tc_q),
    .policy(cmd_policy_q),
    .channel_id(cmd_channel_id_q),
    .direction(cmd_direction_q),
    .cqe_flags(cmd_cqe_flags_q),
    .flow_id(cmd_flow_id_q),
    .msg_id(cmd_msg_id_q),
    .payload_addr(cmd_payload_addr_q),
    .payload_len(cmd_payload_len_q),
    .aligned_len(cmd_aligned_len_q),
    .timestamp(cmd_timestamp_q),
    .frame_seq(cmd_frame_seq_q),
    .sample_count(cmd_sample_count_q),
    .drop_count(16'h0),
    .overflow_count(16'h0),
    .done(writer_done),
    .error(writer_error),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .busy(writer_busy)
);

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state <= ST_IDLE;
        cmd_is_tx_q <= 1'b0;
        wr_ptr_shadow_q <= 32'h0;
        wr_ptr_q <= 32'h0;
        rd_ptr_q <= 32'h0;
        size_q <= 32'h0;
        next_ptr_q <= 32'h0;
        cmd_addr_q <= 32'h0;
        cmd_status_code_q <= 8'h0;
        cmd_tc_q <= 4'h0;
        cmd_policy_q <= 4'h0;
        cmd_channel_id_q <= 8'h0;
        cmd_direction_q <= 8'h0;
        cmd_cqe_flags_q <= 16'h0;
        cmd_flow_id_q <= 16'h0;
        cmd_msg_id_q <= 16'h0;
        cmd_payload_addr_q <= 32'h0;
        cmd_payload_len_q <= 32'h0;
        cmd_aligned_len_q <= 32'h0;
        cmd_timestamp_q <= 64'h0;
        cmd_frame_seq_q <= 32'h0;
        cmd_sample_count_q <= 32'h0;
        rx_done <= 1'b0;
        rx_error <= 1'b0;
        rx_full <= 1'b0;
        tx_done <= 1'b0;
        tx_error <= 1'b0;
        tx_full <= 1'b0;
        cq_commit_valid <= 1'b0;
        cq_commit_ptr <= 32'h0;
    end else if (soft_reset) begin
        state <= ST_IDLE;
        cmd_is_tx_q <= 1'b0;
        wr_ptr_shadow_q <= 32'h0;
        wr_ptr_q <= 32'h0;
        rd_ptr_q <= 32'h0;
        size_q <= 32'h0;
        next_ptr_q <= 32'h0;
        cmd_addr_q <= 32'h0;
        cmd_status_code_q <= 8'h0;
        cmd_tc_q <= 4'h0;
        cmd_policy_q <= 4'h0;
        cmd_channel_id_q <= 8'h0;
        cmd_direction_q <= 8'h0;
        cmd_cqe_flags_q <= 16'h0;
        cmd_flow_id_q <= 16'h0;
        cmd_msg_id_q <= 16'h0;
        cmd_payload_addr_q <= 32'h0;
        cmd_payload_len_q <= 32'h0;
        cmd_aligned_len_q <= 32'h0;
        cmd_timestamp_q <= 64'h0;
        cmd_frame_seq_q <= 32'h0;
        cmd_sample_count_q <= 32'h0;
        rx_done <= 1'b0;
        rx_error <= 1'b0;
        rx_full <= 1'b0;
        tx_done <= 1'b0;
        tx_error <= 1'b0;
        tx_full <= 1'b0;
        cq_commit_valid <= 1'b0;
        cq_commit_ptr <= 32'h0;
    end else begin
        rx_done <= 1'b0;
        rx_error <= 1'b0;
        rx_full <= 1'b0;
        tx_done <= 1'b0;
        tx_error <= 1'b0;
        tx_full <= 1'b0;
        cq_commit_valid <= 1'b0;

        case (state)
        ST_IDLE: begin
            if (idle_accept_rx) begin
                cmd_is_tx_q <= 1'b0;
                wr_ptr_q <= wr_ptr_shadow_q;
                rd_ptr_q <= cq_rd_ptr;
                size_q <= cq_size;
                cmd_addr_q <= cq_base_l + (wr_ptr_shadow_q << 6);
                cmd_status_code_q <= `DMA_ST_FRAME_DONE;
                cmd_tc_q <= rx_tc;
                cmd_policy_q <= rx_policy;
                cmd_channel_id_q <= {4'h0, rx_ch};
                cmd_direction_q <= `DMA_CQE_DIR_RX;
                cmd_cqe_flags_q <= rx_cqe_flags;
                cmd_flow_id_q <= rx_flow_id;
                cmd_msg_id_q <= rx_msg_id;
                cmd_payload_addr_q <= rx_payload_addr;
                cmd_payload_len_q <= rx_payload_len;
                cmd_aligned_len_q <= rx_aligned_len;
                cmd_timestamp_q <= rx_timestamp;
                cmd_frame_seq_q <= rx_frame_seq;
                cmd_sample_count_q <= rx_sample_count;
                state <= ST_NEXT;
            end else if (idle_accept_tx) begin
                cmd_is_tx_q <= 1'b1;
                wr_ptr_q <= wr_ptr_shadow_q;
                rd_ptr_q <= cq_rd_ptr;
                size_q <= cq_size;
                cmd_addr_q <= cq_base_l + (wr_ptr_shadow_q << 6);
                cmd_status_code_q <= tx_status_code;
                cmd_tc_q <= tx_tc;
                cmd_policy_q <= tx_policy;
                cmd_channel_id_q <= {4'h0, tx_ch};
                cmd_direction_q <= `DMA_CQE_DIR_TX;
                cmd_cqe_flags_q <= tx_cqe_flags;
                cmd_flow_id_q <= tx_flow_id;
                cmd_msg_id_q <= tx_msg_id;
                cmd_payload_addr_q <= tx_payload_addr;
                cmd_payload_len_q <= tx_payload_len;
                cmd_aligned_len_q <= tx_aligned_len;
                cmd_timestamp_q <= 64'h0;
                cmd_frame_seq_q <= tx_frame_seq;
                cmd_sample_count_q <= 32'h0;
                state <= ST_NEXT;
            end else begin
                wr_ptr_shadow_q <= cq_wr_ptr_sync;
            end
        end
        ST_NEXT: begin
            next_ptr_q <= (wr_ptr_q + 1 >= size_q) ? 32'h0 : (wr_ptr_q + 1);
            state <= ST_CHECK;
        end
        ST_CHECK: begin
            if ((size_q == 32'h0) || (next_ptr_q == rd_ptr_q)) begin
                if (cmd_is_tx_q) begin
                    tx_done <= 1'b1;
                    tx_full <= 1'b1;
                end else begin
                    rx_done <= 1'b1;
                    rx_full <= 1'b1;
                end
                state <= ST_IDLE;
            end else begin
                state <= ST_START;
            end
        end
        ST_START: begin
            state <= ST_WAIT;
        end
        ST_WAIT: begin
            if (writer_done) begin
                if (cmd_is_tx_q) begin
                    tx_done <= 1'b1;
                    tx_error <= writer_error;
                end else begin
                    rx_done <= 1'b1;
                    rx_error <= writer_error;
                end
                if (!writer_error) begin
                    cq_commit_valid <= 1'b1;
                    cq_commit_ptr <= next_ptr_q;
                    wr_ptr_shadow_q <= next_ptr_q;
                end
                state <= ST_IDLE;
            end
        end
        default: state <= ST_IDLE;
        endcase
    end
end

endmodule
