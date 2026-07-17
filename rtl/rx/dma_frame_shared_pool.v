`timescale 1ns/1ps

// 共享 frame pool：多个 RX channel 通过 block free list 共用 payload 空间，
// metadata context 保存帧的所有权、长度和释放信息。写入侧提交完整 metadata 后
// 才允许读出；读出和 release 由独立状态机推进，避免 pool 空间提前复用。
module dma_frame_shared_pool #(
    parameter integer CH_NUM = 16,
    parameter integer CH_ID_W = 4,
    parameter integer BLOCK_NUM = 64,
    parameter integer BLOCK_AW = 6,
    parameter integer DATA_W = 512,
    parameter integer KEEP_W = 64,
    parameter integer META_DEPTH = 4,
    parameter integer META_AW = 2,
    parameter integer MAX_FRAME_BLOCKS = 32,
    parameter integer DEBUG_OWNERSHIP = 0,
    parameter integer SERIAL_INGRESS = 0
)(
    input  wire                  clk,
    input  wire                  rstn,
    input  wire                  soft_reset,

    input  wire                  s_valid,
    output wire                  s_ready,
    input  wire [CH_ID_W-1:0]    s_ch_id,
    input  wire [DATA_W-1:0]     s_data,
    input  wire [KEEP_W-1:0]     s_keep,
    input  wire                  s_last,
    input  wire                  s_drop_enable,
    input  wire                  s_no_drop,

    output wire                  m_valid,
    input  wire                  m_ready,
    output wire [CH_ID_W-1:0]    m_ch_id,
    output wire [DATA_W-1:0]     m_data,
    output wire [KEEP_W-1:0]     m_keep,
    output wire                  m_last,

    output wire [15:0]           free_count,
    output wire [15:0]           alloc_count,
    output wire [15:0]           committed_frame_count,
    output wire [15:0]           dropped_frame_count,
    output wire                  overflow_sticky,
    output wire                  double_free_error,
    output wire                  double_alloc_error,
    output wire                  leak_check_error,
    output reg                   commit_event_valid,
    output reg  [CH_ID_W-1:0]    commit_event_ch,
    output reg  [31:0]           commit_event_byte_count,
    output reg                   drop_event_valid,
    output reg  [CH_ID_W-1:0]    drop_event_ch
);

localparam integer TOTAL_META = CH_NUM * META_DEPTH;
localparam [15:0] BLOCK_NUM_16 = BLOCK_NUM;
localparam [15:0] MAX_FRAME_BLOCKS_16 = MAX_FRAME_BLOCKS;
localparam [META_AW:0] META_DEPTH_COUNT = META_DEPTH;
localparam HAS_POOL_DRAIN_PIPELINE = (`DMA_ENABLE_FRAME_SHARED_POOL_DRAIN_PIPELINE != 0);

// 读状态机先仲裁请求并读取 metadata，再逐 block 提供 payload，最后等待 release。
localparam [2:0] RD_IDLE         = 3'd0;
localparam [2:0] RD_SCHED_GRANT  = 3'd1;
localparam [2:0] RD_LOAD_META    = 3'd2;
localparam [2:0] RD_START        = 3'd3;
localparam [2:0] RD_REQ          = 3'd4;
localparam [2:0] RD_WAIT         = 3'd5;
localparam [2:0] RD_VALID        = 3'd6;
localparam [2:0] RD_RELEASE_WAIT = 3'd7;

localparam [1:0] REL_IDLE        = 2'd0;
localparam [1:0] REL_READ_NEXT   = 2'd1;
localparam [1:0] REL_RELEASE_ONE = 2'd2;

reg [BLOCK_AW-1:0] next_ptr [0:BLOCK_NUM-1];
reg [BLOCK_AW-1:0] free_fifo [0:BLOCK_NUM-1];
reg block_allocated [0:BLOCK_NUM-1];

reg open_valid [0:CH_NUM-1];
reg open_dropping [0:CH_NUM-1];
reg [BLOCK_AW-1:0] open_head [0:CH_NUM-1];
reg [BLOCK_AW-1:0] open_tail [0:CH_NUM-1];
reg [15:0] open_block_count [0:CH_NUM-1];
reg [31:0] open_byte_count [0:CH_NUM-1];

