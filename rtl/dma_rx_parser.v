`timescale 1ns/1ps
`include "dma_defs.vh"

// RX 入口的组合 SHDR64 解析器：从单个 512-bit header beat 提取 metadata，
// 同时计算固定格式 header 的 CRC 和静态合法性。它只处理 Header，不消费 payload；
// 下游 channel match/admission 使用输出 metadata 决定是否接收本帧。
module dma_rx_parser(
    input      [511:0] header_beat,
    output             header_ok,
    output     [7:0]   version,
    output     [7:0]   header_len,
    output     [3:0]   traffic_class,
    output     [15:0]  flow_id,
    output     [15:0]  msg_id,
    output     [31:0]  payload_len,
    output     [31:0]  aligned_len,
    output     [31:0]  frame_seq,
    output     [63:0]  timestamp,
    output     [31:0]  sample_count
);

initial begin
    if (`DMA_HEADER_BYTES != 64)
        $fatal(1, "dma_rx_parser requires DMA_HEADER_BYTES == 64");
end

function [7:0] hdr_byte;
    input [511:0] beat;
    input integer index;
    begin
        hdr_byte = beat[index*8 +: 8];
    end
endfunction

function [15:0] hdr_u16;
    input [511:0] beat;
    input integer index;
    begin
        hdr_u16 = {hdr_byte(beat, index+1), hdr_byte(beat, index)};
    end
endfunction

function [31:0] hdr_u32;
    input [511:0] beat;
    input integer index;
    begin
        hdr_u32 = {hdr_byte(beat, index+3), hdr_byte(beat, index+2),
                   hdr_byte(beat, index+1), hdr_byte(beat, index)};
    end
endfunction

function [63:0] hdr_u64;
    input [511:0] beat;
    input integer index;
    begin
        hdr_u64 = {hdr_u32(beat, index+4), hdr_u32(beat, index)};
    end
endfunction

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
    input [511:0] beat;
    integer b;
    reg [31:0] crc;
    begin
        crc = 32'hffff_ffff;
        for (b = 0; b < 48; b = b + 1)
            crc = crc32_byte(crc, hdr_byte(beat, b));
        header_crc32 = crc ^ 32'hffff_ffff;
    end
endfunction

wire [7:0] traffic_class_byte = hdr_byte(header_beat, 6);

assign version       = hdr_byte(header_beat, 4);
assign header_len    = hdr_byte(header_beat, 5);
assign traffic_class = traffic_class_byte[3:0];
assign flow_id       = hdr_u16(header_beat, 8);
assign msg_id        = hdr_u16(header_beat, 10);
assign payload_len   = hdr_u32(header_beat, 12);
assign aligned_len   = (payload_len + 32'd63) & 32'hffff_ffc0;
assign frame_seq     = hdr_u32(header_beat, 16);
assign timestamp     = hdr_u64(header_beat, 24);
assign sample_count  = hdr_u32(header_beat, 40);

assign header_ok = (hdr_u32(header_beat, 0) == `DMA_FRAME_MAGIC) &&
                   (version == 8'h07) &&
                   (header_len == `DMA_HEADER_BYTES) &&
                   (header_crc32(header_beat) == hdr_u32(header_beat, 48));

endmodule
