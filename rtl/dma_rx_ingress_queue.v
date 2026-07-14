`timescale 1ns/1ps
`include "dma_defs.vh"

module dma_rx_ingress_queue #(
    parameter PAYLOAD_WORDS = 2048,
    parameter PAYLOAD_AW    = 11,
    parameter META_DEPTH    = 16,
    parameter META_AW       = 4
)(
    input             clk,
    input             rstn,

    input      [31:0] req_aligned_len,
    output            can_accept_frame,
    output            near_full,
    output            full,

    input             start_frame,
    input      [3:0]  in_ch,
    input      [3:0]  in_tc,
    input      [3:0]  in_policy,
    input      [15:0] in_flow_id,
    input      [15:0] in_msg_id,
    input      [31:0] in_payload_len,
    input      [31:0] in_aligned_len,
    input      [31:0] in_dst_addr,
    input      [31:0] in_frame_seq,
    input      [63:0] in_timestamp,
    input      [31:0] in_sample_count,
    input             in_cpl_en,
    input             in_ring,

    input      [511:0] payload_tdata,
    input              payload_tvalid,
    output             payload_tready,
    output reg         collect_done,

    output             meta_valid,
    input              meta_pop,
    output      [3:0]  out_ch,
    output      [3:0]  out_tc,
    output      [3:0]  out_policy,
    output     [15:0]  out_flow_id,
    output     [15:0]  out_msg_id,
    output     [31:0]  out_payload_len,
    output     [31:0]  out_aligned_len,
    output     [31:0]  out_dst_addr,
    output     [31:0]  out_frame_seq,
    output     [63:0]  out_timestamp,
    output     [31:0]  out_sample_count,
    output             out_cpl_en,
    output             out_ring,
    input      [PAYLOAD_AW-1:0] payload_rd_index,
    output     [63:0]  payload_rd_data,
    output     [31:0]  used_bytes,
    output     [META_AW:0] meta_used
);

reg [63:0] payload_mem [0:PAYLOAD_WORDS-1];

reg [3:0]  meta_ch [0:META_DEPTH-1];
reg [3:0]  meta_tc [0:META_DEPTH-1];
reg [3:0]  meta_policy [0:META_DEPTH-1];
reg [15:0] meta_flow_id [0:META_DEPTH-1];
reg [15:0] meta_msg_id [0:META_DEPTH-1];
reg [31:0] meta_payload_len [0:META_DEPTH-1];
reg [31:0] meta_aligned_len [0:META_DEPTH-1];
reg [31:0] meta_dst_addr [0:META_DEPTH-1];
reg [31:0] meta_frame_seq [0:META_DEPTH-1];
reg [63:0] meta_timestamp [0:META_DEPTH-1];
reg [31:0] meta_sample_count [0:META_DEPTH-1];
reg        meta_cpl_en [0:META_DEPTH-1];
reg        meta_ring [0:META_DEPTH-1];
reg [PAYLOAD_AW-1:0] meta_payload_start [0:META_DEPTH-1];
reg [PAYLOAD_AW:0]   meta_alloc_words [0:META_DEPTH-1];

reg [PAYLOAD_AW-1:0] payload_wr_ptr;
reg [META_AW-1:0] meta_wr_ptr;
reg [META_AW-1:0] meta_rd_ptr;
reg [META_AW:0] meta_count;
reg [PAYLOAD_AW:0] used_words;

reg collect_active;
reg [PAYLOAD_AW-1:0] collect_wr_ptr;
reg [PAYLOAD_AW-1:0] collect_start_ptr;
reg [8:0] beats_needed;
reg [8:0] beats_seen;
reg [PAYLOAD_AW:0] collect_alloc_words;

reg [3:0]  pend_ch;
reg [3:0]  pend_tc;
reg [3:0]  pend_policy;
reg [15:0] pend_flow_id;
reg [15:0] pend_msg_id;
reg [31:0] pend_payload_len;
reg [31:0] pend_aligned_len;
reg [31:0] pend_dst_addr;
reg [31:0] pend_frame_seq;
reg [63:0] pend_timestamp;
reg [31:0] pend_sample_count;
reg        pend_cpl_en;
reg        pend_ring;

