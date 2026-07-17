`timescale 1ns/1ps
`include "dma_defs.vh"

// 可选 UDP/IPv4 -> SHDR64 RX adapter。输入是 Ethernet II/IPv4/UDP 的 receive
// profile，输出为 DMA 原生 SHDR64 stream；固定剥离 42-byte protocol header，
// 用 22-byte carry 与固定 merge 形成后续 payload beat。
// 该 adapter 不实现 Ethernet FCS、UDP checksum、VLAN/IPv6、fragment reassembly，
// 也不提供 UDP 端到端流控；AXI4-Stream backpressure 只约束本地数据接口。
module dma_udp_ipv4_to_shdr64_adapter #(
    parameter integer MAX_PAYLOAD_BYTES = 4096
)(
    input              clk,
    input              rstn,
    input              soft_reset,

    input      [511:0] s_axis_tdata,
    input       [63:0] s_axis_tkeep,
    input              s_axis_tvalid,
    output             s_axis_tready,
    input              s_axis_tlast,

    output reg [511:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input              m_axis_tready,

    output reg         stat_accept,
    output reg         stat_drop,
    output reg  [7:0]  stat_drop_reason
);

// Drop reason 是软件/仿真可读的分类编码；每个输入包最多发布一次 drop 事件。
localparam [7:0] DROP_NONE              = 8'h00;
localparam [7:0] DROP_ETHERTYPE         = 8'h01;
localparam [7:0] DROP_IPV4_VERSION      = 8'h02;
localparam [7:0] DROP_IPV4_IHL          = 8'h03;
localparam [7:0] DROP_IPV4_PROTOCOL     = 8'h04;
localparam [7:0] DROP_IPV4_FRAGMENT     = 8'h05;
localparam [7:0] DROP_IPV4_TOTAL_LENGTH = 8'h06;
localparam [7:0] DROP_UDP_LENGTH_MIN    = 8'h07;
localparam [7:0] DROP_UDP_EXCEEDS_IP    = 8'h08;
localparam [7:0] DROP_LENGTH_PROFILE    = 8'h09;
localparam [7:0] DROP_HEADER_SHORT      = 8'h0a;
localparam [7:0] DROP_NONLAST_KEEP      = 8'h0b;
localparam [7:0] DROP_LAST_KEEP         = 8'h0c;
localparam [7:0] DROP_TRUNCATED         = 8'h0d;
localparam [7:0] DROP_PAYLOAD_TOO_LARGE = 8'h0e;

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_CRC        = 3'd1;
localparam [2:0] ST_HEADER     = 3'd2;
localparam [2:0] ST_PAYLOAD    = 3'd3;
localparam [2:0] ST_COMPLETE   = 3'd4;
localparam [2:0] ST_DROP_DRAIN = 3'd5;

reg [2:0]   state_q;
reg [511:0] carry_data_q;
reg         input_done_q;
reg         drop_seen_q;
reg [31:0]  input_bytes_q;
reg [31:0]  expected_bytes_q;
reg [31:0]  payload_remaining_q;
reg [31:0]  frame_seq_q;
reg [383:0] header_base_q;
reg [31:0]  crc_q;
reg [2:0]   crc_chunk_q;

wire output_free_w = !m_axis_tvalid || m_axis_tready;
wire output_fire_w = m_axis_tvalid && m_axis_tready;

function [7:0] packet_byte;
    input [511:0] beat;
    input integer index;
    begin
        packet_byte = beat[index*8 +: 8];
    end
endfunction

function [15:0] packet_be16;
    input [511:0] beat;
    input integer index;
    begin
        packet_be16 = {packet_byte(beat, index), packet_byte(beat, index + 1)};
    end
endfunction

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] data;
    integer bit_index;
    reg [31:0] c;
    begin
        c = crc_in ^ {24'h0, data};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
            c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        crc32_byte = c;
    end
endfunction

function [31:0] crc32_8bytes;
    input [31:0] crc_in;
    input [383:0] bytes;
    input integer base;
    integer i;
    reg [31:0] c;
    begin
        c = crc_in;
        for (i = 0; i < 8; i = i + 1)
            c = crc32_byte(c, bytes[(base + i)*8 +: 8]);
        crc32_8bytes = c;
    end
endfunction

function [383:0] build_header_base;
    input [15:0] flow_id;
    input [31:0] payload_len;
    input [31:0] frame_seq;
    reg [383:0] h;
    begin
        h = 384'h0;
        h[0 +: 32] = `DMA_FRAME_MAGIC;
        h[32 +: 8] = 8'h07;
        h[40 +: 8] = `DMA_HEADER_BYTES;
        h[48 +: 8] = {4'h0, `DMA_TC_FC};
        h[64 +: 16] = flow_id;
        h[80 +: 16] = 16'h0000;
        h[96 +: 32] = payload_len;
        h[128 +: 32] = frame_seq;
        build_header_base = h;
    end
endfunction

function [511:0] merge_payload;
    input [511:0] previous_beat;
    input [511:0] current_beat;
    begin
        merge_payload = {current_beat[335:0], previous_beat[511:336]};
    end
endfunction

function [511:0] zero_payload_tail;
    input [511:0] data;
    input [6:0] valid_bytes;
    integer i;
    reg [511:0] masked;
    begin
        masked = 512'h0;
        for (i = 0; i < 64; i = i + 1)
            if (i < valid_bytes)
                masked[i*8 +: 8] = data[i*8 +: 8];
        zero_payload_tail = masked;
    end
endfunction

wire [1:0] keep_count_2_w [0:31];
wire [2:0] keep_count_4_w [0:15];
wire [3:0] keep_count_8_w [0:7];
wire [4:0] keep_count_16_w [0:3];
wire [5:0] keep_count_32_w [0:1];
genvar keep_group;
generate
    for (keep_group = 0; keep_group < 32; keep_group = keep_group + 1) begin : g_keep_count_2
        assign keep_count_2_w[keep_group] =
            s_axis_tkeep[keep_group*2] + s_axis_tkeep[keep_group*2+1];
    end
    for (keep_group = 0; keep_group < 16; keep_group = keep_group + 1) begin : g_keep_count_4
        assign keep_count_4_w[keep_group] =
            keep_count_2_w[keep_group*2] + keep_count_2_w[keep_group*2+1];
    end
    for (keep_group = 0; keep_group < 8; keep_group = keep_group + 1) begin : g_keep_count_8
        assign keep_count_8_w[keep_group] =
            keep_count_4_w[keep_group*2] + keep_count_4_w[keep_group*2+1];
    end
    for (keep_group = 0; keep_group < 4; keep_group = keep_group + 1) begin : g_keep_count_16
        assign keep_count_16_w[keep_group] =
            keep_count_8_w[keep_group*2] + keep_count_8_w[keep_group*2+1];
    end
    for (keep_group = 0; keep_group < 2; keep_group = keep_group + 1) begin : g_keep_count_32
        assign keep_count_32_w[keep_group] =
            keep_count_16_w[keep_group*2] + keep_count_16_w[keep_group*2+1];
    end
endgenerate

wire [6:0]  in_keep_count_w = keep_count_32_w[0] + keep_count_32_w[1];
wire        in_keep_contiguous_w =
    ~|(s_axis_tkeep[63:1] & ~s_axis_tkeep[62:0]);
wire        in_keep_full_w = (s_axis_tkeep == 64'hffff_ffff_ffff_ffff);
wire [15:0] ether_type_w = packet_be16(s_axis_tdata, 12);
wire [7:0]  ip_version_ihl_w = packet_byte(s_axis_tdata, 14);
wire [3:0]  ip_version_w = ip_version_ihl_w[7:4];
wire [3:0]  ip_ihl_w = ip_version_ihl_w[3:0];
wire [15:0] ip_total_length_w = packet_be16(s_axis_tdata, 16);
wire [15:0] ip_fragment_w = packet_be16(s_axis_tdata, 20);
wire [7:0]  ip_protocol_w = packet_byte(s_axis_tdata, 23);
wire [15:0] udp_dst_port_w = packet_be16(s_axis_tdata, 36);
wire [15:0] udp_length_w = packet_be16(s_axis_tdata, 38);
wire [31:0] payload_length_w = (udp_length_w >= 16'd8) ?
                               {16'h0, udp_length_w} - 32'd8 : 32'd0;
wire [31:0] packet_length_w = 32'd34 + {16'h0, udp_length_w};

reg [7:0] first_drop_reason_r;
always @* begin
    first_drop_reason_r = DROP_NONE;
    if (!s_axis_tlast && !in_keep_full_w)
        first_drop_reason_r = DROP_NONLAST_KEEP;
    else if (s_axis_tlast && (!in_keep_contiguous_w || (in_keep_count_w == 0)))
        first_drop_reason_r = DROP_LAST_KEEP;
    else if (in_keep_count_w < 7'd42)
        first_drop_reason_r = DROP_HEADER_SHORT;
    else if (ether_type_w != 16'h0800)
        first_drop_reason_r = DROP_ETHERTYPE;
    else if (ip_version_w != 4)
        first_drop_reason_r = DROP_IPV4_VERSION;
    else if (ip_ihl_w != 5)
        first_drop_reason_r = DROP_IPV4_IHL;
    else if (ip_protocol_w != 8'd17)
        first_drop_reason_r = DROP_IPV4_PROTOCOL;
    else if ((ip_fragment_w & 16'h3fff) != 16'h0000)
        first_drop_reason_r = DROP_IPV4_FRAGMENT;
    else if (ip_total_length_w < 16'd28)
        first_drop_reason_r = DROP_IPV4_TOTAL_LENGTH;
    else if (udp_length_w < 16'd8)
        first_drop_reason_r = DROP_UDP_LENGTH_MIN;
    else if ({16'h0, udp_length_w} > ({16'h0, ip_total_length_w} - 32'd20))
        first_drop_reason_r = DROP_UDP_EXCEEDS_IP;
    else if ({16'h0, udp_length_w} != ({16'h0, ip_total_length_w} - 32'd20))
        first_drop_reason_r = DROP_LENGTH_PROFILE;
    else if (payload_length_w > MAX_PAYLOAD_BYTES)
        first_drop_reason_r = DROP_PAYLOAD_TOO_LARGE;
    else if (s_axis_tlast && ({25'h0, in_keep_count_w} < packet_length_w))
        first_drop_reason_r = DROP_TRUNCATED;
end

wire [31:0] crc_next_w = crc32_8bytes(crc_q, header_base_q, crc_chunk_q * 8);
wire [31:0] crc_final_w = crc_next_w ^ 32'hffff_ffff;
wire [31:0] input_bytes_next_w = input_bytes_q + {25'h0, in_keep_count_w};
wire payload_input_shape_ok_w = s_axis_tlast ?
                                (in_keep_contiguous_w && (in_keep_count_w != 0)) :
                                in_keep_full_w;
wire payload_input_truncated_w = s_axis_tlast &&
                                 (input_bytes_next_w < expected_bytes_q);
wire [511:0] payload_merge_w = merge_payload(carry_data_q, s_axis_tdata);

assign s_axis_tready =
    (state_q == ST_IDLE) ? 1'b1 :
    (state_q == ST_PAYLOAD && (payload_remaining_q > 32'd22)) ? output_free_w :
    (state_q == ST_COMPLETE && !input_done_q) ? 1'b1 :
    (state_q == ST_DROP_DRAIN) ? 1'b1 :
    1'b0;

wire input_fire_w = s_axis_tvalid && s_axis_tready;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state_q <= ST_IDLE;
        input_done_q <= 1'b0;
        drop_seen_q <= 1'b0;
        input_bytes_q <= 32'd0;
        expected_bytes_q <= 32'd0;
        payload_remaining_q <= 32'd0;
        frame_seq_q <= 32'd0;
        crc_q <= 32'hffff_ffff;
        crc_chunk_q <= 3'd0;
        m_axis_tvalid <= 1'b0;
        stat_accept <= 1'b0;
        stat_drop <= 1'b0;
        stat_drop_reason <= DROP_NONE;
    end else if (soft_reset) begin
        state_q <= ST_IDLE;
        input_done_q <= 1'b0;
        drop_seen_q <= 1'b0;
        input_bytes_q <= 32'd0;
        expected_bytes_q <= 32'd0;
        payload_remaining_q <= 32'd0;
        frame_seq_q <= 32'd0;
        crc_q <= 32'hffff_ffff;
        crc_chunk_q <= 3'd0;
        m_axis_tvalid <= 1'b0;
        stat_accept <= 1'b0;
        stat_drop <= 1'b0;
        stat_drop_reason <= DROP_NONE;
    end else begin
        stat_accept <= 1'b0;
        stat_drop <= 1'b0;

        if (output_fire_w)
            m_axis_tvalid <= 1'b0;

        case (state_q)
        ST_IDLE: begin
            if (input_fire_w) begin
                carry_data_q <= s_axis_tdata;
                input_done_q <= s_axis_tlast;
                input_bytes_q <= {25'h0, in_keep_count_w};
                expected_bytes_q <= packet_length_w;
                payload_remaining_q <= payload_length_w;
                header_base_q <= build_header_base(udp_dst_port_w,
                                                   payload_length_w,
                                                   frame_seq_q);
                if (first_drop_reason_r != DROP_NONE) begin
                    stat_drop <= 1'b1;
                    stat_drop_reason <= first_drop_reason_r;
                    state_q <= s_axis_tlast ? ST_IDLE : ST_DROP_DRAIN;
                end else begin
                    drop_seen_q <= 1'b0;
                    crc_q <= 32'hffff_ffff;
                    crc_chunk_q <= 3'd0;
                    state_q <= ST_CRC;
                end
            end
        end

        ST_CRC: begin
            crc_q <= crc_next_w;
            if (crc_chunk_q == 3'd5) begin
                m_axis_tdata <= {64'h0, 32'h0, crc_final_w, header_base_q};
                m_axis_tvalid <= 1'b1;
                state_q <= ST_HEADER;
            end else begin
                crc_chunk_q <= crc_chunk_q + 1'b1;
            end
        end

        ST_HEADER: begin
            if (output_fire_w) begin
                if (payload_remaining_q == 0) begin
                    if (input_done_q) begin
                        stat_accept <= 1'b1;
                        frame_seq_q <= frame_seq_q + 1'b1;
                        state_q <= ST_IDLE;
                    end else begin
                        state_q <= ST_COMPLETE;
                    end
                end else begin
                    state_q <= ST_PAYLOAD;
                end
            end
        end

        ST_PAYLOAD: begin
            if ((payload_remaining_q <= 32'd22) && output_free_w) begin
                m_axis_tdata <= zero_payload_tail(
                    {336'h0, carry_data_q[511:336]},
                    payload_remaining_q[6:0]);
                m_axis_tvalid <= 1'b1;
                payload_remaining_q <= 32'd0;
                state_q <= ST_COMPLETE;
            end else if (input_fire_w) begin
                carry_data_q <= s_axis_tdata;
                input_done_q <= s_axis_tlast;
                input_bytes_q <= input_bytes_next_w;
                if (payload_remaining_q >= 32'd64)
                    m_axis_tdata <= payload_merge_w;
                else
                    m_axis_tdata <= zero_payload_tail(
                        payload_merge_w, payload_remaining_q[6:0]);
                if (payload_remaining_q <= 32'd64)
                    payload_remaining_q <= 32'd0;
                else
                    payload_remaining_q <= payload_remaining_q - 32'd64;
                if (!payload_input_shape_ok_w || payload_input_truncated_w) begin
                    stat_drop <= 1'b1;
                    stat_drop_reason <= !payload_input_shape_ok_w ?
                        (s_axis_tlast ? DROP_LAST_KEEP : DROP_NONLAST_KEEP) :
                        DROP_TRUNCATED;
                    drop_seen_q <= 1'b1;
                    state_q <= s_axis_tlast ? ST_COMPLETE : ST_DROP_DRAIN;
                end else begin
                    m_axis_tvalid <= 1'b1;
                    if (payload_remaining_q <= 32'd64) begin
                        state_q <= ST_COMPLETE;
                    end
                end
            end
        end

        ST_COMPLETE: begin
            if (!input_done_q && input_fire_w) begin
                input_bytes_q <= input_bytes_next_w;
                if (!payload_input_shape_ok_w || payload_input_truncated_w) begin
                    if (!drop_seen_q) begin
                        stat_drop <= 1'b1;
                        stat_drop_reason <= !payload_input_shape_ok_w ?
                            (s_axis_tlast ? DROP_LAST_KEEP : DROP_NONLAST_KEEP) :
                            DROP_TRUNCATED;
                    end
                    drop_seen_q <= 1'b1;
                    if (s_axis_tlast) begin
                        input_done_q <= 1'b1;
                        if (output_free_w)
                            state_q <= ST_IDLE;
                    end
                end else if (s_axis_tlast) begin
                    input_done_q <= 1'b1;
                    if (output_free_w) begin
                        if (!drop_seen_q) begin
                            stat_accept <= 1'b1;
                            frame_seq_q <= frame_seq_q + 1'b1;
                        end
                        state_q <= ST_IDLE;
                    end
                end
            end else if (input_done_q && output_free_w) begin
                if (!drop_seen_q) begin
                    stat_accept <= 1'b1;
                    frame_seq_q <= frame_seq_q + 1'b1;
                end
                state_q <= ST_IDLE;
            end
        end

        ST_DROP_DRAIN: begin
            if (input_fire_w && s_axis_tlast)
                state_q <= ST_IDLE;
        end

        default: begin
            state_q <= ST_IDLE;
            m_axis_tvalid <= 1'b0;
        end
        endcase
    end
end

endmodule
