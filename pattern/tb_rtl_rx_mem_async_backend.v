`timescale 1ns/1ps

module tb_rtl_rx_mem_async_backend;

`ifdef DMA_RX_MEM_ASYNC64_PROFILE
localparam integer AXI_BYTES = 8;
localparam integer AXI_DATA_WIDTH = 64;
localparam integer AXI_STRB_WIDTH = 8;
localparam [2:0] EXPECTED_AWSIZE = 3'd3;
`else
localparam integer AXI_BYTES = 64;
localparam integer AXI_DATA_WIDTH = 512;
localparam integer AXI_STRB_WIDTH = 64;
localparam [2:0] EXPECTED_AWSIZE = 3'd6;
`endif

localparam integer MEM_BYTES = 8*1024*1024;
localparam integer AWQ_DEPTH = 16;
localparam integer BQ_DEPTH = 16;
localparam [31:0] SLVERR_ADDR = 32'h0070_0000;
localparam [31:0] DECERR_ADDR = 32'h0071_0000;

reg s_clk = 1'b0;
reg m_clk = 1'b0;
reg s_clk_enable = 1'b1;
reg m_clk_enable = 1'b1;
real s_half_ns = 2.5;
real m_half_ns = 2.5;
reg s_arstn = 1'b0;
reg m_arstn = 1'b0;
wire s_rstn;
wire m_rstn;
reg s_soft_reset = 1'b0;

reg s_cmd_valid = 1'b0;
wire s_cmd_ready;
reg [31:0] s_cmd_addr = 32'h0;
reg [31:0] s_cmd_len = 32'h0;
reg [31:0] s_cmd_aligned_len = 32'h0;
reg [3:0] s_cmd_channel = 4'h0;
reg s_payload_tvalid = 1'b0;
wire s_payload_tready;
reg [511:0] s_payload_tdata = 512'h0;
reg [63:0] s_payload_tkeep = 64'h0;
reg s_payload_tlast = 1'b0;
wire s_cpl_valid;
reg s_cpl_ready = 1'b0;
wire s_cpl_error;
wire [3:0] s_cpl_error_code;
wire [7:0] s_cpl_tag;
wire bridge_busy;
wire bridge_protocol_error;

wire m_soft_reset;
wire m_cmd_valid;
wire m_cmd_ready;
wire [31:0] m_cmd_addr;
wire [31:0] m_cmd_len;
wire [31:0] m_cmd_aligned_len;
wire [3:0] m_cmd_channel;
wire [7:0] m_cmd_tag;
wire m_payload_tvalid;
wire m_payload_tready;
wire [511:0] m_payload_tdata;
wire [63:0] m_payload_tkeep;
wire m_payload_tlast;
wire [5:0] m_payload_level;
wire writer_cpl_valid;
wire writer_cpl_ready;
wire writer_cpl_error;
wire [3:0] writer_cpl_error_code;
wire writer_busy;

wire [31:0] m_axi_awaddr;
wire [7:0] m_axi_awlen;
wire [2:0] m_axi_awsize;
wire [1:0] m_axi_awburst;
wire m_axi_awvalid;
reg m_axi_awready = 1'b0;
wire [AXI_DATA_WIDTH-1:0] m_axi_wdata;
wire [AXI_STRB_WIDTH-1:0] m_axi_wstrb;
wire m_axi_wlast;
wire m_axi_wvalid;
reg m_axi_wready = 1'b0;
reg [1:0] m_axi_bresp = 2'b00;
reg m_axi_bvalid = 1'b0;
wire m_axi_bready;

