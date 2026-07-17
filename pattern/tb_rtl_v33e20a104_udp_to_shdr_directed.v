`timescale 1ns/1ps
`include "dma_defs.vh"

module tb;

reg clk;
reg rstn;
reg soft_reset;
reg [511:0] s_axis_tdata;
reg [63:0] s_axis_tkeep;
reg s_axis_tvalid;
wire s_axis_tready;
reg s_axis_tlast;
wire [511:0] m_axis_tdata;
wire m_axis_tvalid;
wire m_axis_tready;
wire stat_accept;
wire stat_drop;
wire [7:0] stat_drop_reason;

reg payload_ready;
integer segment_beat_index;
integer output_count;
integer accept_count;
integer drop_count;
integer parser_count;
integer errors;
integer timeout;
integer case_index;
reg [511:0] output_beats [0:127];
reg [7:0] packet_bytes [0:8191];

wire parser_in_valid = m_axis_tvalid && (segment_beat_index == 0);
wire parser_in_ready;
wire parser_out_valid;
wire parser_out_header_ok;
wire [7:0] parser_out_version;
wire [7:0] parser_out_header_len;
wire [3:0] parser_out_tc;
wire [15:0] parser_out_flow_id;
wire [15:0] parser_out_msg_id;
wire [31:0] parser_out_payload_len;
wire [31:0] parser_out_aligned_len;
wire [31:0] parser_out_frame_seq;
wire [63:0] parser_out_timestamp;
wire [31:0] parser_out_sample_count;

assign m_axis_tready = (segment_beat_index == 0) ? parser_in_ready : payload_ready;

dma_udp_ipv4_to_shdr64_adapter u_dut (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .stat_accept(stat_accept),
    .stat_drop(stat_drop),
    .stat_drop_reason(stat_drop_reason)
);

