`timescale 1ns/1ps
`include "dma_sim_def.vh"

// TB-only two-master memory model.  Port 0 carries the legacy TX/CQ AXI
// traffic and port 1 carries the Async64 RX payload writes.  Shared mode
// retires at most one 64-bit data beat per HP clock; split mode permits each
// traffic class to retire independently in the same cycle.
module axi_hp0_dual_master_64_model #(
    parameter integer SHARED_SERVICE = 1,
    parameter integer RESPONSE_LATENCY = 16,
    parameter integer SERVICE_PERCENT = 100
)(
    input hp_clk,
    input hp_rstn,

    input m0_clk,
    input m0_rstn,
    input [31:0] m0_awaddr,
    input [7:0] m0_awlen,
    input [2:0] m0_awsize,
    input [1:0] m0_awburst,
    input m0_awvalid,
    output m0_awready,
    input [63:0] m0_wdata,
    input [7:0] m0_wstrb,
    input m0_wlast,
    input m0_wvalid,
    output m0_wready,
    output [1:0] m0_bresp,
    output m0_bvalid,
    input m0_bready,
    input [31:0] m0_araddr,
    input [7:0] m0_arlen,
    input [2:0] m0_arsize,
    input [1:0] m0_arburst,
    input m0_arvalid,
    output m0_arready,
    output [63:0] m0_rdata,
    output [1:0] m0_rresp,
    output m0_rlast,
    output m0_rvalid,
    input m0_rready,

    input m1_clk,
    input m1_rstn,
    input [31:0] m1_awaddr,
    input [7:0] m1_awlen,
    input [2:0] m1_awsize,
    input [1:0] m1_awburst,
    input m1_awvalid,
    output m1_awready,
    input [63:0] m1_wdata,
    input [7:0] m1_wstrb,
    input m1_wlast,
    input m1_wvalid,
    output m1_wready,
    output [1:0] m1_bresp,
    output m1_bvalid,
    input m1_bready
);

localparam integer CMD_DEPTH = 32;
localparam integer CMD_AW = 5;
localparam integer DATA_DEPTH = 256;
localparam integer DATA_AW = 8;

reg [31:0] m0_aw_addr_q [0:CMD_DEPTH-1];
reg [7:0]  m0_aw_len_q  [0:CMD_DEPTH-1];
reg [CMD_AW-1:0] m0_aw_wr_ptr;
reg [CMD_AW-1:0] m0_aw_rd_ptr;

reg [63:0] m0_w_data_q [0:DATA_DEPTH-1];
reg [7:0]  m0_w_strb_q [0:DATA_DEPTH-1];
reg        m0_w_last_q [0:DATA_DEPTH-1];
reg [DATA_AW-1:0] m0_w_wr_ptr;
reg [DATA_AW-1:0] m0_w_rd_ptr;

reg [31:0] m0_ar_addr_q [0:CMD_DEPTH-1];
reg [7:0]  m0_ar_len_q  [0:CMD_DEPTH-1];
reg [63:0] m0_ar_due_q  [0:CMD_DEPTH-1];
reg [CMD_AW-1:0] m0_ar_wr_ptr;
reg [CMD_AW-1:0] m0_ar_rd_ptr;

reg [31:0] m1_aw_addr_q [0:CMD_DEPTH-1];
reg [7:0]  m1_aw_len_q  [0:CMD_DEPTH-1];
reg [CMD_AW-1:0] m1_aw_wr_ptr;
reg [CMD_AW-1:0] m1_aw_rd_ptr;

reg [63:0] m1_w_data_q [0:DATA_DEPTH-1];
reg [7:0]  m1_w_strb_q [0:DATA_DEPTH-1];
reg        m1_w_last_q [0:DATA_DEPTH-1];
reg [DATA_AW-1:0] m1_w_wr_ptr;
reg [DATA_AW-1:0] m1_w_rd_ptr;

