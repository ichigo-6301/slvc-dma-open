`timescale 1ns/1ps

// RX payload memory-domain CDC. A committed frame crosses as one command,
// ordered 512-bit payload beats, and one completion. AXI remains entirely in
// the memory clock domain; the bridge never transports AW/W/B independently.
module dma_rx_payload_cdc_bridge #(
    parameter integer TAG_WIDTH = 8,
    parameter integer CMD_FIFO_LOG2 = 2,
    parameter integer PAYLOAD_FIFO_LOG2 = 5,
    parameter integer CPL_FIFO_LOG2 = 2
)(
    input                       s_clk,
    input                       s_rst_n,
    input                       s_soft_reset,

    input                       s_cmd_valid,
    output                      s_cmd_ready,
    input      [31:0]           s_cmd_addr,
    input      [31:0]           s_cmd_len,
    input      [31:0]           s_cmd_aligned_len,
    input      [3:0]            s_cmd_channel,

    input                       s_payload_tvalid,
    output                      s_payload_tready,
    input      [511:0]          s_payload_tdata,
    input      [63:0]           s_payload_tkeep,
    input                       s_payload_tlast,

    output                      s_cpl_valid,
    input                       s_cpl_ready,
    output                      s_cpl_error,
    output     [3:0]            s_cpl_error_code,
    output     [TAG_WIDTH-1:0]  s_cpl_tag,
    output                      s_busy,
    output                      s_protocol_error,

    input                       m_clk,
    input                       m_rst_n,
    output                      m_soft_reset,

    output                      m_cmd_valid,
    input                       m_cmd_ready,
    output     [31:0]           m_cmd_addr,
    output     [31:0]           m_cmd_len,
    output     [31:0]           m_cmd_aligned_len,
    output     [3:0]            m_cmd_channel,
    output     [TAG_WIDTH-1:0]  m_cmd_tag,

    output                      m_payload_tvalid,
    input                       m_payload_tready,
    output     [511:0]          m_payload_tdata,
    output     [63:0]           m_payload_tkeep,
    output                      m_payload_tlast,
    output     [PAYLOAD_FIFO_LOG2:0] m_payload_level,

    input                       m_cpl_valid,
    output                      m_cpl_ready,
    input                       m_cpl_error,
    input      [3:0]            m_cpl_error_code
);

localparam integer CMD_WIDTH = 32 + 32 + 32 + 4 + TAG_WIDTH;
localparam integer PAYLOAD_WIDTH = 512 + 64 + 1;
localparam integer CPL_WIDTH = TAG_WIDTH + 1 + 4;
localparam [3:0] ERR_TAG_MISMATCH = 4'd7;

wire [CMD_WIDTH-1:0] cmd_s_data;
wire [CMD_WIDTH-1:0] cmd_m_data;
wire cmd_fifo_s_ready;
wire cmd_fifo_m_valid;
wire cmd_fifo_m_ready;
wire cmd_fifo_s_full;
wire cmd_fifo_m_empty;
wire [CMD_FIFO_LOG2:0] cmd_fifo_s_level;
wire [CMD_FIFO_LOG2:0] cmd_fifo_m_level;

wire [PAYLOAD_WIDTH-1:0] payload_s_data;
wire [PAYLOAD_WIDTH-1:0] payload_m_data;
wire payload_fifo_s_ready;
wire payload_fifo_m_valid;
wire payload_fifo_m_ready;
wire payload_fifo_s_full;
wire payload_fifo_m_empty;
wire [PAYLOAD_FIFO_LOG2:0] payload_fifo_s_level;
wire [PAYLOAD_FIFO_LOG2:0] payload_fifo_m_level;

wire [CPL_WIDTH-1:0] cpl_s_data;
wire [CPL_WIDTH-1:0] cpl_m_data;
wire [TAG_WIDTH-1:0] cpl_tag_raw;
wire cpl_error_raw;
wire [3:0] cpl_error_code_raw;
wire cpl_fifo_s_ready;
wire cpl_fifo_m_valid;
wire cpl_fifo_m_ready;
wire cpl_fifo_s_full;
wire cpl_fifo_m_empty;
wire [CPL_FIFO_LOG2:0] cpl_fifo_s_level;
wire [CPL_FIFO_LOG2:0] cpl_fifo_m_level;

reg [TAG_WIDTH-1:0] next_tag_q;
reg [TAG_WIDTH-1:0] active_tag_q;
reg source_active_q;
reg source_payload_done_q;
reg source_protocol_error_q;

reg [TAG_WIDTH-1:0] mem_active_tag_q;
reg mem_active_q;
reg mem_protocol_error_q;

reg soft_reset_toggle_q;
(* ASYNC_REG = "TRUE" *) reg soft_reset_sync1_q;
(* ASYNC_REG = "TRUE" *) reg soft_reset_sync2_q;
reg soft_reset_seen_q;

(* ASYNC_REG = "TRUE" *) reg mem_error_sync1_q;
(* ASYNC_REG = "TRUE" *) reg mem_error_sync2_q;

wire s_cmd_fire = s_cmd_valid && s_cmd_ready;
wire s_payload_fire = s_payload_tvalid && s_payload_tready;
wire s_cpl_fire = s_cpl_valid && s_cpl_ready;
wire m_cmd_fire = m_cmd_valid && m_cmd_ready;
wire m_cpl_fire = m_cpl_valid && m_cpl_ready;
wire completion_tag_mismatch = (cpl_tag_raw != active_tag_q);

assign cmd_s_data = {next_tag_q, s_cmd_channel, s_cmd_aligned_len,
                     s_cmd_len, s_cmd_addr};
assign {m_cmd_tag, m_cmd_channel, m_cmd_aligned_len,
        m_cmd_len, m_cmd_addr} = cmd_m_data;

assign payload_s_data = {s_payload_tlast, s_payload_tkeep, s_payload_tdata};
assign {m_payload_tlast, m_payload_tkeep, m_payload_tdata} = payload_m_data;

assign cpl_s_data = {mem_active_tag_q, m_cpl_error, m_cpl_error_code};
assign {cpl_tag_raw, cpl_error_raw, cpl_error_code_raw} = cpl_m_data;
assign s_cpl_tag = cpl_tag_raw;
assign s_cpl_error = completion_tag_mismatch ? 1'b1 : cpl_error_raw;
assign s_cpl_error_code = completion_tag_mismatch ?
                          ERR_TAG_MISMATCH : cpl_error_code_raw;

assign s_cmd_ready = !source_active_q && !s_soft_reset && cmd_fifo_s_ready;
assign s_payload_tready = source_active_q && !source_payload_done_q &&
                          payload_fifo_s_ready;
assign s_cpl_valid = cpl_fifo_m_valid;
assign cpl_fifo_m_ready = s_cpl_ready;
assign s_busy = source_active_q || s_cmd_valid || cpl_fifo_m_valid ||
                (cmd_fifo_s_level != 0) || (payload_fifo_s_level != 0);
assign s_protocol_error = source_protocol_error_q || mem_error_sync2_q;

assign m_cmd_valid = cmd_fifo_m_valid && !mem_active_q && !m_soft_reset;
assign cmd_fifo_m_ready = m_cmd_ready && !mem_active_q && !m_soft_reset;
assign m_payload_tvalid = payload_fifo_m_valid && mem_active_q && !m_soft_reset;
assign payload_fifo_m_ready = m_payload_tready && mem_active_q && !m_soft_reset;
assign m_payload_level = payload_fifo_m_level;
assign m_cpl_ready = mem_active_q && cpl_fifo_s_ready && !m_soft_reset;
assign m_soft_reset = soft_reset_sync2_q ^ soft_reset_seen_q;

dma_async_fifo_tech #(
    .DATA_WIDTH(CMD_WIDTH),
    .DEPTH_LOG2(CMD_FIFO_LOG2)
) u_cmd_fifo (
    .s_clk(s_clk), .s_rst_n(s_rst_n), .s_data(cmd_s_data),
    .s_valid(s_cmd_valid && !source_active_q && !s_soft_reset),
    .s_ready(cmd_fifo_s_ready),
    .s_full(cmd_fifo_s_full), .s_level(cmd_fifo_s_level),
    .m_clk(m_clk), .m_rst_n(m_rst_n), .m_data(cmd_m_data),
    .m_valid(cmd_fifo_m_valid), .m_ready(cmd_fifo_m_ready),
    .m_empty(cmd_fifo_m_empty), .m_level(cmd_fifo_m_level)
);

dma_async_fifo_tech #(
    .DATA_WIDTH(PAYLOAD_WIDTH),
    .DEPTH_LOG2(PAYLOAD_FIFO_LOG2),
    .FIFO_MEMORY_TYPE("block")
) u_payload_fifo (
    .s_clk(s_clk), .s_rst_n(s_rst_n), .s_data(payload_s_data),
    .s_valid(s_payload_tvalid && source_active_q && !source_payload_done_q &&
             !s_soft_reset),
    .s_ready(payload_fifo_s_ready), .s_full(payload_fifo_s_full),
    .s_level(payload_fifo_s_level),
    .m_clk(m_clk), .m_rst_n(m_rst_n), .m_data(payload_m_data),
    .m_valid(payload_fifo_m_valid), .m_ready(payload_fifo_m_ready),
    .m_empty(payload_fifo_m_empty), .m_level(payload_fifo_m_level)
);

dma_async_fifo_tech #(
    .DATA_WIDTH(CPL_WIDTH),
    .DEPTH_LOG2(CPL_FIFO_LOG2)
) u_cpl_fifo (
    .s_clk(m_clk), .s_rst_n(m_rst_n), .s_data(cpl_s_data),
    .s_valid(m_cpl_valid && mem_active_q), .s_ready(cpl_fifo_s_ready),
    .s_full(cpl_fifo_s_full), .s_level(cpl_fifo_s_level),
    .m_clk(s_clk), .m_rst_n(s_rst_n), .m_data(cpl_m_data),
    .m_valid(cpl_fifo_m_valid), .m_ready(cpl_fifo_m_ready),
    .m_empty(cpl_fifo_m_empty), .m_level(cpl_fifo_m_level)
);

always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
        next_tag_q <= {TAG_WIDTH{1'b0}};
        active_tag_q <= {TAG_WIDTH{1'b0}};
        source_active_q <= 1'b0;
        source_payload_done_q <= 1'b0;
        source_protocol_error_q <= 1'b0;
        soft_reset_toggle_q <= 1'b0;
        mem_error_sync1_q <= 1'b0;
        mem_error_sync2_q <= 1'b0;
    end else begin
        mem_error_sync1_q <= mem_protocol_error_q;
        mem_error_sync2_q <= mem_error_sync1_q;

        if (s_soft_reset) begin
            source_active_q <= 1'b0;
            source_payload_done_q <= 1'b0;
            source_protocol_error_q <= 1'b0;
            soft_reset_toggle_q <= ~soft_reset_toggle_q;
        end else begin
            if (s_cmd_fire) begin
                if (source_active_q)
                    source_protocol_error_q <= 1'b1;
                source_active_q <= 1'b1;
                source_payload_done_q <= 1'b0;
                active_tag_q <= next_tag_q;
                next_tag_q <= next_tag_q + 1'b1;
            end

            if (s_payload_fire) begin
                if (!source_active_q || source_payload_done_q)
                    source_protocol_error_q <= 1'b1;
                if (s_payload_tlast)
                    source_payload_done_q <= 1'b1;
            end

            if (s_cpl_fire) begin
                if (!source_active_q || (!source_payload_done_q && !s_cpl_error) ||
                    completion_tag_mismatch)
                    source_protocol_error_q <= 1'b1;
                source_active_q <= 1'b0;
                source_payload_done_q <= 1'b0;
            end
        end
    end
end

always @(posedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        mem_active_tag_q <= {TAG_WIDTH{1'b0}};
        mem_active_q <= 1'b0;
        mem_protocol_error_q <= 1'b0;
        soft_reset_sync1_q <= 1'b0;
        soft_reset_sync2_q <= 1'b0;
        soft_reset_seen_q <= 1'b0;
    end else begin
        soft_reset_sync1_q <= soft_reset_toggle_q;
        soft_reset_sync2_q <= soft_reset_sync1_q;

        if (m_soft_reset) begin
            if (mem_active_q || cmd_fifo_m_valid || payload_fifo_m_valid ||
                m_cpl_valid)
                mem_protocol_error_q <= 1'b1;
            mem_active_q <= 1'b0;
            soft_reset_seen_q <= soft_reset_sync2_q;
        end else begin
            if (m_cmd_fire) begin
                if (mem_active_q)
                    mem_protocol_error_q <= 1'b1;
                mem_active_q <= 1'b1;
                mem_active_tag_q <= m_cmd_tag;
            end
            if (m_cpl_fire) begin
                if (!mem_active_q)
                    mem_protocol_error_q <= 1'b1;
                mem_active_q <= 1'b0;
            end
        end
    end
end

`ifndef SYNTHESIS
always @(posedge s_clk) begin
    if (s_rst_n && s_soft_reset && s_busy)
        $fatal(1, "dma_rx_payload_cdc_bridge soft reset requires idle bridge");
end
always @(posedge m_clk) begin
    if (m_rst_n && m_soft_reset &&
        (mem_active_q || cmd_fifo_m_valid || payload_fifo_m_valid || m_cpl_valid))
        $fatal(1, "dma_rx_payload_cdc_bridge memory soft reset arrived while busy");
end
`endif

endmodule
