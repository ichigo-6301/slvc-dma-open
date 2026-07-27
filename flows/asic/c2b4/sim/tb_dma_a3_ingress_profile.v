`timescale 1ns/1ps

`ifndef DMA_A3_CHANNELS
`define DMA_A3_CHANNELS 4
`endif
`ifndef DMA_A3_PAYLOAD_WORDS
`define DMA_A3_PAYLOAD_WORDS 512
`endif
`ifndef DMA_A3_PAYLOAD_AW
`define DMA_A3_PAYLOAD_AW 9
`endif

module tb_dma_a3_ingress_profile;

localparam integer CHANNELS = `DMA_A3_CHANNELS;
localparam integer PAYLOAD_WORDS = `DMA_A3_PAYLOAD_WORDS;
localparam integer PAYLOAD_AW = `DMA_A3_PAYLOAD_AW;
localparam integer META_DEPTH = 2;
localparam integer META_AW = 1;
localparam [3:0] LAST_CH = CHANNELS - 1;
localparam [3:0] UNSUPPORTED_CH = CHANNELS;

reg clk = 1'b0;
always #5 clk = ~clk;
reg rstn = 1'b0;
reg soft_reset = 1'b0;
reg ch_reset_valid = 1'b0;
reg [3:0] ch_reset_ch = 4'h0;
reg [3:0] req_ch = 4'h0;
reg [31:0] req_aligned_len = 32'd64;
wire can_accept_frame;
wire near_full;
wire full;
wire [CHANNELS*32-1:0] used_bytes_flat;
wire [CHANNELS*32-1:0] meta_used_flat;
reg start_frame = 1'b0;
reg [3:0] in_ch = 4'h0;
reg [31:0] in_payload_len = 32'd64;
reg [31:0] in_aligned_len = 32'd64;
reg [31:0] in_frame_seq = 32'h0;
reg [511:0] payload_tdata = 512'h0;
reg payload_tvalid = 1'b0;
wire payload_tready;
wire collect_done;
wire meta_valid;
reg meta_pop = 1'b0;
wire [3:0] out_ch;
wire [31:0] out_frame_seq;
reg payload_rd_req = 1'b0;
reg [PAYLOAD_AW-1:0] payload_rd_index = {PAYLOAD_AW{1'b0}};
wire payload_rd_valid;
wire [63:0] payload_rd_data;

integer errors = 0;
integer cases = 0;
integer lane;
reg [511:0] expected_payload;

dma_rx_fc_ingress_bank #(
    .CHANNELS(CHANNELS),
    .PAYLOAD_WORDS(PAYLOAD_WORDS),
    .PAYLOAD_AW(PAYLOAD_AW),
    .META_DEPTH(META_DEPTH),
    .META_AW(META_AW),
    .WIDE_READ_ENABLE(0)
) u_dut (
    .clk(clk), .rstn(rstn), .soft_reset(soft_reset),
    .ch_reset_valid(ch_reset_valid), .ch_reset_ch(ch_reset_ch),
    .req_ch(req_ch), .req_aligned_len(req_aligned_len),
    .can_accept_frame(can_accept_frame), .near_full(near_full), .full(full),
    .used_bytes_flat(used_bytes_flat), .meta_used_flat(meta_used_flat),
    .start_frame(start_frame), .in_ch(in_ch), .in_tc(4'h0),
    .in_policy(4'h0), .in_flow_id(16'h0), .in_msg_id(16'h0),
    .in_payload_len(in_payload_len), .in_aligned_len(in_aligned_len),
    .in_dst_addr(32'h0), .in_next_wr_ptr(32'h0),
    .in_frame_seq(in_frame_seq), .in_timestamp(64'h0),
    .in_sample_count(32'h0), .in_cpl_en(1'b0), .in_ring(1'b0),
    .in_wrap_before(1'b0), .payload_tdata(payload_tdata),
    .payload_tvalid(payload_tvalid), .payload_tready(payload_tready),
    .collect_done(collect_done), .meta_valid(meta_valid), .meta_pop(meta_pop),
    .out_ch(out_ch), .out_tc(), .out_policy(), .out_flow_id(), .out_msg_id(),
    .out_payload_len(), .out_aligned_len(), .out_dst_addr(),
    .out_next_wr_ptr(), .out_frame_seq(out_frame_seq), .out_timestamp(),
    .out_sample_count(), .out_cpl_en(), .out_ring(), .out_wrap_before(),
    .payload_rd_req(payload_rd_req), .payload_rd_index(payload_rd_index),
    .payload_rd_valid(payload_rd_valid), .payload_rd_data(payload_rd_data),
    .wide_payload_enable(1'b0), .wide_payload_tvalid(),
    .wide_payload_tready(1'b0), .wide_payload_tdata(),
    .wide_payload_tkeep(), .wide_payload_tlast()
);

function [31:0] used_bytes;
    input integer ch;
    used_bytes = used_bytes_flat[ch*32 +: 32];
endfunction

function [31:0] meta_used;
    input integer ch;
    meta_used = meta_used_flat[ch*32 +: 32];
endfunction

function [511:0] make_payload;
    input [7:0] seed;
    integer index;
    begin
        make_payload = 512'h0;
        for (index = 0; index < 8; index = index + 1)
            make_payload[index*64 +: 64] = {seed, index[7:0], 16'h5a3c, 32'h1020_3040};
    end
endfunction

task fail;
    input [511:0] message;
    begin
        $display("Error: %0s", message);
        errors = errors + 1;
        $finish;
    end
endtask

task expect;
    input condition;
    input [511:0] message;
    begin
        if (!condition)
            fail(message);
        cases = cases + 1;
    end
endtask

task send_frame;
    input [3:0] channel;
    input [31:0] sequence;
    input [7:0] seed;
    reg [511:0] data;
    integer guard;
    reg [31:0] before_meta;
    begin
        data = make_payload(seed);
        before_meta = meta_used(channel);
        req_ch = channel;
        req_aligned_len = 32'd64;
        guard = 0;
        while (!can_accept_frame && guard < 100) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (!can_accept_frame)
            fail("frame admission timeout");
        @(negedge clk);
        in_ch = channel;
        in_payload_len = 32'd64;
        in_aligned_len = 32'd64;
        in_frame_seq = sequence;
        start_frame = 1'b1;
        @(posedge clk);
        @(negedge clk);
        start_frame = 1'b0;
        payload_tdata = data;
        payload_tvalid = 1'b1;
        guard = 0;
        while (!payload_tready && guard < 100) begin
            @(posedge clk);
            guard = guard + 1;
        end
        @(posedge clk);
        @(negedge clk);
        payload_tvalid = 1'b0;
        guard = 0;
        while ((meta_used(channel) == before_meta) && guard < 100) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (meta_used(channel) == before_meta)
            fail("frame commit timeout");
    end
endtask

task wait_meta;
    input [3:0] expected_ch;
    input [31:0] expected_seq;
    integer guard;
    begin
        guard = 0;
        while (!meta_valid && guard < 200) begin
            @(posedge clk);
            guard = guard + 1;
        end
        expect(meta_valid, "metadata output timeout");
        expect(out_ch == expected_ch, "round-robin channel mismatch");
        expect(out_frame_seq == expected_seq, "metadata sequence mismatch");
    end
endtask

task check_payload;
    input [7:0] seed;
    reg [511:0] data;
    integer guard;
    begin
        data = make_payload(seed);
        for (lane = 0; lane < 8; lane = lane + 1) begin
            @(negedge clk);
            payload_rd_index = lane[PAYLOAD_AW-1:0];
            payload_rd_req = 1'b1;
            @(posedge clk);
            @(negedge clk);
            payload_rd_req = 1'b0;
            guard = 0;
            while (!payload_rd_valid && guard < 20) begin
                @(posedge clk);
                guard = guard + 1;
            end
            expect(payload_rd_valid, "payload read timeout");
            expect(payload_rd_data == data[lane*64 +: 64], "payload data mismatch");
        end
    end
endtask

task pop_meta;
    begin
        @(negedge clk);
        meta_pop = 1'b1;
        @(posedge clk);
        @(negedge clk);
        meta_pop = 1'b0;
    end
endtask

initial begin
    repeat (6) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);

    req_ch = UNSUPPORTED_CH;
    repeat (2) @(posedge clk);
    expect(!can_accept_frame, "unsupported channel admission");

    send_frame(4'd0, 32'd10, 8'h10);
    send_frame(4'd0, 32'd11, 8'h11);
    req_ch = 4'd0;
    repeat (3) @(posedge clk);
    expect(meta_used(0) == 2, "metadata depth did not fill");
    expect(used_bytes(0) == 128, "used byte accounting mismatch");
    expect(!can_accept_frame && full, "metadata full gate mismatch");
    wait_meta(4'd0, 32'd10);
    check_payload(8'h10);
    pop_meta();
    wait_meta(4'd0, 32'd11);
    check_payload(8'h11);
    pop_meta();
    repeat (5) @(posedge clk);
    expect(meta_used(0) == 0 && used_bytes(0) == 0, "metadata empty accounting mismatch");

    send_frame(LAST_CH, 32'd20, 8'h20);
    send_frame(4'd0, 32'd21, 8'h21);
    wait_meta(LAST_CH, 32'd20);
    pop_meta();
    wait_meta(4'd0, 32'd21);
    pop_meta();

    send_frame(4'd0, 32'd30, 8'h30);
    send_frame(LAST_CH, 32'd31, 8'h31);
    @(negedge clk);
    ch_reset_ch = 4'd0;
    ch_reset_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    ch_reset_valid = 1'b0;
    repeat (5) @(posedge clk);
    expect(meta_used(0) == 0 && used_bytes(0) == 0,
           "per-channel reset did not clear channel zero");
    expect(meta_used(LAST_CH) == 1 && used_bytes(LAST_CH) == 64,
           "per-channel reset disturbed the other channel");
    wait_meta(LAST_CH, 32'd31);
    check_payload(8'h31);
    pop_meta();

    @(negedge clk);
    soft_reset = 1'b1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    soft_reset = 1'b0;
    repeat (4) @(posedge clk);
    expect(!meta_valid && meta_used(0) == 0 && meta_used(LAST_CH) == 0,
           "soft reset valid isolation mismatch");

    $display("PASS tb_dma_a3_ingress_profile channels=%0d payload_words=%0d meta_depth=%0d cases=%0d",
             CHANNELS, PAYLOAD_WORDS, META_DEPTH, cases);
    $finish;
end

endmodule