reg [63:0] m0_r_data_q [0:DATA_DEPTH-1];
reg        m0_r_last_q [0:DATA_DEPTH-1];
reg [DATA_AW-1:0] m0_r_wr_ptr;
reg [DATA_AW-1:0] m0_r_rd_ptr;

reg [CMD_AW-1:0] m0_b_wr_ptr;
reg [CMD_AW-1:0] m0_b_rd_ptr;
reg [CMD_AW-1:0] m1_b_wr_ptr;
reg [CMD_AW-1:0] m1_b_rd_ptr;

reg [63:0] m0_b_due_q [0:CMD_DEPTH-1];
reg [CMD_AW-1:0] m0_b_due_wr_ptr;
reg [CMD_AW-1:0] m0_b_due_rd_ptr;
reg [63:0] m1_b_due_q [0:CMD_DEPTH-1];
reg [CMD_AW-1:0] m1_b_due_wr_ptr;
reg [CMD_AW-1:0] m1_b_due_rd_ptr;

reg m0_wr_active;
reg [31:0] m0_wr_addr;
reg [7:0] m0_wr_left;
reg m1_wr_active;
reg [31:0] m1_wr_addr;
reg [7:0] m1_wr_left;
reg m0_rd_active;
reg [31:0] m0_rd_addr;
reg [7:0] m0_rd_left;
reg [63:0] m0_rd_due;

reg [1:0] rr_q;
reg [63:0] hp_cycle_q;
reg grant_m0_read;
reg grant_m0_write;
reg grant_m1_write;

reg [63:0] debug_m0_read_beats;
reg [63:0] debug_m0_write_beats;
reg [63:0] debug_m1_write_beats;
reg [63:0] debug_idle_service_cycles;
reg [31:0] debug_protocol_errors;
reg [31:0] debug_m0_write_outstanding;
reg [31:0] debug_m0_write_peak_outstanding;
reg [31:0] debug_m1_write_outstanding;
reg [31:0] debug_m1_write_peak_outstanding;

integer byte_i;

wire [CMD_AW-1:0] m0_aw_wr_next = m0_aw_wr_ptr + 1'b1;
wire [DATA_AW-1:0] m0_w_wr_next = m0_w_wr_ptr + 1'b1;
wire [CMD_AW-1:0] m0_ar_wr_next = m0_ar_wr_ptr + 1'b1;
wire [CMD_AW-1:0] m1_aw_wr_next = m1_aw_wr_ptr + 1'b1;
wire [DATA_AW-1:0] m1_w_wr_next = m1_w_wr_ptr + 1'b1;
wire [DATA_AW-1:0] m0_r_wr_next = m0_r_wr_ptr + 1'b1;
wire [CMD_AW-1:0] m0_b_wr_next = m0_b_wr_ptr + 1'b1;
wire [CMD_AW-1:0] m1_b_wr_next = m1_b_wr_ptr + 1'b1;

assign m0_awready = m0_aw_wr_next != m0_aw_rd_ptr;
assign m0_wready = m0_w_wr_next != m0_w_rd_ptr;
assign m0_arready = m0_ar_wr_next != m0_ar_rd_ptr;
assign m1_awready = m1_aw_wr_next != m1_aw_rd_ptr;
assign m1_wready = m1_w_wr_next != m1_w_rd_ptr;

assign m0_bvalid = m0_b_rd_ptr != m0_b_wr_ptr;
assign m0_bresp = 2'b00;
assign m1_bvalid = m1_b_rd_ptr != m1_b_wr_ptr;
assign m1_bresp = 2'b00;
assign m0_rvalid = m0_r_rd_ptr != m0_r_wr_ptr;
assign m0_rdata = m0_r_data_q[m0_r_rd_ptr];
assign m0_rresp = 2'b00;
assign m0_rlast = m0_r_last_q[m0_r_rd_ptr];

wire m0_read_req = m0_rd_active && (hp_cycle_q >= m0_rd_due) &&
                   (m0_r_wr_next != m0_r_rd_ptr);
