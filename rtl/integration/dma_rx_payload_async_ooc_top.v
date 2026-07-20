`timescale 1ns/1ps

// Synthesis boundary for the optional dual-clock RX payload backend. The
// production frame_dma_rx_top uses the same bridge, serializer, and writers;
// this wrapper exposes only their command/payload/completion and AXI contracts
// so ASIC OOC reports do not include unrelated DMA control logic.
module dma_rx_payload_async_ooc_top #(
    parameter integer MAX_OUTSTANDING = 4
)(
    input               s_clk,
    input               s_aresetn,
    input               s_reset_request,
    input               s_soft_reset,
    output              s_reset_done,
    input               s_cmd_valid,
    output              s_cmd_ready,
    input      [31:0]   s_cmd_addr,
    input      [31:0]   s_cmd_len,
    input      [31:0]   s_cmd_aligned_len,
    input       [3:0]   s_cmd_channel,
    input               s_payload_tvalid,
    output              s_payload_tready,
    input      [511:0]  s_payload_tdata,
    input      [63:0]   s_payload_tkeep,
    input               s_payload_tlast,
    output              s_cpl_valid,
    input               s_cpl_ready,
    output              s_cpl_error,
    output      [3:0]   s_cpl_error_code,
    output      [7:0]   s_cpl_tag,
    output              s_busy,
    output              s_protocol_error,

    input               mem_clk,
    input               mem_aresetn,
    output     [31:0]   m_axi_awaddr,
    output      [7:0]   m_axi_awlen,
    output      [2:0]   m_axi_awsize,
    output      [1:0]   m_axi_awburst,
    output              m_axi_awvalid,
    input               m_axi_awready,
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
    output     [63:0]   m_axi_wdata,
    output      [7:0]   m_axi_wstrb,
`else
    output    [511:0]   m_axi_wdata,
    output     [63:0]   m_axi_wstrb,
