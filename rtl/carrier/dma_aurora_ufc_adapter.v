`timescale 1ns/1ps
`include "dma_defs.vh"

// Aurora UFC 适配器把 Core 的消息 entry 拆成 carrier 所需的 128-bit UFC beat，
// 并在接收侧按 beat 重新拼回完整消息。tx/rx index 只描述一条消息内部的位置，
// 不替代 AXI4-Stream payload 的流控。
module dma_aurora_ufc_adapter #(
    parameter integer UFC_AXIS_DATA_W = 64
)(
    input                         clk,
    input                         rstn,

    input                         ufc_tx_valid,
    output                        ufc_tx_ready,
    input      [7:0]              ufc_tx_opcode,
    input      [15:0]             ufc_tx_flow_id,
    input      [31:0]             ufc_tx_arg0,
    input      [31:0]             ufc_tx_arg1,

    output reg                    ufc_rx_valid,
    input                         ufc_rx_ready,
    output reg [7:0]              ufc_rx_opcode,
    output reg [15:0]             ufc_rx_flow_id,
    output reg [31:0]             ufc_rx_arg0,
    output reg [31:0]             ufc_rx_arg1,

    output reg [UFC_AXIS_DATA_W-1:0] aurora_ufc_tx_tdata,
    output reg                    aurora_ufc_tx_tvalid,
    input                         aurora_ufc_tx_tready,
    output reg                    aurora_ufc_tx_tlast,

    input      [UFC_AXIS_DATA_W-1:0] aurora_ufc_rx_tdata,
    input                         aurora_ufc_rx_tvalid,
    output                        aurora_ufc_rx_tready,
    input                         aurora_ufc_rx_tlast,

    output reg                    rx_drop_pulse,
    output reg [3:0]              rx_drop_reason
);

localparam integer BEAT_BYTES = UFC_AXIS_DATA_W / 8;
localparam [1:0] LAST_BEAT_IDX = (UFC_AXIS_DATA_W >= 128) ? 2'd0 : 2'd1;

reg [127:0] tx_packet;
reg [1:0]   tx_idx;
reg         tx_active;
reg [127:0] rx_packet;
reg [1:0]   rx_idx;
wire [127:0] aurora_ufc_rx_ext = aurora_ufc_rx_tdata;

assign ufc_tx_ready = !tx_active && !aurora_ufc_tx_tvalid;
assign aurora_ufc_rx_tready = !ufc_rx_valid;

function [127:0] pack_msg;
    input [7:0] opcode;
    input [15:0] flow_id;
    input [31:0] arg0;
    input [31:0] arg1;
    begin
        pack_msg = 128'h0;
        pack_msg[7:0]    = `DMA_UFC_MSG_MAGIC;
        pack_msg[15:8]   = `DMA_UFC_MSG_VERSION;
        pack_msg[23:16]  = opcode;
        pack_msg[47:32]  = flow_id;
        pack_msg[95:64]  = arg0;
        pack_msg[127:96] = arg1;
    end
endfunction

