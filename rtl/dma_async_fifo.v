`timescale 1ns/1ps

// 通用双时钟 FIFO：写域和读域分别维护 binary/Gray pointer，并通过两级同步器
// 交换对端 Gray pointer。full/empty 只依据同步后的指针判断，数据 RAM 不清零。
module dma_async_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH_LOG2 = 4,
    parameter integer READ_PIPELINE = 0
)(
    input                       s_clk,
    input                       s_rst_n,
    input      [DATA_WIDTH-1:0] s_data,
    input                       s_valid,
    output                      s_ready,

    input                       m_clk,
    input                       m_rst_n,
    output reg [DATA_WIDTH-1:0] m_data,
    output reg                  m_valid,
    input                       m_ready
);

// PTR_W 多出一位用于区分环回后的 full 与 empty。
localparam integer DEPTH = (1 << DEPTH_LOG2);
localparam integer PTR_W = DEPTH_LOG2 + 1;

`ifndef SYNTHESIS
initial begin
    if (DATA_WIDTH < 1)
        $fatal(1, "dma_async_fifo requires DATA_WIDTH >= 1");
    if (DEPTH_LOG2 < 2)
        $fatal(1, "dma_async_fifo requires DEPTH_LOG2 >= 2");
end
`endif

(* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

reg [PTR_W-1:0] s_wbin;
reg [PTR_W-1:0] s_wgray;
reg [PTR_W-1:0] s_rgray_sync1;
reg [PTR_W-1:0] s_rgray_sync2;

reg [PTR_W-1:0] m_rbin;
reg [PTR_W-1:0] m_rgray;
reg [PTR_W-1:0] m_wgray_sync1;
reg [PTR_W-1:0] m_wgray_sync2;

wire [PTR_W-1:0] s_wbin_next;
wire [PTR_W-1:0] s_wgray_next;
wire [PTR_W-1:0] m_rbin_next;
wire [PTR_W-1:0] m_rgray_next;
wire             s_full;
wire             m_empty;
wire             s_fire;
wire             m_can_load;

function [PTR_W-1:0] bin2gray;
    input [PTR_W-1:0] value;
    begin
        bin2gray = (value >> 1) ^ value;
    end
endfunction

assign s_wbin_next  = s_wbin + 1'b1;
assign s_wgray_next = bin2gray(s_wbin_next);
assign m_rbin_next  = m_rbin + 1'b1;
assign m_rgray_next = bin2gray(m_rbin_next);

assign s_full = (s_wgray_next == {~s_rgray_sync2[PTR_W-1:PTR_W-2], s_rgray_sync2[PTR_W-3:0]});
assign m_empty = (m_rgray == m_wgray_sync2);
assign s_ready = !s_full;
assign s_fire = s_valid && s_ready;
assign m_can_load = (!m_valid || m_ready) && !m_empty;

always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
        s_wbin <= {PTR_W{1'b0}};
        s_wgray <= {PTR_W{1'b0}};
        s_rgray_sync1 <= {PTR_W{1'b0}};
        s_rgray_sync2 <= {PTR_W{1'b0}};
    end else begin
        s_rgray_sync1 <= m_rgray;
        s_rgray_sync2 <= s_rgray_sync1;
        if (s_fire) begin
            mem[s_wbin[DEPTH_LOG2-1:0]] <= s_data;
            s_wbin <= s_wbin_next;
            s_wgray <= s_wgray_next;
        end
    end
end

generate
if (READ_PIPELINE == 0) begin : g_read_direct
    always @(posedge m_clk or negedge m_rst_n) begin
        if (!m_rst_n) begin
            m_rbin <= {PTR_W{1'b0}};
            m_rgray <= {PTR_W{1'b0}};
            m_wgray_sync1 <= {PTR_W{1'b0}};
            m_wgray_sync2 <= {PTR_W{1'b0}};
            m_data <= {DATA_WIDTH{1'b0}};
            m_valid <= 1'b0;
        end else begin
            m_wgray_sync1 <= s_wgray;
            m_wgray_sync2 <= m_wgray_sync1;
            if (m_can_load) begin
                m_data <= mem[m_rbin[DEPTH_LOG2-1:0]];
                m_rbin <= m_rbin_next;
                m_rgray <= m_rgray_next;
                m_valid <= 1'b1;
            end else if (m_valid && m_ready) begin
                m_valid <= 1'b0;
            end
        end
    end
end else begin : g_read_pipeline
    reg [DEPTH_LOG2-1:0] m_rd_addr;
    reg                  m_rd_pending;

    wire                 m_output_accept;
    wire                 m_capture_pending;
    wire                 m_more_after_capture;

    assign m_output_accept = (!m_valid || m_ready);
    assign m_capture_pending = m_rd_pending && m_output_accept;
    assign m_more_after_capture = (m_rgray_next != m_wgray_sync2);

    always @(posedge m_clk or negedge m_rst_n) begin
        if (!m_rst_n) begin
            m_rbin <= {PTR_W{1'b0}};
            m_rgray <= {PTR_W{1'b0}};
            m_wgray_sync1 <= {PTR_W{1'b0}};
            m_wgray_sync2 <= {PTR_W{1'b0}};
            m_rd_addr <= {DEPTH_LOG2{1'b0}};
            m_rd_pending <= 1'b0;
            m_data <= {DATA_WIDTH{1'b0}};
            m_valid <= 1'b0;
        end else begin
            m_wgray_sync1 <= s_wgray;
            m_wgray_sync2 <= m_wgray_sync1;

            if (m_capture_pending) begin
                m_data <= mem[m_rd_addr];
                m_rbin <= m_rbin_next;
                m_rgray <= m_rgray_next;
                m_valid <= 1'b1;

                if (m_more_after_capture) begin
                    m_rd_addr <= m_rbin_next[DEPTH_LOG2-1:0];
                    m_rd_pending <= 1'b1;
                end else begin
                    m_rd_pending <= 1'b0;
                end
            end else begin
                if (!m_rd_pending && !m_empty) begin
                    m_rd_addr <= m_rbin[DEPTH_LOG2-1:0];
                    m_rd_pending <= 1'b1;
                end
                if (m_valid && m_ready) begin
                    m_valid <= 1'b0;
                end
            end
        end
    end
end
endgenerate

endmodule
