`timescale 1ns/1ps
`include "dma_sim_def.vh"

module axi_ddr_mem_model #(
    parameter integer AW_WAIT = 0,
    parameter integer W_WAIT  = 0,
    parameter integer B_WAIT  = 0,
    parameter integer AR_WAIT = 0,
    parameter integer R_WAIT  = 0,
    parameter integer ERROR_ADDR_EN = 0,
    parameter [31:0]  ERROR_ADDR = 32'h0,
    parameter integer RERROR_ADDR_EN = 0,
    parameter [31:0]  RERROR_ADDR = 32'h0
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

localparam integer WRQ_DEPTH = 16;
localparam integer WRQ_AW = 4;
localparam integer RDQ_DEPTH = 16;
localparam integer RDQ_AW = 4;

reg [31:0] wrq_addr  [0:WRQ_DEPTH-1];
reg [7:0]  wrq_len   [0:WRQ_DEPTH-1];
reg        wrq_error [0:WRQ_DEPTH-1];
reg [WRQ_AW-1:0] wrq_wr_ptr;
reg [WRQ_AW-1:0] wrq_rd_ptr;
reg [WRQ_AW:0]   wrq_count;

reg        wr_active;
reg [31:0] wr_addr;
reg [7:0]  wr_left;
reg        wr_error;

reg        bq_error [0:WRQ_DEPTH-1];
reg [WRQ_AW-1:0] bq_wr_ptr;
reg [WRQ_AW-1:0] bq_rd_ptr;
reg [WRQ_AW:0]   bq_count;

reg [31:0] rdq_addr [0:RDQ_DEPTH-1];
reg [7:0]  rdq_len  [0:RDQ_DEPTH-1];
reg        rdq_error[0:RDQ_DEPTH-1];
reg [RDQ_AW-1:0] rdq_wr_ptr;
reg [RDQ_AW-1:0] rdq_rd_ptr;
reg [RDQ_AW:0]   rdq_count;

reg [31:0] rd_addr;
reg [7:0]  rd_left;
reg        rd_active;
reg        rd_error;

reg        runtime_rerror_addr_en;
reg [31:0] runtime_rerror_addr;
reg        runtime_werror_addr_en;
reg [31:0] runtime_werror_addr;
reg        runtime_werror_burst_en;
reg [31:0] runtime_werror_burst_idx;
reg [31:0] write_burst_issue_index;

reg [31:0] debug_write_outstanding;
reg [31:0] debug_write_peak_outstanding;

integer aw_wait_cnt;
integer w_wait_cnt;
integer b_wait_cnt;
integer ar_wait_cnt;
integer r_wait_cnt;
integer i;

wire aw_push = awready && awvalid;
wire wrq_pop = !wr_active && (wrq_count != 0);
wire bq_push = wready && wvalid && ((wr_left == 0) || wlast);
wire bq_pop = bvalid && bready;

task preload_pattern;
    input [31:0] addr;
    input integer len;
    input [7:0] seed;
    integer j;
    begin
        for (j = 0; j < len; j = j + 1)
            `DMA_SYS_MEM_PATH[addr + j] = seed ^ j[7:0];
    end
endtask

task clear_region;
    input [31:0] addr;
    input integer len;
    integer j;
    begin
        for (j = 0; j < len; j = j + 1)
            `DMA_SYS_MEM_PATH[addr + j] = 8'h0;
    end
endtask

task compare_regions;
    input [31:0] exp_addr;
    input [31:0] got_addr;
    input integer len;
    integer j;
    begin
        for (j = 0; j < len; j = j + 1) begin
            if (`DMA_SYS_MEM_PATH[exp_addr + j] !== `DMA_SYS_MEM_PATH[got_addr + j]) begin
                $display("Error: DDR compare mismatch byte=%0d exp_addr=%08x got_addr=%08x exp=%02x got=%02x",
                         j, exp_addr + j, got_addr + j,
                         `DMA_SYS_MEM_PATH[exp_addr + j],
                         `DMA_SYS_MEM_PATH[got_addr + j]);
                $finish;
            end
        end
    end
endtask

