`timescale 1ns/1ps
`include "dma_sim_def.vh"

module aurora_ufc_bfm #(
    parameter integer UFC_AXIS_DATA_W = 64
)(
    input                         clk,
    input                         rstn,

    input      [UFC_AXIS_DATA_W-1:0] tx_tdata,
    input                         tx_tvalid,
    output reg                    tx_tready,
    input                         tx_tlast,

    output reg [UFC_AXIS_DATA_W-1:0] rx_tdata,
    output reg                    rx_tvalid,
    input                         rx_tready,
    output reg                    rx_tlast
);

reg [127:0] tx_pkt;
reg [1:0]   tx_idx;
reg         random_ready_en;
integer     ready_seed;
integer     ready_stall_pct;

integer tx_msg_count;
reg [7:0]  last_tx_opcode;
reg [15:0] last_tx_flow_id;
reg [31:0] last_tx_arg0;
reg [31:0] last_tx_arg1;
reg        tx_format_error;

initial begin
    tx_tready = 1'b1;
    rx_tdata = {UFC_AXIS_DATA_W{1'b0}};
    rx_tvalid = 1'b0;
    rx_tlast = 1'b0;
    tx_pkt = 128'h0;
    tx_idx = 2'h0;
    random_ready_en = 1'b0;
    ready_seed = 32'h1234_5678;
    ready_stall_pct = 0;
    tx_msg_count = 0;
    last_tx_opcode = 8'h0;
    last_tx_flow_id = 16'h0;
    last_tx_arg0 = 32'h0;
    last_tx_arg1 = 32'h0;
    tx_format_error = 1'b0;
end

function integer rand_mod100;
    input dummy;
    integer r;
    begin
        r = $random(ready_seed);
        if (r < 0)
            r = -r;
        rand_mod100 = r % 100;
    end
endfunction

task set_ready_fixed;
    input ready;
    begin
        random_ready_en = 1'b0;
        tx_tready = ready;
    end
endtask

task set_ready_random;
    input integer seed;
    input integer stall_pct;
    begin
        ready_seed = seed;
        ready_stall_pct = stall_pct;
        random_ready_en = 1'b1;
    end
endtask

function [127:0] pack_msg;
    input [7:0] opcode;
    input [15:0] flow_id;
    input [31:0] arg0;
    input [31:0] arg1;
    input        good_magic;
    input        good_version;
    begin
        pack_msg = 128'h0;
        pack_msg[7:0]    = good_magic ? `DMA_UFC_MSG_MAGIC : 8'h00;
        pack_msg[15:8]   = good_version ? `DMA_UFC_MSG_VERSION : 8'h00;
        pack_msg[23:16]  = opcode;
        pack_msg[47:32]  = flow_id;
        pack_msg[95:64]  = arg0;
        pack_msg[127:96] = arg1;
    end
endfunction

task send_rx_msg;
    input [7:0] opcode;
    input [15:0] flow_id;
    input [31:0] arg0;
    input [31:0] arg1;
    input        good_magic;
    input        good_version;
    input        good_tlast;
    reg [127:0] pkt;
    begin
        pkt = pack_msg(opcode, flow_id, arg0, arg1, good_magic, good_version);
        @(posedge clk);
        rx_tdata <= pkt[63:0];
        rx_tlast <= 1'b0;
        rx_tvalid <= 1'b1;
        while (!rx_tready)
            @(posedge clk);
        @(posedge clk);
        rx_tdata <= pkt[127:64];
        rx_tlast <= good_tlast;
        while (!rx_tready)
            @(posedge clk);
        @(posedge clk);
        rx_tvalid <= 1'b0;
        rx_tlast <= 1'b0;
        rx_tdata <= {UFC_AXIS_DATA_W{1'b0}};
    end
endtask

task wait_tx_count;
    input integer exp_count;
    input integer timeout_cycles;
    integer poll;
    begin
        poll = 0;
        while ((tx_msg_count < exp_count) && (poll < timeout_cycles)) begin
            @(posedge clk);
            poll = poll + 1;
        end
        if (poll >= timeout_cycles) begin
            $display("Error: timeout waiting Aurora UFC TX count exp=%0d got=%0d",
                     exp_count, tx_msg_count);
            $finish;
        end
    end
endtask

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tx_tready <= 1'b1;
        tx_pkt <= 128'h0;
        tx_idx <= 2'h0;
        tx_msg_count <= 0;
        tx_format_error <= 1'b0;
    end else begin
        if (random_ready_en)
            tx_tready <= (rand_mod100(1'b0) >= ready_stall_pct);

        if (tx_tvalid && tx_tready) begin
            if (tx_idx == 2'h0) begin
                tx_pkt[63:0] <= tx_tdata[63:0];
                if (tx_tlast) begin
                    tx_idx <= 2'h0;
                    tx_format_error <= 1'b1;
                end else begin
                    tx_idx <= 2'h1;
                end
            end else begin
                tx_pkt[127:64] <= tx_tdata[63:0];
                tx_idx <= 2'h0;
                if (!tx_tlast) begin
                    tx_format_error <= 1'b1;
                end else begin
                    tx_msg_count <= tx_msg_count + 1;
                    last_tx_opcode <= tx_pkt[23:16];
                    last_tx_flow_id <= tx_pkt[47:32];
                    last_tx_arg0 <= tx_tdata[31:0];
                    last_tx_arg1 <= tx_tdata[63:32];
                    if ((tx_pkt[7:0] != `DMA_UFC_MSG_MAGIC) ||
                        (tx_pkt[15:8] != `DMA_UFC_MSG_VERSION))
                        tx_format_error <= 1'b1;
                end
            end
        end
    end
end

endmodule
