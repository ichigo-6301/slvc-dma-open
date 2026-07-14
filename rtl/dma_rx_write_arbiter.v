`timescale 1ns/1ps

module dma_rx_write_arbiter(
    input             clk,
    input             rstn,
    input             soft_reset,
    input             payload_busy,
    input      [31:0] p_awaddr,
    input      [7:0]  p_awlen,
    input      [2:0]  p_awsize,
    input      [1:0]  p_awburst,
    input             p_awvalid,
    output            p_awready,
    input      [63:0] p_wdata,
    input      [7:0]  p_wstrb,
    input             p_wlast,
    input             p_wvalid,
    output            p_wready,
    output     [1:0]  p_bresp,
    output            p_bvalid,
    input             p_bready,
    input             cqe_busy,
    input      [31:0] c_awaddr,
    input      [7:0]  c_awlen,
    input      [2:0]  c_awsize,
    input      [1:0]  c_awburst,
    input             c_awvalid,
    output            c_awready,
    input      [63:0] c_wdata,
    input      [7:0]  c_wstrb,
    input             c_wlast,
    input             c_wvalid,
    output            c_wready,
    output     [1:0]  c_bresp,
    output            c_bvalid,
    input             c_bready,
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
    output            m_axi_bready
);

localparam [1:0] GRANT_NONE    = 2'd0;
localparam [1:0] GRANT_PAYLOAD = 2'd1;
localparam [1:0] GRANT_CQE     = 2'd2;

reg [1:0] grant_q;
reg [1:0] grant_d;
reg       aw_stage_valid_q;
reg [7:0] aw_credit_q;
reg [31:0] aw_stage_addr_q;
reg [7:0]  aw_stage_len_q;
reg [2:0]  aw_stage_size_q;
reg [1:0]  aw_stage_burst_q;

wire payload_selected = (grant_q == GRANT_PAYLOAD);
wire cqe_selected = (grant_q == GRANT_CQE);
wire aw_down_fire = aw_stage_valid_q && m_axi_awready;
wire w_down_last_fire = m_axi_wvalid && m_axi_wready && m_axi_wlast;
wire w_credit_valid = (aw_credit_q != 0);

always @(*) begin
    grant_d = grant_q;
    case (grant_q)
    GRANT_NONE: begin
        if (cqe_busy)
            grant_d = GRANT_CQE;
        else if (payload_busy)
            grant_d = GRANT_PAYLOAD;
    end
    GRANT_PAYLOAD: begin
        if (!payload_busy) begin
            if (cqe_busy)
                grant_d = GRANT_CQE;
            else
                grant_d = GRANT_NONE;
        end
    end
    GRANT_CQE: begin
        if (!cqe_busy) begin
            if (payload_busy)
                grant_d = GRANT_PAYLOAD;
            else
                grant_d = GRANT_NONE;
        end
    end
    default: grant_d = GRANT_NONE;
    endcase
end

assign m_axi_awaddr  = aw_stage_addr_q;
assign m_axi_awlen   = aw_stage_len_q;
assign m_axi_awsize  = aw_stage_size_q;
assign m_axi_awburst = aw_stage_burst_q;
assign m_axi_awvalid = aw_stage_valid_q;
assign m_axi_wdata   = cqe_selected ? c_wdata : p_wdata;
assign m_axi_wstrb   = cqe_selected ? c_wstrb : p_wstrb;
assign m_axi_wlast   = cqe_selected ? c_wlast : p_wlast;
assign m_axi_wvalid  = cqe_selected ? (w_credit_valid && c_wvalid) :
                       (payload_selected ? (w_credit_valid && p_wvalid) : 1'b0);
assign m_axi_bready  = cqe_selected ? c_bready : (payload_selected ? p_bready : 1'b0);

assign c_awready = cqe_selected && !aw_stage_valid_q;
assign c_wready  = cqe_selected && w_credit_valid && m_axi_wready;
assign c_bresp   = cqe_selected ? m_axi_bresp : 2'b00;
assign c_bvalid  = cqe_selected ? m_axi_bvalid : 1'b0;

assign p_awready = payload_selected && !aw_stage_valid_q;
assign p_wready  = payload_selected && w_credit_valid && m_axi_wready;
assign p_bresp   = payload_selected ? m_axi_bresp : 2'b00;
assign p_bvalid  = payload_selected ? m_axi_bvalid : 1'b0;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        grant_q <= GRANT_NONE;
        aw_stage_valid_q <= 1'b0;
        aw_credit_q <= 8'h0;
        aw_stage_addr_q <= 32'h0;
        aw_stage_len_q <= 8'h0;
        aw_stage_size_q <= 3'h0;
        aw_stage_burst_q <= 2'h0;
    end else if (soft_reset) begin
        grant_q <= GRANT_NONE;
        aw_stage_valid_q <= 1'b0;
        aw_credit_q <= 8'h0;
    end else begin
        grant_q <= grant_d;
        if (grant_d != grant_q) begin
            aw_stage_valid_q <= 1'b0;
            aw_credit_q <= 8'h0;
        end else if (aw_down_fire) begin
            aw_stage_valid_q <= 1'b0;
        end else if (!aw_stage_valid_q) begin
            if (payload_selected && p_awvalid) begin
                aw_stage_valid_q <= 1'b1;
                aw_stage_addr_q <= p_awaddr;
                aw_stage_len_q <= p_awlen;
                aw_stage_size_q <= p_awsize;
                aw_stage_burst_q <= p_awburst;
            end else if (cqe_selected && c_awvalid) begin
                aw_stage_valid_q <= 1'b1;
                aw_stage_addr_q <= c_awaddr;
                aw_stage_len_q <= c_awlen;
                aw_stage_size_q <= c_awsize;
                aw_stage_burst_q <= c_awburst;
            end
        end

        if (grant_d == grant_q) begin
            case ({aw_down_fire, w_down_last_fire})
            2'b10: aw_credit_q <= aw_credit_q + 1'b1;
            2'b01: aw_credit_q <= aw_credit_q - 1'b1;
            default: aw_credit_q <= aw_credit_q;
            endcase
        end
    end
end

endmodule