`endif
    output              m_axi_wlast,
    output              m_axi_wvalid,
    input               m_axi_wready,
    input       [1:0]   m_axi_bresp,
    input               m_axi_bvalid,
    output              m_axi_bready,
    output              mem_writer_busy
);

wire s_rstn;
wire mem_rstn;
wire mem_soft_reset;
wire mem_cmd_valid;
wire mem_cmd_ready;
wire [31:0] mem_cmd_addr;
wire [31:0] mem_cmd_len;
wire [31:0] mem_cmd_aligned_len;
wire [3:0] mem_cmd_channel;
wire [7:0] mem_cmd_tag;
wire mem_payload_tvalid;
wire mem_payload_tready;
wire [511:0] mem_payload_tdata;
wire [63:0] mem_payload_tkeep;
wire mem_payload_tlast;
wire [5:0] mem_payload_level;
wire writer_cpl_valid;
wire writer_cpl_ready;
wire writer_cpl_error;
wire [3:0] writer_cpl_error_code;
wire bridge_protocol_error;
wire mem_backend_busy;
wire mem_protocol_error;

assign s_protocol_error = bridge_protocol_error;

dma_reset_sync u_source_reset_sync (
    .clk(s_clk), .arstn(s_aresetn), .rstn(s_rstn)
);

dma_reset_sync u_mem_reset_sync (
    .clk(mem_clk), .arstn(mem_aresetn), .rstn(mem_rstn)
);

dma_rx_payload_cdc_bridge #(
    .TAG_WIDTH(8),
    .CMD_FIFO_LOG2(2),
    .PAYLOAD_FIFO_LOG2(5),
    .CPL_FIFO_LOG2(2)
) u_bridge (
    .s_clk(s_clk), .s_rst_n(s_rstn),
    .s_reset_request(s_reset_request), .s_soft_reset(s_soft_reset),
    .s_reset_done(s_reset_done),
    .s_cmd_valid(s_cmd_valid), .s_cmd_ready(s_cmd_ready),
    .s_cmd_addr(s_cmd_addr), .s_cmd_len(s_cmd_len),
    .s_cmd_aligned_len(s_cmd_aligned_len), .s_cmd_channel(s_cmd_channel),
    .s_payload_tvalid(s_payload_tvalid), .s_payload_tready(s_payload_tready),
    .s_payload_tdata(s_payload_tdata), .s_payload_tkeep(s_payload_tkeep),
    .s_payload_tlast(s_payload_tlast),
    .s_cpl_valid(s_cpl_valid), .s_cpl_ready(s_cpl_ready),
    .s_cpl_error(s_cpl_error), .s_cpl_error_code(s_cpl_error_code),
    .s_cpl_tag(s_cpl_tag), .s_busy(s_busy),
    .s_protocol_error(bridge_protocol_error),
    .m_clk(mem_clk), .m_rst_n(mem_rstn),
    .m_backend_busy(mem_backend_busy), .m_protocol_error(mem_protocol_error),
    .m_soft_reset(mem_soft_reset),
    .m_cmd_valid(mem_cmd_valid), .m_cmd_ready(mem_cmd_ready),
    .m_cmd_addr(mem_cmd_addr), .m_cmd_len(mem_cmd_len),
    .m_cmd_aligned_len(mem_cmd_aligned_len),
    .m_cmd_channel(mem_cmd_channel), .m_cmd_tag(mem_cmd_tag),
    .m_payload_tvalid(mem_payload_tvalid),
    .m_payload_tready(mem_payload_tready),
    .m_payload_tdata(mem_payload_tdata), .m_payload_tkeep(mem_payload_tkeep),
    .m_payload_tlast(mem_payload_tlast), .m_payload_level(mem_payload_level),
    .m_cpl_valid(writer_cpl_valid), .m_cpl_ready(writer_cpl_ready),
    .m_cpl_error(writer_cpl_error), .m_cpl_error_code(writer_cpl_error_code)
);

`ifdef DMA_RX_MEM_ASYNC64_PROFILE
wire serializer_tvalid;
wire serializer_tready;
wire [63:0] serializer_tdata;
wire [7:0] serializer_tkeep;
wire serializer_tlast;
wire [3:0] serializer_held_beats;
wire serializer_format_error;
wire serializer_busy;
wire [9:0] serializer_available_beats =
    ({4'h0, mem_payload_level} << 3) + {6'h0, serializer_held_beats};

dma_rx_payload_serializer_512_to_64 u_serializer (
    .clk(mem_clk), .rstn(mem_rstn), .soft_reset(mem_soft_reset),
    .s_tvalid(mem_payload_tvalid), .s_tready(mem_payload_tready),
    .s_tdata(mem_payload_tdata), .s_tkeep(mem_payload_tkeep),
    .s_tlast(mem_payload_tlast),
    .m_tvalid(serializer_tvalid), .m_tready(serializer_tready),
    .m_tdata(serializer_tdata), .m_tkeep(serializer_tkeep),
    .m_tlast(serializer_tlast), .held_beats(serializer_held_beats),
    .format_error(serializer_format_error), .busy(serializer_busy)
);

dma_axi_write_engine_64_stream #(
    .MAX_BURST_BEATS(16), .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_CMD_BYTES(4096), .USE_SOURCE_CREDIT(1)
) u_writer (
    .clk(mem_clk), .rstn(mem_rstn), .soft_reset(mem_soft_reset),
    .cmd_valid(mem_cmd_valid), .cmd_ready(mem_cmd_ready),
    .cmd_addr(mem_cmd_addr), .cmd_len(mem_cmd_len),
    .s_payload_tvalid(serializer_tvalid), .s_payload_tready(serializer_tready),
    .s_payload_tdata(serializer_tdata), .s_payload_tkeep(serializer_tkeep),
    .s_payload_tlast(serializer_tlast),
    .s_payload_level(serializer_available_beats),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .cpl_valid(writer_cpl_valid), .cpl_ready(writer_cpl_ready),
    .cpl_error(writer_cpl_error), .cpl_error_code(writer_cpl_error_code),
    .busy(mem_writer_busy)
);
assign mem_backend_busy = mem_writer_busy || serializer_busy;
assign mem_protocol_error = serializer_format_error;
`else
dma_axi_write_engine_512 #(
    .MAX_BURST_BEATS(16), .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_CMD_BYTES(4096), .USE_SOURCE_CREDIT(0)
) u_writer (
    .clk(mem_clk), .rstn(mem_rstn), .soft_reset(mem_soft_reset),
    .cmd_valid(mem_cmd_valid), .cmd_ready(mem_cmd_ready),
    .cmd_addr(mem_cmd_addr), .cmd_len(mem_cmd_len),
    .s_payload_tvalid(mem_payload_tvalid),
    .s_payload_tready(mem_payload_tready),
    .s_payload_tdata(mem_payload_tdata), .s_payload_tkeep(mem_payload_tkeep),
    .s_payload_tlast(mem_payload_tlast),
    .s_payload_level({2'b00, mem_payload_level}),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .cpl_valid(writer_cpl_valid), .cpl_ready(writer_cpl_ready),
    .cpl_error(writer_cpl_error), .cpl_error_code(writer_cpl_error_code),
    .busy(mem_writer_busy)
);
assign mem_backend_busy = mem_writer_busy;
assign mem_protocol_error = 1'b0;
`endif

endmodule