reg [7:0] memory [0:MEM_BYTES-1];
reg [31:0] aw_addr_q [0:AWQ_DEPTH-1];
reg [7:0] aw_len_q [0:AWQ_DEPTH-1];
reg [1:0] aw_resp_q [0:AWQ_DEPTH-1];
integer aw_wr_ptr = 0;
integer aw_rd_ptr = 0;
integer aw_count = 0;
reg [1:0] b_resp_q [0:BQ_DEPTH-1];
integer b_wr_ptr = 0;
integer b_rd_ptr = 0;
integer b_count = 0;
reg wr_active = 1'b0;
reg [31:0] wr_addr_q = 32'h0;
reg [7:0] wr_beats_left_q = 8'h0;
reg [1:0] wr_resp_q = 2'b00;
reg [31:0] mem_lfsr_q = 32'h91e3_502d;
reg ideal_memory = 1'b0;
reg hold_b_responses = 1'b0;
integer aw_count_next;
integer b_count_next;
integer memory_i;
integer bytes_written_this_beat;

integer errors = 0;
integer directed_lengths [0:17];
integer directed_i;
integer ratio_i;
integer stress_i;
integer stress_frames = 2000;
integer random_seed = 32'h5dca_1027;
integer frames_completed = 0;
integer commands_sent = 0;
integer source_payload_bytes = 0;
integer cdc_write_beats = 0;
integer cdc_read_beats = 0;
integer axi_write_bytes = 0;
integer source_stall_cycles = 0;
integer fifo_full_cycles = 0;
integer fifo_empty_cycles = 0;
integer axi_aw_stall_cycles = 0;
integer axi_w_stall_cycles = 0;
integer axi_w_fire_cycles = 0;
integer mem_active_cycles = 0;
integer peak_fifo_occupancy = 0;
integer peak_outstanding = 0;
integer throughput_enable = 0;
integer throughput_started = 0;
integer throughput_done = 0;
integer throughput_w_fires = 0;
integer throughput_cycles = 0;
integer throughput_expected_wbeats = 0;
integer throughput_utilization_x100 = 0;
integer throughput_bytes_per_cycle_x1000 = 0;
integer throughput_gap_reports = 0;

wire aw_fire = m_axi_awvalid && m_axi_awready;
wire w_fire = m_axi_wvalid && m_axi_wready;
wire b_fire = m_axi_bvalid && m_axi_bready;

always begin
    #(s_half_ns);
    if (s_clk_enable)
        s_clk = ~s_clk;
end

initial begin
    #1.1;
    forever begin
        #(m_half_ns);
        if (m_clk_enable)
            m_clk = ~m_clk;
    end
end

dma_reset_sync u_s_reset_sync(.clk(s_clk), .arstn(s_arstn), .rstn(s_rstn));
dma_reset_sync u_m_reset_sync(.clk(m_clk), .arstn(m_arstn), .rstn(m_rstn));

dma_rx_payload_cdc_bridge #(
    .TAG_WIDTH(8),
    .CMD_FIFO_LOG2(2),
    .PAYLOAD_FIFO_LOG2(5),
    .CPL_FIFO_LOG2(2)
) u_bridge (
    .s_clk(s_clk), .s_rst_n(s_rstn), .s_soft_reset(s_soft_reset),
    .s_cmd_valid(s_cmd_valid), .s_cmd_ready(s_cmd_ready),
    .s_cmd_addr(s_cmd_addr), .s_cmd_len(s_cmd_len),
    .s_cmd_aligned_len(s_cmd_aligned_len), .s_cmd_channel(s_cmd_channel),
    .s_payload_tvalid(s_payload_tvalid), .s_payload_tready(s_payload_tready),
    .s_payload_tdata(s_payload_tdata), .s_payload_tkeep(s_payload_tkeep),
    .s_payload_tlast(s_payload_tlast),
    .s_cpl_valid(s_cpl_valid), .s_cpl_ready(s_cpl_ready),
    .s_cpl_error(s_cpl_error), .s_cpl_error_code(s_cpl_error_code),
    .s_cpl_tag(s_cpl_tag), .s_busy(bridge_busy),
    .s_protocol_error(bridge_protocol_error),
    .m_clk(m_clk), .m_rst_n(m_rstn), .m_soft_reset(m_soft_reset),
    .m_cmd_valid(m_cmd_valid), .m_cmd_ready(m_cmd_ready),
    .m_cmd_addr(m_cmd_addr), .m_cmd_len(m_cmd_len),
    .m_cmd_aligned_len(m_cmd_aligned_len), .m_cmd_channel(m_cmd_channel),
    .m_cmd_tag(m_cmd_tag),
    .m_payload_tvalid(m_payload_tvalid), .m_payload_tready(m_payload_tready),
    .m_payload_tdata(m_payload_tdata), .m_payload_tkeep(m_payload_tkeep),
    .m_payload_tlast(m_payload_tlast), .m_payload_level(m_payload_level),
    .m_cpl_valid(writer_cpl_valid), .m_cpl_ready(writer_cpl_ready),
    .m_cpl_error(writer_cpl_error), .m_cpl_error_code(writer_cpl_error_code)
);

