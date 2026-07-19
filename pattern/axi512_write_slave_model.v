`timescale 1ns/1ps
`include "dma_sim_def.vh"

module axi512_write_slave_model #(
    parameter integer RANDOM_STALL = 0,
    parameter integer RANDOM_SEED = 32'h5120_2001,
    parameter integer ERROR_ADDR_EN = 0,
    parameter [31:0] ERROR_ADDR = 32'h0
)(
    input               aclk,
    input               arstn,
    input      [31:0]   awaddr,
    input      [7:0]    awlen,
    input      [2:0]    awsize,
    input      [1:0]    awburst,
    input               awvalid,
    output reg          awready,
    input      [511:0]  wdata,
    input      [63:0]   wstrb,
    input               wlast,
    input               wvalid,
    output reg          wready,
    output reg [1:0]    bresp,
    output reg          bvalid,
    input               bready
);

localparam integer Q_DEPTH = 16;

reg [31:0] aw_addr_q [0:Q_DEPTH-1];
reg [7:0]  aw_len_q [0:Q_DEPTH-1];
reg        aw_error_q [0:Q_DEPTH-1];
integer aw_wr_ptr;
integer aw_rd_ptr;
integer aw_count;

reg [1:0] b_resp_q [0:Q_DEPTH-1];
integer b_wr_ptr;
integer b_rd_ptr;
integer b_count;

reg wr_active;
reg [31:0] wr_addr;
reg [7:0] wr_left;
reg wr_error;
reg [31:0] lfsr_q;
integer aw_count_next;
integer b_count_next;
integer i;

wire aw_fire = awvalid && awready;
wire w_fire = wvalid && wready;

always @(negedge aclk or negedge arstn) begin
    if (!arstn) begin
        lfsr_q <= RANDOM_SEED;
        awready <= 1'b0;
        wready <= 1'b0;
    end else begin
        lfsr_q <= {lfsr_q[30:0], lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
        awready <= (aw_count < Q_DEPTH) &&
                   (!RANDOM_STALL || lfsr_q[0] || lfsr_q[4]);
        wready <= wr_active &&
                  (!RANDOM_STALL || lfsr_q[1] || lfsr_q[5]);
    end
end

always @(posedge aclk or negedge arstn) begin
    if (!arstn) begin
        aw_wr_ptr = 0;
        aw_rd_ptr = 0;
        aw_count = 0;
        b_wr_ptr = 0;
        b_rd_ptr = 0;
        b_count = 0;
        wr_active <= 1'b0;
        wr_addr <= 32'h0;
        wr_left <= 8'h0;
        wr_error <= 1'b0;
        bresp <= 2'b00;
        bvalid <= 1'b0;
    end else begin
        aw_count_next = aw_count;
        b_count_next = b_count;

        if (aw_fire) begin
            if (awsize != 3'd6)
                $fatal(1, "axi512_write_slave_model expected AWSIZE=6");
            if (awburst != 2'b01)
                $fatal(1, "axi512_write_slave_model expected INCR burst");
            if (awaddr[5:0] != 0)
                $fatal(1, "axi512_write_slave_model saw unaligned AWADDR");
            if ((awaddr[11:0] + ((awlen + 1'b1) << 6)) > 4096)
                $fatal(1, "axi512_write_slave_model burst crossed 4KB");
            aw_addr_q[aw_wr_ptr] = awaddr;
            aw_len_q[aw_wr_ptr] = awlen;
            aw_error_q[aw_wr_ptr] = ERROR_ADDR_EN && (awaddr == ERROR_ADDR);
            aw_wr_ptr = (aw_wr_ptr + 1) % Q_DEPTH;
            aw_count_next = aw_count_next + 1;
        end

        if (!wr_active && (aw_count_next != 0)) begin
            wr_addr <= aw_addr_q[aw_rd_ptr];
            wr_left <= aw_len_q[aw_rd_ptr];
            wr_error <= aw_error_q[aw_rd_ptr];
            aw_rd_ptr = (aw_rd_ptr + 1) % Q_DEPTH;
            aw_count_next = aw_count_next - 1;
            wr_active <= 1'b1;
        end

        if (w_fire) begin
            if (!wr_active)
                $fatal(1, "axi512_write_slave_model saw W without AW");
            if (wlast != (wr_left == 0))
                $fatal(1, "axi512_write_slave_model WLAST mismatch");
            for (i = 0; i < 64; i = i + 1) begin
                if (wstrb[i] && ((wr_addr + i) < `DMA_SIM_MEM_BYTES))
                    `DMA_SYS_MEM_PATH[wr_addr + i] <= wdata[i*8 +: 8];
            end
            wr_addr <= wr_addr + 32'd64;
            if (wr_left == 0) begin
                wr_active <= 1'b0;
                b_resp_q[b_wr_ptr] = wr_error ? 2'b10 : 2'b00;
                b_wr_ptr = (b_wr_ptr + 1) % Q_DEPTH;
                b_count_next = b_count_next + 1;
            end else begin
                wr_left <= wr_left - 1'b1;
            end
        end

        if (bvalid && bready) begin
            bvalid <= 1'b0;
        end else if (!bvalid && (b_count_next != 0)) begin
            bresp <= b_resp_q[b_rd_ptr];
            b_rd_ptr = (b_rd_ptr + 1) % Q_DEPTH;
            b_count_next = b_count_next - 1;
            bvalid <= 1'b1;
        end

        aw_count = aw_count_next;
        b_count = b_count_next;
    end
end

endmodule