reg serial_open_valid;
reg serial_open_dropping;
reg [CH_ID_W-1:0] serial_ch;
reg [BLOCK_AW-1:0] serial_open_head;
reg [BLOCK_AW-1:0] serial_open_tail;
reg [15:0] serial_open_block_count;
reg [31:0] serial_open_byte_count;

reg [BLOCK_AW-1:0] meta_head [0:TOTAL_META-1];
reg [BLOCK_AW-1:0] meta_tail [0:TOTAL_META-1];
reg [15:0] meta_block_count [0:TOTAL_META-1];
reg [31:0] meta_byte_count [0:TOTAL_META-1];
reg [7:0] meta_flags [0:TOTAL_META-1];
reg [META_AW-1:0] meta_wr_ptr [0:CH_NUM-1];
reg [META_AW-1:0] meta_rd_ptr [0:CH_NUM-1];
reg [META_AW:0] meta_count [0:CH_NUM-1];
reg [CH_NUM-1:0] meta_nonempty_q;

reg [BLOCK_AW-1:0] free_rd_ptr;
reg [BLOCK_AW-1:0] free_wr_ptr;
reg [15:0] free_count_q;
reg [15:0] alloc_count_q;
reg [15:0] committed_frame_count_q;
reg [15:0] dropped_frame_count_q;
reg overflow_sticky_q;
reg double_free_error_q;
reg double_alloc_error_q;
reg leak_check_error_q;

reg [2:0] rd_state;
reg [CH_ID_W-1:0] drain_ch;
reg [BLOCK_AW-1:0] drain_cur;
reg [15:0] drain_remaining;
reg [CH_ID_W-1:0] sched_rr;
reg [CH_NUM-1:0] sched_req_q;
reg [CH_NUM-1:0] rr_mask;
reg [CH_NUM-1:0] masked_req;
reg grant_valid_comb;
reg [CH_ID_W-1:0] grant_ch_comb;
reg grant_valid_q;
reg [CH_ID_W-1:0] grant_ch_q;
reg [CH_ID_W-1:0] selected_ch_q;
reg [BLOCK_AW-1:0] selected_meta_head_q;
reg [15:0] selected_meta_count_q;
reg [DATA_W-1:0] m_data_q;
reg [KEEP_W-1:0] m_keep_q;
reg m_last_q;

reg [1:0] rel_state;
reg [BLOCK_AW-1:0] rel_cur;
reg [BLOCK_AW-1:0] rel_next;
reg [15:0] rel_remaining;

reg ram_wr_en_q;
reg [BLOCK_AW-1:0] ram_wr_addr_q;
reg [DATA_W-1:0] ram_wr_data_q;
reg [KEEP_W-1:0] ram_wr_keep_q;
reg ram_rd_en_q;
reg [BLOCK_AW-1:0] ram_rd_addr_q;
wire [DATA_W-1:0] ram_rd_data;
wire [KEEP_W-1:0] ram_rd_keep;

wire [BLOCK_AW-1:0] alloc_blk = free_fifo[free_rd_ptr];

integer i;
integer grant_i;

function [15:0] keep_count;
    input [KEEP_W-1:0] keep;
    integer k;
    begin
        keep_count = 16'h0;
        for (k = 0; k < KEEP_W; k = k + 1)
            keep_count = keep_count + keep[k];
    end
endfunction

