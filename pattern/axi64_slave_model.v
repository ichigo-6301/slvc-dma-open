`timescale 1ns/1ps
`include "dma_sim_def.vh"

module axi64_slave_model #(
    parameter integer AW_STALL_MOD = 0,
    parameter integer W_STALL_MOD  = 0,
    parameter integer RANDOM_STALL = 0,
    parameter integer RANDOM_SEED  = 32'h2a5a_1001,
    parameter integer ERROR_ADDR_EN = 0,
    parameter [31:0]  ERROR_ADDR    = 32'h0,
    parameter integer RERROR_ADDR_EN = 0,
    parameter [31:0]  RERROR_ADDR    = 32'h0
)(
    input             aclk,
    input             arstn,
    input      [31:0] awaddr,
    input      [7:0]  awlen,
    input      [2:0]  awsize,
    input      [1:0]  awburst,
    input             awvalid,
    output reg        awready,
    input      [63:0] wdata,
    input      [7:0]  wstrb,
    input             wlast,
    input             wvalid,
    output reg        wready,
    output reg [1:0]  bresp,
    output reg        bvalid,
    input             bready,
    input      [31:0] araddr,
    input      [7:0]  arlen,
    input      [2:0]  arsize,
    input      [1:0]  arburst,
    input             arvalid,
    output reg        arready,
    output reg [63:0] rdata,
    output reg [1:0]  rresp,
    output reg        rlast,
    output reg        rvalid,
    input             rready
);

reg [31:0] wr_addr;
reg        wr_error;
reg [7:0]  wr_left;
reg        wr_active;
reg [31:0] rd_addr;
reg        rd_error;
reg [7:0]  rd_left;
reg        rd_active;
reg [31:0] stall_cnt;
reg        rand_aw_allow;
reg        rand_w_allow;
integer    rand_seed;
integer    stall_pct;
integer i;

localparam integer AW_STALL_SAFE = (AW_STALL_MOD < 2) ? 32'h7fffffff : AW_STALL_MOD;
localparam integer W_STALL_SAFE  = (W_STALL_MOD  < 2) ? 32'h7fffffff : W_STALL_MOD;

wire aw_det_allow = (AW_STALL_MOD < 2) || ((stall_cnt % AW_STALL_SAFE) != (AW_STALL_SAFE - 1));
wire w_det_allow  = (W_STALL_MOD  < 2) || ((stall_cnt % W_STALL_SAFE)  != (W_STALL_SAFE - 1));
wire aw_allow = RANDOM_STALL ? rand_aw_allow : aw_det_allow;
wire w_allow  = RANDOM_STALL ? rand_w_allow  : w_det_allow;

function integer rand_pct;
    input dummy;
    integer r;
    begin
        r = $random(rand_seed);
        if (r < 0)
            r = -r;
        rand_pct = r % 100;
    end
endfunction

initial begin
    rand_seed = RANDOM_SEED;
    stall_pct = 0;
    if (!$value$plusargs("STALL_PCT=%d", stall_pct))
        stall_pct = 35;
    rand_aw_allow = 1'b1;
    rand_w_allow = 1'b1;
end

always @(posedge aclk or negedge arstn) begin
    if (!arstn) begin
        awready <= 1'b1;
        wready <= 1'b0;
        bresp <= 2'b00;
        bvalid <= 1'b0;
        arready <= 1'b1;
        rdata <= 64'h0;
        rresp <= 2'b00;
        rlast <= 1'b0;
        rvalid <= 1'b0;
        wr_addr <= 32'h0;
        wr_error <= 1'b0;
        wr_left <= 8'h0;
        wr_active <= 1'b0;
        rd_addr <= 32'h0;
        rd_error <= 1'b0;
        rd_left <= 8'h0;
        rd_active <= 1'b0;
        stall_cnt <= 32'h0;
        rand_aw_allow <= 1'b1;
        rand_w_allow <= 1'b1;
    end else begin
        stall_cnt <= stall_cnt + 1'b1;
        if (RANDOM_STALL) begin
            rand_aw_allow <= (rand_pct(1'b0) >= stall_pct);
            rand_w_allow <= (rand_pct(1'b0) >= stall_pct);
        end
        if (!wr_active && !bvalid)
            awready <= aw_allow;
        if (wr_active)
            wready <= w_allow;

        if (awready && awvalid) begin
            wr_addr <= awaddr;
            wr_error <= ERROR_ADDR_EN && (awaddr == ERROR_ADDR);
            wr_left <= awlen;
            wr_active <= 1'b1;
            wready <= w_allow;
            awready <= 1'b0;
        end

        if (wready && wvalid) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (wstrb[i] && ((wr_addr + i) < `DMA_SIM_MEM_BYTES))
                    `DMA_SYS_MEM_PATH[wr_addr + i] <= wdata[i*8 +: 8];
            end
            wr_addr <= wr_addr + 8;
            if ((wr_left == 0) || wlast) begin
                wr_active <= 1'b0;
                wready <= 1'b0;
                bvalid <= 1'b1;
                bresp <= wr_error ? 2'b10 : 2'b00;
                awready <= 1'b1;
            end else begin
                wr_left <= wr_left - 1'b1;
            end
        end

        if (bvalid && bready)
            bvalid <= 1'b0;

        if (arready && arvalid) begin
            rd_addr <= araddr;
            rd_error <= RERROR_ADDR_EN && (araddr == RERROR_ADDR);
            rd_left <= arlen;
            rd_active <= 1'b1;
            arready <= 1'b0;
            rvalid <= 1'b0;
        end

        if (rd_active && (!rvalid || rready)) begin
            for (i = 0; i < 8; i = i + 1) begin
                if ((rd_addr + i) < `DMA_SIM_MEM_BYTES)
                    rdata[i*8 +: 8] <= `DMA_SYS_MEM_PATH[rd_addr + i];
                else
                    rdata[i*8 +: 8] <= 8'h00;
            end
            rresp <= rd_error ? 2'b10 : 2'b00;
            rvalid <= 1'b1;
            rlast <= (rd_left == 0);
            rd_addr <= rd_addr + 8;
            if (rd_left == 0) begin
                rd_active <= 1'b0;
                arready <= 1'b1;
            end else begin
                rd_left <= rd_left - 1'b1;
            end
        end else if (rvalid && rready) begin
            rvalid <= 1'b0;
            rlast <= 1'b0;
        end
    end
end

endmodule
