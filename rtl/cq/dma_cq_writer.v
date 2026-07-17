`timescale 1ns/1ps
`include "dma_defs.vh"

// Legacy 单来源 CQ writer。它把 64-byte CQE 分成 body 和 owner/valid 字段两次 AXI
// 写入，保证 software 看到 owner 之前，CQE body 已经完整落到内存。
module dma_cq_writer(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             start,
    output            ready,
    input      [31:0] cqe_addr,
    input      [7:0]  status_code,
    input      [3:0]  traffic_class,
    input      [3:0]  policy,
    input      [7:0]  channel_id,
    input      [7:0]  direction,
    input      [15:0] cqe_flags,
    input      [15:0] flow_id,
    input      [15:0] msg_id,
    input      [31:0] payload_addr,
    input      [31:0] payload_len,
    input      [31:0] aligned_len,
    input      [63:0] timestamp,
    input      [31:0] frame_seq,
    input      [31:0] sample_count,
    input      [15:0] drop_count,
    input      [15:0] overflow_count,
    output reg        done,
    output reg        error,
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

// Body-first / owner-last 的状态顺序是 CQ 软件可见性契约，不应由 ready 提前打破。
localparam ST_IDLE     = 3'd0;
localparam ST_BODY_AW  = 3'd1;
localparam ST_BODY_W   = 3'd2;
localparam ST_BODY_B   = 3'd3;
localparam ST_OWNER_AW = 3'd4;
localparam ST_OWNER_W  = 3'd5;
localparam ST_OWNER_B  = 3'd6;

reg [2:0] state;
reg [2:0] idx;
reg [31:0] cqe_addr_q;
reg [63:0] cqe_word [0:7];

assign ready = (state == ST_IDLE);
assign busy = (state != ST_IDLE);

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state <= ST_IDLE;
        idx <= 3'h0;
        done <= 1'b0;
        error <= 1'b0;
        m_axi_awaddr <= 32'h0;
        m_axi_awlen <= 8'h0;
        m_axi_awsize <= 3'd3;
        m_axi_awburst <= 2'b01;
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= 64'h0;
        m_axi_wstrb <= 8'h0;
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        cqe_addr_q <= 32'h0;
    end else if (soft_reset) begin
        state <= ST_IDLE;
        idx <= 3'h0;
        done <= 1'b0;
        error <= 1'b0;
        m_axi_awaddr <= 32'h0;
        m_axi_awlen <= 8'h0;
        m_axi_awsize <= 3'd3;
        m_axi_awburst <= 2'b01;
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= 64'h0;
        m_axi_wstrb <= 8'h0;
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        cqe_addr_q <= 32'h0;
    end else begin
        done <= 1'b0;
        error <= 1'b0;
        case (state)
        ST_IDLE: begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
            if (start) begin
                cqe_addr_q <= cqe_addr;
                cqe_word[0] <= {{8'h0, status_code}, 16'd64, `DMA_CQE_MAGIC};
                cqe_word[1] <= {16'h0000, direction, channel_id, cqe_flags, {4'h0, policy}, {4'h0, traffic_class}};
                cqe_word[2] <= {32'h0, payload_addr};
                cqe_word[3] <= {aligned_len, payload_len};
                cqe_word[4] <= timestamp;
                cqe_word[5] <= {msg_id, flow_id, frame_seq};
                cqe_word[6] <= {32'h0, sample_count};
                cqe_word[7] <= {32'h0000_0001, overflow_count, drop_count};
                idx <= 3'h0;
                state <= ST_BODY_AW;
            end
        end
        ST_BODY_AW: begin
            m_axi_awaddr <= cqe_addr_q;
            m_axi_awlen <= 8'd6;
            m_axi_awsize <= 3'd3;
            m_axi_awburst <= 2'b01;
            m_axi_awvalid <= 1'b1;
            if (m_axi_awvalid && m_axi_awready) begin
                m_axi_awvalid <= 1'b0;
                idx <= 3'h0;
                state <= ST_BODY_W;
            end
        end
        ST_BODY_W: begin
            if (!m_axi_wvalid) begin
                m_axi_wdata <= cqe_word[idx];
                m_axi_wstrb <= 8'hff;
                m_axi_wlast <= (idx == 3'd6);
                m_axi_wvalid <= 1'b1;
            end else if (m_axi_wvalid && m_axi_wready) begin
                m_axi_wvalid <= 1'b0;
                if (idx == 3'd6) begin
                    m_axi_wlast <= 1'b0;
                    m_axi_bready <= 1'b1;
                    state <= ST_BODY_B;
                end else begin
                    idx <= idx + 1'b1;
                end
            end
        end
        ST_BODY_B: begin
            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bready <= 1'b0;
                if (m_axi_bresp != 2'b00) begin
                    error <= 1'b1;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    state <= ST_OWNER_AW;
                end
            end
        end
        ST_OWNER_AW: begin
            m_axi_awaddr <= cqe_addr_q + 32'd56;
            m_axi_awlen <= 8'd0;
            m_axi_awsize <= 3'd3;
            m_axi_awburst <= 2'b01;
            m_axi_awvalid <= 1'b1;
            if (m_axi_awvalid && m_axi_awready) begin
                m_axi_awvalid <= 1'b0;
                state <= ST_OWNER_W;
            end
        end
        ST_OWNER_W: begin
            if (!m_axi_wvalid) begin
                m_axi_wdata <= cqe_word[7];
                m_axi_wstrb <= 8'hff;
                m_axi_wlast <= 1'b1;
                m_axi_wvalid <= 1'b1;
            end else if (m_axi_wvalid && m_axi_wready) begin
                m_axi_wvalid <= 1'b0;
                m_axi_wlast <= 1'b0;
                m_axi_bready <= 1'b1;
                state <= ST_OWNER_B;
            end
        end
        ST_OWNER_B: begin
            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bready <= 1'b0;
                error <= (m_axi_bresp != 2'b00);
                done <= 1'b1;
                state <= ST_IDLE;
            end
        end
        default: state <= ST_IDLE;
        endcase
    end
end

endmodule
