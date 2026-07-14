`timescale 1ns/1ps
`include "dma_defs.vh"

module mcf_endpoint #(
    parameter integer NUM_SRC = 4,
    parameter integer SL_DATA_WIDTH = 512,
    parameter integer CHANNEL_ID_W = 16,
    parameter integer STREAM_ID_W = 16,
    parameter integer MAX_CHANNELS = 16
)(
    input                               clk,
    input                               rstn,

    input                               ctrl_rx_valid,
    output                              ctrl_rx_ready,
    input      [7:0]                    ctrl_rx_opcode,
    input      [15:0]                   ctrl_rx_channel_id,
    input      [31:0]                   ctrl_rx_arg0,
    input      [31:0]                   ctrl_rx_arg1,
    output reg [MAX_CHANNELS-1:0]       paused_channel_mask,
    output reg [31:0]                   pause_count,
    output reg [31:0]                   resume_count,
    output reg [31:0]                   paused_reject_count,
    output reg [31:0]                   invalid_ctrl_count,

    input      [NUM_SRC-1:0]            src_seg_valid,
    output reg [NUM_SRC-1:0]            src_seg_ready,
    input      [NUM_SRC*CHANNEL_ID_W-1:0] src_channel_id,
    input      [NUM_SRC*32-1:0]         src_payload_len,
    input      [NUM_SRC*STREAM_ID_W-1:0] src_stream_id,
    input      [NUM_SRC*64-1:0]         src_timestamp,
    input      [NUM_SRC*32-1:0]         src_user_meta0,

    input      [NUM_SRC*SL_DATA_WIDTH-1:0] src_tdata,
    input      [NUM_SRC-1:0]            src_tvalid,
    output reg [NUM_SRC-1:0]            src_tready,

    output reg [SL_DATA_WIDTH-1:0]      sl_tx_tdata,
    output reg                          sl_tx_tvalid,
    input                               sl_tx_tready
);

`ifndef SYNTHESIS
initial begin
    if (NUM_SRC < 1)
        $fatal(1, "mcf_endpoint requires NUM_SRC >= 1");
    if (SL_DATA_WIDTH != 512)
        $fatal(1, "mcf_endpoint P0 requires SL_DATA_WIDTH == 512");
    if (CHANNEL_ID_W != 16)
        $fatal(1, "mcf_endpoint P0 requires CHANNEL_ID_W == 16");
    if (STREAM_ID_W != 16)
        $fatal(1, "mcf_endpoint P0 requires STREAM_ID_W == 16");
    if (MAX_CHANNELS < 1 || MAX_CHANNELS > 65536)
        $fatal(1, "mcf_endpoint requires 1 <= MAX_CHANNELS <= 65536");
end
`endif

localparam ST_IDLE         = 3'd0;
localparam ST_HEADER       = 3'd1;
localparam ST_PAYLOAD_LOAD = 3'd2;
localparam ST_PAYLOAD_SEND = 3'd3;

reg [2:0] state;
reg [31:0] rr_ptr;
reg [31:0] active_src;
reg [15:0] active_channel_id;
reg [15:0] active_stream_id;
reg [31:0] active_payload_len;
reg [63:0] active_timestamp;
reg [31:0] active_user_meta0;
reg [31:0] active_payload_beats;
reg [31:0] payload_beat_idx;
reg [31:0] segment_seq;

integer i;
integer scan_i;
integer scan_src;
reg [15:0] scan_ch;
reg found_valid;
reg [31:0] found_src;
reg paused_pending;
wire [511:0] header_beat;
wire [SL_DATA_WIDTH-1:0] active_payload_data;

assign active_payload_data = src_tdata[active_src*SL_DATA_WIDTH +: SL_DATA_WIDTH];
assign ctrl_rx_ready = rstn;

wire ctrl_fire = ctrl_rx_valid && ctrl_rx_ready;

function [7:0] src_byte;
    input [383:0] hdr;
    input integer index;
    begin
        src_byte = hdr[index*8 +: 8];
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
    input [383:0] first_48_bytes;
    integer b;
    reg [31:0] crc;
    begin
        crc = 32'hffff_ffff;
        for (b = 0; b < 48; b = b + 1)
            crc = crc32_byte(crc, src_byte(first_48_bytes, b));
        header_crc32 = crc ^ 32'hffff_ffff;
    end
endfunction