task clear_all;
    integer j;
    begin
        for (j = 0; j < `DMA_SIM_MEM_BYTES; j = j + 1)
            `DMA_SYS_MEM_PATH[j] = 8'h0;
    end
endtask

task set_read_error_addr;
    input enable;
    input [31:0] addr;
    begin
        runtime_rerror_addr_en = enable;
        runtime_rerror_addr = addr;
    end
endtask

task set_write_error_addr;
    input enable;
    input [31:0] addr;
    begin
        runtime_werror_addr_en = enable;
        runtime_werror_addr = addr;
    end
endtask

task set_write_error_burst;
    input enable;
    input [31:0] burst_idx;
    begin
        runtime_werror_burst_en = enable;
        runtime_werror_burst_idx = burst_idx;
    end
endtask

always @(posedge aclk or negedge arstn) begin
    if (!arstn) begin
        awready <= 1'b0;
        wready <= 1'b0;
        bresp <= 2'b00;
        bvalid <= 1'b0;
        arready <= 1'b0;
        rdata <= 64'h0;
        rresp <= 2'b00;
        rlast <= 1'b0;
        rvalid <= 1'b0;

        wrq_wr_ptr <= {WRQ_AW{1'b0}};
        wrq_rd_ptr <= {WRQ_AW{1'b0}};
        wrq_count <= {(WRQ_AW+1){1'b0}};
        wr_active <= 1'b0;
        wr_addr <= 32'h0;
        wr_left <= 8'h0;
        wr_error <= 1'b0;

        bq_wr_ptr <= {WRQ_AW{1'b0}};
        bq_rd_ptr <= {WRQ_AW{1'b0}};
        bq_count <= {(WRQ_AW+1){1'b0}};

        rdq_wr_ptr <= {RDQ_AW{1'b0}};
        rdq_rd_ptr <= {RDQ_AW{1'b0}};
        rdq_count <= {(RDQ_AW+1){1'b0}};
        rd_addr <= 32'h0;
        rd_left <= 8'h0;
        rd_active <= 1'b0;
        rd_error <= 1'b0;

        runtime_rerror_addr_en <= RERROR_ADDR_EN;
        runtime_rerror_addr <= RERROR_ADDR;
        runtime_werror_addr_en <= ERROR_ADDR_EN;
        runtime_werror_addr <= ERROR_ADDR;
        runtime_werror_burst_en <= 1'b0;
        runtime_werror_burst_idx <= 32'h0;
        write_burst_issue_index <= 32'h0;
        debug_write_outstanding <= 32'h0;
        debug_write_peak_outstanding <= 32'h0;

        aw_wait_cnt <= 0;
        w_wait_cnt <= 0;
        b_wait_cnt <= 0;
        ar_wait_cnt <= 0;
        r_wait_cnt <= 0;
    end else begin
        if (wrq_count < WRQ_DEPTH) begin
            if (aw_wait_cnt >= AW_WAIT)
                awready <= 1'b1;
            else begin
                awready <= 1'b0;
                aw_wait_cnt <= aw_wait_cnt + 1;
            end
        end else begin
            awready <= 1'b0;
            aw_wait_cnt <= 0;
        end

        if (aw_push) begin
            wrq_addr[wrq_wr_ptr] <= awaddr;
            wrq_len[wrq_wr_ptr] <= awlen;
            wrq_error[wrq_wr_ptr] <= (runtime_werror_addr_en && (awaddr == runtime_werror_addr)) ||
                                     (runtime_werror_burst_en && (write_burst_issue_index == runtime_werror_burst_idx));
            awready <= 1'b0;
            write_burst_issue_index <= write_burst_issue_index + 1'b1;
        end

        if (wrq_pop) begin
            wr_addr <= wrq_addr[wrq_rd_ptr];
            wr_left <= wrq_len[wrq_rd_ptr];
            wr_error <= wrq_error[wrq_rd_ptr];
            wr_active <= 1'b1;
            w_wait_cnt <= 0;
        end

        if (wr_active && !wready) begin
            if (w_wait_cnt >= W_WAIT)
                wready <= 1'b1;
            else
                w_wait_cnt <= w_wait_cnt + 1;
        end

        if (wready && wvalid) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (wstrb[i] && ((wr_addr + i) < `DMA_SIM_MEM_BYTES))
                    `DMA_SYS_MEM_PATH[wr_addr + i] <= wdata[i*8 +: 8];
            end
            wr_addr <= wr_addr + 8;
            w_wait_cnt <= 0;
            if ((wr_left == 0) || wlast) begin
                wr_active <= 1'b0;
                wready <= 1'b0;
                bq_error[bq_wr_ptr] <= wr_error;
                b_wait_cnt <= 0;
            end else begin
                wr_left <= wr_left - 1'b1;
                wready <= (W_WAIT == 0);
            end
        end

        if (!bvalid && (bq_count != 0)) begin
            if (b_wait_cnt < B_WAIT) begin
                b_wait_cnt <= b_wait_cnt + 1;
            end else begin
                bvalid <= 1'b1;
                bresp <= bq_error[bq_rd_ptr] ? 2'b10 : 2'b00;
            end
        end

        if (bq_pop) begin
            bvalid <= 1'b0;
            b_wait_cnt <= 0;
        end

        if (aw_push)
            wrq_wr_ptr <= wrq_wr_ptr + 1'b1;
        if (wrq_pop)
            wrq_rd_ptr <= wrq_rd_ptr + 1'b1;
        case ({aw_push, wrq_pop})
        2'b10: wrq_count <= wrq_count + 1'b1;
        2'b01: wrq_count <= wrq_count - 1'b1;
        default: begin end
        endcase

        if (bq_push)
            bq_wr_ptr <= bq_wr_ptr + 1'b1;
        if (bq_pop)
            bq_rd_ptr <= bq_rd_ptr + 1'b1;
        case ({bq_push, bq_pop})
        2'b10: bq_count <= bq_count + 1'b1;
        2'b01: bq_count <= bq_count - 1'b1;
        default: begin end
        endcase

        case ({aw_push, bq_pop})
        2'b10: debug_write_outstanding <= debug_write_outstanding + 1'b1;
        2'b01: if (debug_write_outstanding != 0) debug_write_outstanding <= debug_write_outstanding - 1'b1;
        default: begin end
        endcase
        if (aw_push) begin
            if ((debug_write_outstanding + (bq_pop ? 32'd0 : 32'd1)) > debug_write_peak_outstanding)
                debug_write_peak_outstanding <= debug_write_outstanding + (bq_pop ? 32'd0 : 32'd1);
        end

        if (rdq_count < RDQ_DEPTH) begin
            if (ar_wait_cnt >= AR_WAIT)
                arready <= 1'b1;
            else begin
                arready <= 1'b0;
                ar_wait_cnt <= ar_wait_cnt + 1;
            end
        end else begin
            arready <= 1'b0;
            ar_wait_cnt <= 0;
        end

        if (arready && arvalid) begin
            rdq_addr[rdq_wr_ptr] <= araddr;
            rdq_len[rdq_wr_ptr] <= arlen;
            rdq_error[rdq_wr_ptr] <= runtime_rerror_addr_en && (araddr == runtime_rerror_addr);
            rdq_wr_ptr <= rdq_wr_ptr + 1'b1;
            rdq_count <= rdq_count + 1'b1;
            arready <= 1'b0;
        end

        if (rvalid && rready) begin
            rvalid <= 1'b0;
            rlast <= 1'b0;
        end

        if (!rd_active && !rvalid && (rdq_count != 0) && !(arready && arvalid)) begin
            rd_addr <= rdq_addr[rdq_rd_ptr];
            rd_left <= rdq_len[rdq_rd_ptr];
            rd_error <= rdq_error[rdq_rd_ptr];
            rdq_rd_ptr <= rdq_rd_ptr + 1'b1;
            rdq_count <= rdq_count - 1'b1;
            rd_active <= 1'b1;
            r_wait_cnt <= 0;
        end else if (rd_active && !rvalid) begin
            if (r_wait_cnt >= R_WAIT) begin
                for (i = 0; i < 8; i = i + 1) begin
                    if ((rd_addr + i) < `DMA_SIM_MEM_BYTES)
                        rdata[i*8 +: 8] <= `DMA_SYS_MEM_PATH[rd_addr + i];
                    else
                        rdata[i*8 +: 8] <= 8'h0;
                end
                rresp <= rd_error ? 2'b10 : 2'b00;
                rlast <= (rd_left == 0);
                rvalid <= 1'b1;
                rd_addr <= rd_addr + 8;
                r_wait_cnt <= 0;
                if (rd_left == 0)
                    rd_active <= 1'b0;
                else
                    rd_left <= rd_left - 1'b1;
            end else begin
                r_wait_cnt <= r_wait_cnt + 1;
            end
        end
    end
end

endmodule
