`timescale 1ns/1ps

// Technology-neutral asynchronous FIFO boundary. FPGA builds use the generic
// Gray-pointer implementation below; an ASIC profile can replace this wrapper
// with a characterized 1W1R dual-clock memory while preserving the interface.
module dma_async_fifo_tech #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH_LOG2 = 4,
    parameter integer READ_PIPELINE = 0,
    parameter FIFO_MEMORY_TYPE = "auto"
)(
    input                       s_clk,
    input                       s_rst_n,
    input      [DATA_WIDTH-1:0] s_data,
    input                       s_valid,
    output                      s_ready,
    output                      s_full,
    output     [DEPTH_LOG2:0]   s_level,

    input                       m_clk,
    input                       m_rst_n,
    output     [DATA_WIDTH-1:0] m_data,
    output                      m_valid,
    input                       m_ready,
    output                      m_empty,
    output     [DEPTH_LOG2:0]   m_level
);

`ifdef DMA_ASYNC_FIFO_XPM
generate
if (DEPTH_LOG2 >= 4) begin : g_xpm_fifo
    localparam integer FIFO_DEPTH = (1 << DEPTH_LOG2);
    wire xpm_full;
    wire xpm_empty;
    wire xpm_wr_rst_busy;
    wire xpm_rd_rst_busy;
    wire [DEPTH_LOG2:0] xpm_wr_data_count;
    wire [DEPTH_LOG2:0] xpm_rd_data_count;
    wire xpm_overflow;
    wire xpm_underflow;
    wire xpm_reset = !s_rst_n;

    assign s_ready = !xpm_full && !xpm_wr_rst_busy;
    assign s_full = xpm_full;
    assign s_level = xpm_wr_data_count;
    assign m_valid = !xpm_empty && !xpm_rd_rst_busy;
    assign m_empty = xpm_empty;
    assign m_level = xpm_rd_data_count;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE(FIFO_MEMORY_TYPE),
        .ECC_MODE("no_ecc"),
        .RELATED_CLOCKS(0),
        .FIFO_WRITE_DEPTH(FIFO_DEPTH),
        .WRITE_DATA_WIDTH(DATA_WIDTH),
        .WR_DATA_COUNT_WIDTH(DEPTH_LOG2 + 1),
        .PROG_FULL_THRESH(10),
        .FULL_RESET_VALUE(0),
        .USE_ADV_FEATURES("0404"),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .READ_DATA_WIDTH(DATA_WIDTH),
        .RD_DATA_COUNT_WIDTH(DEPTH_LOG2 + 1),
        .PROG_EMPTY_THRESH(10),
        .DOUT_RESET_VALUE("0"),
        .CDC_SYNC_STAGES(2),
        .WAKEUP_TIME(0)
    ) u_xpm_fifo (
        .sleep(1'b0),
        .rst(xpm_reset),
        .wr_clk(s_clk),
        .wr_en(s_valid && s_ready),
        .din(s_data),
        .full(xpm_full),
        .prog_full(),
        .wr_data_count(xpm_wr_data_count),
        .overflow(xpm_overflow),
        .wr_rst_busy(xpm_wr_rst_busy),
        .almost_full(),
        .wr_ack(),
        .rd_clk(m_clk),
        .rd_en(m_valid && m_ready),
        .dout(m_data),
        .empty(xpm_empty),
        .prog_empty(),
        .rd_data_count(xpm_rd_data_count),
        .underflow(xpm_underflow),
        .rd_rst_busy(xpm_rd_rst_busy),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
end else begin : g_small_gray_fifo
    wire [DEPTH_LOG2:0] generic_m_level;

    dma_async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH_LOG2(DEPTH_LOG2),
        .READ_PIPELINE(READ_PIPELINE)
    ) u_fifo (
        .s_clk(s_clk), .s_rst_n(s_rst_n), .s_data(s_data),
        .s_valid(s_valid), .s_ready(s_ready),
        .m_clk(m_clk), .m_rst_n(m_rst_n), .m_data(m_data),
        .m_valid(m_valid), .m_ready(m_ready),
        .s_full(s_full), .m_empty(m_empty), .s_level(s_level),
        .m_level(generic_m_level)
    );
    assign m_level = generic_m_level + {{DEPTH_LOG2{1'b0}}, m_valid};
end
endgenerate
`else
wire [DEPTH_LOG2:0] generic_m_level;

dma_async_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH_LOG2(DEPTH_LOG2),
    .READ_PIPELINE(READ_PIPELINE)
) u_fifo (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_data(s_data),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_data(m_data),
    .m_valid(m_valid),
    .m_ready(m_ready),
    .s_full(s_full),
    .m_empty(m_empty),
    .s_level(s_level),
    .m_level(generic_m_level)
);

assign m_level = generic_m_level + {{DEPTH_LOG2{1'b0}}, m_valid};
`endif

endmodule