task load_tx_data;
    input [127:0] packet;
    input [1:0]   idx;
    begin
        if (UFC_AXIS_DATA_W >= 128)
            aurora_ufc_tx_tdata <= packet[UFC_AXIS_DATA_W-1:0];
        else if (idx == 2'd0)
            aurora_ufc_tx_tdata <= packet[UFC_AXIS_DATA_W-1:0];
        else
            aurora_ufc_tx_tdata <= packet[(UFC_AXIS_DATA_W*idx) +: UFC_AXIS_DATA_W];
    end
endtask

task set_drop;
    input [3:0] reason;
    begin
        rx_drop_pulse <= 1'b1;
        rx_drop_reason <= reason;
    end
endtask

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tx_packet <= 128'h0;
        tx_idx <= 2'h0;
        tx_active <= 1'b0;
        aurora_ufc_tx_tdata <= {UFC_AXIS_DATA_W{1'b0}};
        aurora_ufc_tx_tvalid <= 1'b0;
        aurora_ufc_tx_tlast <= 1'b0;
    end else begin
        if (ufc_tx_valid && ufc_tx_ready) begin
            tx_packet <= pack_msg(ufc_tx_opcode, ufc_tx_flow_id, ufc_tx_arg0, ufc_tx_arg1);
            tx_idx <= 2'h0;
            tx_active <= 1'b1;
            aurora_ufc_tx_tvalid <= 1'b1;
            aurora_ufc_tx_tlast <= (LAST_BEAT_IDX == 2'd0);
            load_tx_data(pack_msg(ufc_tx_opcode, ufc_tx_flow_id, ufc_tx_arg0, ufc_tx_arg1), 2'h0);
        end else if (aurora_ufc_tx_tvalid && aurora_ufc_tx_tready) begin
            if (tx_idx == LAST_BEAT_IDX) begin
                tx_active <= 1'b0;
                tx_idx <= 2'h0;
                aurora_ufc_tx_tvalid <= 1'b0;
                aurora_ufc_tx_tlast <= 1'b0;
                aurora_ufc_tx_tdata <= {UFC_AXIS_DATA_W{1'b0}};
            end else begin
                tx_idx <= tx_idx + 1'b1;
                aurora_ufc_tx_tlast <= ((tx_idx + 1'b1) == LAST_BEAT_IDX);
                load_tx_data(tx_packet, tx_idx + 1'b1);
            end
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ufc_rx_valid <= 1'b0;
        ufc_rx_opcode <= 8'h0;
        ufc_rx_flow_id <= 16'h0;
        ufc_rx_arg0 <= 32'h0;
        ufc_rx_arg1 <= 32'h0;
        rx_packet <= 128'h0;
        rx_idx <= 2'h0;
        rx_drop_pulse <= 1'b0;
        rx_drop_reason <= 4'h0;
    end else begin
        rx_drop_pulse <= 1'b0;

        if (ufc_rx_valid && ufc_rx_ready)
            ufc_rx_valid <= 1'b0;

        if (aurora_ufc_rx_tvalid && aurora_ufc_rx_tready) begin
            if (UFC_AXIS_DATA_W >= 128) begin
                rx_packet <= aurora_ufc_rx_ext;
                if (!aurora_ufc_rx_tlast) begin
                    set_drop(1 << `DMA_UFC_ADP_DROP_TLAST);
                end else if (aurora_ufc_rx_ext[7:0] != `DMA_UFC_MSG_MAGIC) begin
                    set_drop(1 << `DMA_UFC_ADP_DROP_MAGIC);
                end else if (aurora_ufc_rx_ext[15:8] != `DMA_UFC_MSG_VERSION) begin
                    set_drop(1 << `DMA_UFC_ADP_DROP_VERSION);
                end else begin
                    ufc_rx_valid <= 1'b1;
                    ufc_rx_opcode <= aurora_ufc_rx_ext[23:16];
                    ufc_rx_flow_id <= aurora_ufc_rx_ext[47:32];
                    ufc_rx_arg0 <= aurora_ufc_rx_ext[95:64];
                    ufc_rx_arg1 <= aurora_ufc_rx_ext[127:96];
                end
            end else if (rx_idx == 2'h0) begin
                rx_packet[UFC_AXIS_DATA_W-1:0] <= aurora_ufc_rx_tdata;
                if (aurora_ufc_rx_tlast) begin
                    rx_idx <= 2'h0;
                    set_drop(1 << `DMA_UFC_ADP_DROP_TLAST);
                end else begin
                    rx_idx <= 2'h1;
                end
            end else begin
                rx_packet[(UFC_AXIS_DATA_W*rx_idx) +: UFC_AXIS_DATA_W] <= aurora_ufc_rx_tdata;
                rx_idx <= 2'h0;
                if (!aurora_ufc_rx_tlast) begin
                    set_drop(1 << `DMA_UFC_ADP_DROP_TLAST);
                end else if (rx_packet[7:0] != `DMA_UFC_MSG_MAGIC) begin
                    set_drop(1 << `DMA_UFC_ADP_DROP_MAGIC);
                end else if (rx_packet[15:8] != `DMA_UFC_MSG_VERSION) begin
                    set_drop(1 << `DMA_UFC_ADP_DROP_VERSION);
                end else begin
                    ufc_rx_valid <= 1'b1;
                    ufc_rx_opcode <= rx_packet[23:16];
                    ufc_rx_flow_id <= rx_packet[47:32];
                    ufc_rx_arg0 <= aurora_ufc_rx_tdata[31:0];
                    ufc_rx_arg1 <= aurora_ufc_rx_tdata[63:32];
                end
            end
        end
    end
end

endmodule
