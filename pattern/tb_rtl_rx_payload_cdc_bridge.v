`timescale 1ns/1ps

module tb_rtl_rx_payload_cdc_bridge;

reg s_clk = 1'b0;
reg m_clk = 1'b0;
reg s_clk_enable = 1'b1;
reg m_clk_enable = 1'b1;
real s_half_ns = 5.0;
real m_half_ns = 2.5;
reg s_rst_n = 1'b0;
reg m_rst_n = 1'b0;
reg s_reset_request = 1'b0;
reg s_soft_reset = 1'b0;
wire s_reset_done;

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
wire s_busy;
wire s_protocol_error;

wire m_soft_reset;
wire m_cmd_valid;
reg m_cmd_ready = 1'b0;
wire [31:0] m_cmd_addr;
wire [31:0] m_cmd_len;
wire [31:0] m_cmd_aligned_len;
wire [3:0] m_cmd_channel;
wire [7:0] m_cmd_tag;
wire m_payload_tvalid;
reg m_payload_tready = 1'b0;
wire [511:0] m_payload_tdata;
wire [63:0] m_payload_tkeep;
wire m_payload_tlast;
wire [5:0] m_payload_level;
reg m_cpl_valid = 1'b0;
wire m_cpl_ready;
reg m_cpl_error = 1'b0;
reg [3:0] m_cpl_error_code = 4'h0;
reg m_protocol_error = 1'b0;

integer errors = 0;
integer command_count = 0;
integer mem_command_count = 0;
integer payload_frame_count = 0;
integer mem_payload_frame_count = 0;
integer completion_count = 0;
integer mem_completion_count = 0;
integer source_payload_bytes = 0;
integer cdc_read_bytes = 0;
integer source_stall_cycles = 0;
integer fifo_empty_cycles = 0;
integer peak_payload_level = 0;
integer frame_id;
integer beat_index;
integer byte_index;
integer payload_bytes_this_beat;
integer expected_mem_bytes_left = 0;
integer active_mem_frame_id = 0;
integer cpl_delay_q = 0;
integer random_seed = 32'h4c44_4321;
integer ratio_case;
integer random_frame;
integer protocol_error_case_count = 0;
reg mem_frame_active = 1'b0;
reg [7:0] expected_source_tag = 8'h0;
reg [7:0] expected_mem_tag = 8'h0;
reg [31:0] expected_mem_addr = 32'h0;
reg [31:0] expected_mem_len = 32'h0;
reg [31:0] lfsr_q = 32'h7a31_9d05;

reg [2:0] prev_cmd_wgray = 3'h0;
reg [7:0] prev_payload_wgray = 8'h0;
reg [2:0] prev_cpl_rgray = 3'h0;
reg [2:0] prev_cmd_rgray = 3'h0;
reg [7:0] prev_payload_rgray = 8'h0;
reg [2:0] prev_cpl_wgray = 3'h0;

always begin
    #(s_half_ns);
    if (s_clk_enable)
        s_clk = ~s_clk;
end

initial begin
    #1.3;
    forever begin
        #(m_half_ns);
        if (m_clk_enable)
            m_clk = ~m_clk;
    end
end

dma_rx_payload_cdc_bridge #(
    .TAG_WIDTH(8),
    .CMD_FIFO_LOG2(2),
    .PAYLOAD_FIFO_LOG2(5),
    .CPL_FIFO_LOG2(2)
) u_dut (
    .s_clk(s_clk),
    .s_rst_n(s_rst_n),
    .s_reset_request(s_reset_request),
    .s_soft_reset(s_soft_reset),
    .s_reset_done(s_reset_done),
    .s_cmd_valid(s_cmd_valid),
    .s_cmd_ready(s_cmd_ready),
    .s_cmd_addr(s_cmd_addr),
    .s_cmd_len(s_cmd_len),
    .s_cmd_aligned_len(s_cmd_aligned_len),
    .s_cmd_channel(s_cmd_channel),
    .s_payload_tvalid(s_payload_tvalid),
    .s_payload_tready(s_payload_tready),
    .s_payload_tdata(s_payload_tdata),
    .s_payload_tkeep(s_payload_tkeep),
    .s_payload_tlast(s_payload_tlast),
    .s_cpl_valid(s_cpl_valid),
    .s_cpl_ready(s_cpl_ready),
    .s_cpl_error(s_cpl_error),
    .s_cpl_error_code(s_cpl_error_code),
    .s_cpl_tag(s_cpl_tag),
    .s_busy(s_busy),
    .s_protocol_error(s_protocol_error),
    .m_clk(m_clk),
    .m_rst_n(m_rst_n),
    .m_backend_busy(mem_frame_active || m_cpl_valid),
    .m_protocol_error(m_protocol_error),
    .m_soft_reset(m_soft_reset),
    .m_cmd_valid(m_cmd_valid),
    .m_cmd_ready(m_cmd_ready),
    .m_cmd_addr(m_cmd_addr),
    .m_cmd_len(m_cmd_len),
    .m_cmd_aligned_len(m_cmd_aligned_len),
    .m_cmd_channel(m_cmd_channel),
    .m_cmd_tag(m_cmd_tag),
    .m_payload_tvalid(m_payload_tvalid),
    .m_payload_tready(m_payload_tready),
    .m_payload_tdata(m_payload_tdata),
    .m_payload_tkeep(m_payload_tkeep),
    .m_payload_tlast(m_payload_tlast),
    .m_payload_level(m_payload_level),
    .m_cpl_valid(m_cpl_valid),
    .m_cpl_ready(m_cpl_ready),
    .m_cpl_error(m_cpl_error),
    .m_cpl_error_code(m_cpl_error_code)
);

function integer count_ones;
    input [31:0] value;
    integer count_i;
    begin
        count_ones = 0;
        for (count_i = 0; count_i < 32; count_i = count_i + 1)
            if (value[count_i])
                count_ones = count_ones + 1;
    end
endfunction

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
        pattern_byte = (id * 29 + offset * 17 + 8'h5b) & 8'hff;
    end
endfunction

task fail;
    input [8*160-1:0] message;
    begin
        $display("FAIL tb_rtl_rx_payload_cdc_bridge: %0s", message);
        errors = errors + 1;
    end
endtask

task apply_hard_reset;
    begin
        s_cmd_valid = 1'b0;
        s_payload_tvalid = 1'b0;
        s_cpl_ready = 1'b0;
        s_reset_request = 1'b0;
        s_soft_reset = 1'b0;
        m_protocol_error = 1'b0;
        s_rst_n = 1'b0;
        m_rst_n = 1'b0;
        expected_source_tag = 8'h0;
        prev_cmd_wgray = 3'h0;
        prev_payload_wgray = 8'h0;
        prev_cpl_rgray = 3'h0;
        prev_cmd_rgray = 3'h0;
        prev_payload_rgray = 8'h0;
        prev_cpl_wgray = 3'h0;
        repeat (6) @(posedge s_clk);
        repeat (6) @(posedge m_clk);
        @(negedge s_clk);
        s_rst_n = 1'b1;
        @(negedge m_clk);
        m_rst_n = 1'b1;
        repeat (8) @(posedge s_clk);
        if (s_cpl_valid || s_busy || s_protocol_error)
            fail("hard reset exposed stale source-domain state");
    end
endtask

task expect_protocol_error;
    input [8*80-1:0] case_name;
    integer guard;
    begin
        guard = 0;
        while (!s_protocol_error && (guard < 64)) begin
            @(posedge s_clk);
            guard = guard + 1;
        end
        if (!s_protocol_error)
            fail({"protocol error was not observed: ", case_name});
        else begin
            protocol_error_case_count = protocol_error_case_count + 1;
            $display("CDC_BRIDGE_PROTOCOL_ERROR case=%0s", case_name);
        end
    end
endtask

task inject_payload_without_command;
    begin
        @(negedge s_clk);
        s_payload_tdata = 512'h0123;
        s_payload_tkeep = 64'hffff_ffff_ffff_ffff;
        s_payload_tlast = 1'b1;
        s_payload_tvalid = 1'b1;
        repeat (3) begin
            @(posedge s_clk);
            #1;
            if (s_payload_tready)
                fail("payload without command was accepted");
        end
        expect_protocol_error("payload_without_command");
        if (m_payload_tvalid || (u_dut.payload_fifo_s_level != 0))
            fail("payload without command entered the payload FIFO");
        @(negedge s_clk);
        s_payload_tvalid = 1'b0;
        s_payload_tlast = 1'b0;
        s_payload_tkeep = 64'h0;
    end
endtask

task send_frame_with_payload_after_tlast;
    input integer id;
    integer lane;
    reg [511:0] data_value;
    begin
        @(negedge s_clk);
        s_cmd_addr = 32'h0010_0000 + id * 32'h2000;
        s_cmd_len = 32'd64;
        s_cmd_aligned_len = 32'd64;
        s_cmd_channel = id[3:0];
        s_cmd_valid = 1'b1;
        while (!s_cmd_ready)
            @(negedge s_clk);
        @(negedge s_clk);
        s_cmd_valid = 1'b0;
        command_count = command_count + 1;

        data_value = 512'h0;
        for (lane = 0; lane < 64; lane = lane + 1)
            data_value[lane*8 +: 8] = pattern_byte(id, lane);
        s_payload_tdata = data_value;
        s_payload_tkeep = 64'hffff_ffff_ffff_ffff;
        s_payload_tlast = 1'b1;
        s_payload_tvalid = 1'b1;
        while (!s_payload_tready)
            @(negedge s_clk);
        @(negedge s_clk);
        source_payload_bytes = source_payload_bytes + 64;
        payload_frame_count = payload_frame_count + 1;

        s_payload_tdata = ~data_value;
        s_payload_tlast = 1'b0;
        repeat (3) begin
            @(posedge s_clk);
            #1;
            if (s_payload_tready)
                fail("payload after TLAST was accepted");
        end
        expect_protocol_error("payload_after_tlast");
        @(negedge s_clk);
        s_payload_tvalid = 1'b0;
        s_payload_tkeep = 64'h0;

        s_cpl_ready = 1'b1;
        while (!s_cpl_valid)
            @(posedge s_clk);
        if (s_cpl_error || (s_cpl_error_code != 0))
            fail("payload-after-TLAST case changed the valid completion");
        if (s_cpl_tag != expected_source_tag)
            fail("payload-after-TLAST completion tag mismatch");
        expected_source_tag = expected_source_tag + 1'b1;
        @(negedge s_clk);
        s_cpl_ready = 1'b0;
        completion_count = completion_count + 1;
        while (s_busy)
            @(posedge s_clk);
    end
endtask

task inject_completion_without_command;
    input [8*80-1:0] case_name;
    begin
        @(negedge m_clk);
        m_cpl_error = 1'b0;
        m_cpl_error_code = 4'h0;
        m_cpl_valid = 1'b1;
        repeat (3) begin
            @(posedge m_clk);
            #1;
            if (m_cpl_ready)
                fail("completion without command was accepted");
        end
        expect_protocol_error(case_name);
        if (u_dut.cpl_fifo_s_level != 0)
            fail("completion without command entered the completion FIFO");
        @(negedge m_clk);
        m_cpl_valid = 1'b0;
    end
endtask

task send_frame;
    input integer id;
    input integer length;
    integer beat_count;
    integer beat;
    integer lane;
    integer bytes_this;
    reg [511:0] data_value;
    begin
        beat_count = (length + 63) / 64;
        @(negedge s_clk);
        s_cmd_addr = 32'h0010_0000 + id * 32'h2000;
        s_cmd_len = length;
        s_cmd_aligned_len = (length + 63) & 32'hffff_ffc0;
        s_cmd_channel = id[3:0];
        s_cmd_valid = 1'b1;
        while (!s_cmd_ready)
            @(negedge s_clk);
        @(negedge s_clk);
        s_cmd_valid = 1'b0;
        command_count = command_count + 1;

        for (beat = 0; beat < beat_count; beat = beat + 1) begin
            bytes_this = length - beat * 64;
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
        end
        s_payload_tvalid = 1'b0;
        s_payload_tlast = 1'b0;
        s_payload_tkeep = 64'h0;
        payload_frame_count = payload_frame_count + 1;

        repeat ((id % 7) + 2) @(posedge s_clk);
        s_cpl_ready = 1'b1;
        @(posedge s_clk);
        while (!s_cpl_valid)
            @(posedge s_clk);
        if (s_cpl_error || (s_cpl_error_code != 0))
            fail("unexpected completion error");
        if (s_cpl_tag != expected_source_tag)
            fail("completion tag sequence mismatch");
        expected_source_tag = expected_source_tag + 1'b1;
        @(negedge s_clk);
        s_cpl_ready = 1'b0;
        completion_count = completion_count + 1;
        while (s_busy)
            @(posedge s_clk);
    end
endtask

always @(negedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        lfsr_q <= 32'h7a31_9d05;
        m_cmd_ready <= 1'b0;
        m_payload_tready <= 1'b0;
    end else begin
        lfsr_q <= {lfsr_q[30:0], lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
        m_cmd_ready <= !mem_frame_active && (lfsr_q[0] || lfsr_q[3]);
        m_payload_tready <= mem_frame_active && (lfsr_q[1] || lfsr_q[5]);
    end
end

always @(posedge m_clk or negedge m_rst_n) begin
    if (!m_rst_n) begin
        mem_frame_active <= 1'b0;
        expected_mem_tag <= 8'h0;
        expected_mem_addr <= 32'h0;
        expected_mem_len <= 32'h0;
        expected_mem_bytes_left <= 0;
        active_mem_frame_id <= 0;
        m_cpl_valid <= 1'b0;
        m_cpl_error <= 1'b0;
        m_cpl_error_code <= 4'h0;
        cpl_delay_q <= 0;
    end else begin
        if (m_cmd_valid && m_cmd_ready) begin
            if (mem_frame_active)
                fail("memory command overlapped active frame");
            if (m_cmd_tag != expected_mem_tag)
                fail("memory command tag sequence mismatch");
            if (m_cmd_aligned_len != ((m_cmd_len + 63) & 32'hffff_ffc0))
                fail("aligned length changed across command CDC");
            mem_frame_active <= 1'b1;
            expected_mem_addr <= m_cmd_addr;
            expected_mem_len <= m_cmd_len;
            expected_mem_bytes_left <= m_cmd_len;
            active_mem_frame_id <= mem_command_count;
            expected_mem_tag <= expected_mem_tag + 1'b1;
            mem_command_count <= mem_command_count + 1;
        end

        if (m_payload_tvalid && m_payload_tready) begin
            payload_bytes_this_beat = (expected_mem_bytes_left > 64) ? 64 : expected_mem_bytes_left;
            if (m_payload_tkeep != keep_for_bytes(payload_bytes_this_beat))
                fail("payload keep changed across CDC");
            if (m_payload_tlast != (expected_mem_bytes_left <= 64))
                fail("payload last changed across CDC");
            for (byte_index = 0; byte_index < payload_bytes_this_beat; byte_index = byte_index + 1)
                if (m_payload_tdata[byte_index*8 +: 8] !=
                    pattern_byte(active_mem_frame_id, expected_mem_len - expected_mem_bytes_left + byte_index))
                    fail("payload byte mismatch across CDC");
            cdc_read_bytes <= cdc_read_bytes + payload_bytes_this_beat;
            expected_mem_bytes_left <= expected_mem_bytes_left - payload_bytes_this_beat;
            if (m_payload_tlast) begin
                mem_frame_active <= 1'b0;
                mem_payload_frame_count <= mem_payload_frame_count + 1;
                cpl_delay_q <= (active_mem_frame_id % 5) + 1;
            end
        end else if (mem_frame_active && !m_payload_tvalid) begin
            fifo_empty_cycles <= fifo_empty_cycles + 1;
        end

        if (m_payload_level > peak_payload_level)
            peak_payload_level <= m_payload_level;

        if (cpl_delay_q != 0)
            cpl_delay_q <= cpl_delay_q - 1;
        else if (!m_cpl_valid && (mem_payload_frame_count > mem_completion_count)) begin
            m_cpl_valid <= 1'b1;
            m_cpl_error <= 1'b0;
            m_cpl_error_code <= 4'h0;
        end

        if (m_cpl_valid && m_cpl_ready) begin
            m_cpl_valid <= 1'b0;
            mem_completion_count <= mem_completion_count + 1;
        end
    end
end

always @(posedge s_clk) begin
    if (s_rst_n) begin
        if (s_payload_tvalid && !s_payload_tready)
            source_stall_cycles <= source_stall_cycles + 1;
        if ((command_count < completion_count) || ((command_count - completion_count) > 1))
            fail("command/completion in-flight invariant failed");
        if (count_ones({29'h0, u_dut.u_cmd_fifo.u_fifo.s_wgray ^ prev_cmd_wgray}) > 1)
            fail("command FIFO local write Gray pointer changed by more than one bit");
        if (count_ones({24'h0, u_dut.u_payload_fifo.u_fifo.s_wgray ^ prev_payload_wgray}) > 1)
            fail("payload FIFO local write Gray pointer changed by more than one bit");
        if (count_ones({29'h0, u_dut.u_cpl_fifo.u_fifo.m_rgray ^ prev_cpl_rgray}) > 1)
            fail("completion FIFO local read Gray pointer changed by more than one bit");
        prev_cmd_wgray <= u_dut.u_cmd_fifo.u_fifo.s_wgray;
        prev_payload_wgray <= u_dut.u_payload_fifo.u_fifo.s_wgray;
        prev_cpl_rgray <= u_dut.u_cpl_fifo.u_fifo.m_rgray;
    end
end

always @(posedge m_clk) begin
    if (m_rst_n) begin
        if (count_ones({29'h0, u_dut.u_cmd_fifo.u_fifo.m_rgray ^ prev_cmd_rgray}) > 1)
            fail("command FIFO local read Gray pointer changed by more than one bit");
        if (count_ones({24'h0, u_dut.u_payload_fifo.u_fifo.m_rgray ^ prev_payload_rgray}) > 1)
            fail("payload FIFO local read Gray pointer changed by more than one bit");
        if (count_ones({29'h0, u_dut.u_cpl_fifo.u_fifo.s_wgray ^ prev_cpl_wgray}) > 1)
            fail("completion FIFO local write Gray pointer changed by more than one bit");
        prev_cmd_rgray <= u_dut.u_cmd_fifo.u_fifo.m_rgray;
        prev_payload_rgray <= u_dut.u_payload_fifo.u_fifo.m_rgray;
        prev_cpl_wgray <= u_dut.u_cpl_fifo.u_fifo.s_wgray;
    end
end

initial begin
    $display("CDC_BRIDGE_PHASE ratios_and_random_phase");
    apply_hard_reset();

    for (ratio_case = 0; ratio_case < 6; ratio_case = ratio_case + 1) begin
        case (ratio_case)
        0: begin s_half_ns = 5.0; m_half_ns = 2.5; end
        1: begin s_half_ns = 2.5; m_half_ns = 5.0; end
        2: begin s_half_ns = 4.0; m_half_ns = 2.5; end
        3: begin s_half_ns = 2.5; m_half_ns = 4.0; end
        4: begin s_half_ns = 2.5; m_half_ns = 2.5; end
        default: begin s_half_ns = 3.7; m_half_ns = 5.3; end
        endcase
        for (frame_id = ratio_case*8; frame_id < ratio_case*8+8; frame_id = frame_id + 1)
            send_frame(frame_id, ((frame_id * 173) % 4096) + 1);
    end

    $display("CDC_BRIDGE_PHASE clock_stops");
    fork
        begin
            send_frame(48, 4096);
        end
        begin
            wait (s_payload_tvalid);
            repeat (4) @(posedge s_clk);
            m_clk_enable = 1'b0;
            #600;
            m_clk_enable = 1'b1;
        end
    join

    fork
        begin
            send_frame(49, 2049);
        end
        begin
            wait (m_payload_tvalid);
            repeat (3) @(posedge m_clk);
            s_clk_enable = 1'b0;
            #140;
            s_clk_enable = 1'b1;
        end
    join

    $display("CDC_BRIDGE_PHASE random_stress frames=400");
    for (random_frame = 0; random_frame < 400; random_frame = random_frame + 1)
        send_frame(50 + random_frame, (($random(random_seed) & 32'h7fff_ffff) % 4096) + 1);

    while (s_busy || m_cpl_valid)
        @(posedge s_clk);

    $display("CDC_BRIDGE_PHASE protocol_error_reachability");
    apply_hard_reset();
    inject_payload_without_command();

    apply_hard_reset();
    send_frame_with_payload_after_tlast(command_count);

    apply_hard_reset();
    inject_completion_without_command("completion_without_command");

    apply_hard_reset();
    send_frame(command_count, 64);
    inject_completion_without_command("duplicate_completion");

    apply_hard_reset();
    $display("CDC_BRIDGE_PHASE memory_protocol_error_visibility");
    @(negedge m_clk);
    m_protocol_error = 1'b1;
    @(negedge m_clk);
    m_protocol_error = 1'b0;
    repeat (6) @(posedge s_clk);
    if (!s_protocol_error)
        fail("memory-domain protocol error was not synchronized to source");
    else begin
        protocol_error_case_count = protocol_error_case_count + 1;
        $display("CDC_BRIDGE_PROTOCOL_ERROR case=memory_backend_error");
    end

    s_reset_request = 1'b1;
    @(posedge s_clk);
    s_reset_request = 1'b0;
    while (!s_reset_done)
        @(posedge s_clk);
    s_soft_reset = 1'b1;
    @(posedge s_clk);
    s_soft_reset = 1'b0;
    repeat (8) @(posedge s_clk);
    if (s_busy || s_cpl_valid || s_protocol_error)
        fail("idle soft reset did not return bridge to clean state");

    if (command_count != completion_count)
        fail("final command/completion count mismatch");
    if (payload_frame_count != mem_payload_frame_count)
        fail("final payload frame count mismatch");
    if (source_payload_bytes != cdc_read_bytes)
        fail("final payload byte count mismatch");
    if (source_stall_cycles == 0)
        fail("payload FIFO full backpressure was not exercised");
    if (peak_payload_level < 24)
        fail("payload FIFO near-full level was not exercised");
    if (protocol_error_case_count != 5)
        fail("directed protocol-error case count mismatch");
    if (s_protocol_error)
        fail("bridge protocol error asserted");

    if (errors != 0)
        $fatal(1, "tb_rtl_rx_payload_cdc_bridge failed errors=%0d", errors);
    $display("PASS tb_rtl_rx_payload_cdc_bridge frames=%0d bytes=%0d source_stalls=%0d fifo_empty=%0d peak_payload_level=%0d clock_profiles=6 clock_stops=2 protocol_error_cases=%0d",
             command_count, source_payload_bytes, source_stall_cycles,
             fifo_empty_cycles, peak_payload_level, protocol_error_case_count);
    $finish;
end

initial begin
    #100000000;
    $fatal(1, "tb_rtl_rx_payload_cdc_bridge timeout");
end

endmodule