function [511:0] build_header;
    input [15:0] channel_id;
    input [15:0] stream_id;
    input [31:0] payload_len;
    input [31:0] seq;
    input [63:0] timestamp;
    input [31:0] sample_count;
    reg [383:0] hdr0;
    reg [31:0] crc;
    begin
        hdr0[  0 +: 32] = `DMA_FRAME_MAGIC;
        hdr0[ 32 +: 8]  = 8'h07;
        hdr0[ 40 +: 8]  = `DMA_HEADER_BYTES;
        hdr0[ 48 +: 8]  = {4'h0, `DMA_TC_FC};
        hdr0[ 56 +: 8]  = 8'h0;
        hdr0[ 64 +: 16] = channel_id;
        hdr0[ 80 +: 16] = stream_id;
        hdr0[ 96 +: 32] = payload_len;
        hdr0[128 +: 32] = seq;
        hdr0[160 +: 32] = 32'h0;
        hdr0[192 +: 64] = timestamp;
        hdr0[256 +: 64] = 64'h0;
        hdr0[320 +: 32] = sample_count;
        hdr0[352 +: 32] = 32'h0;
        crc = header_crc32(hdr0);
        build_header = {96'h0, 32'h0, crc, hdr0};
    end
endfunction

assign header_beat = build_header(active_channel_id, active_stream_id,
                                  active_payload_len, segment_seq,
                                  active_timestamp, active_user_meta0);

always @(*) begin
    found_valid = 1'b0;
    found_src = rr_ptr;
    paused_pending = 1'b0;
    for (scan_i = 0; scan_i < NUM_SRC; scan_i = scan_i + 1) begin
        scan_src = rr_ptr + scan_i;
        if (scan_src >= NUM_SRC)
            scan_src = scan_src - NUM_SRC;
        scan_ch = src_channel_id[scan_src*CHANNEL_ID_W +: CHANNEL_ID_W];
        if (src_seg_valid[scan_src]) begin
            if (scan_ch < MAX_CHANNELS) begin
                if (paused_channel_mask[scan_ch])
                    paused_pending = 1'b1;
                if (!found_valid && !paused_channel_mask[scan_ch]) begin
                    found_valid = 1'b1;
                    found_src = scan_src;
                end
            end else if (!found_valid) begin
                found_valid = 1'b1;
                found_src = scan_src;
            end
        end
    end
end

always @(*) begin
    src_seg_ready = {NUM_SRC{1'b0}};
    src_tready = {NUM_SRC{1'b0}};
    if (state == ST_IDLE && found_valid)
        src_seg_ready[found_src] = 1'b1;
    if (state == ST_PAYLOAD_LOAD)
        src_tready[active_src] = sl_tx_tready;
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state <= ST_IDLE;
        rr_ptr <= 32'h0;
        active_src <= 32'h0;
        active_channel_id <= 16'h0;
        active_stream_id <= 16'h0;
        active_payload_len <= 32'h0;
        active_timestamp <= 64'h0;
        active_user_meta0 <= 32'h0;
        active_payload_beats <= 32'h0;
        payload_beat_idx <= 32'h0;
        segment_seq <= 32'h0;
        sl_tx_tdata <= {SL_DATA_WIDTH{1'b0}};
        sl_tx_tvalid <= 1'b0;
        paused_channel_mask <= {MAX_CHANNELS{1'b0}};
        pause_count <= 32'h0;
        resume_count <= 32'h0;
        paused_reject_count <= 32'h0;
        invalid_ctrl_count <= 32'h0;
    end else begin
        if (ctrl_fire) begin
            if (ctrl_rx_channel_id < MAX_CHANNELS) begin
                if (ctrl_rx_opcode == `DMA_UFC_OP_PAUSE) begin
                    paused_channel_mask[ctrl_rx_channel_id] <= 1'b1;
                    pause_count <= pause_count + 1'b1;
                end else if (ctrl_rx_opcode == `DMA_UFC_OP_RESUME) begin
                    paused_channel_mask[ctrl_rx_channel_id] <= 1'b0;
                    resume_count <= resume_count + 1'b1;
                end
            end else if ((ctrl_rx_opcode == `DMA_UFC_OP_PAUSE) ||
                         (ctrl_rx_opcode == `DMA_UFC_OP_RESUME)) begin
                invalid_ctrl_count <= invalid_ctrl_count + 1'b1;
            end
        end
        if (state == ST_IDLE && paused_pending)
            paused_reject_count <= paused_reject_count + 1'b1;

        case (state)
        ST_IDLE: begin
            sl_tx_tvalid <= 1'b0;
            payload_beat_idx <= 32'h0;
            if (found_valid) begin
                active_src <= found_src;
                active_channel_id <= src_channel_id[found_src*CHANNEL_ID_W +: CHANNEL_ID_W];
                active_stream_id <= src_stream_id[found_src*STREAM_ID_W +: STREAM_ID_W];
                active_payload_len <= src_payload_len[found_src*32 +: 32];
                active_timestamp <= src_timestamp[found_src*64 +: 64];
                active_user_meta0 <= src_user_meta0[found_src*32 +: 32];
                active_payload_beats <= (src_payload_len[found_src*32 +: 32] + 32'd63) >> 6;
                rr_ptr <= (found_src == (NUM_SRC - 1)) ? 32'h0 : (found_src + 1'b1);
                state <= ST_HEADER;
            end
        end
        ST_HEADER: begin
            sl_tx_tdata <= header_beat;
            sl_tx_tvalid <= 1'b1;
            if (sl_tx_tvalid && sl_tx_tready) begin
                segment_seq <= segment_seq + 1'b1;
                sl_tx_tvalid <= 1'b0;
                if (active_payload_beats == 32'h0)
                    state <= ST_IDLE;
                else
                    state <= ST_PAYLOAD_LOAD;
            end
        end
        ST_PAYLOAD_LOAD: begin
            sl_tx_tvalid <= 1'b0;
            if (src_tvalid[active_src] && sl_tx_tready) begin
                sl_tx_tdata <= active_payload_data;
                sl_tx_tvalid <= 1'b1;
                state <= ST_PAYLOAD_SEND;
            end
        end
        ST_PAYLOAD_SEND: begin
            if (sl_tx_tvalid && sl_tx_tready) begin
                payload_beat_idx <= payload_beat_idx + 1'b1;
                if (payload_beat_idx + 1'b1 >= active_payload_beats) begin
                    sl_tx_tvalid <= 1'b0;
                    state <= ST_IDLE;
                end else begin
                    sl_tx_tvalid <= 1'b0;
                    state <= ST_PAYLOAD_LOAD;
                end
            end
        end
        default: begin
            state <= ST_IDLE;
            sl_tx_tvalid <= 1'b0;
        end
        endcase
    end
end

endmodule