`ifdef DMA_RX_MEM_ASYNC64_PROFILE
wire serializer_tvalid;
wire serializer_tready;
wire [63:0] serializer_tdata;
wire [7:0] serializer_tkeep;
wire serializer_tlast;
wire [3:0] serializer_held_beats;
wire serializer_format_error;
wire serializer_busy;
wire [9:0] serializer_available_beats =
    ({4'h0, m_payload_level} << 3) + {6'h0, serializer_held_beats};

dma_rx_payload_serializer_512_to_64 u_serializer (
    .clk(m_clk), .rstn(m_rstn), .soft_reset(m_soft_reset),
    .s_tvalid(m_payload_tvalid), .s_tready(m_payload_tready),
    .s_tdata(m_payload_tdata), .s_tkeep(m_payload_tkeep),
    .s_tlast(m_payload_tlast),
    .m_tvalid(serializer_tvalid), .m_tready(serializer_tready),
    .m_tdata(serializer_tdata), .m_tkeep(serializer_tkeep),
    .m_tlast(serializer_tlast), .held_beats(serializer_held_beats),
    .format_error(serializer_format_error), .busy(serializer_busy)
);

dma_axi_write_engine_64_stream #(
    .MAX_BURST_BEATS(16), .MAX_OUTSTANDING(4),
    .MAX_CMD_BYTES(1048576), .USE_SOURCE_CREDIT(1)
) u_writer (
    .clk(m_clk), .rstn(m_rstn), .soft_reset(m_soft_reset),
    .cmd_valid(m_cmd_valid), .cmd_ready(m_cmd_ready),
    .cmd_addr(m_cmd_addr), .cmd_len(m_cmd_len),
    .s_payload_tvalid(serializer_tvalid), .s_payload_tready(serializer_tready),
    .s_payload_tdata(serializer_tdata), .s_payload_tkeep(serializer_tkeep),
    .s_payload_tlast(serializer_tlast),
    .s_payload_level(serializer_available_beats),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .cpl_valid(writer_cpl_valid), .cpl_ready(writer_cpl_ready),
    .cpl_error(writer_cpl_error), .cpl_error_code(writer_cpl_error_code),
    .busy(writer_busy)
);
`else
dma_axi_write_engine_512 #(
    .MAX_BURST_BEATS(16), .MAX_OUTSTANDING(4),
    .MAX_CMD_BYTES(1048576), .USE_SOURCE_CREDIT(1)
) u_writer (
    .clk(m_clk), .rstn(m_rstn), .soft_reset(m_soft_reset),
    .cmd_valid(m_cmd_valid), .cmd_ready(m_cmd_ready),
    .cmd_addr(m_cmd_addr), .cmd_len(m_cmd_len),
    .s_payload_tvalid(m_payload_tvalid), .s_payload_tready(m_payload_tready),
    .s_payload_tdata(m_payload_tdata), .s_payload_tkeep(m_payload_tkeep),
    .s_payload_tlast(m_payload_tlast),
    .s_payload_level({2'b00, m_payload_level}),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .cpl_valid(writer_cpl_valid), .cpl_ready(writer_cpl_ready),
    .cpl_error(writer_cpl_error), .cpl_error_code(writer_cpl_error_code),
    .busy(writer_busy)
);
`endif

function [63:0] keep_for_bytes;
    input integer bytes;
    integer keep_i;
    begin
        keep_for_bytes = 64'h0;
        for (keep_i = 0; keep_i < 64; keep_i = keep_i + 1)
            if (keep_i < bytes)
                keep_for_bytes[keep_i] = 1'b1;
    end
endfunction

function [7:0] pattern_byte;
    input integer id;
    input integer offset;
    begin
        pattern_byte = (id * 37 + offset * 11 + 8'h69) & 8'hff;
    end
endfunction

function [1:0] response_for_addr;
    input [31:0] addr;
    begin
        if (addr == SLVERR_ADDR)
            response_for_addr = 2'b10;
        else if (addr == DECERR_ADDR)
            response_for_addr = 2'b11;
        else
            response_for_addr = 2'b00;
    end
endfunction

task fail;
    input [8*192-1:0] message;
    begin
        $display("FAIL tb_rtl_rx_mem_async_backend: %0s", message);
        errors = errors + 1;
    end
endtask

task apply_hard_reset;
    begin
        s_cmd_valid = 1'b0;
        s_payload_tvalid = 1'b0;
        s_cpl_ready = 1'b0;
        s_arstn = 1'b0;
        m_arstn = 1'b0;
        #50;
        @(negedge s_clk);
        s_arstn = 1'b1;
        @(negedge m_clk);
        m_arstn = 1'b1;
        wait (s_rstn && m_rstn);
        repeat (8) @(posedge s_clk);
        if (bridge_busy || s_cpl_valid || bridge_protocol_error || writer_busy)
            fail("hard reset exposed stale transaction state");
    end
endtask

task send_frame;
    input integer id;
    input [31:0] address;
    input integer length;
    input [3:0] expected_error_code;
    integer beat_count;
    integer beat;
    integer lane;
    integer bytes_this;
    integer pad_end;
    reg [511:0] data_value;
    reg held_error;
    reg [3:0] held_code;
    reg [7:0] held_tag;
    begin
        beat_count = (length + 63) / 64;
        pad_end = (length + 63) & 32'hffff_ffc0;
        for (lane = 0; lane < pad_end; lane = lane + 1)
            memory[address + lane] = 8'ha5;

        @(negedge s_clk);
        s_cmd_addr = address;
        s_cmd_len = length;
        s_cmd_aligned_len = pad_end;
        s_cmd_channel = id[3:0];
        s_cmd_valid = 1'b1;
        while (!s_cmd_ready)
            @(negedge s_clk);
        @(negedge s_clk);
        s_cmd_valid = 1'b0;
        commands_sent = commands_sent + 1;

        for (beat = 0; beat < beat_count; beat = beat + 1) begin
            bytes_this = length - beat*64;
            if (bytes_this > 64)
                bytes_this = 64;
            data_value = 512'h0;
            for (lane = 0; lane < bytes_this; lane = lane + 1)
                data_value[lane*8 +: 8] = pattern_byte(id, beat*64 + lane);
            s_payload_tdata = data_value;
            s_payload_tkeep = keep_for_bytes(bytes_this);
            s_payload_tlast = (beat == beat_count-1);
            s_payload_tvalid = 1'b1;
            while (!s_payload_tready)
                @(negedge s_clk);
            @(negedge s_clk);
            source_payload_bytes = source_payload_bytes + bytes_this;
            cdc_write_beats = cdc_write_beats + 1;
        end
        s_payload_tvalid = 1'b0;
        s_payload_tlast = 1'b0;
        s_payload_tkeep = 64'h0;

        while (!s_cpl_valid)
            @(posedge s_clk);
        held_error = s_cpl_error;
        held_code = s_cpl_error_code;
        held_tag = s_cpl_tag;
        repeat ((id % 5) + 2) begin
            @(posedge s_clk);
            if (!s_cpl_valid || (s_cpl_error != held_error) ||
                (s_cpl_error_code != held_code) || (s_cpl_tag != held_tag))
                fail("completion changed under source backpressure");
        end
        if ((expected_error_code == 0) && s_cpl_error)
            fail("unexpected completion error");
        if ((expected_error_code != 0) &&
            (!s_cpl_error || (s_cpl_error_code != expected_error_code)))
            fail("expected AXI response error was not reported");
        @(negedge s_clk);
        s_cpl_ready = 1'b1;
        @(posedge s_clk);
        @(negedge s_clk);
        s_cpl_ready = 1'b0;
        frames_completed = frames_completed + 1;
        while (bridge_busy)
            @(posedge s_clk);

        for (lane = 0; lane < length; lane = lane + 1)
            if (memory[address + lane] != pattern_byte(id, lane))
                fail("byte-level memory scoreboard mismatch");
        for (lane = length; lane < pad_end; lane = lane + 1)
            if (memory[address + lane] != 8'ha5)
                fail("tail WSTRB modified padding byte");
    end
endtask

always @(negedge m_clk or negedge m_rstn) begin
    if (!m_rstn) begin
        mem_lfsr_q <= 32'h91e3_502d;
        m_axi_awready <= 1'b0;
        m_axi_wready <= 1'b0;
    end else begin
        mem_lfsr_q <= {mem_lfsr_q[30:0],
                       mem_lfsr_q[31] ^ mem_lfsr_q[21] ^
                       mem_lfsr_q[1] ^ mem_lfsr_q[0]};
        m_axi_awready <= (aw_count < AWQ_DEPTH) &&
                         (ideal_memory || mem_lfsr_q[0] || mem_lfsr_q[4]);
        m_axi_wready <= wr_active &&
                       (ideal_memory || mem_lfsr_q[1] || mem_lfsr_q[5]);
    end
end

always @(posedge m_clk or negedge m_rstn) begin
    if (!m_rstn) begin
        aw_wr_ptr = 0;
        aw_rd_ptr = 0;
        aw_count = 0;
        b_wr_ptr = 0;
        b_rd_ptr = 0;
        b_count = 0;
        wr_active <= 1'b0;
        wr_addr_q <= 32'h0;
        wr_beats_left_q <= 8'h0;
        wr_resp_q <= 2'b00;
        m_axi_bresp <= 2'b00;
        m_axi_bvalid <= 1'b0;
    end else begin
        aw_count_next = aw_count;
        b_count_next = b_count;

        if (aw_fire) begin
            if (m_axi_awsize != EXPECTED_AWSIZE)
                fail("unexpected AWSIZE");
            if (m_axi_awburst != 2'b01)
                fail("unexpected AWBURST");
            if ((m_axi_awaddr[11:0] + (m_axi_awlen+1)*AXI_BYTES) > 4096)
                fail("AXI burst crossed 4KB boundary");
            if (m_axi_awlen >= 16)
                fail("AXI burst exceeded 16 beats");
            aw_addr_q[aw_wr_ptr] = m_axi_awaddr;
            aw_len_q[aw_wr_ptr] = m_axi_awlen;
            aw_resp_q[aw_wr_ptr] = response_for_addr(m_axi_awaddr);
            aw_wr_ptr = (aw_wr_ptr + 1) % AWQ_DEPTH;
            aw_count_next = aw_count_next + 1;
        end

        if (!wr_active && (aw_count_next != 0)) begin
            wr_addr_q <= aw_addr_q[aw_rd_ptr];
            wr_beats_left_q <= aw_len_q[aw_rd_ptr];
            wr_resp_q <= aw_resp_q[aw_rd_ptr];
            aw_rd_ptr = (aw_rd_ptr + 1) % AWQ_DEPTH;
            aw_count_next = aw_count_next - 1;
            wr_active <= 1'b1;
        end

        if (w_fire) begin
            if (!wr_active)
                fail("W beat arrived without accepted AW");
            if (m_axi_wlast != (wr_beats_left_q == 0))
                fail("WLAST did not match AWLEN");
            bytes_written_this_beat = 0;
            for (memory_i = 0; memory_i < AXI_BYTES; memory_i = memory_i + 1)
                if (m_axi_wstrb[memory_i] && ((wr_addr_q+memory_i) < MEM_BYTES)) begin
                    memory[wr_addr_q+memory_i] <= m_axi_wdata[memory_i*8 +: 8];
                    bytes_written_this_beat = bytes_written_this_beat + 1;
                end
            axi_write_bytes <= axi_write_bytes + bytes_written_this_beat;
            wr_addr_q <= wr_addr_q + AXI_BYTES;
            if (wr_beats_left_q == 0) begin
                b_resp_q[b_wr_ptr] = wr_resp_q;
                b_wr_ptr = (b_wr_ptr + 1) % BQ_DEPTH;
                b_count_next = b_count_next + 1;
                if (aw_count_next != 0) begin
                    wr_addr_q <= aw_addr_q[aw_rd_ptr];
                    wr_beats_left_q <= aw_len_q[aw_rd_ptr];
                    wr_resp_q <= aw_resp_q[aw_rd_ptr];
                    aw_rd_ptr = (aw_rd_ptr + 1) % AWQ_DEPTH;
                    aw_count_next = aw_count_next - 1;
                    wr_active <= 1'b1;
                end else begin
                    wr_active <= 1'b0;
                end
            end else begin
                wr_beats_left_q <= wr_beats_left_q - 1'b1;
            end
        end

        if (m_axi_bvalid && m_axi_bready) begin
            m_axi_bvalid <= 1'b0;
        end else if (!m_axi_bvalid && (b_count_next != 0) &&
                     !hold_b_responses &&
                     (ideal_memory || mem_lfsr_q[2] || mem_lfsr_q[6])) begin
            m_axi_bresp <= b_resp_q[b_rd_ptr];
            b_rd_ptr = (b_rd_ptr + 1) % BQ_DEPTH;
            b_count_next = b_count_next - 1;
            m_axi_bvalid <= 1'b1;
        end

        aw_count = aw_count_next;
        b_count = b_count_next;
    end
end

always @(posedge s_clk) begin
    if (s_rstn) begin
        if (s_payload_tvalid && !s_payload_tready)
            source_stall_cycles <= source_stall_cycles + 1;
        if (u_bridge.u_payload_fifo.s_full)
            fifo_full_cycles <= fifo_full_cycles + 1;
        if (commands_sent < frames_completed || (commands_sent-frames_completed) > 1)
            fail("command/completion accounting invariant failed");
    end
end

always @(posedge m_clk) begin
    if (m_rstn) begin
        if (m_payload_tvalid && m_payload_tready)
            cdc_read_beats <= cdc_read_beats + 1;
        if (!m_payload_tvalid && writer_busy)
            fifo_empty_cycles <= fifo_empty_cycles + 1;
        if (m_axi_awvalid && !m_axi_awready)
            axi_aw_stall_cycles <= axi_aw_stall_cycles + 1;
        if (m_axi_wvalid && !m_axi_wready)
            axi_w_stall_cycles <= axi_w_stall_cycles + 1;
        if (w_fire)
            axi_w_fire_cycles <= axi_w_fire_cycles + 1;
        if (writer_busy)
            mem_active_cycles <= mem_active_cycles + 1;
        if (m_payload_level > peak_fifo_occupancy)
            peak_fifo_occupancy <= m_payload_level;
        if (u_writer.outstanding_count_q > peak_outstanding)
            peak_outstanding <= u_writer.outstanding_count_q;

        if (throughput_enable && !throughput_done) begin
            if (throughput_started)
                throughput_cycles <= throughput_cycles + 1;
            if (w_fire) begin
                if (!throughput_started) begin
                    throughput_started <= 1;
                    throughput_cycles <= 1;
                end
                throughput_w_fires <= throughput_w_fires + 1;
                if ((throughput_w_fires + 1) >= throughput_expected_wbeats)
                    throughput_done <= 1;
            end
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
            if (throughput_started && !w_fire && (throughput_gap_reports < 12)) begin
                $display("ASYNC64_GAP awvalid=%0d awready=%0d wvalid=%0d wready=%0d serializer_valid=%0d serializer_ready=%0d plan_count=%0d w_burst_active=%0d reserved=%0d source_level=%0d",
                         m_axi_awvalid, m_axi_awready, m_axi_wvalid, m_axi_wready,
                         serializer_tvalid, serializer_tready,
                         u_writer.plan_count_q, u_writer.w_burst_active_q,
                         u_writer.reserved_source_beats_q,
                         serializer_available_beats);
                throughput_gap_reports <= throughput_gap_reports + 1;
            end
`endif
        end
    end
end

initial begin
    if (!$value$plusargs("STRESS_FRAMES=%d", stress_frames))
        stress_frames = 2000;
    for (memory_i = 0; memory_i < MEM_BYTES; memory_i = memory_i + 1)
        memory[memory_i] = 8'h00;

    directed_lengths[0]=1; directed_lengths[1]=7; directed_lengths[2]=8;
    directed_lengths[3]=31; directed_lengths[4]=63; directed_lengths[5]=64;
    directed_lengths[6]=65; directed_lengths[7]=127; directed_lengths[8]=128;
    directed_lengths[9]=255; directed_lengths[10]=256; directed_lengths[11]=511;
    directed_lengths[12]=512; directed_lengths[13]=1023; directed_lengths[14]=1024;
    directed_lengths[15]=2048; directed_lengths[16]=4095; directed_lengths[17]=4096;

    apply_hard_reset();
    $display("ASYNC_BACKEND_PHASE directed_lengths");
    for (directed_i=0; directed_i<18; directed_i=directed_i+1)
        send_frame(directed_i, 32'h0001_0000 + directed_i*32'h1200,
                   directed_lengths[directed_i], 4'h0);

    $display("ASYNC_BACKEND_PHASE clock_ratios");
    for (ratio_i=0; ratio_i<6; ratio_i=ratio_i+1) begin
        case (ratio_i)
        0: begin s_half_ns=5.0; m_half_ns=2.5; end
        1: begin s_half_ns=2.5; m_half_ns=5.0; end
        2: begin s_half_ns=4.0; m_half_ns=2.5; end
        3: begin s_half_ns=2.5; m_half_ns=4.0; end
        4: begin s_half_ns=2.5; m_half_ns=2.5; end
        default: begin s_half_ns=3.7; m_half_ns=5.3; end
        endcase
        send_frame(32+ratio_i, 32'h0004_0000 + ratio_i*32'h2000,
                   1537 + ratio_i*173, 4'h0);
    end

    $display("ASYNC_BACKEND_PHASE four_k_boundaries");
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
    send_frame(48, 32'h0005_0ff8, 4096, 4'h0);
`else
    send_frame(48, 32'h0005_0fc0, 4096, 4'h0);
`endif
    send_frame(49, 32'h0005_2000, 4096, 4'h0);

    $display("ASYNC_BACKEND_PHASE max_outstanding");
    hold_b_responses=1'b1;
    fork
        send_frame(54, 32'h0005_c000, 4096, 4'h0);
        begin
            wait (u_writer.outstanding_count_q == 4);
            repeat (5) @(posedge m_clk);
            hold_b_responses=1'b0;
        end
    join

    $display("ASYNC_BACKEND_PHASE response_errors");
    send_frame(50, SLVERR_ADDR, 512, 4'd4);
    send_frame(51, DECERR_ADDR, 512, 4'd5);

    $display("ASYNC_BACKEND_PHASE clock_stops");
    fork
        send_frame(52, 32'h0005_8000, 4096, 4'h0);
        begin
            wait (s_payload_tvalid);
            repeat (4) @(posedge s_clk);
            m_clk_enable = 1'b0;
            #900;
            m_clk_enable = 1'b1;
        end
    join
    fork
        send_frame(53, 32'h0005_a000, 3073, 4'h0);
        begin
            wait (m_payload_tvalid);
            repeat (3) @(posedge m_clk);
            s_clk_enable = 1'b0;
            #500;
            s_clk_enable = 1'b1;
        end
    join

    $display("ASYNC_BACKEND_PHASE random_stress frames=%0d", stress_frames);
    for (stress_i=0; stress_i<stress_frames; stress_i=stress_i+1)
        send_frame(100+stress_i,
                   32'h0010_0000 + (stress_i % 512)*32'h1000,
                   (($random(random_seed) & 32'h7fff_ffff) % 4096)+1, 4'h0);

    $display("ASYNC_BACKEND_PHASE throughput_1mib");
    s_half_ns=2.5;
    m_half_ns=2.5;
    ideal_memory=1'b1;
    throughput_enable=1;
    throughput_started=0;
    throughput_done=0;
    throughput_w_fires=0;
    throughput_cycles=0;
    throughput_gap_reports=0;
    throughput_expected_wbeats=1048576/AXI_BYTES;
    send_frame(4095, 32'h0060_0000, 1048576, 4'h0);
    throughput_enable=0;
    ideal_memory=1'b0;
    throughput_utilization_x100=(throughput_w_fires*10000)/throughput_cycles;
    throughput_bytes_per_cycle_x1000=(1048576*1000)/throughput_cycles;
    if (throughput_utilization_x100 < 9500)
        fail("ideal-memory W utilization fell below 95 percent");

    while (bridge_busy || writer_busy)
        @(posedge s_clk);
    s_soft_reset=1'b1;
    @(posedge s_clk);
    s_soft_reset=1'b0;
    repeat (8) @(posedge s_clk);
    if (bridge_busy || writer_busy || s_cpl_valid || bridge_protocol_error)
        fail("idle soft reset did not leave a clean backend");

    if (commands_sent != frames_completed)
        fail("final command/completion count mismatch");
    if (peak_outstanding != 4)
        fail("maximum outstanding depth was not reached");
    if (fifo_full_cycles == 0 || source_stall_cycles == 0)
        fail("payload FIFO full/source backpressure was not exercised");
    if (bridge_protocol_error)
        fail("CDC bridge protocol error asserted");
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
    if (u_serializer.format_error)
        fail("serializer format error asserted for legal payloads");
`endif

    $display("ASYNC_BACKEND_THROUGHPUT bytes=1048576 axi_bytes_per_cycle_x1000=%0d utilization_pct_x100=%0d w_fire_cycles=%0d mem_cycles=%0d peak_outstanding=%0d",
             throughput_bytes_per_cycle_x1000, throughput_utilization_x100,
             throughput_w_fires, throughput_cycles, peak_outstanding);
    $display("ASYNC_BACKEND_STATS source_payload_bytes=%0d cdc_write_beats=%0d cdc_read_beats=%0d axi_write_bytes=%0d source_stall_cycles=%0d fifo_full_cycles=%0d fifo_empty_cycles=%0d aw_stall_cycles=%0d w_stall_cycles=%0d axi_w_fire_cycles=%0d mem_active_cycles=%0d peak_fifo_occupancy=%0d frames_completed=%0d",
             source_payload_bytes, cdc_write_beats, cdc_read_beats,
             axi_write_bytes, source_stall_cycles, fifo_full_cycles,
             fifo_empty_cycles, axi_aw_stall_cycles, axi_w_stall_cycles,
             axi_w_fire_cycles, mem_active_cycles, peak_fifo_occupancy,
             frames_completed);
    if (errors != 0)
        $fatal(1, "tb_rtl_rx_mem_async_backend failed errors=%0d", errors);
`ifdef DMA_RX_MEM_ASYNC64_PROFILE
    $display("PASS tb_rtl_rx_mem_async64_backend stress_frames=%0d clock_profiles=6 clock_stops=2", stress_frames);
`else
    $display("PASS tb_rtl_rx_mem_async512_backend stress_frames=%0d clock_profiles=6 clock_stops=2", stress_frames);
`endif
    $finish;
end

initial begin
    #500000000;
    $fatal(1, "tb_rtl_rx_mem_async_backend timeout");
end

endmodule