wire m0_write_req = m0_wr_active && (m0_w_rd_ptr != m0_w_wr_ptr);
wire m1_write_req = m1_wr_active && (m1_w_rd_ptr != m1_w_wr_ptr);
wire service_enable = (SERVICE_PERCENT >= 100) ? 1'b1 :
                      (SERVICE_PERCENT >= 75) ? (hp_cycle_q[1:0] != 2'b11) :
                      (hp_cycle_q[0] == 1'b0);

initial begin
    if (!((SHARED_SERVICE == 0) || (SHARED_SERVICE == 1)))
        $fatal(1, "SHARED_SERVICE must be zero or one");
    if (!((SERVICE_PERCENT == 100) || (SERVICE_PERCENT == 75) ||
          (SERVICE_PERCENT == 50)))
        $fatal(1, "SERVICE_PERCENT must be 100, 75, or 50");
end

task clear_region;
    input [31:0] addr;
    input integer len;
    integer j;
    begin
        for (j = 0; j < len; j = j + 1)
            if ((addr + j) < `DMA_SIM_MEM_BYTES)
                `DMA_SYS_MEM_PATH[addr + j] = 8'h0;
    end
endtask

task clear_all;
    integer j;
    begin
        for (j = 0; j < `DMA_SIM_MEM_BYTES; j = j + 1)
            `DMA_SYS_MEM_PATH[j] = 8'h0;
    end
endtask

task preload_pattern;
    input [31:0] addr;
    input integer len;
    input [7:0] seed;
    integer j;
    begin
        for (j = 0; j < len; j = j + 1)
            if ((addr + j) < `DMA_SIM_MEM_BYTES)
                `DMA_SYS_MEM_PATH[addr + j] = seed ^ j[7:0];
    end
endtask

always @* begin
    grant_m0_read = 1'b0;
    grant_m0_write = 1'b0;
    grant_m1_write = 1'b0;
    if (service_enable) begin
        if (!SHARED_SERVICE) begin
            grant_m0_read = m0_read_req;
            grant_m0_write = m0_write_req;
            grant_m1_write = m1_write_req;
        end else begin
            case (rr_q)
            2'd0: begin
                if (m0_read_req) grant_m0_read = 1'b1;
                else if (m0_write_req) grant_m0_write = 1'b1;
                else if (m1_write_req) grant_m1_write = 1'b1;
            end
            2'd1: begin
                if (m0_write_req) grant_m0_write = 1'b1;
                else if (m1_write_req) grant_m1_write = 1'b1;
                else if (m0_read_req) grant_m0_read = 1'b1;
            end
            default: begin
                if (m1_write_req) grant_m1_write = 1'b1;
                else if (m0_read_req) grant_m0_read = 1'b1;
                else if (m0_write_req) grant_m0_write = 1'b1;
            end
            endcase
        end
    end
end

always @(posedge m0_clk or negedge m0_rstn) begin
    if (!m0_rstn) begin
        m0_aw_wr_ptr <= 0;
        m0_w_wr_ptr <= 0;
        m0_ar_wr_ptr <= 0;
        m0_b_rd_ptr <= 0;
        m0_r_rd_ptr <= 0;
        debug_m0_write_outstanding <= 0;
        debug_m0_write_peak_outstanding <= 0;
    end else begin
        if (m0_awvalid && m0_awready) begin
            m0_aw_addr_q[m0_aw_wr_ptr] <= m0_awaddr;
            m0_aw_len_q[m0_aw_wr_ptr] <= m0_awlen;
            m0_aw_wr_ptr <= m0_aw_wr_next;
        end
        if (m0_wvalid && m0_wready) begin
            m0_w_data_q[m0_w_wr_ptr] <= m0_wdata;
            m0_w_strb_q[m0_w_wr_ptr] <= m0_wstrb;
            m0_w_last_q[m0_w_wr_ptr] <= m0_wlast;
            m0_w_wr_ptr <= m0_w_wr_next;
        end
        if (m0_arvalid && m0_arready) begin
            m0_ar_addr_q[m0_ar_wr_ptr] <= m0_araddr;
            m0_ar_len_q[m0_ar_wr_ptr] <= m0_arlen;
            m0_ar_due_q[m0_ar_wr_ptr] <= hp_cycle_q + RESPONSE_LATENCY;
            m0_ar_wr_ptr <= m0_ar_wr_next;
        end
        if (m0_bvalid && m0_bready)
            m0_b_rd_ptr <= m0_b_rd_ptr + 1'b1;
        if (m0_rvalid && m0_rready)
            m0_r_rd_ptr <= m0_r_rd_ptr + 1'b1;

        case ({m0_awvalid && m0_awready, m0_bvalid && m0_bready})
        2'b10: debug_m0_write_outstanding <= debug_m0_write_outstanding + 1'b1;
        2'b01: if (debug_m0_write_outstanding != 0)
            debug_m0_write_outstanding <= debug_m0_write_outstanding - 1'b1;
        default: begin end
        endcase
        if (m0_awvalid && m0_awready &&
            ((debug_m0_write_outstanding + 1'b1) > debug_m0_write_peak_outstanding))
            debug_m0_write_peak_outstanding <= debug_m0_write_outstanding + 1'b1;
    end
end

always @(posedge m1_clk or negedge m1_rstn) begin
    if (!m1_rstn) begin
        m1_aw_wr_ptr <= 0;
        m1_w_wr_ptr <= 0;
        m1_b_rd_ptr <= 0;
        debug_m1_write_outstanding <= 0;
        debug_m1_write_peak_outstanding <= 0;
    end else begin
        if (m1_awvalid && m1_awready) begin
            m1_aw_addr_q[m1_aw_wr_ptr] <= m1_awaddr;
            m1_aw_len_q[m1_aw_wr_ptr] <= m1_awlen;
            m1_aw_wr_ptr <= m1_aw_wr_next;
        end
        if (m1_wvalid && m1_wready) begin
            m1_w_data_q[m1_w_wr_ptr] <= m1_wdata;
            m1_w_strb_q[m1_w_wr_ptr] <= m1_wstrb;
            m1_w_last_q[m1_w_wr_ptr] <= m1_wlast;
            m1_w_wr_ptr <= m1_w_wr_next;
        end
        if (m1_bvalid && m1_bready)
            m1_b_rd_ptr <= m1_b_rd_ptr + 1'b1;

        case ({m1_awvalid && m1_awready, m1_bvalid && m1_bready})
        2'b10: debug_m1_write_outstanding <= debug_m1_write_outstanding + 1'b1;
        2'b01: if (debug_m1_write_outstanding != 0)
            debug_m1_write_outstanding <= debug_m1_write_outstanding - 1'b1;
        default: begin end
        endcase
        if (m1_awvalid && m1_awready &&
            ((debug_m1_write_outstanding + 1'b1) > debug_m1_write_peak_outstanding))
            debug_m1_write_peak_outstanding <= debug_m1_write_outstanding + 1'b1;
    end
end

always @(posedge hp_clk or negedge hp_rstn) begin
    if (!hp_rstn) begin
        m0_aw_rd_ptr <= 0;
        m0_w_rd_ptr <= 0;
        m0_ar_rd_ptr <= 0;
        m1_aw_rd_ptr <= 0;
        m1_w_rd_ptr <= 0;
        m0_r_wr_ptr <= 0;
        m0_b_wr_ptr <= 0;
        m1_b_wr_ptr <= 0;
        m0_b_due_wr_ptr <= 0;
        m0_b_due_rd_ptr <= 0;
        m1_b_due_wr_ptr <= 0;
        m1_b_due_rd_ptr <= 0;
        m0_wr_active <= 1'b0;
        m1_wr_active <= 1'b0;
        m0_rd_active <= 1'b0;
        m0_wr_addr <= 0;
        m1_wr_addr <= 0;
        m0_rd_addr <= 0;
        m0_wr_left <= 0;
        m1_wr_left <= 0;
        m0_rd_left <= 0;
        m0_rd_due <= 0;
        rr_q <= 0;
        hp_cycle_q <= 0;
        debug_m0_read_beats <= 0;
        debug_m0_write_beats <= 0;
        debug_m1_write_beats <= 0;
        debug_idle_service_cycles <= 0;
        debug_protocol_errors <= 0;
    end else begin
        hp_cycle_q <= hp_cycle_q + 1'b1;

        if (!m0_wr_active && (m0_aw_rd_ptr != m0_aw_wr_ptr)) begin
            m0_wr_addr <= m0_aw_addr_q[m0_aw_rd_ptr];
            m0_wr_left <= m0_aw_len_q[m0_aw_rd_ptr];
            m0_aw_rd_ptr <= m0_aw_rd_ptr + 1'b1;
            m0_wr_active <= 1'b1;
        end
        if (!m1_wr_active && (m1_aw_rd_ptr != m1_aw_wr_ptr)) begin
            m1_wr_addr <= m1_aw_addr_q[m1_aw_rd_ptr];
            m1_wr_left <= m1_aw_len_q[m1_aw_rd_ptr];
            m1_aw_rd_ptr <= m1_aw_rd_ptr + 1'b1;
            m1_wr_active <= 1'b1;
        end
        if (!m0_rd_active && (m0_ar_rd_ptr != m0_ar_wr_ptr)) begin
            m0_rd_addr <= m0_ar_addr_q[m0_ar_rd_ptr];
            m0_rd_left <= m0_ar_len_q[m0_ar_rd_ptr];
            m0_rd_due <= m0_ar_due_q[m0_ar_rd_ptr];
            m0_ar_rd_ptr <= m0_ar_rd_ptr + 1'b1;
            m0_rd_active <= 1'b1;
        end

        if ((m0_b_due_rd_ptr != m0_b_due_wr_ptr) &&
            (m0_b_due_q[m0_b_due_rd_ptr] <= hp_cycle_q) &&
            (m0_b_wr_next != m0_b_rd_ptr)) begin
            m0_b_due_rd_ptr <= m0_b_due_rd_ptr + 1'b1;
            m0_b_wr_ptr <= m0_b_wr_ptr + 1'b1;
        end
        if ((m1_b_due_rd_ptr != m1_b_due_wr_ptr) &&
            (m1_b_due_q[m1_b_due_rd_ptr] <= hp_cycle_q) &&
            (m1_b_wr_next != m1_b_rd_ptr)) begin
            m1_b_due_rd_ptr <= m1_b_due_rd_ptr + 1'b1;
            m1_b_wr_ptr <= m1_b_wr_ptr + 1'b1;
        end

        if (grant_m0_read) begin
            for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1)
                m0_r_data_q[m0_r_wr_ptr][byte_i*8 +: 8] <=
                    ((m0_rd_addr + byte_i) < `DMA_SIM_MEM_BYTES) ?
                    `DMA_SYS_MEM_PATH[m0_rd_addr + byte_i] : 8'h0;
            m0_r_last_q[m0_r_wr_ptr] <= (m0_rd_left == 0);
            m0_r_wr_ptr <= m0_r_wr_ptr + 1'b1;
            m0_rd_addr <= m0_rd_addr + 8;
            debug_m0_read_beats <= debug_m0_read_beats + 1'b1;
            if (m0_rd_left == 0) begin
                if (m0_ar_rd_ptr != m0_ar_wr_ptr) begin
                    m0_rd_addr <= m0_ar_addr_q[m0_ar_rd_ptr];
                    m0_rd_left <= m0_ar_len_q[m0_ar_rd_ptr];
                    m0_rd_due <= m0_ar_due_q[m0_ar_rd_ptr];
                    m0_ar_rd_ptr <= m0_ar_rd_ptr + 1'b1;
                end else begin
                    m0_rd_active <= 1'b0;
                end
            end else begin
                m0_rd_left <= m0_rd_left - 1'b1;
            end
            if (SHARED_SERVICE)
                rr_q <= 2'd1;
        end

        if (grant_m0_write) begin
            for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1)
                if (m0_w_strb_q[m0_w_rd_ptr][byte_i] &&
                    ((m0_wr_addr + byte_i) < `DMA_SIM_MEM_BYTES))
                    `DMA_SYS_MEM_PATH[m0_wr_addr + byte_i] <=
                        m0_w_data_q[m0_w_rd_ptr][byte_i*8 +: 8];
            if (m0_w_last_q[m0_w_rd_ptr] != (m0_wr_left == 0))
                debug_protocol_errors <= debug_protocol_errors + 1'b1;
            m0_w_rd_ptr <= m0_w_rd_ptr + 1'b1;
            m0_wr_addr <= m0_wr_addr + 8;
            debug_m0_write_beats <= debug_m0_write_beats + 1'b1;
            if (m0_wr_left == 0) begin
                m0_b_due_q[m0_b_due_wr_ptr] <= hp_cycle_q + RESPONSE_LATENCY;
                m0_b_due_wr_ptr <= m0_b_due_wr_ptr + 1'b1;
                if (m0_aw_rd_ptr != m0_aw_wr_ptr) begin
                    m0_wr_addr <= m0_aw_addr_q[m0_aw_rd_ptr];
                    m0_wr_left <= m0_aw_len_q[m0_aw_rd_ptr];
                    m0_aw_rd_ptr <= m0_aw_rd_ptr + 1'b1;
                end else begin
                    m0_wr_active <= 1'b0;
                end
            end else begin
                m0_wr_left <= m0_wr_left - 1'b1;
            end
            if (SHARED_SERVICE)
                rr_q <= 2'd2;
        end

        if (grant_m1_write) begin
            for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1)
                if (m1_w_strb_q[m1_w_rd_ptr][byte_i] &&
                    ((m1_wr_addr + byte_i) < `DMA_SIM_MEM_BYTES))
                    `DMA_SYS_MEM_PATH[m1_wr_addr + byte_i] <=
                        m1_w_data_q[m1_w_rd_ptr][byte_i*8 +: 8];
            if (m1_w_last_q[m1_w_rd_ptr] != (m1_wr_left == 0))
                debug_protocol_errors <= debug_protocol_errors + 1'b1;
            m1_w_rd_ptr <= m1_w_rd_ptr + 1'b1;
            m1_wr_addr <= m1_wr_addr + 8;
            debug_m1_write_beats <= debug_m1_write_beats + 1'b1;
            if (m1_wr_left == 0) begin
                m1_b_due_q[m1_b_due_wr_ptr] <= hp_cycle_q + RESPONSE_LATENCY;
                m1_b_due_wr_ptr <= m1_b_due_wr_ptr + 1'b1;
                if (m1_aw_rd_ptr != m1_aw_wr_ptr) begin
                    m1_wr_addr <= m1_aw_addr_q[m1_aw_rd_ptr];
                    m1_wr_left <= m1_aw_len_q[m1_aw_rd_ptr];
                    m1_aw_rd_ptr <= m1_aw_rd_ptr + 1'b1;
                end else begin
                    m1_wr_active <= 1'b0;
                end
            end else begin
                m1_wr_left <= m1_wr_left - 1'b1;
            end
            if (SHARED_SERVICE)
                rr_q <= 2'd0;
        end

        if (service_enable && !grant_m0_read && !grant_m0_write && !grant_m1_write)
            debug_idle_service_cycles <= debug_idle_service_cycles + 1'b1;
    end
end

endmodule
