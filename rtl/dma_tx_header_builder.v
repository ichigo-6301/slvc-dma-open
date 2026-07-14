`timescale 1ns/1ps
`include "dma_defs.vh"

module dma_tx_header_builder(
    input      [3:0]  traffic_class,
    input      [15:0] tag_id,
    input      [31:0] payload_len,
    input      [31:0] frame_seq,
    input      [63:0] timestamp,
    input      [31:0] sample_count,
    output     [511:0] header_beat
);

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] data;
    integer b;
    reg [31:0] c;
    begin
        c = crc_in ^ {24'h0, data};
        for (b = 0; b < 8; b = b + 1)
            c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        crc32_byte = c;
    end
endfunction

function [31:0] header_crc32;
    input [383:0] first_48_bytes;
    integer b;
    reg [31:0] crc;
    begin
        crc = 32'hffff_ffff;
        for (b = 0; b < 48; b = b + 1)
            crc = crc32_byte(crc, first_48_bytes[b*8 +: 8]);
        header_crc32 = crc ^ 32'hffff_ffff;
    end
endfunction

wire [15:0] flow_id = (traffic_class == `DMA_TC_AUX) ? 16'h0 : tag_id;
wire [15:0] msg_id  = (traffic_class == `DMA_TC_AUX) ? tag_id : 16'h0;
wire [383:0] hdr0;
wire [31:0] crc;

assign hdr0[  0 +: 32] = `DMA_FRAME_MAGIC;
assign hdr0[ 32 +: 8]  = 8'h07;
assign hdr0[ 40 +: 8]  = `DMA_HEADER_BYTES;
assign hdr0[ 48 +: 8]  = {4'h0, traffic_class};
assign hdr0[ 56 +: 8]  = 8'h0;
assign hdr0[ 64 +: 16] = flow_id;
assign hdr0[ 80 +: 16] = msg_id;
assign hdr0[ 96 +: 32] = payload_len;
assign hdr0[128 +: 32] = frame_seq;
assign hdr0[160 +: 32] = 32'h0;
assign hdr0[192 +: 64] = timestamp;
assign hdr0[256 +: 64] = 64'h0;
assign hdr0[320 +: 32] = sample_count;
assign hdr0[352 +: 32] = 32'h0;

assign crc = header_crc32(hdr0);
assign header_beat = {96'h0, 32'h0, crc, hdr0};

endmodule
