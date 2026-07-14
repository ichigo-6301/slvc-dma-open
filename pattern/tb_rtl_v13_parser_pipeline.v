`timescale 1ns/1ps
`include "dma_defs.vh"

module tb;

reg clk;
reg rstn;

reg         in_valid;
wire        in_ready;
reg [511:0] in_header_beat;

wire        out_valid;
reg         out_ready;
wire        out_header_ok;
wire [7:0]  out_version;
wire [7:0]  out_header_len;
wire [3:0]  out_traffic_class;
wire [15:0] out_flow_id;
wire [15:0] out_msg_id;
wire [31:0] out_payload_len;
wire [31:0] out_aligned_len;
wire [31:0] out_frame_seq;
wire [63:0] out_timestamp;
wire [31:0] out_sample_count;

reg [511:0] sl_s_data;
reg         sl_s_valid;
wire        sl_s_ready;
wire [511:0] sl_m_data;
wire        sl_m_valid;
reg         sl_m_ready;

integer errors;
integer timeout;

dma_rx_parser_pipe u_parser (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(1'b0),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .in_header_beat(in_header_beat),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_header_ok(out_header_ok),
    .out_version(out_version),
    .out_header_len(out_header_len),
    .out_traffic_class(out_traffic_class),
    .out_flow_id(out_flow_id),
    .out_msg_id(out_msg_id),
    .out_payload_len(out_payload_len),
    .out_aligned_len(out_aligned_len),
    .out_frame_seq(out_frame_seq),
    .out_timestamp(out_timestamp),
    .out_sample_count(out_sample_count)
);

dma_axis_register_slice #(
    .DATA_WIDTH(512)
) u_slice (
    .clk(clk),
    .rstn(rstn),
    .s_axis_tdata(sl_s_data),
    .s_axis_tvalid(sl_s_valid),
    .s_axis_tready(sl_s_ready),
    .m_axis_tdata(sl_m_data),
    .m_axis_tvalid(sl_m_valid),
    .m_axis_tready(sl_m_ready)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

function [7:0] hdr_byte;
    input [511:0] beat;
    input integer index;
    begin
        hdr_byte = beat[index*8 +: 8];
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
            c = crc32_byte(c, hdr_byte(beat, i));
        header_crc32 = c ^ 32'hffff_ffff;
    end
endfunction

function [511:0] build_header;
    input [3:0] tc;
    input [15:0] flow_id;
    input [15:0] msg_id;
    input [31:0] payload_len;
    input [31:0] frame_seq;
    input [63:0] timestamp;
    input [31:0] sample_count;
    input corrupt_crc;
    reg [511:0] b;
    reg [31:0] crc;
    begin
        b = 512'h0;
        b[0*8 +: 8] = 8'h46;
        b[1*8 +: 8] = 8'h44;
        b[2*8 +: 8] = 8'h4d;
        b[3*8 +: 8] = 8'h41;
        b[4*8 +: 8] = 8'h07;
        b[5*8 +: 8] = 8'd64;
        b[6*8 +: 8] = {4'h0, tc};
        b[8*8 +: 8] = flow_id[7:0];
        b[9*8 +: 8] = flow_id[15:8];
        b[10*8 +: 8] = msg_id[7:0];
        b[11*8 +: 8] = msg_id[15:8];
        b[12*8 +: 8] = payload_len[7:0];
        b[13*8 +: 8] = payload_len[15:8];
        b[14*8 +: 8] = payload_len[23:16];
        b[15*8 +: 8] = payload_len[31:24];
        b[16*8 +: 8] = frame_seq[7:0];
        b[17*8 +: 8] = frame_seq[15:8];
        b[18*8 +: 8] = frame_seq[23:16];
        b[19*8 +: 8] = frame_seq[31:24];
        b[24*8 +: 8] = timestamp[7:0];
        b[25*8 +: 8] = timestamp[15:8];
        b[26*8 +: 8] = timestamp[23:16];
        b[27*8 +: 8] = timestamp[31:24];
        b[28*8 +: 8] = timestamp[39:32];
        b[29*8 +: 8] = timestamp[47:40];
        b[30*8 +: 8] = timestamp[55:48];
        b[31*8 +: 8] = timestamp[63:56];
        b[40*8 +: 8] = sample_count[7:0];
        b[41*8 +: 8] = sample_count[15:8];
        b[42*8 +: 8] = sample_count[23:16];
        b[43*8 +: 8] = sample_count[31:24];
        crc = header_crc32(b);
        if (corrupt_crc)
            crc = crc ^ 32'h0000_0001;
        b[48*8 +: 8] = crc[7:0];
        b[49*8 +: 8] = crc[15:8];
        b[50*8 +: 8] = crc[23:16];
        b[51*8 +: 8] = crc[31:24];
        build_header = b;
    end
endfunction

task fail;
    input [1023:0] msg;
    begin
        errors = errors + 1;
        $display("[ERR] %0s @%0t", msg, $time);
    end
endtask

task drive_header;
    input [511:0] h;
    begin
        @(negedge clk);
        timeout = 0;
        while (!in_ready && timeout < 100) begin
            timeout = timeout + 1;
            @(negedge clk);
        end
        if (!in_ready)
            fail("parser in_ready timeout");
        in_header_beat = h;
        in_valid = 1'b1;
        @(negedge clk);
        in_valid = 1'b0;
        in_header_beat = 512'h0;
    end
endtask

task wait_parser_valid;
    begin
        timeout = 0;
        while (!out_valid && timeout < 100) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        if (!out_valid)
            fail("parser out_valid timeout");
    end
endtask

task check_valid_header;
    input [511:0] h;
    input [3:0] tc;
    input [15:0] flow_id;
    input [15:0] msg_id;
    input [31:0] payload_len;
    input [31:0] frame_seq;
    input [63:0] timestamp;
    input [31:0] sample_count;
    begin
        out_ready = 1'b0;
        drive_header(h);
        wait_parser_valid();
        repeat (4) begin
            @(posedge clk);
            if (!out_valid)
                fail("out_valid dropped while out_ready=0");
            if (out_payload_len !== payload_len)
                fail("payload_len changed while stalled");
        end
        if (!out_header_ok) fail("valid header rejected");
        if (out_version !== 8'h07) fail("version mismatch");
        if (out_header_len !== 8'd64) fail("header_len mismatch");
        if (out_traffic_class !== tc) fail("traffic_class mismatch");
        if (out_flow_id !== flow_id) fail("flow_id mismatch");
        if (out_msg_id !== msg_id) fail("msg_id mismatch");
        if (out_payload_len !== payload_len) fail("payload_len mismatch");
        if (out_aligned_len !== ((payload_len + 32'd63) & 32'hffff_ffc0)) fail("aligned_len mismatch");
        if (out_frame_seq !== frame_seq) fail("frame_seq mismatch");
        if (out_timestamp !== timestamp) fail("timestamp mismatch");
        if (out_sample_count !== sample_count) fail("sample_count mismatch");
        @(negedge clk);
        out_ready = 1'b1;
        @(negedge clk);
        out_ready = 1'b0;
    end
endtask

task check_bad_crc;
    input [511:0] h;
    begin
        out_ready = 1'b1;
        drive_header(h);
        wait_parser_valid();
        if (out_header_ok)
            fail("bad CRC header accepted");
        @(negedge clk);
        out_ready = 1'b0;
    end
endtask

task check_slice_stall;
    reg [511:0] first_word;
    reg [511:0] second_word;
    begin
        first_word = {8{64'h0123_4567_89ab_cdef}};
        second_word = {8{64'hfedc_ba98_7654_3210}};
        sl_m_ready = 1'b0;
        @(negedge clk);
        sl_s_data = first_word;
        sl_s_valid = 1'b1;
        @(negedge clk);
        sl_s_valid = 1'b0;
        sl_s_data = second_word;
        repeat (3) begin
            @(posedge clk);
            if (!sl_m_valid)
                fail("slice m_valid dropped during stall");
            if (sl_m_data !== first_word)
                fail("slice data changed during stall");
            if (sl_s_ready)
                fail("slice accepted second word while full");
        end
        @(negedge clk);
        sl_m_ready = 1'b1;
        @(negedge clk);
        sl_m_ready = 1'b0;
        if (sl_m_valid)
            fail("slice valid did not clear after transfer");
    end
endtask

initial begin
    errors = 0;
    rstn = 1'b0;
    in_valid = 1'b0;
    in_header_beat = 512'h0;
    out_ready = 1'b0;
    sl_s_data = 512'h0;
    sl_s_valid = 1'b0;
    sl_m_ready = 1'b0;

    repeat (5) @(posedge clk);
    rstn = 1'b1;
    repeat (2) @(posedge clk);

    check_valid_header(
        build_header(`DMA_TC_FC, 16'h1234, 16'h0000, 32'd65, 32'h0102_0304,
                     64'h1122_3344_5566_7788, 32'ha5a5_5a5a, 1'b0),
        `DMA_TC_FC, 16'h1234, 16'h0000, 32'd65, 32'h0102_0304,
        64'h1122_3344_5566_7788, 32'ha5a5_5a5a
    );

    check_bad_crc(
        build_header(`DMA_TC_FC, 16'h1234, 16'h0000, 32'd128, 32'h0000_0002,
                     64'h0, 32'h0, 1'b1)
    );

    check_valid_header(
        build_header(`DMA_TC_AUX, 16'h0000, 16'hbeef, 32'd4096, 32'h0000_00ff,
                     64'h0102_0304_0506_0708, 32'h0000_0011, 1'b0),
        `DMA_TC_AUX, 16'h0000, 16'hbeef, 32'd4096, 32'h0000_00ff,
        64'h0102_0304_0506_0708, 32'h0000_0011
    );

    check_slice_stall();

    repeat (5) @(posedge clk);
    if (errors == 0)
        $display("Errors: 0, Warnings: 0");
    else
        $display("Errors: %0d, Warnings: 0", errors);
    $finish;
end

endmodule
