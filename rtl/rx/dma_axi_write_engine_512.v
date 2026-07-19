`timescale 1ns/1ps

// Optional same-clock RX payload writer for a dedicated 512-bit AXI4 master.
// Commands describe one complete, already committed frame. Accepted AW bursts
// are queued independently from W data so address and response backpressure do
// not couple directly into the frame source. The source remains locked by the
// owner of the command until completion is accepted.
module dma_axi_write_engine_512 #(
    parameter integer MAX_BURST_BEATS = 16,
    parameter integer MAX_OUTSTANDING = 4,
    parameter integer MAX_CMD_BYTES = 1048576
)(
    input               clk,
    input               rstn,
    input               soft_reset,

    input               cmd_valid,
    output              cmd_ready,
    input      [31:0]   cmd_addr,
    input      [31:0]   cmd_len,

    input               s_payload_tvalid,
    output              s_payload_tready,
    input      [511:0]  s_payload_tdata,
    input      [63:0]   s_payload_tkeep,
    input               s_payload_tlast,

    output reg [31:0]   m_axi_awaddr,
    output reg [7:0]    m_axi_awlen,
    output reg [2:0]    m_axi_awsize,
    output reg [1:0]    m_axi_awburst,
    output reg          m_axi_awvalid,
    input               m_axi_awready,

    output reg [511:0]  m_axi_wdata,
    output reg [63:0]   m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input               m_axi_wready,

    input      [1:0]    m_axi_bresp,
    input               m_axi_bvalid,
    output              m_axi_bready,

    output reg          cpl_valid,
    input               cpl_ready,
    output reg          cpl_error,
    output reg [3:0]    cpl_error_code,
    output              busy
);

localparam [3:0] ERR_NONE          = 4'd0;
localparam [3:0] ERR_UNALIGNED     = 4'd1;
localparam [3:0] ERR_LENGTH        = 4'd2;
localparam [3:0] ERR_SOURCE_FORMAT = 4'd3;
localparam [3:0] ERR_AXI_SLVERR    = 4'd4;
localparam [3:0] ERR_AXI_DECERR    = 4'd5;
localparam [3:0] ERR_AXI_RESPONSE  = 4'd6;

reg          active_q;
reg          error_seen_q;
reg [3:0]    error_code_q;
reg [31:0]   issue_addr_q;
reg [31:0]   issue_beats_left_q;
reg [31:0]   source_bytes_left_q;
reg [31:0]   total_beats_q;
reg [31:0]   w_beats_accepted_q;

reg [7:0]    aw_plan_beats_q;

// The plan queue contains only AW bursts already accepted by the slave. This
// makes WLAST independent of AWREADY and permits several B responses in flight.
reg [7:0]    plan_beats_mem [0:MAX_OUTSTANDING-1];
reg [7:0]    plan_wr_ptr_q;
reg [7:0]    plan_rd_ptr_q;
reg [7:0]    plan_count_q;
reg          w_burst_active_q;
reg [7:0]    w_burst_beats_left_q;
reg [7:0]    outstanding_count_q;

reg [31:0]   plan_beats_to_4k_c;
reg [31:0]   plan_beats_c;

wire cmd_fire = cmd_valid && cmd_ready;
wire aw_fire = m_axi_awvalid && m_axi_awready;
wire w_fire = m_axi_wvalid && m_axi_wready;
wire b_fire = m_axi_bvalid && m_axi_bready;
wire cpl_fire = cpl_valid && cpl_ready;
wire w_output_ready = !m_axi_wvalid || m_axi_wready;
wire source_fire = s_payload_tvalid && s_payload_tready;
wire source_last_expected = (source_bytes_left_q <= 32'd64);
wire [63:0] source_keep_expected = keep_for_bytes(source_bytes_left_q);
wire plan_pop_start = active_q && !w_burst_active_q && (plan_count_q != 0);
wire plan_pop_continue = source_fire && (w_burst_beats_left_q == 1) &&
                         (plan_count_q != 0);
wire plan_pop = plan_pop_start || plan_pop_continue;

assign cmd_ready = !active_q && !cpl_valid;
assign busy = active_q || cpl_valid;
assign s_payload_tready = active_q && w_burst_active_q && w_output_ready &&
                          (source_bytes_left_q != 0);
assign m_axi_bready = active_q && (outstanding_count_q != 0);

function [7:0] plan_ptr_next;
    input [7:0] ptr;
    begin
        if (ptr == MAX_OUTSTANDING-1)
            plan_ptr_next = 8'd0;
        else
            plan_ptr_next = ptr + 1'b1;
    end
endfunction

function [63:0] keep_for_bytes;
    input [31:0] bytes;
    integer i;
    begin
        keep_for_bytes = 64'h0;
        for (i = 0; i < 64; i = i + 1) begin
            if (i < bytes)
                keep_for_bytes[i] = 1'b1;
        end
    end
endfunction

always @(*) begin
    plan_beats_to_4k_c = (32'd4096 - {20'h0, issue_addr_q[11:0]}) >> 6;
    if (plan_beats_to_4k_c == 0)
        plan_beats_to_4k_c = 32'd64;

    plan_beats_c = issue_beats_left_q;
    if (plan_beats_c > MAX_BURST_BEATS)
        plan_beats_c = MAX_BURST_BEATS;
    if (plan_beats_c > plan_beats_to_4k_c)
        plan_beats_c = plan_beats_to_4k_c;
    if (plan_beats_c == 0)
        plan_beats_c = 32'd1;

end

initial begin
    if ((MAX_BURST_BEATS < 1) || (MAX_BURST_BEATS > 256))
        $fatal(1, "dma_axi_write_engine_512 MAX_BURST_BEATS must be 1..256");
    if ((MAX_OUTSTANDING < 1) || (MAX_OUTSTANDING > 255))
        $fatal(1, "dma_axi_write_engine_512 MAX_OUTSTANDING must be 1..255");
    if (MAX_CMD_BYTES < 4096)
        $fatal(1, "dma_axi_write_engine_512 MAX_CMD_BYTES must cover 4096 bytes");
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        active_q <= 1'b0;
        error_seen_q <= 1'b0;
        error_code_q <= ERR_NONE;
        issue_addr_q <= 32'h0;
        issue_beats_left_q <= 32'h0;
        source_bytes_left_q <= 32'h0;
        total_beats_q <= 32'h0;
        w_beats_accepted_q <= 32'h0;
        aw_plan_beats_q <= 8'h0;
        plan_wr_ptr_q <= 8'h0;
        plan_rd_ptr_q <= 8'h0;
        plan_count_q <= 8'h0;
        w_burst_active_q <= 1'b0;
        w_burst_beats_left_q <= 8'h0;
        outstanding_count_q <= 8'h0;
        m_axi_awaddr <= 32'h0;
        m_axi_awlen <= 8'h0;
        m_axi_awsize <= 3'd6;
        m_axi_awburst <= 2'b01;
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= 512'h0;
        m_axi_wstrb <= 64'h0;
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        cpl_valid <= 1'b0;
        cpl_error <= 1'b0;
        cpl_error_code <= ERR_NONE;
    end else if (soft_reset) begin
        active_q <= 1'b0;
        error_seen_q <= 1'b0;
        error_code_q <= ERR_NONE;
        issue_addr_q <= 32'h0;
        issue_beats_left_q <= 32'h0;
        source_bytes_left_q <= 32'h0;
        total_beats_q <= 32'h0;
        w_beats_accepted_q <= 32'h0;
        aw_plan_beats_q <= 8'h0;
        plan_wr_ptr_q <= 8'h0;
        plan_rd_ptr_q <= 8'h0;
        plan_count_q <= 8'h0;
        w_burst_active_q <= 1'b0;
        w_burst_beats_left_q <= 8'h0;
        outstanding_count_q <= 8'h0;
        m_axi_awaddr <= 32'h0;
        m_axi_awlen <= 8'h0;
        m_axi_awsize <= 3'd6;
        m_axi_awburst <= 2'b01;
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= 512'h0;
        m_axi_wstrb <= 64'h0;
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        cpl_valid <= 1'b0;
        cpl_error <= 1'b0;
        cpl_error_code <= ERR_NONE;
    end else begin
        if (cpl_fire)
            cpl_valid <= 1'b0;

        if (cmd_fire) begin
            error_seen_q <= 1'b0;
            error_code_q <= ERR_NONE;
            issue_addr_q <= cmd_addr;
            issue_beats_left_q <= (cmd_len + 32'd63) >> 6;
            source_bytes_left_q <= cmd_len;
            total_beats_q <= (cmd_len + 32'd63) >> 6;
            w_beats_accepted_q <= 32'h0;
            plan_wr_ptr_q <= 8'h0;
            plan_rd_ptr_q <= 8'h0;
            plan_count_q <= 8'h0;
            w_burst_active_q <= 1'b0;
            w_burst_beats_left_q <= 8'h0;
            outstanding_count_q <= 8'h0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_wlast <= 1'b0;

            if (cmd_len == 0) begin
                cpl_valid <= 1'b1;
                cpl_error <= 1'b0;
                cpl_error_code <= ERR_NONE;
            end else if (cmd_addr[5:0] != 0) begin
                cpl_valid <= 1'b1;
                cpl_error <= 1'b1;
                cpl_error_code <= ERR_UNALIGNED;
            end else if (cmd_len > MAX_CMD_BYTES) begin
                cpl_valid <= 1'b1;
                cpl_error <= 1'b1;
                cpl_error_code <= ERR_LENGTH;
            end else begin
                active_q <= 1'b1;
            end
        end

        if (active_q) begin
            if (m_axi_awvalid) begin
                if (aw_fire) begin
                    m_axi_awvalid <= 1'b0;
                    issue_addr_q <= issue_addr_q + {aw_plan_beats_q, 6'b000000};
                    issue_beats_left_q <= issue_beats_left_q - aw_plan_beats_q;
                end
            end else if ((issue_beats_left_q != 0) &&
                         (outstanding_count_q < MAX_OUTSTANDING) &&
                         (plan_count_q < MAX_OUTSTANDING)) begin
                m_axi_awaddr <= issue_addr_q;
                m_axi_awlen <= plan_beats_c[7:0] - 1'b1;
                m_axi_awsize <= 3'd6;
                m_axi_awburst <= 2'b01;
                m_axi_awvalid <= 1'b1;
                aw_plan_beats_q <= plan_beats_c[7:0];
            end

            if (aw_fire) begin
                plan_beats_mem[plan_wr_ptr_q] <= aw_plan_beats_q;
                plan_wr_ptr_q <= plan_ptr_next(plan_wr_ptr_q);
            end
            if (plan_pop)
                plan_rd_ptr_q <= plan_ptr_next(plan_rd_ptr_q);
            case ({aw_fire, plan_pop})
            2'b10: plan_count_q <= plan_count_q + 1'b1;
            2'b01: plan_count_q <= plan_count_q - 1'b1;
            default: begin
            end
            endcase

            if (plan_pop_start) begin
                w_burst_active_q <= 1'b1;
                w_burst_beats_left_q <= plan_beats_mem[plan_rd_ptr_q];
            end

            if (w_fire) begin
                m_axi_wvalid <= 1'b0;
                m_axi_wlast <= 1'b0;
                w_beats_accepted_q <= w_beats_accepted_q + 1'b1;
            end
            if (source_fire) begin
                m_axi_wdata <= s_payload_tdata;
                m_axi_wstrb <= source_keep_expected;
                m_axi_wlast <= (w_burst_beats_left_q == 1);
                m_axi_wvalid <= 1'b1;
                if (source_bytes_left_q > 32'd64)
                    source_bytes_left_q <= source_bytes_left_q - 32'd64;
                else
                    source_bytes_left_q <= 32'h0;

                if ((s_payload_tkeep != source_keep_expected) ||
                    (s_payload_tlast != source_last_expected)) begin
                    if (!error_seen_q) begin
                        error_seen_q <= 1'b1;
                        error_code_q <= ERR_SOURCE_FORMAT;
                    end
                end

                if (w_burst_beats_left_q > 1) begin
                    w_burst_beats_left_q <= w_burst_beats_left_q - 1'b1;
                end else if (plan_pop_continue) begin
                    w_burst_active_q <= 1'b1;
                    w_burst_beats_left_q <= plan_beats_mem[plan_rd_ptr_q];
                end else begin
                    w_burst_active_q <= 1'b0;
                    w_burst_beats_left_q <= 8'h0;
                end
            end

            case ({aw_fire, b_fire})
            2'b10: outstanding_count_q <= outstanding_count_q + 1'b1;
            2'b01: outstanding_count_q <= outstanding_count_q - 1'b1;
            default: begin
            end
            endcase

            if (b_fire && (m_axi_bresp != 2'b00) && !error_seen_q) begin
                error_seen_q <= 1'b1;
                case (m_axi_bresp)
                2'b10: error_code_q <= ERR_AXI_SLVERR;
                2'b11: error_code_q <= ERR_AXI_DECERR;
                default: error_code_q <= ERR_AXI_RESPONSE;
                endcase
            end

            if ((issue_beats_left_q == 0) && !m_axi_awvalid &&
                (plan_count_q == 0) && !w_burst_active_q &&
                (source_bytes_left_q == 0) && !m_axi_wvalid &&
                (w_beats_accepted_q == total_beats_q) &&
                (outstanding_count_q == 0)) begin
                active_q <= 1'b0;
                cpl_valid <= 1'b1;
                cpl_error <= error_seen_q;
                cpl_error_code <= error_seen_q ? error_code_q : ERR_NONE;
            end
        end
    end
end

endmodule
