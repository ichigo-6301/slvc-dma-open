`timescale 1ns/1ps
`include "dma_defs.vh"

// 带弹性边界的 RX parser。输入 header 先锁存，再分拍完成 CRC、校验和输出，
// 因而 parser 的计算延迟不会把上游 ready 直接连到后级状态。out_valid 保持到
// out_ready 握手，等待期间 metadata 与结果必须稳定。
module dma_rx_parser_pipe(
    input              clk,
    input              rstn,
    input              soft_reset,

    input              in_valid,
    output             in_ready,
    input      [511:0] in_header_beat,

    output reg         out_valid,
    input              out_ready,
    output reg         out_header_ok,
    output reg [7:0]   out_version,
    output reg [7:0]   out_header_len,
    output reg [3:0]   out_traffic_class,
    output reg [15:0]  out_flow_id,
    output reg [15:0]  out_msg_id,
    output reg [31:0]  out_payload_len,
    output reg [31:0]  out_aligned_len,
    output reg [31:0]  out_frame_seq,
    output reg [63:0]  out_timestamp,
    output reg [31:0]  out_sample_count
);

`ifndef SYNTHESIS
initial begin
    if (`DMA_HEADER_BYTES != 64)
        $fatal(1, "dma_rx_parser_pipe requires DMA_HEADER_BYTES == 64");
end
`endif

// CRC、静态字段检查和结果发布分开，便于在 header 校验失败时统一回到空闲态。
localparam ST_IDLE     = 2'd0;
localparam ST_CRC      = 2'd1;
localparam ST_VALIDATE = 2'd2;
localparam ST_OUT      = 2'd3;

reg [1:0] state;
reg [511:0] header_reg;
reg [2:0] crc_chunk;
reg [31:0] crc_reg;
reg [31:0] crc_final_q;
reg [31:0] expected_crc_q;
reg        header_static_ok_q;

assign in_ready = (state == ST_IDLE) && (!out_valid || out_ready);

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

function [31:0] crc32_8bytes;
    input [31:0] crc_in;
    input [511:0] beat;
    input integer base;
    integer i;
    reg [31:0] c;
    begin
        c = crc_in;
        for (i = 0; i < 8; i = i + 1)
            c = crc32_byte(c, hdr_byte(beat, base + i));
        crc32_8bytes = c;
    end
endfunction

wire [31:0] crc_next = crc32_8bytes(crc_reg, header_reg, crc_chunk * 8);
wire [31:0] crc_final = crc_next ^ 32'hffff_ffff;
wire [7:0] traffic_class_byte = hdr_byte(header_reg, 6);
wire [31:0] payload_len_w = hdr_u32(header_reg, 12);

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state <= ST_IDLE;
        out_valid <= 1'b0;
    end else if (soft_reset) begin
        state <= ST_IDLE;
        out_valid <= 1'b0;
    end else begin
        if (out_valid && out_ready)
            out_valid <= 1'b0;

        case (state)
        ST_IDLE: begin
            if (in_valid && in_ready) begin
                header_reg <= in_header_beat;
                crc_reg <= 32'hffff_ffff;
                crc_chunk <= 3'h0;
                state <= ST_CRC;
            end
        end
        ST_CRC: begin
            crc_reg <= crc_next;
            if (crc_chunk == 3'd5) begin
                crc_final_q <= crc_final;
                expected_crc_q <= hdr_u32(header_reg, 48);
                header_static_ok_q <= (hdr_u32(header_reg, 0) == `DMA_FRAME_MAGIC) &&
                                      (hdr_byte(header_reg, 4) == 8'h07) &&
                                      (hdr_byte(header_reg, 5) == `DMA_HEADER_BYTES);
                out_version <= hdr_byte(header_reg, 4);
                out_header_len <= hdr_byte(header_reg, 5);
                out_traffic_class <= traffic_class_byte[3:0];
                out_flow_id <= hdr_u16(header_reg, 8);
                out_msg_id <= hdr_u16(header_reg, 10);
                out_payload_len <= payload_len_w;
                out_aligned_len <= (payload_len_w + 32'd63) & 32'hffff_ffc0;
                out_frame_seq <= hdr_u32(header_reg, 16);
                out_timestamp <= hdr_u64(header_reg, 24);
                out_sample_count <= hdr_u32(header_reg, 40);
                state <= ST_VALIDATE;
            end else begin
                crc_chunk <= crc_chunk + 1'b1;
            end
        end
        ST_VALIDATE: begin
            out_header_ok <= header_static_ok_q && (crc_final_q == expected_crc_q);
            out_valid <= 1'b1;
            state <= ST_OUT;
        end
        ST_OUT: begin
            if (!out_valid || out_ready)
                state <= ST_IDLE;
        end
        default: state <= ST_IDLE;
        endcase
    end
end

endmodule
