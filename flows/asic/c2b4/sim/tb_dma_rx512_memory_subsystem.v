`timescale 1ns/1ps

`ifndef DMA_A3_CHANNELS
`define DMA_A3_CHANNELS 16
`endif
`ifndef DMA_A3_PAYLOAD_WORDS
`define DMA_A3_PAYLOAD_WORDS 1024
`endif
`ifndef DMA_A3_PAYLOAD_AW
`define DMA_A3_PAYLOAD_AW 10
`endif
`ifndef DMA_A3_META_DEPTH
`define DMA_A3_META_DEPTH 4
`endif
`ifndef DMA_A3_META_AW
`define DMA_A3_META_AW 2
`endif

module tb_dma_rx512_memory_subsystem;

localparam integer DUT_CHANNELS = `DMA_A3_CHANNELS;
localparam integer DUT_PAYLOAD_WORDS = `DMA_A3_PAYLOAD_WORDS;
localparam integer DUT_PAYLOAD_AW = `DMA_A3_PAYLOAD_AW;
localparam integer DUT_META_DEPTH = `DMA_A3_META_DEPTH;
localparam integer DUT_META_AW = `DMA_A3_META_AW;
localparam [3:0] DUT_LAST_CH = DUT_CHANNELS - 1;
localparam [3:0] DUT_UNSUPPORTED_CH = DUT_CHANNELS;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rstn = 1'b0;
reg soft_reset = 1'b0;
reg ch_reset_valid = 1'b0;
reg [3:0] ch_reset_ch = 4'h0;

reg fixed_start_frame = 1'b0;
reg [3:0] fixed_ch = 4'h0;
reg [3:0] fixed_policy = 4'h5;
reg [31:0] fixed_payload_len = 32'h0;
reg [31:0] fixed_aligned_len = 32'h0;
reg [31:0] fixed_dst_addr = 32'h0;
reg [31:0] fixed_frame_seq = 32'h0;
reg fixed_payload_tvalid = 1'b0;
wire fixed_payload_tready;
reg [511:0] fixed_payload_tdata = 512'h0;
wire fixed_collect_done;
wire fixed_can_accept;
wire fixed_near_full;
wire fixed_full;

reg shared_start_frame = 1'b0;
reg [3:0] shared_ch = 4'h0;
reg [3:0] shared_policy = 4'h5;
reg [31:0] shared_payload_len = 32'h0;
reg [31:0] shared_aligned_len = 32'h0;
reg [31:0] shared_dst_addr = 32'h0;
reg [31:0] shared_frame_seq = 32'h0;
reg shared_payload_tvalid = 1'b0;
wire shared_payload_tready;
reg [511:0] shared_payload_tdata = 512'h0;
wire shared_collect_done;
wire shared_can_accept;
wire shared_near_full;
wire shared_full;

wire [31:0] m_axi_awaddr;
wire [7:0] m_axi_awlen;
wire [2:0] m_axi_awsize;
wire [1:0] m_axi_awburst;
wire m_axi_awvalid;
reg m_axi_awready = 1'b0;
wire [511:0] m_axi_wdata;
wire [63:0] m_axi_wstrb;
wire m_axi_wlast;
wire m_axi_wvalid;
reg m_axi_wready = 1'b0;
reg [1:0] m_axi_bresp = 2'b00;
reg m_axi_bvalid = 1'b0;
wire m_axi_bready;

wire cpl_valid;
reg cpl_ready = 1'b1;
wire cpl_error;
wire [3:0] cpl_error_code;
wire [3:0] cpl_ch;
wire [31:0] cpl_dst_addr;
wire [31:0] cpl_payload_len;
wire [31:0] cpl_frame_seq;
wire cpl_source_shared;
wire [15:0] shared_pool_free_count;
wire [15:0] shared_pool_alloc_count;
wire shared_pool_overflow_sticky;
wire shared_pool_leak_check_error;
wire busy;

integer errors = 0;
integer completed_frames = 0;
integer aw_count = 0;
integer w_count = 0;
integer aw_stall_cycles = 0;
integer w_stall_cycles = 0;
integer four_k_split_seen = 0;
integer tail_strobe_seen = 0;
integer completion_stall_seen = 0;
integer i;

reg [31:0] lfsr_q = 32'h1ace_b00c;
reg force_axi_stall = 1'b0;
integer aw_queue [0:31];
integer aw_q_wr = 0;
integer aw_q_rd = 0;
integer aw_q_count = 0;
integer current_w_left = 0;
integer b_pending = 0;
integer burst_beats;
integer bytes_this;
reg [63:0] expected_keep;
reg [511:0] expected_data;

reg [31:0] expected_aw_addr = 32'h0;
reg [31:0] expected_dst_addr = 32'h0;
integer expected_aw_bytes_left = 0;
integer expected_payload_len = 0;
integer expected_payload_offset = 0;
integer expected_seed = 0;
reg expected_source_shared = 1'b0;
reg [3:0] expected_ch = 4'h0;
reg [31:0] expected_frame_seq = 32'h0;

reg aw_stalled_q = 1'b0;
reg [42:0] aw_held_q = 43'h0;
reg w_stalled_q = 1'b0;
reg [576:0] w_held_q = 577'h0;
reg cpl_stalled_q = 1'b0;
reg [72:0] cpl_held_q = 73'h0;

dma_rx512_memory_subsystem_top #(
    .CHANNELS(DUT_CHANNELS),
    .FIXED_PAYLOAD_WORDS(DUT_PAYLOAD_WORDS),
    .FIXED_PAYLOAD_AW(DUT_PAYLOAD_AW),
    .FIXED_META_DEPTH(DUT_META_DEPTH),
    .FIXED_META_AW(DUT_META_AW),
    .SHARED_BLOCK_NUM(64),
    .SHARED_BLOCK_AW(6)
) u_dut (
    .clk(clk), .rstn(rstn), .soft_reset(soft_reset),
    .ch_reset_valid(ch_reset_valid), .ch_reset_ch(ch_reset_ch),
    .fixed_start_frame(fixed_start_frame),
    .fixed_ch(fixed_ch), .fixed_policy(fixed_policy),
    .fixed_payload_len(fixed_payload_len),
    .fixed_aligned_len(fixed_aligned_len),
    .fixed_dst_addr(fixed_dst_addr), .fixed_frame_seq(fixed_frame_seq),
    .fixed_payload_tvalid(fixed_payload_tvalid),
    .fixed_payload_tready(fixed_payload_tready),
    .fixed_payload_tdata(fixed_payload_tdata),
    .fixed_collect_done(fixed_collect_done),
    .fixed_can_accept(fixed_can_accept),
    .fixed_near_full(fixed_near_full), .fixed_full(fixed_full),
    .shared_start_frame(shared_start_frame),
    .shared_ch(shared_ch), .shared_policy(shared_policy),
    .shared_payload_len(shared_payload_len),
    .shared_aligned_len(shared_aligned_len),
    .shared_dst_addr(shared_dst_addr), .shared_frame_seq(shared_frame_seq),
    .shared_payload_tvalid(shared_payload_tvalid),
    .shared_payload_tready(shared_payload_tready),
    .shared_payload_tdata(shared_payload_tdata),
    .shared_collect_done(shared_collect_done),
    .shared_can_accept(shared_can_accept),
    .shared_near_full(shared_near_full), .shared_full(shared_full),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .cpl_valid(cpl_valid), .cpl_ready(cpl_ready),
    .cpl_error(cpl_error), .cpl_error_code(cpl_error_code),
    .cpl_ch(cpl_ch), .cpl_dst_addr(cpl_dst_addr),
    .cpl_payload_len(cpl_payload_len), .cpl_frame_seq(cpl_frame_seq),
    .cpl_source_shared(cpl_source_shared),
    .shared_pool_free_count(shared_pool_free_count),
    .shared_pool_alloc_count(shared_pool_alloc_count),
    .shared_pool_overflow_sticky(shared_pool_overflow_sticky),
    .shared_pool_leak_check_error(shared_pool_leak_check_error),
    .busy(busy)
);

function [511:0] payload_pattern;
    input [7:0] seed;
    input [15:0] beat;
    integer lane;
    begin
        payload_pattern = 512'h0;
        for (lane = 0; lane < 16; lane = lane + 1)
            payload_pattern[lane*32 +: 32] = {seed, beat[7:0], lane[7:0], 8'h5a};
    end
endfunction

function [63:0] keep_for_bytes;
    input integer bytes;
    integer lane;
    begin
        keep_for_bytes = 64'h0;
        for (lane = 0; lane < 64; lane = lane + 1)
            if (lane < bytes)
                keep_for_bytes[lane] = 1'b1;
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

task set_expected;
    input source_shared;
    input [3:0] channel;
    input [31:0] address;
    input integer length;
    input [31:0] frame_seq;
    input integer seed;
    begin
        expected_source_shared = source_shared;
        expected_ch = channel;
        expected_aw_addr = address;
        expected_dst_addr = address;
        expected_aw_bytes_left = length;
        expected_payload_len = length;
        expected_payload_offset = 0;
        expected_frame_seq = frame_seq;
        expected_seed = seed;
    end
endtask

task send_fixed_frame;
    input [3:0] channel;
    input [31:0] address;
    input integer length;
    input [31:0] frame_seq;
    input integer seed;
    integer beats;
    integer beat;
    integer accepted;
    integer guard;
    begin
        set_expected(1'b0, channel, address, length, frame_seq, seed);
        @(negedge clk);
        fixed_ch = channel;
        fixed_payload_len = length;
        fixed_aligned_len = (length + 7) & 32'hffff_fff8;
        fixed_dst_addr = address;
        fixed_frame_seq = frame_seq;
        guard = 0;
        while (!fixed_can_accept && guard < 200) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (!fixed_can_accept)
            fail("fixed admission timed out");
        @(negedge clk);
        fixed_start_frame = 1'b1;
        @(posedge clk);
        @(negedge clk);
        fixed_start_frame = 1'b0;
        beats = (length + 63) / 64;
        for (beat = 0; beat < beats; beat = beat + 1) begin
            fixed_payload_tvalid = 1'b1;
            fixed_payload_tdata = payload_pattern(seed[7:0], beat[15:0]);
            accepted = 0;
            guard = 0;
            while (!accepted && guard < 200) begin
                @(posedge clk);
                if (fixed_payload_tready)
                    accepted = 1;
                else
                    guard = guard + 1;
            end
            if (!accepted)
                fail("fixed payload handshake timed out");
            @(negedge clk);
        end
        fixed_payload_tvalid = 1'b0;
        fixed_payload_tdata = 512'h0;
    end
endtask

task send_shared_frame;
    input [3:0] channel;
    input [31:0] address;
    input integer length;
    input [31:0] frame_seq;
    input integer seed;
    integer beats;
    integer beat;
    integer accepted;
    integer guard;
    begin
        set_expected(1'b1, channel, address, length, frame_seq, seed);
        @(negedge clk);
        shared_ch = channel;
        shared_payload_len = length;
        shared_aligned_len = (length + 7) & 32'hffff_fff8;
        shared_dst_addr = address;
        shared_frame_seq = frame_seq;
        guard = 0;
        while (!shared_can_accept && guard < 300) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (!shared_can_accept)
            fail("shared admission timed out");
        @(negedge clk);
        shared_start_frame = 1'b1;
        @(posedge clk);
        @(negedge clk);
        shared_start_frame = 1'b0;
        beats = (length + 63) / 64;
        for (beat = 0; beat < beats; beat = beat + 1) begin
            shared_payload_tvalid = 1'b1;
            shared_payload_tdata = payload_pattern(seed[7:0], beat[15:0]);
            accepted = 0;
            guard = 0;
            while (!accepted && guard < 300) begin
                @(posedge clk);
                if (shared_payload_tready)
                    accepted = 1;
                else
                    guard = guard + 1;
            end
            if (!accepted)
                fail("shared payload handshake timed out");
            @(negedge clk);
        end
        shared_payload_tvalid = 1'b0;
        shared_payload_tdata = 512'h0;
    end
endtask

task wait_completion;
    input stall_completion;
    integer guard;
    reg [72:0] held;
    begin
        cpl_ready = stall_completion ? 1'b0 : 1'b1;
        guard = 0;
        while (!cpl_valid && guard < 2000) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (!cpl_valid)
            fail("completion timed out");
        if (stall_completion) begin
            held = {cpl_error, cpl_error_code, cpl_ch, cpl_dst_addr,
                    cpl_payload_len};
            repeat (5) begin
                @(posedge clk);
                if (!cpl_valid ||
                    ({cpl_error, cpl_error_code, cpl_ch, cpl_dst_addr,
                      cpl_payload_len} !== held))
                    fail("completion changed while backpressured");
            end
            completion_stall_seen = completion_stall_seen + 1;
            @(negedge clk);
            cpl_ready = 1'b1;
        end
        if (cpl_error || (cpl_error_code != 0))
            fail("unexpected writer completion error");
        if ((cpl_ch !== expected_ch) ||
            (cpl_dst_addr !== expected_dst_addr) ||
            (cpl_payload_len !== expected_payload_len) ||
            (cpl_frame_seq !== expected_frame_seq) ||
            (cpl_source_shared !== expected_source_shared))
            fail("completion metadata mismatch");
        if (expected_payload_offset != expected_payload_len)
            fail("completion preceded payload transfer");
        @(posedge clk);
        completed_frames = completed_frames + 1;
        @(negedge clk);
        cpl_ready = 1'b1;
    end
endtask

// Randomized AXI ready and an ordered response queue exercise independent
// AW/W/B backpressure without changing the writer protocol.
always @(posedge clk or negedge rstn) begin
    if (!rstn || soft_reset) begin
        lfsr_q <= 32'h1ace_b00c;
        m_axi_awready <= 1'b0;
        m_axi_wready <= 1'b0;
        m_axi_bvalid <= 1'b0;
        m_axi_bresp <= 2'b00;
        aw_q_wr = 0;
        aw_q_rd = 0;
        aw_q_count = 0;
        current_w_left = 0;
        b_pending = 0;
    end else begin
        lfsr_q <= {lfsr_q[30:0], lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
        if (force_axi_stall) begin
            m_axi_awready <= 1'b0;
            m_axi_wready <= 1'b0;
        end else begin
            m_axi_awready <= lfsr_q[0] | lfsr_q[4];
            m_axi_wready <= lfsr_q[1] | lfsr_q[5];
        end

        if (m_axi_awvalid && m_axi_awready) begin
            burst_beats = m_axi_awlen + 1;
            if ((m_axi_awsize != 3'd6) || (m_axi_awburst != 2'b01))
                fail("AXI AW format mismatch");
            if ((m_axi_awaddr[11:0] + (burst_beats << 6)) > 4096)
                fail("AXI burst crossed 4 KiB boundary");
            if (m_axi_awaddr !== expected_aw_addr)
                fail("AXI AW address mismatch");
            if (m_axi_awaddr[11:0] == 12'hfc0)
                four_k_split_seen = four_k_split_seen + 1;
            aw_queue[aw_q_wr] = burst_beats;
            aw_q_wr = (aw_q_wr + 1) & 31;
            aw_q_count = aw_q_count + 1;
            expected_aw_addr = expected_aw_addr + (burst_beats << 6);
            if (expected_aw_bytes_left > (burst_beats << 6))
                expected_aw_bytes_left = expected_aw_bytes_left - (burst_beats << 6);
            else
                expected_aw_bytes_left = 0;
            aw_count = aw_count + 1;
        end

        if (m_axi_wvalid && m_axi_wready) begin
            if (current_w_left == 0) begin
                if (aw_q_count == 0)
                    fail("AXI W beat has no accepted AW plan");
                current_w_left = aw_queue[aw_q_rd];
                aw_q_rd = (aw_q_rd + 1) & 31;
                aw_q_count = aw_q_count - 1;
            end
            if (m_axi_wlast !== (current_w_left == 1))
                fail("AXI WLAST mismatch");
            bytes_this = expected_payload_len - expected_payload_offset;
            if (bytes_this > 64)
                bytes_this = 64;
            expected_keep = keep_for_bytes(bytes_this);
            if (m_axi_wstrb !== expected_keep)
                fail("AXI WSTRB mismatch");
            if (bytes_this < 64)
                tail_strobe_seen = tail_strobe_seen + 1;
            expected_data = payload_pattern(expected_seed[7:0],
                                            (expected_payload_offset / 64));
            for (i = 0; i < 64; i = i + 1)
                if (expected_keep[i] &&
                    (m_axi_wdata[i*8 +: 8] !== expected_data[i*8 +: 8]))
                    fail("AXI WDATA mismatch");
            expected_payload_offset = expected_payload_offset + bytes_this;
            current_w_left = current_w_left - 1;
            w_count = w_count + 1;
            if (m_axi_wlast)
                b_pending = b_pending + 1;
        end

        if (m_axi_bvalid && m_axi_bready)
            m_axi_bvalid <= 1'b0;
        if (!m_axi_bvalid && (b_pending != 0)) begin
            m_axi_bvalid <= 1'b1;
            m_axi_bresp <= 2'b00;
            b_pending = b_pending - 1;
        end
    end
end

// All output payloads must remain stable for an entire stall window.
always @(posedge clk) begin
    if (rstn && !soft_reset) begin
        if (aw_stalled_q &&
            ({m_axi_awaddr, m_axi_awlen, m_axi_awsize} !== aw_held_q))
            fail("AW payload changed while stalled");
        if (w_stalled_q &&
            ({m_axi_wdata, m_axi_wstrb, m_axi_wlast} !== w_held_q))
            fail("W payload changed while stalled");
        if (cpl_stalled_q &&
            ({cpl_error, cpl_error_code, cpl_ch, cpl_dst_addr,
              cpl_payload_len} !== cpl_held_q))
            fail("completion payload changed while stalled");
        aw_stalled_q <= m_axi_awvalid && !m_axi_awready;
        w_stalled_q <= m_axi_wvalid && !m_axi_wready;
        cpl_stalled_q <= cpl_valid && !cpl_ready;
        aw_held_q <= {m_axi_awaddr, m_axi_awlen, m_axi_awsize};
        w_held_q <= {m_axi_wdata, m_axi_wstrb, m_axi_wlast};
        cpl_held_q <= {cpl_error, cpl_error_code, cpl_ch, cpl_dst_addr,
                       cpl_payload_len};
        if (m_axi_awvalid && !m_axi_awready)
            aw_stall_cycles = aw_stall_cycles + 1;
        if (m_axi_wvalid && !m_axi_wready)
            w_stall_cycles = w_stall_cycles + 1;
    end else begin
        aw_stalled_q <= 1'b0;
        w_stalled_q <= 1'b0;
        cpl_stalled_q <= 1'b0;
    end
end

initial begin
    repeat (8) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);
    if ((shared_pool_free_count != 64) || (shared_pool_alloc_count != 0))
        fail("shared pool reset accounting mismatch");

`ifdef DMA_A3_PROFILE
    $display("A3_MEMORY_PHASE unsupported_channel");
    @(negedge clk);
    fixed_ch = DUT_UNSUPPORTED_CH;
    fixed_aligned_len = 32'd64;
    repeat (2) @(posedge clk);
    if (fixed_can_accept)
        fail("unsupported fixed channel was admitted");

    $display("A3_MEMORY_PHASE consecutive_max_frames");
    send_fixed_frame(DUT_LAST_CH, 32'h0010_0000, 4096, 32'd901, 8'h91);
    wait_completion(1'b0);
    send_fixed_frame(DUT_LAST_CH, 32'h0011_0000, 4096, 32'd902, 8'h92);
    wait_completion(1'b0);
`endif

    $display("A1_MEMORY_PHASE fixed_4k_tail_backpressure");
    send_fixed_frame(4'd0, 32'h0000_0fc0, 65, 32'd101, 8'h11);
    wait_completion(1'b1);

    $display("A1_MEMORY_PHASE shared_full_beats");
    send_shared_frame(4'd1, 32'h0001_4000, 128, 32'd202, 8'h22);
    wait_completion(1'b0);

    $display("A1_MEMORY_PHASE fixed_shared_alternation");
    send_fixed_frame(DUT_LAST_CH, 32'h0002_8000, 1024, 32'd303, 8'h33);
    wait_completion(1'b0);
    send_shared_frame(4'd0, 32'h0003_c000, 63, 32'd404, 8'h44);
    wait_completion(1'b0);

    $display("A1_MEMORY_PHASE reset_valid_isolation");
    force_axi_stall = 1'b1;
    send_fixed_frame(4'd1, 32'h0004_0000, 128, 32'd505, 8'h55);
    i = 0;
    while (!m_axi_awvalid && i < 1000) begin
        @(posedge clk);
        i = i + 1;
    end
    if (!m_axi_awvalid)
        fail("reset test never reached stalled AW");
    @(negedge clk);
    soft_reset = 1'b1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    soft_reset = 1'b0;
    force_axi_stall = 1'b0;
    repeat (8) begin
        @(posedge clk);
        if (m_axi_awvalid || m_axi_wvalid || cpl_valid)
            fail("reset exposed stale AXI or completion valid");
    end

    $display("A1_MEMORY_PHASE reset_recovery");
    send_shared_frame(DUT_LAST_CH, 32'h0005_0000, 256, 32'd606, 8'h66);
    wait_completion(1'b0);

    if (four_k_split_seen == 0)
        fail("4 KiB split coverage was not observed");
    if (tail_strobe_seen < 2)
        fail("tail strobe coverage was not observed");
    if ((aw_stall_cycles == 0) || (w_stall_cycles == 0))
        fail("AXI backpressure coverage was not observed");
    if (completion_stall_seen != 1)
        fail("completion backpressure coverage mismatch");
    if (shared_pool_overflow_sticky || shared_pool_leak_check_error)
        fail("shared pool reported an integrity error");

    $display("PASS tb_dma_rx512_memory_subsystem channels=%0d payload_words=%0d meta_depth=%0d frames=%0d aw=%0d w=%0d aw_stall=%0d w_stall=%0d",
             DUT_CHANNELS, DUT_PAYLOAD_WORDS, DUT_META_DEPTH, completed_frames,
             aw_count, w_count, aw_stall_cycles, w_stall_cycles);
    $finish;
end

endmodule