function [META_AW-1:0] meta_ptr_next;
    input [META_AW-1:0] ptr;
    begin
        if (ptr == META_DEPTH-1)
            meta_ptr_next = {META_AW{1'b0}};
        else
            meta_ptr_next = ptr + 1'b1;
    end
endfunction

function [BLOCK_AW-1:0] block_ptr_next;
    input [BLOCK_AW-1:0] ptr;
    begin
        if (ptr == BLOCK_NUM-1)
            block_ptr_next = {BLOCK_AW{1'b0}};
        else
            block_ptr_next = ptr + 1'b1;
    end
endfunction

function [CH_ID_W-1:0] ch_ptr_next;
    input [CH_ID_W-1:0] ptr;
    begin
        if (ptr == CH_NUM-1)
            ch_ptr_next = {CH_ID_W{1'b0}};
        else
            ch_ptr_next = ptr + 1'b1;
    end
endfunction

wire ch_in_range = (s_ch_id < CH_NUM);
wire meta_full_for_s = ch_in_range && (meta_count[s_ch_id] >= META_DEPTH_COUNT);
wire ingress_open_valid = (SERIAL_INGRESS != 0) ? serial_open_valid : open_valid[s_ch_id];
wire ingress_open_dropping = (SERIAL_INGRESS != 0) ? serial_open_dropping : open_dropping[s_ch_id];
wire [15:0] ingress_open_block_count =
    (SERIAL_INGRESS != 0) ? serial_open_block_count : open_block_count[s_ch_id];
wire serial_channel_ok = (SERIAL_INGRESS == 0) ||
                         (!(serial_open_valid || serial_open_dropping)) ||
                         (s_ch_id == serial_ch);
wire no_drop_would_overflow =
    ch_in_range &&
    !ingress_open_dropping &&
    ((free_count_q == 16'h0) ||
     (ingress_open_block_count >= MAX_FRAME_BLOCKS_16) ||
     (s_last && meta_full_for_s));
wire release_busy = (rel_state != REL_IDLE);
wire drain_releases_this_cycle = (rd_state == RD_VALID) && m_ready;
wire scheduler_meta_pop_cycle = (rd_state == RD_LOAD_META);
wire alloc_or_drop_release_blocked = release_busy ||
                                     drain_releases_this_cycle ||
                                     scheduler_meta_pop_cycle;
wire accept_w = s_valid && s_ready;
wire commit_meta_w = accept_w &&
                     s_last &&
                     !ingress_open_dropping &&
                     !((free_count_q == 16'h0) ||
                       (ingress_open_block_count >= MAX_FRAME_BLOCKS_16) ||
                       (s_last && meta_full_for_s));

assign s_ready = ch_in_range &&
                 serial_channel_ok &&
                 (ingress_open_dropping ||
                  (!alloc_or_drop_release_blocked &&
                   (!s_no_drop || !no_drop_would_overflow)));

assign m_valid = (rd_state == RD_VALID);
assign m_ch_id = drain_ch;
assign m_data = m_data_q;
assign m_keep = m_keep_q;
assign m_last = m_last_q;
assign free_count = free_count_q;
assign alloc_count = alloc_count_q;
assign committed_frame_count = committed_frame_count_q;
assign dropped_frame_count = dropped_frame_count_q;
assign overflow_sticky = overflow_sticky_q;
assign double_free_error = (DEBUG_OWNERSHIP != 0) ? double_free_error_q : 1'b0;
assign double_alloc_error = (DEBUG_OWNERSHIP != 0) ? double_alloc_error_q : 1'b0;
assign leak_check_error = leak_check_error_q;

dma_frame_payload_ram #(
    .BLOCK_NUM(BLOCK_NUM),
    .BLOCK_AW(BLOCK_AW),
    .DATA_W(DATA_W),
    .KEEP_W(KEEP_W)
) u_payload_ram (
    .clk(clk),
    .wr_en(ram_wr_en_q),
    .wr_addr(ram_wr_addr_q),
    .wr_data(ram_wr_data_q),
    .wr_keep(ram_wr_keep_q),
    .rd_en(ram_rd_en_q),
    .rd_addr(ram_rd_addr_q),
    .rd_data(ram_rd_data),
    .rd_keep(ram_rd_keep)
);

task start_release_list;
    input [BLOCK_AW-1:0] head;
    input [15:0] count;
    begin
        if (count != 16'h0) begin
            rel_cur <= head;
            rel_remaining <= count;
            rel_state <= REL_READ_NEXT;
        end
    end
endtask

always @(*) begin
    rr_mask = {CH_NUM{1'b0}};
    for (grant_i = 0; grant_i < CH_NUM; grant_i = grant_i + 1) begin
        if (grant_i >= sched_rr)
            rr_mask[grant_i] = 1'b1;
    end

    masked_req = sched_req_q & rr_mask;
    grant_valid_comb = 1'b0;
    grant_ch_comb = {CH_ID_W{1'b0}};

    if (masked_req != {CH_NUM{1'b0}}) begin
        for (grant_i = 0; grant_i < CH_NUM; grant_i = grant_i + 1) begin
            if (!grant_valid_comb && masked_req[grant_i]) begin
                grant_valid_comb = 1'b1;
                grant_ch_comb = grant_i[CH_ID_W-1:0];
            end
        end
    end else begin
        for (grant_i = 0; grant_i < CH_NUM; grant_i = grant_i + 1) begin
            if (!grant_valid_comb && sched_req_q[grant_i]) begin
                grant_valid_comb = 1'b1;
                grant_ch_comb = grant_i[CH_ID_W-1:0];
            end
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        free_rd_ptr <= {BLOCK_AW{1'b0}};
        free_wr_ptr <= {BLOCK_AW{1'b0}};
        free_count_q <= BLOCK_NUM_16;
        alloc_count_q <= 16'h0;
        committed_frame_count_q <= 16'h0;
        dropped_frame_count_q <= 16'h0;
        overflow_sticky_q <= 1'b0;
        double_free_error_q <= 1'b0;
        double_alloc_error_q <= 1'b0;
        leak_check_error_q <= 1'b0;

        rd_state <= RD_IDLE;
        drain_ch <= {CH_ID_W{1'b0}};
        drain_cur <= {BLOCK_AW{1'b0}};
        drain_remaining <= 16'h0;
        sched_rr <= {CH_ID_W{1'b0}};
        sched_req_q <= {CH_NUM{1'b0}};
        grant_valid_q <= 1'b0;
        grant_ch_q <= {CH_ID_W{1'b0}};
        selected_ch_q <= {CH_ID_W{1'b0}};
        selected_meta_head_q <= {BLOCK_AW{1'b0}};
        selected_meta_count_q <= 16'h0;
        if (!rstn) begin
            m_data_q <= {DATA_W{1'b0}};
            m_keep_q <= {KEEP_W{1'b0}};
            m_last_q <= 1'b0;
        end

        rel_state <= REL_IDLE;
        rel_cur <= {BLOCK_AW{1'b0}};
        rel_next <= {BLOCK_AW{1'b0}};
        rel_remaining <= 16'h0;

        ram_wr_en_q <= 1'b0;
        if (!rstn) begin
            ram_wr_addr_q <= {BLOCK_AW{1'b0}};
            ram_wr_data_q <= {DATA_W{1'b0}};
            ram_wr_keep_q <= {KEEP_W{1'b0}};
        end
        ram_rd_en_q <= 1'b0;
        ram_rd_addr_q <= {BLOCK_AW{1'b0}};
        commit_event_valid <= 1'b0;
        commit_event_ch <= {CH_ID_W{1'b0}};
        commit_event_byte_count <= 32'h0;
        drop_event_valid <= 1'b0;
        drop_event_ch <= {CH_ID_W{1'b0}};

        for (i = 0; i < BLOCK_NUM; i = i + 1) begin
            free_fifo[i] <= i[BLOCK_AW-1:0];
            next_ptr[i] <= {BLOCK_AW{1'b0}};
            block_allocated[i] <= 1'b0;
        end
        for (i = 0; i < CH_NUM; i = i + 1) begin
            open_valid[i] <= 1'b0;
            open_dropping[i] <= 1'b0;
            open_head[i] <= {BLOCK_AW{1'b0}};
            open_tail[i] <= {BLOCK_AW{1'b0}};
            open_block_count[i] <= 16'h0;
            open_byte_count[i] <= 32'h0;
            meta_wr_ptr[i] <= {META_AW{1'b0}};
            meta_rd_ptr[i] <= {META_AW{1'b0}};
            meta_count[i] <= {(META_AW+1){1'b0}};
        end
        serial_open_valid <= 1'b0;
        serial_open_dropping <= 1'b0;
        serial_ch <= {CH_ID_W{1'b0}};
        serial_open_head <= {BLOCK_AW{1'b0}};
        serial_open_tail <= {BLOCK_AW{1'b0}};
        serial_open_block_count <= 16'h0;
        serial_open_byte_count <= 32'h0;
        meta_nonempty_q <= {CH_NUM{1'b0}};
        if (!rstn) begin
            for (i = 0; i < TOTAL_META; i = i + 1) begin
                meta_head[i] <= {BLOCK_AW{1'b0}};
                meta_tail[i] <= {BLOCK_AW{1'b0}};
                meta_block_count[i] <= 16'h0;
                meta_byte_count[i] <= 32'h0;
                meta_flags[i] <= 8'h0;
            end
        end
    end else if (soft_reset) begin
        free_rd_ptr <= {BLOCK_AW{1'b0}};
        free_wr_ptr <= {BLOCK_AW{1'b0}};
        free_count_q <= BLOCK_NUM_16;
        alloc_count_q <= 16'h0;
        committed_frame_count_q <= 16'h0;
        dropped_frame_count_q <= 16'h0;
        overflow_sticky_q <= 1'b0;
        double_free_error_q <= 1'b0;
        double_alloc_error_q <= 1'b0;
        leak_check_error_q <= 1'b0;

        rd_state <= RD_IDLE;
        drain_ch <= {CH_ID_W{1'b0}};
        drain_cur <= {BLOCK_AW{1'b0}};
        drain_remaining <= 16'h0;
        sched_rr <= {CH_ID_W{1'b0}};
        sched_req_q <= {CH_NUM{1'b0}};
        grant_valid_q <= 1'b0;
        grant_ch_q <= {CH_ID_W{1'b0}};
        selected_ch_q <= {CH_ID_W{1'b0}};
        selected_meta_head_q <= {BLOCK_AW{1'b0}};
        selected_meta_count_q <= 16'h0;
        if (!rstn) begin
            m_data_q <= {DATA_W{1'b0}};
            m_keep_q <= {KEEP_W{1'b0}};
            m_last_q <= 1'b0;
        end

        rel_state <= REL_IDLE;
        rel_cur <= {BLOCK_AW{1'b0}};
        rel_next <= {BLOCK_AW{1'b0}};
        rel_remaining <= 16'h0;

        ram_wr_en_q <= 1'b0;
        if (!rstn) begin
            ram_wr_addr_q <= {BLOCK_AW{1'b0}};
            ram_wr_data_q <= {DATA_W{1'b0}};
            ram_wr_keep_q <= {KEEP_W{1'b0}};
        end
        ram_rd_en_q <= 1'b0;
        ram_rd_addr_q <= {BLOCK_AW{1'b0}};
        commit_event_valid <= 1'b0;
        commit_event_ch <= {CH_ID_W{1'b0}};
        commit_event_byte_count <= 32'h0;
        drop_event_valid <= 1'b0;
        drop_event_ch <= {CH_ID_W{1'b0}};

        for (i = 0; i < BLOCK_NUM; i = i + 1) begin
            free_fifo[i] <= i[BLOCK_AW-1:0];
            next_ptr[i] <= {BLOCK_AW{1'b0}};
            block_allocated[i] <= 1'b0;
        end
        for (i = 0; i < CH_NUM; i = i + 1) begin
            open_valid[i] <= 1'b0;
            open_dropping[i] <= 1'b0;
            open_head[i] <= {BLOCK_AW{1'b0}};
            open_tail[i] <= {BLOCK_AW{1'b0}};
            open_block_count[i] <= 16'h0;
            open_byte_count[i] <= 32'h0;
            meta_wr_ptr[i] <= {META_AW{1'b0}};
            meta_rd_ptr[i] <= {META_AW{1'b0}};
            meta_count[i] <= {(META_AW+1){1'b0}};
        end
        serial_open_valid <= 1'b0;
        serial_open_dropping <= 1'b0;
        serial_ch <= {CH_ID_W{1'b0}};
        serial_open_head <= {BLOCK_AW{1'b0}};
        serial_open_tail <= {BLOCK_AW{1'b0}};
        serial_open_block_count <= 16'h0;
        serial_open_byte_count <= 32'h0;
        meta_nonempty_q <= {CH_NUM{1'b0}};
        if (!rstn) begin
            for (i = 0; i < TOTAL_META; i = i + 1) begin
                meta_head[i] <= {BLOCK_AW{1'b0}};
                meta_tail[i] <= {BLOCK_AW{1'b0}};
                meta_block_count[i] <= 16'h0;
                meta_byte_count[i] <= 32'h0;
                meta_flags[i] <= 8'h0;
            end
        end
    end else begin
        ram_wr_en_q <= 1'b0;
        ram_rd_en_q <= 1'b0;
        commit_event_valid <= 1'b0;
        drop_event_valid <= 1'b0;

        if ((free_count_q + alloc_count_q) != BLOCK_NUM_16)
            leak_check_error_q <= 1'b1;

        case (rel_state)
            REL_IDLE: begin
            end
            REL_READ_NEXT: begin
                rel_next <= next_ptr[rel_cur];
                rel_state <= REL_RELEASE_ONE;
            end
            REL_RELEASE_ONE: begin
                if (DEBUG_OWNERSHIP != 0) begin
                    if (!block_allocated[rel_cur])
                        double_free_error_q <= 1'b1;
                    else
                        block_allocated[rel_cur] <= 1'b0;
                end

                free_fifo[free_wr_ptr] <= rel_cur;
                free_wr_ptr <= block_ptr_next(free_wr_ptr);
                free_count_q <= free_count_q + 1'b1;
                alloc_count_q <= alloc_count_q - 1'b1;

                if (rel_remaining <= 16'd1) begin
                    rel_remaining <= 16'h0;
                    rel_state <= REL_IDLE;
                end else begin
                    rel_cur <= rel_next;
                    rel_remaining <= rel_remaining - 1'b1;
                    rel_state <= REL_READ_NEXT;
                end
            end
            default: begin
                rel_state <= REL_IDLE;
            end
        endcase

        if (accept_w) begin
            if (SERIAL_INGRESS != 0) begin
                if (!(serial_open_valid || serial_open_dropping))
                    serial_ch <= s_ch_id;

                if (serial_open_dropping) begin
                    if (s_last) begin
                        serial_open_dropping <= 1'b0;
                        dropped_frame_count_q <= dropped_frame_count_q + 1'b1;
                        drop_event_valid <= 1'b1;
                        drop_event_ch <= s_ch_id;
                    end
                end else if ((free_count_q == 16'h0) ||
                             (serial_open_block_count >= MAX_FRAME_BLOCKS_16) ||
                             (s_last && meta_full_for_s)) begin
                    if (s_drop_enable && !s_no_drop) begin
                        if (serial_open_valid && (serial_open_block_count != 16'h0))
                            start_release_list(serial_open_head, serial_open_block_count);

                        serial_open_valid <= 1'b0;
                        serial_open_block_count <= 16'h0;
                        serial_open_byte_count <= 32'h0;
                        overflow_sticky_q <= 1'b1;

                        if (s_last) begin
                            serial_open_dropping <= 1'b0;
                            dropped_frame_count_q <= dropped_frame_count_q + 1'b1;
                            drop_event_valid <= 1'b1;
                            drop_event_ch <= s_ch_id;
                        end else begin
                            serial_open_dropping <= 1'b1;
                        end
                    end
                end else begin
                    if (DEBUG_OWNERSHIP != 0) begin
                        if (block_allocated[alloc_blk])
                            double_alloc_error_q <= 1'b1;
                        block_allocated[alloc_blk] <= 1'b1;
                    end

                    ram_wr_en_q <= 1'b1;
                    ram_wr_addr_q <= alloc_blk;
                    ram_wr_data_q <= s_data;
                    ram_wr_keep_q <= s_keep;
                    next_ptr[alloc_blk] <= {BLOCK_AW{1'b0}};

                    if (!serial_open_valid) begin
                        serial_open_valid <= !s_last;
                        serial_open_head <= alloc_blk;
                        serial_open_tail <= alloc_blk;
                        serial_open_block_count <= s_last ? 16'h0 : 16'h1;
                        serial_open_byte_count <= s_last ? 32'h0 : {16'h0, keep_count(s_keep)};
                    end else begin
                        next_ptr[serial_open_tail] <= alloc_blk;
                        serial_open_tail <= alloc_blk;
                        serial_open_block_count <= s_last ? 16'h0 : (serial_open_block_count + 1'b1);
                        serial_open_byte_count <= s_last ? 32'h0 :
                                                  (serial_open_byte_count + keep_count(s_keep));
                    end

                    if (s_last) begin
                        meta_head[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <=
                            serial_open_valid ? serial_open_head : alloc_blk;
                        meta_tail[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <= alloc_blk;
                        meta_block_count[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <=
                            serial_open_valid ? (serial_open_block_count + 1'b1) : 16'h1;
                        meta_byte_count[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <=
                            serial_open_valid ? (serial_open_byte_count + keep_count(s_keep)) :
                                                {16'h0, keep_count(s_keep)};
                        meta_flags[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <= 8'h1;
                        meta_wr_ptr[s_ch_id] <= meta_ptr_next(meta_wr_ptr[s_ch_id]);
                        meta_count[s_ch_id] <= meta_count[s_ch_id] + 1'b1;
                        meta_nonempty_q[s_ch_id] <= 1'b1;
                        commit_event_valid <= 1'b1;
                        commit_event_ch <= s_ch_id;
                        commit_event_byte_count <=
                            serial_open_valid ? (serial_open_byte_count + keep_count(s_keep)) :
                                                {16'h0, keep_count(s_keep)};
                        committed_frame_count_q <= committed_frame_count_q + 1'b1;
                        serial_open_valid <= 1'b0;
                    end

                    free_rd_ptr <= block_ptr_next(free_rd_ptr);
                    free_count_q <= free_count_q - 1'b1;
                    alloc_count_q <= alloc_count_q + 1'b1;
                end
            end else if (open_dropping[s_ch_id]) begin
                if (s_last) begin
                    open_dropping[s_ch_id] <= 1'b0;
                    dropped_frame_count_q <= dropped_frame_count_q + 1'b1;
                    drop_event_valid <= 1'b1;
                    drop_event_ch <= s_ch_id;
                end
            end else if ((free_count_q == 16'h0) ||
                         (open_block_count[s_ch_id] >= MAX_FRAME_BLOCKS_16) ||
                         (s_last && meta_full_for_s)) begin
                if (s_drop_enable && !s_no_drop) begin
                    if (open_valid[s_ch_id] && (open_block_count[s_ch_id] != 16'h0))
                        start_release_list(open_head[s_ch_id], open_block_count[s_ch_id]);

                    open_valid[s_ch_id] <= 1'b0;
                    open_block_count[s_ch_id] <= 16'h0;
                    open_byte_count[s_ch_id] <= 32'h0;
                    overflow_sticky_q <= 1'b1;

                    if (s_last) begin
                        open_dropping[s_ch_id] <= 1'b0;
                        dropped_frame_count_q <= dropped_frame_count_q + 1'b1;
                        drop_event_valid <= 1'b1;
                        drop_event_ch <= s_ch_id;
                    end else begin
                        open_dropping[s_ch_id] <= 1'b1;
                    end
                end
            end else begin
                if (DEBUG_OWNERSHIP != 0) begin
                    if (block_allocated[alloc_blk])
                        double_alloc_error_q <= 1'b1;
                    block_allocated[alloc_blk] <= 1'b1;
                end

                ram_wr_en_q <= 1'b1;
                ram_wr_addr_q <= alloc_blk;
                ram_wr_data_q <= s_data;
                ram_wr_keep_q <= s_keep;
                next_ptr[alloc_blk] <= {BLOCK_AW{1'b0}};

                if (!open_valid[s_ch_id]) begin
                    open_valid[s_ch_id] <= !s_last;
                    open_head[s_ch_id] <= alloc_blk;
                    open_tail[s_ch_id] <= alloc_blk;
                    open_block_count[s_ch_id] <= s_last ? 16'h0 : 16'h1;
                    open_byte_count[s_ch_id] <= s_last ? 32'h0 : {16'h0, keep_count(s_keep)};
                end else begin
                    next_ptr[open_tail[s_ch_id]] <= alloc_blk;
                    open_tail[s_ch_id] <= alloc_blk;
                    open_block_count[s_ch_id] <= s_last ? 16'h0 : (open_block_count[s_ch_id] + 1'b1);
                    open_byte_count[s_ch_id] <= s_last ? 32'h0 : (open_byte_count[s_ch_id] + keep_count(s_keep));
                end

                if (s_last) begin
                    meta_head[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <=
                        open_valid[s_ch_id] ? open_head[s_ch_id] : alloc_blk;
                    meta_tail[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <= alloc_blk;
                    meta_block_count[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <=
                        open_valid[s_ch_id] ? (open_block_count[s_ch_id] + 1'b1) : 16'h1;
                    meta_byte_count[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <=
                        open_valid[s_ch_id] ? (open_byte_count[s_ch_id] + keep_count(s_keep)) : {16'h0, keep_count(s_keep)};
                    meta_flags[s_ch_id*META_DEPTH + meta_wr_ptr[s_ch_id]] <= 8'h1;
                    meta_wr_ptr[s_ch_id] <= meta_ptr_next(meta_wr_ptr[s_ch_id]);
                    meta_count[s_ch_id] <= meta_count[s_ch_id] + 1'b1;
                    meta_nonempty_q[s_ch_id] <= 1'b1;
                    commit_event_valid <= 1'b1;
                    commit_event_ch <= s_ch_id;
                    commit_event_byte_count <=
                        open_valid[s_ch_id] ? (open_byte_count[s_ch_id] + keep_count(s_keep)) : {16'h0, keep_count(s_keep)};
                    committed_frame_count_q <= committed_frame_count_q + 1'b1;
                    open_valid[s_ch_id] <= 1'b0;
                end

                free_rd_ptr <= block_ptr_next(free_rd_ptr);
                free_count_q <= free_count_q - 1'b1;
                alloc_count_q <= alloc_count_q + 1'b1;
            end
        end

        case (rd_state)
            RD_IDLE: begin
                grant_valid_q <= 1'b0;
                if (!accept_w && (rel_state == REL_IDLE) && (meta_nonempty_q != {CH_NUM{1'b0}})) begin
                    sched_req_q <= meta_nonempty_q;
                    rd_state <= RD_SCHED_GRANT;
                end
            end
            RD_SCHED_GRANT: begin
                grant_valid_q <= grant_valid_comb;
                grant_ch_q <= grant_ch_comb;
                if (grant_valid_comb)
                    rd_state <= RD_LOAD_META;
                else
                    rd_state <= RD_IDLE;
            end
            RD_LOAD_META: begin
                selected_ch_q <= grant_ch_q;
                selected_meta_head_q <= meta_head[grant_ch_q*META_DEPTH + meta_rd_ptr[grant_ch_q]];
                selected_meta_count_q <= meta_block_count[grant_ch_q*META_DEPTH + meta_rd_ptr[grant_ch_q]];
                meta_rd_ptr[grant_ch_q] <= meta_ptr_next(meta_rd_ptr[grant_ch_q]);
                if (commit_meta_w && (s_ch_id == grant_ch_q)) begin
                    meta_count[grant_ch_q] <= meta_count[grant_ch_q];
                    meta_nonempty_q[grant_ch_q] <= 1'b1;
                end else begin
                    meta_count[grant_ch_q] <= meta_count[grant_ch_q] - 1'b1;
                    if (meta_count[grant_ch_q] <= 1)
                        meta_nonempty_q[grant_ch_q] <= 1'b0;
                    else
                        meta_nonempty_q[grant_ch_q] <= 1'b1;
                end
                sched_rr <= ch_ptr_next(grant_ch_q);
                rd_state <= RD_START;
            end
            RD_START: begin
                drain_ch <= selected_ch_q;
                drain_cur <= selected_meta_head_q;
                drain_remaining <= selected_meta_count_q;
                ram_rd_en_q <= 1'b1;
                ram_rd_addr_q <= selected_meta_head_q;
                rd_state <= RD_REQ;
            end
            RD_REQ: begin
                rd_state <= RD_WAIT;
            end
            RD_WAIT: begin
                m_data_q <= ram_rd_data;
                m_keep_q <= ram_rd_keep;
                m_last_q <= (drain_remaining == 16'd1);
                rd_state <= RD_VALID;
            end
            RD_VALID: begin
                if (m_ready) begin
                    start_release_list(drain_cur, 16'd1);
                    if (drain_remaining <= 16'd1) begin
                        drain_remaining <= 16'h0;
                        m_last_q <= 1'b0;
                        rd_state <= RD_IDLE;
                    end else begin
                        ram_rd_addr_q <= next_ptr[drain_cur];
                        drain_cur <= next_ptr[drain_cur];
                        drain_remaining <= drain_remaining - 1'b1;
                        m_last_q <= 1'b0;
                        if (HAS_POOL_DRAIN_PIPELINE) begin
                            ram_rd_en_q <= 1'b1;
                            rd_state <= RD_REQ;
                        end else begin
                            rd_state <= RD_RELEASE_WAIT;
                        end
                    end
                end
            end
            RD_RELEASE_WAIT: begin
                if (rel_state == REL_IDLE) begin
                    ram_rd_en_q <= 1'b1;
                    ram_rd_addr_q <= drain_cur;
                    rd_state <= RD_REQ;
                end
            end
            default: begin
                rd_state <= RD_IDLE;
            end
        endcase
    end
end

endmodule