wire [PAYLOAD_AW:0] req_words = req_aligned_len[PAYLOAD_AW+2:3];
wire [PAYLOAD_AW:0] free_words = PAYLOAD_WORDS[PAYLOAD_AW:0] - used_words;
wire commit_payload = collect_active && payload_tvalid && payload_tready &&
                      ((beats_seen + 1'b1) >= beats_needed);
wire commit_zero = start_frame && (in_payload_len == 0);
wire commit_frame = commit_payload || commit_zero;
wire pop_frame = meta_pop && meta_valid;
wire [META_AW-1:0] meta_wr_ptr_next = (meta_wr_ptr == META_DEPTH-1) ? {META_AW{1'b0}} : meta_wr_ptr + 1'b1;
wire [META_AW-1:0] meta_rd_ptr_next = (meta_rd_ptr == META_DEPTH-1) ? {META_AW{1'b0}} : meta_rd_ptr + 1'b1;

assign can_accept_frame = (meta_count < META_DEPTH[META_AW:0]) && (free_words >= req_words);
assign near_full = (free_words <= (PAYLOAD_WORDS/4));
assign full = (meta_count >= META_DEPTH[META_AW:0]) || (free_words == 0);
assign payload_tready = collect_active;
assign meta_valid = (meta_count != 0);
assign meta_used = meta_count;
assign used_bytes = {18'h0, used_words, 3'b000};

assign out_ch = meta_ch[meta_rd_ptr];
assign out_tc = meta_tc[meta_rd_ptr];
assign out_policy = meta_policy[meta_rd_ptr];
assign out_flow_id = meta_flow_id[meta_rd_ptr];
assign out_msg_id = meta_msg_id[meta_rd_ptr];
assign out_payload_len = meta_payload_len[meta_rd_ptr];
assign out_aligned_len = meta_aligned_len[meta_rd_ptr];
assign out_dst_addr = meta_dst_addr[meta_rd_ptr];
assign out_frame_seq = meta_frame_seq[meta_rd_ptr];
assign out_timestamp = meta_timestamp[meta_rd_ptr];
assign out_sample_count = meta_sample_count[meta_rd_ptr];
assign out_cpl_en = meta_cpl_en[meta_rd_ptr];
assign out_ring = meta_ring[meta_rd_ptr];
assign payload_rd_data = payload_mem[(meta_payload_start[meta_rd_ptr] + payload_rd_index) % PAYLOAD_WORDS];

task write_meta;
    input [META_AW-1:0] idx;
    input [PAYLOAD_AW-1:0] payload_start;
    input [PAYLOAD_AW:0] alloc_words;
    begin
        meta_ch[idx] = pend_ch;
        meta_tc[idx] = pend_tc;
        meta_policy[idx] = pend_policy;
        meta_flow_id[idx] = pend_flow_id;
        meta_msg_id[idx] = pend_msg_id;
        meta_payload_len[idx] = pend_payload_len;
        meta_aligned_len[idx] = pend_aligned_len;
        meta_dst_addr[idx] = pend_dst_addr;
        meta_frame_seq[idx] = pend_frame_seq;
        meta_timestamp[idx] = pend_timestamp;
        meta_sample_count[idx] = pend_sample_count;
        meta_cpl_en[idx] = pend_cpl_en;
        meta_ring[idx] = pend_ring;
        meta_payload_start[idx] = payload_start;
        meta_alloc_words[idx] = alloc_words;
    end
endtask

integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        payload_wr_ptr <= {PAYLOAD_AW{1'b0}};
        meta_wr_ptr <= {META_AW{1'b0}};
        meta_rd_ptr <= {META_AW{1'b0}};
        meta_count <= {(META_AW+1){1'b0}};
        used_words <= {(PAYLOAD_AW+1){1'b0}};
        collect_active <= 1'b0;
        collect_wr_ptr <= {PAYLOAD_AW{1'b0}};
        collect_start_ptr <= {PAYLOAD_AW{1'b0}};
        beats_needed <= 9'h0;
        beats_seen <= 9'h0;
        collect_alloc_words <= {(PAYLOAD_AW+1){1'b0}};
        collect_done <= 1'b0;
        pend_ch <= 4'h0;
        pend_tc <= 4'h0;
        pend_policy <= 4'h0;
        pend_flow_id <= 16'h0;
        pend_msg_id <= 16'h0;
        pend_payload_len <= 32'h0;
        pend_aligned_len <= 32'h0;
        pend_dst_addr <= 32'h0;
        pend_frame_seq <= 32'h0;
        pend_timestamp <= 64'h0;
        pend_sample_count <= 32'h0;
        pend_cpl_en <= 1'b0;
        pend_ring <= 1'b0;
        for (i = 0; i < META_DEPTH; i = i + 1) begin
            meta_ch[i] = 4'h0;
            meta_tc[i] = 4'h0;
            meta_policy[i] = 4'h0;
            meta_flow_id[i] = 16'h0;
            meta_msg_id[i] = 16'h0;
            meta_payload_len[i] = 32'h0;
            meta_aligned_len[i] = 32'h0;
            meta_dst_addr[i] = 32'h0;
            meta_frame_seq[i] = 32'h0;
            meta_timestamp[i] = 64'h0;
            meta_sample_count[i] = 32'h0;
            meta_cpl_en[i] = 1'b0;
            meta_ring[i] = 1'b0;
            meta_payload_start[i] = {PAYLOAD_AW{1'b0}};
            meta_alloc_words[i] = {(PAYLOAD_AW+1){1'b0}};
        end
    end else begin
        collect_done <= 1'b0;

        if (start_frame) begin
            pend_ch <= in_ch;
            pend_tc <= in_tc;
            pend_policy <= in_policy;
            pend_flow_id <= in_flow_id;
            pend_msg_id <= in_msg_id;
            pend_payload_len <= in_payload_len;
            pend_aligned_len <= in_aligned_len;
            pend_dst_addr <= in_dst_addr;
            pend_frame_seq <= in_frame_seq;
            pend_timestamp <= in_timestamp;
            pend_sample_count <= in_sample_count;
            pend_cpl_en <= in_cpl_en;
            pend_ring <= in_ring;
            collect_start_ptr <= payload_wr_ptr;
            collect_wr_ptr <= payload_wr_ptr;
            collect_alloc_words <= in_aligned_len[PAYLOAD_AW+2:3];
            beats_needed <= (in_aligned_len + 32'd63) >> 6;
            beats_seen <= 9'h0;
            collect_active <= (in_payload_len != 0);
            if (in_payload_len == 0) begin
                meta_ch[meta_wr_ptr] = in_ch;
                meta_tc[meta_wr_ptr] = in_tc;
                meta_policy[meta_wr_ptr] = in_policy;
                meta_flow_id[meta_wr_ptr] = in_flow_id;
                meta_msg_id[meta_wr_ptr] = in_msg_id;
                meta_payload_len[meta_wr_ptr] = in_payload_len;
                meta_aligned_len[meta_wr_ptr] = in_aligned_len;
                meta_dst_addr[meta_wr_ptr] = in_dst_addr;
                meta_frame_seq[meta_wr_ptr] = in_frame_seq;
                meta_timestamp[meta_wr_ptr] = in_timestamp;
                meta_sample_count[meta_wr_ptr] = in_sample_count;
                meta_cpl_en[meta_wr_ptr] = in_cpl_en;
                meta_ring[meta_wr_ptr] = in_ring;
                meta_payload_start[meta_wr_ptr] = payload_wr_ptr;
                meta_alloc_words[meta_wr_ptr] = {(PAYLOAD_AW+1){1'b0}};
                meta_wr_ptr <= meta_wr_ptr_next;
                collect_done <= 1'b1;
            end
        end

        else if (payload_tvalid && payload_tready) begin
            payload_mem[(collect_wr_ptr + 0) % PAYLOAD_WORDS] <= payload_tdata[  0 +: 64];
            payload_mem[(collect_wr_ptr + 1) % PAYLOAD_WORDS] <= payload_tdata[ 64 +: 64];
            payload_mem[(collect_wr_ptr + 2) % PAYLOAD_WORDS] <= payload_tdata[128 +: 64];
            payload_mem[(collect_wr_ptr + 3) % PAYLOAD_WORDS] <= payload_tdata[192 +: 64];
            payload_mem[(collect_wr_ptr + 4) % PAYLOAD_WORDS] <= payload_tdata[256 +: 64];
            payload_mem[(collect_wr_ptr + 5) % PAYLOAD_WORDS] <= payload_tdata[320 +: 64];
            payload_mem[(collect_wr_ptr + 6) % PAYLOAD_WORDS] <= payload_tdata[384 +: 64];
            payload_mem[(collect_wr_ptr + 7) % PAYLOAD_WORDS] <= payload_tdata[448 +: 64];
            collect_wr_ptr <= (collect_wr_ptr + 8) % PAYLOAD_WORDS;
            beats_seen <= beats_seen + 1'b1;
            if ((beats_seen + 1'b1) >= beats_needed) begin
                write_meta(meta_wr_ptr, collect_start_ptr, collect_alloc_words);
                payload_wr_ptr <= (collect_start_ptr + collect_alloc_words) % PAYLOAD_WORDS;
                meta_wr_ptr <= meta_wr_ptr_next;
                collect_active <= 1'b0;
                collect_done <= 1'b1;
            end
        end

        if (pop_frame)
            meta_rd_ptr <= meta_rd_ptr_next;

        case ({commit_frame, pop_frame})
        2'b10: begin
            meta_count <= meta_count + 1'b1;
            used_words <= used_words + (commit_zero ? {(PAYLOAD_AW+1){1'b0}} : collect_alloc_words);
        end
        2'b01: begin
            meta_count <= meta_count - 1'b1;
            used_words <= used_words - meta_alloc_words[meta_rd_ptr];
        end
        2'b11: begin
            used_words <= used_words + (commit_zero ? {(PAYLOAD_AW+1){1'b0}} : collect_alloc_words) -
                          meta_alloc_words[meta_rd_ptr];
        end
        default: ;
        endcase
    end
end

endmodule