dma_rx_parser_pipe u_parser (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .in_valid(parser_in_valid),
    .in_ready(parser_in_ready),
    .in_header_beat(m_axis_tdata),
    .out_valid(parser_out_valid),
    .out_ready(1'b1),
    .out_header_ok(parser_out_header_ok),
    .out_version(parser_out_version),
    .out_header_len(parser_out_header_len),
    .out_traffic_class(parser_out_tc),
    .out_flow_id(parser_out_flow_id),
    .out_msg_id(parser_out_msg_id),
    .out_payload_len(parser_out_payload_len),
    .out_aligned_len(parser_out_aligned_len),
    .out_frame_seq(parser_out_frame_seq),
    .out_timestamp(parser_out_timestamp),
    .out_sample_count(parser_out_sample_count)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

function [7:0] beat_byte;
    input [511:0] beat;
    input integer index;
    begin
        beat_byte = beat[index*8 +: 8];
    end
endfunction

function [15:0] beat_u16;
    input [511:0] beat;
    input integer index;
    begin
        beat_u16 = {beat_byte(beat, index + 1), beat_byte(beat, index)};
    end
endfunction

function [31:0] beat_u32;
    input [511:0] beat;
    input integer index;
    begin
        beat_u32 = {beat_byte(beat, index + 3), beat_byte(beat, index + 2),
                    beat_byte(beat, index + 1), beat_byte(beat, index)};
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
    integer i;
    reg [31:0] c;
    begin
        c = 32'hffff_ffff;
        for (i = 0; i < 48; i = i + 1)
            c = crc32_byte(c, beat_byte(beat, i));
        header_crc32 = c ^ 32'hffff_ffff;
    end
endfunction

task fail;
    input [1023:0] message;
    begin
        errors = errors + 1;
        $display("[ERR] %0s @%0t", message, $time);
    end
endtask

task build_packet;
    input integer payload_len;
    input [15:0] dst_port;
    input integer salt;
    output integer wire_len;
    integer i;
    integer ip_len;
    integer udp_len;
    begin
        ip_len = 28 + payload_len;
        udp_len = 8 + payload_len;
        wire_len = 42 + payload_len;
        if (wire_len < 60)
            wire_len = 60;
        for (i = 0; i < 8192; i = i + 1)
            packet_bytes[i] = 8'h00;
        for (i = 0; i < 6; i = i + 1) begin
            packet_bytes[i] = 8'h10 + i;
            packet_bytes[6+i] = 8'h20 + i;
        end
        packet_bytes[12] = 8'h08;
        packet_bytes[13] = 8'h00;
        packet_bytes[14] = 8'h45;
        packet_bytes[15] = 8'h00;
        packet_bytes[16] = (ip_len >> 8) & 8'hff;
        packet_bytes[17] = ip_len & 8'hff;
        packet_bytes[18] = 8'h12;
        packet_bytes[19] = salt[7:0];
        packet_bytes[20] = 8'h40;
        packet_bytes[21] = 8'h00;
        packet_bytes[22] = 8'h40;
        packet_bytes[23] = 8'h11;
        packet_bytes[26] = 8'h0a;
        packet_bytes[29] = 8'h01;
        packet_bytes[30] = 8'h0a;
        packet_bytes[33] = 8'h02;
        packet_bytes[34] = 8'hc0;
        packet_bytes[35] = 8'h00 | (salt & 8'h3f);
        packet_bytes[36] = dst_port[15:8];
        packet_bytes[37] = dst_port[7:0];
        packet_bytes[38] = (udp_len >> 8) & 8'hff;
        packet_bytes[39] = udp_len & 8'hff;
        for (i = 0; i < payload_len; i = i + 1)
            packet_bytes[42+i] = (i * 37 + salt * 11 + 3) & 8'hff;
    end
endtask

task drive_packet;
    input integer wire_len;
    integer offset;
    integer lane;
    integer valid_bytes;
    reg [511:0] beat;
    reg [63:0] keep;
    begin
        offset = 0;
        @(negedge clk);
        while (offset < wire_len) begin
            valid_bytes = wire_len - offset;
            if (valid_bytes > 64)
                valid_bytes = 64;
            beat = 512'h0;
            keep = 64'h0;
            for (lane = 0; lane < valid_bytes; lane = lane + 1) begin
                beat[lane*8 +: 8] = packet_bytes[offset+lane];
                keep[lane] = 1'b1;
            end
            s_axis_tdata = beat;
            s_axis_tkeep = keep;
            s_axis_tlast = (offset + valid_bytes == wire_len);
            s_axis_tvalid = 1'b1;
            timeout = 0;
            while (!s_axis_tready && timeout < 1000) begin
                timeout = timeout + 1;
                @(negedge clk);
            end
            if (!s_axis_tready)
                fail("input ready timeout");
            @(negedge clk);
            offset = offset + valid_bytes;
        end
        s_axis_tvalid = 1'b0;
        s_axis_tdata = 512'h0;
        s_axis_tkeep = 64'h0;
        s_axis_tlast = 1'b0;
    end
endtask

task check_case;
    input integer payload_len;
    input [15:0] dst_port;
    input integer expected_seq;
    integer wire_len;
    integer expected_beats;
    integer byte_index;
    integer beat_index;
    integer lane;
    integer accept_before;
    integer parser_before;
    begin
        output_count = 0;
        segment_beat_index = 0;
        build_packet(payload_len, dst_port, expected_seq + 1, wire_len);
        accept_before = accept_count;
        parser_before = parser_count;
        drive_packet(wire_len);
        expected_beats = 1 + ((payload_len + 63) / 64);
        timeout = 0;
        while (((accept_count == accept_before) ||
                (output_count < expected_beats) ||
                (parser_count == parser_before)) && timeout < 4000) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        if (timeout >= 4000)
            fail("case completion timeout");
        if (output_count != expected_beats)
            fail("output beat count mismatch");
        if (beat_u32(output_beats[0], 0) !== `DMA_FRAME_MAGIC)
            fail("SHDR magic mismatch");
        if (beat_byte(output_beats[0], 4) !== 8'h07)
            fail("SHDR version mismatch");
        if (beat_byte(output_beats[0], 5) !== 8'd64)
            fail("SHDR header length mismatch");
        if ((beat_byte(output_beats[0], 6) & 8'h0f) !== `DMA_TC_FC)
            fail("SHDR traffic class mismatch");
        if (beat_u16(output_beats[0], 8) !== dst_port)
            fail("SHDR flow id mismatch");
        if (beat_u32(output_beats[0], 12) !== payload_len)
            fail("SHDR payload length mismatch");
        if (beat_u32(output_beats[0], 16) !== expected_seq)
            fail("SHDR frame sequence mismatch");
        if (beat_u32(output_beats[0], 48) !== header_crc32(output_beats[0]))
            fail("SHDR CRC mismatch");
        for (byte_index = 0; byte_index < payload_len; byte_index = byte_index + 1) begin
            beat_index = 1 + (byte_index / 64);
            lane = byte_index % 64;
            if (beat_byte(output_beats[beat_index], lane) !== packet_bytes[42+byte_index])
                fail("payload byte mismatch");
        end
        if (payload_len != 0) begin
            beat_index = (payload_len - 1) / 64 + 1;
            for (lane = payload_len % 64; lane < 64; lane = lane + 1)
                if ((payload_len % 64) != 0 &&
                    beat_byte(output_beats[beat_index], lane) !== 8'h00)
                    fail("payload tail not zero");
        end
        if (drop_count != 0)
            fail("valid case reported drop");
    end
endtask

always @(posedge clk) begin
    if (!rstn || soft_reset) begin
        segment_beat_index <= 0;
    end else begin
        if (m_axis_tvalid && m_axis_tready) begin
            if (output_count < 128)
                output_beats[output_count] <= m_axis_tdata;
            output_count <= output_count + 1;
            segment_beat_index <= segment_beat_index + 1;
        end
        if (stat_accept) begin
            accept_count <= accept_count + 1;
            segment_beat_index <= 0;
        end
        if (stat_drop)
            drop_count <= drop_count + 1;
        if (parser_out_valid) begin
            parser_count <= parser_count + 1;
            if (!parser_out_header_ok) fail("existing parser rejected adapter SHDR");
            if (parser_out_tc !== `DMA_TC_FC) fail("parser traffic class mismatch");
        end
    end
end

reg [511:0] stalled_data_q;
reg stalled_valid_q;
always @(posedge clk) begin
    if (!rstn || soft_reset) begin
        stalled_valid_q <= 1'b0;
    end else begin
        if (m_axis_tvalid && !m_axis_tready) begin
            if (stalled_valid_q && m_axis_tdata !== stalled_data_q)
                fail("output data changed under backpressure");
            stalled_data_q <= m_axis_tdata;
            stalled_valid_q <= 1'b1;
        end else begin
            stalled_valid_q <= 1'b0;
        end
    end
end

initial begin
    rstn = 1'b0;
    soft_reset = 1'b0;
    s_axis_tdata = 512'h0;
    s_axis_tkeep = 64'h0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
    payload_ready = 1'b1;
    segment_beat_index = 0;
    output_count = 0;
    accept_count = 0;
    drop_count = 0;
    parser_count = 0;
    errors = 0;

    repeat (5) @(posedge clk);
    rstn = 1'b1;
    repeat (2) @(posedge clk);

    check_case(0,    16'h4000, 0);
    check_case(1,    16'h4001, 1);
    check_case(21,   16'h4015, 2);
    check_case(22,   16'h4016, 3);
    check_case(23,   16'h4017, 4);
    check_case(31,   16'h401f, 5);
    check_case(63,   16'h403f, 6);
    check_case(64,   16'h4040, 7);
    check_case(65,   16'h4041, 8);
    check_case(127,  16'h407f, 9);
    check_case(128,  16'h4080, 10);
    check_case(255,  16'h40ff, 11);
    check_case(256,  16'h4100, 12);
    check_case(511,  16'h41ff, 13);
    check_case(512,  16'h4200, 14);
    check_case(1023, 16'h43ff, 15);
    check_case(1472, 16'h45c0, 16);
    check_case(4096, 16'h5000, 17);

    repeat (10) @(posedge clk);
    if (errors == 0) begin
        $display("Errors: 0, Warnings: 0");
        $display("PASS tb_rtl_v33e20a104_udp_to_shdr_directed cases=18 parser_checks=%0d", parser_count);
    end else begin
        $display("Errors: %0d, Warnings: 0", errors);
        $fatal(1, "tb_rtl_v33e20a104_udp_to_shdr_directed failed");
    end
    $finish;
end

initial begin
    #2000000;
    $fatal(1, "tb_rtl_v33e20a104_udp_to_shdr_directed timeout");
end

endmodule
