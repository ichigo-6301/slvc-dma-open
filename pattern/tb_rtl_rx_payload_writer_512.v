`timescale 1ns/1ps

module tb_rtl_rx_payload_writer_512;

localparam integer MAX_OUTSTANDING = 4;
localparam integer MAX_BURST_BEATS = 16;
localparam integer TIMEOUT_CYCLES = 200000;

localparam [3:0] ERR_NONE          = 4'd0;
localparam [3:0] ERR_UNALIGNED     = 4'd1;
localparam [3:0] ERR_SOURCE_FORMAT = 4'd3;
localparam [3:0] ERR_AXI_SLVERR    = 4'd4;
localparam [3:0] ERR_AXI_DECERR    = 4'd5;

reg clk = 1'b0;
reg rstn = 1'b0;
reg soft_reset = 1'b0;
always #2.5 clk = ~clk;

reg          cmd_valid = 1'b0;
wire         cmd_ready;
reg [31:0]   cmd_addr = 32'h0;
reg [31:0]   cmd_len = 32'h0;
reg          s_payload_tvalid = 1'b0;
wire         s_payload_tready;
reg [511:0]  s_payload_tdata = 512'h0;
reg [63:0]   s_payload_tkeep = 64'h0;
reg          s_payload_tlast = 1'b0;
wire [31:0]  m_axi_awaddr;
wire [7:0]   m_axi_awlen;
wire [2:0]   m_axi_awsize;
wire [1:0]   m_axi_awburst;
wire         m_axi_awvalid;
reg          m_axi_awready = 1'b1;
wire [511:0] m_axi_wdata;
wire [63:0]  m_axi_wstrb;
wire         m_axi_wlast;
wire         m_axi_wvalid;
reg          m_axi_wready = 1'b1;
reg [1:0]    m_axi_bresp = 2'b00;
reg          m_axi_bvalid = 1'b0;
wire         m_axi_bready;
wire         cpl_valid;
reg          cpl_ready = 1'b1;
wire         cpl_error;
wire [3:0]   cpl_error_code;
wire         busy;

integer cycle_count;
integer case_count;
integer aw_count;
integer w_count;
integer b_count;
integer first_w_cycle;
integer last_w_cycle;
integer peak_outstanding;
integer active_cycle_count;
integer aw_stall_cycle_count;
integer w_stall_cycle_count;
integer expected_aw_bytes_left;
integer expected_aw_addr;
integer expected_w_byte_offset;
integer expected_w_burst_left;
integer expected_total_len;
integer expected_seed;
integer inject_bresp_burst;
reg [1:0] inject_bresp_value;
reg random_backpressure;
reg [31:0] lfsr_q;
reg cpl_seen;
reg cpl_error_seen;
reg [3:0] cpl_code_seen;

integer aw_q_beats [0:31];
integer aw_q_wr_ptr;
integer aw_q_rd_ptr;
integer aw_q_count;
reg [1:0] b_q_resp [0:31];
integer b_q_delay [0:31];
integer b_q_wr_ptr;
integer b_q_rd_ptr;
integer b_q_count;
integer completed_burst_count;

reg aw_stalled_q;
reg [42:0] aw_held_q;
reg w_stalled_q;
reg [576:0] w_held_q;
reg cpl_stalled_q;
reg [4:0] cpl_held_q;

integer i;
integer bytes_this;
integer beats_expected;
integer beats_to_4k;
integer burst_expected;
integer aw_q_count_next;
integer b_q_count_next;
integer active_window;
integer utilization_x100;
integer random_len;
integer random_addr;
integer random_source;
reg [63:0] expected_strb;
reg [7:0] expected_byte;

dma_axi_write_engine_512 #(
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .MAX_OUTSTANDING(MAX_OUTSTANDING),
    .MAX_CMD_BYTES(1048576)
) u_dut (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_addr(cmd_addr),
    .cmd_len(cmd_len),
    .s_payload_tvalid(s_payload_tvalid),
    .s_payload_tready(s_payload_tready),
    .s_payload_tdata(s_payload_tdata),
    .s_payload_tkeep(s_payload_tkeep),
    .s_payload_tlast(s_payload_tlast),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .cpl_valid(cpl_valid),
    .cpl_ready(cpl_ready),
    .cpl_error(cpl_error),
    .cpl_error_code(cpl_error_code),
    .busy(busy)
);

function [63:0] keep_mask;
    input integer count;
    integer k;
    begin
        keep_mask = 64'h0;
        for (k = 0; k < 64; k = k + 1) begin
            if (k < count)
                keep_mask[k] = 1'b1;
        end
    end
endfunction

function [7:0] payload_byte;
    input integer seed;
    input integer offset;
    begin
        payload_byte = (seed + offset * 13 + (offset >> 3)) & 8'hff;
    end
endfunction

task fail;
    input [1023:0] message;
    begin
        $display("FAIL tb_rtl_rx_payload_writer_512: %0s time=%0t", message, $time);
        $fatal(1);
    end
endtask

task clear_scoreboard;
    integer k;
    begin
        aw_count = 0;
        w_count = 0;
        b_count = 0;
        first_w_cycle = -1;
        last_w_cycle = -1;
        peak_outstanding = 0;
        active_cycle_count = 0;
        aw_stall_cycle_count = 0;
        w_stall_cycle_count = 0;
        expected_aw_bytes_left = 0;
        expected_aw_addr = 0;
        expected_w_byte_offset = 0;
        expected_w_burst_left = 0;
        expected_total_len = 0;
        expected_seed = 0;
        inject_bresp_burst = -1;
        inject_bresp_value = 2'b00;
        aw_q_wr_ptr = 0;
        aw_q_rd_ptr = 0;
        aw_q_count = 0;
        b_q_wr_ptr = 0;
        b_q_rd_ptr = 0;
        b_q_count = 0;
        completed_burst_count = 0;
        cpl_seen = 1'b0;
        cpl_error_seen = 1'b0;
        cpl_code_seen = ERR_NONE;
        for (k = 0; k < 32; k = k + 1) begin
            aw_q_beats[k] = 0;
            b_q_resp[k] = 2'b00;
            b_q_delay[k] = 0;
        end
    end
endtask

task clear_drivers;
    begin
        cmd_valid = 1'b0;
        cmd_addr = 32'h0;
        cmd_len = 32'h0;
        s_payload_tvalid = 1'b0;
        s_payload_tdata = 512'h0;
        s_payload_tkeep = 64'h0;
        s_payload_tlast = 1'b0;
        soft_reset = 1'b0;
        m_axi_awready = 1'b1;
        m_axi_wready = 1'b1;
        m_axi_bvalid = 1'b0;
        m_axi_bresp = 2'b00;
        cpl_ready = 1'b1;
        random_backpressure = 1'b0;
        lfsr_q = 32'h1ace_b00c;
        aw_stalled_q = 1'b0;
        w_stalled_q = 1'b0;
        cpl_stalled_q = 1'b0;
    end
endtask

task apply_reset;
    begin
        @(negedge clk);
        rstn = 1'b0;
        clear_drivers();
        clear_scoreboard();
        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);
    end
endtask

task prepare_case;
    input [31:0] addr;
    input [31:0] len;
    input integer seed;
    begin
        clear_scoreboard();
        expected_aw_addr = addr;
        expected_aw_bytes_left = len;
        expected_total_len = len;
        expected_seed = seed;
    end
endtask

task issue_command;
    input [31:0] addr;
    input [31:0] len;
    integer timeout;
    begin
        @(negedge clk);
        cmd_addr = addr;
        cmd_len = len;
        cmd_valid = 1'b1;
        timeout = 0;
        begin : issue_wait
        while (1) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (cmd_ready)
                disable issue_wait;
            if (timeout > 1000)
                fail("cmd_ready timeout");
        end
        end
        @(negedge clk);
        cmd_valid = 1'b0;
    end
endtask

task drive_payload;
    input [31:0] len;
    input integer seed;
    input integer corrupt_last;
    integer offset;
    integer lane;
    integer timeout;
    integer local_bytes;
    reg [511:0] data_v;
    reg [63:0] keep_v;
    reg last_v;
    begin
        offset = 0;
        while (offset < len) begin
            local_bytes = len - offset;
            if (local_bytes > 64)
                local_bytes = 64;
            data_v = {512{1'b1}};
            for (lane = 0; lane < 64; lane = lane + 1) begin
                if (lane < local_bytes)
                    data_v[lane*8 +: 8] = payload_byte(seed, offset + lane);
                else
                    data_v[lane*8 +: 8] = 8'ha5;
            end
            keep_v = keep_mask(local_bytes);
            last_v = ((offset + local_bytes) == len);
            if (corrupt_last && last_v)
                keep_v = 64'hffff_ffff_ffff_ffff;

            @(negedge clk);
            s_payload_tdata = data_v;
            s_payload_tkeep = keep_v;
            s_payload_tlast = last_v;
            s_payload_tvalid = 1'b1;
            timeout = 0;
            begin : payload_wait
            while (1) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (s_payload_tready)
                    disable payload_wait;
                if (timeout > TIMEOUT_CYCLES)
                    fail("payload ready timeout");
            end
            end
            offset = offset + local_bytes;
        end
        @(negedge clk);
        s_payload_tvalid = 1'b0;
        s_payload_tdata = 512'h0;
        s_payload_tkeep = 64'h0;
        s_payload_tlast = 1'b0;
    end
endtask

task wait_completion;
    input expected_error;
    input [3:0] expected_code;
    integer timeout;
    begin
        timeout = 0;
        while (!cpl_seen) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout > TIMEOUT_CYCLES)
                fail("completion timeout");
        end
        if (cpl_error_seen !== expected_error)
            fail("completion error flag mismatch");
        if (cpl_code_seen !== expected_code)
            fail("completion error code mismatch");
        if ((u_dut.plan_count_q != 0) || (u_dut.outstanding_count_q != 0) ||
            u_dut.w_burst_active_q || u_dut.m_axi_awvalid || u_dut.m_axi_wvalid)
            fail("writer state not empty at completion");
        case_count = case_count + 1;
    end
endtask

task run_frame;
    input [31:0] addr;
    input [31:0] len;
    input integer seed;
    input expected_error;
    input [3:0] expected_code;
    input integer corrupt_last;
    begin
        prepare_case(addr, len, seed);
        issue_command(addr, len);
        if ((len != 0) && (addr[5:0] == 0))
            drive_payload(len, seed, corrupt_last);
        wait_completion(expected_error, expected_code);
    end
endtask

// Randomized AXI ready generation is independent of source valid. Keeping it
// on the falling edge gives the DUT a full half-cycle of setup before sampling.
always @(negedge clk or negedge rstn) begin
    if (!rstn) begin
        lfsr_q <= 32'h1ace_b00c;
        m_axi_awready <= 1'b1;
        m_axi_wready <= 1'b1;
    end else begin
        lfsr_q <= {lfsr_q[30:0], lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
        if (random_backpressure) begin
            m_axi_awready <= lfsr_q[0] | lfsr_q[4];
            m_axi_wready <= lfsr_q[1] | lfsr_q[5];
        end else begin
            m_axi_awready <= 1'b1;
            m_axi_wready <= 1'b1;
        end
    end
end

// AXI protocol scoreboard and ordered B-response source.
always @(posedge clk or negedge rstn) begin
    if (!rstn || soft_reset) begin
        cycle_count <= 0;
        m_axi_bvalid <= 1'b0;
        m_axi_bresp <= 2'b00;
        aw_q_wr_ptr = 0;
        aw_q_rd_ptr = 0;
        aw_q_count = 0;
        b_q_wr_ptr = 0;
        b_q_rd_ptr = 0;
        b_q_count = 0;
        expected_w_burst_left = 0;
    end else begin
        cycle_count <= cycle_count + 1;

        if (u_dut.outstanding_count_q > peak_outstanding)
            peak_outstanding = u_dut.outstanding_count_q;
        if (busy)
            active_cycle_count = active_cycle_count + 1;
        if (m_axi_awvalid && !m_axi_awready)
            aw_stall_cycle_count = aw_stall_cycle_count + 1;
        if (m_axi_wvalid && !m_axi_wready)
            w_stall_cycle_count = w_stall_cycle_count + 1;

        aw_q_count_next = aw_q_count;
        if (m_axi_awvalid && m_axi_awready) begin
            if (m_axi_awsize !== 3'd6)
                fail("AWSIZE is not 64 bytes");
            if (m_axi_awburst !== 2'b01)
                fail("AWBURST is not INCR");
            if (m_axi_awaddr[5:0] != 0)
                fail("AWADDR is not 64-byte aligned");
            beats_expected = (expected_aw_bytes_left + 63) / 64;
            beats_to_4k = (4096 - (expected_aw_addr & 12'hfff)) / 64;
            burst_expected = beats_expected;
            if (burst_expected > MAX_BURST_BEATS)
                burst_expected = MAX_BURST_BEATS;
            if (burst_expected > beats_to_4k)
                burst_expected = beats_to_4k;
            if (m_axi_awaddr !== expected_aw_addr[31:0])
                fail("AWADDR sequence mismatch");
            if (m_axi_awlen !== (burst_expected - 1))
                fail("AWLEN mismatch");
            if ((m_axi_awaddr[11:0] + ((m_axi_awlen + 1) << 6)) > 4096)
                fail("AW burst crosses 4KB boundary");
            aw_q_beats[aw_q_wr_ptr] = burst_expected;
            aw_q_wr_ptr = (aw_q_wr_ptr + 1) & 31;
            aw_q_count_next = aw_q_count_next + 1;
            expected_aw_addr = expected_aw_addr + burst_expected * 64;
            if (expected_aw_bytes_left > burst_expected * 64)
                expected_aw_bytes_left = expected_aw_bytes_left - burst_expected * 64;
            else
                expected_aw_bytes_left = 0;
            aw_count = aw_count + 1;
        end

        b_q_count_next = b_q_count;
        if (m_axi_wvalid && m_axi_wready) begin
            if (expected_w_burst_left == 0) begin
                if (aw_q_count_next == 0)
                    fail("W beat arrived without an accepted AW burst");
                expected_w_burst_left = aw_q_beats[aw_q_rd_ptr];
                aw_q_rd_ptr = (aw_q_rd_ptr + 1) & 31;
                aw_q_count_next = aw_q_count_next - 1;
            end

            bytes_this = expected_total_len - expected_w_byte_offset;
            if (bytes_this > 64)
                bytes_this = 64;
            expected_strb = keep_mask(bytes_this);
            if (m_axi_wstrb !== expected_strb)
                fail("WSTRB mismatch");
            if (m_axi_wlast !== (expected_w_burst_left == 1))
                fail("WLAST mismatch");
            for (i = 0; i < 64; i = i + 1) begin
                if (expected_strb[i]) begin
                    expected_byte = payload_byte(expected_seed, expected_w_byte_offset + i);
                    if (m_axi_wdata[i*8 +: 8] !== expected_byte) begin
                        $display("WDATA_MISMATCH addr=%08x len=%0d beat_offset=%0d lane=%0d got=%02x expected=%02x",
                                 expected_aw_addr, expected_total_len, expected_w_byte_offset,
                                 i, m_axi_wdata[i*8 +: 8], expected_byte);
                        fail("WDATA byte mismatch");
                    end
                end
            end

            if (first_w_cycle < 0)
                first_w_cycle = cycle_count;
            last_w_cycle = cycle_count;
            expected_w_byte_offset = expected_w_byte_offset + bytes_this;
            expected_w_burst_left = expected_w_burst_left - 1;
            w_count = w_count + 1;

            if (m_axi_wlast) begin
                if (completed_burst_count == inject_bresp_burst)
                    b_q_resp[b_q_wr_ptr] = inject_bresp_value;
                else
                    b_q_resp[b_q_wr_ptr] = 2'b00;
                b_q_delay[b_q_wr_ptr] = random_backpressure ? (lfsr_q[9:7] & 7) : 0;
                b_q_wr_ptr = (b_q_wr_ptr + 1) & 31;
                b_q_count_next = b_q_count_next + 1;
                completed_burst_count = completed_burst_count + 1;
            end
        end
        aw_q_count = aw_q_count_next;

        if (m_axi_bvalid && m_axi_bready) begin
            m_axi_bvalid <= 1'b0;
            b_count = b_count + 1;
        end else if (!m_axi_bvalid && (b_q_count_next != 0)) begin
            if (b_q_delay[b_q_rd_ptr] != 0) begin
                b_q_delay[b_q_rd_ptr] = b_q_delay[b_q_rd_ptr] - 1;
            end else begin
                m_axi_bvalid <= 1'b1;
                m_axi_bresp <= b_q_resp[b_q_rd_ptr];
                b_q_rd_ptr = (b_q_rd_ptr + 1) & 31;
                b_q_count_next = b_q_count_next - 1;
            end
        end
        b_q_count = b_q_count_next;

        if (cpl_valid && cpl_ready) begin
            cpl_seen = 1'b1;
            cpl_error_seen = cpl_error;
            cpl_code_seen = cpl_error_code;
            if (!cpl_error && (expected_w_byte_offset != expected_total_len))
                fail("completion preceded all payload bytes");
            if ((expected_aw_bytes_left != 0) && !cpl_error)
                fail("completion preceded all AW plans");
        end
    end
end

// AXI and completion payloads must remain stable for the whole stall window.
always @(posedge clk) begin
    if (rstn && !soft_reset) begin
        if (aw_stalled_q && ({m_axi_awaddr, m_axi_awlen, m_axi_awsize, m_axi_awburst} !== aw_held_q))
            fail("AW payload changed while stalled");
        if (w_stalled_q && ({m_axi_wdata, m_axi_wstrb, m_axi_wlast} !== w_held_q))
            fail("W payload changed while stalled");
        if (cpl_stalled_q && ({cpl_error, cpl_error_code} !== cpl_held_q))
            fail("completion payload changed while stalled");
        aw_stalled_q <= m_axi_awvalid && !m_axi_awready;
        w_stalled_q <= m_axi_wvalid && !m_axi_wready;
        cpl_stalled_q <= cpl_valid && !cpl_ready;
        aw_held_q <= {m_axi_awaddr, m_axi_awlen, m_axi_awsize, m_axi_awburst};
        w_held_q <= {m_axi_wdata, m_axi_wstrb, m_axi_wlast};
        cpl_held_q <= {cpl_error, cpl_error_code};
    end
end

initial begin
    case_count = 0;
    clear_drivers();
    clear_scoreboard();
    apply_reset();

    $display("WIDE512_PHASE directed_lengths");
    run_frame(32'h0001_0000, 1,    1, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_1000, 7,    2, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_2000, 8,    3, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_3000, 31,   4, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_4000, 63,   5, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_5000, 64,   6, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_6000, 65,   7, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_7000, 127,  8, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_8000, 128,  9, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_9000, 255, 10, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_a000, 256, 11, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_b000, 511, 12, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_c000, 512, 13, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_d000, 1023, 14, 1'b0, ERR_NONE, 0);
    run_frame(32'h0001_e000, 1024, 15, 1'b0, ERR_NONE, 0);
    run_frame(32'h0002_0000, 2048, 16, 1'b0, ERR_NONE, 0);
    run_frame(32'h0002_1000, 4095, 17, 1'b0, ERR_NONE, 0);
    run_frame(32'h0002_3000, 4096, 18, 1'b0, ERR_NONE, 0);

    $display("WIDE512_PHASE boundary_and_errors");
    run_frame(32'h0003_0f80, 128, 21, 1'b0, ERR_NONE, 0);
    run_frame(32'h0003_0fc0, 65,  22, 1'b0, ERR_NONE, 0);
    run_frame(32'h0004_0000, 12288, 23, 1'b0, ERR_NONE, 0);
    run_frame(32'h0005_0004, 64, 24, 1'b1, ERR_UNALIGNED, 0);
    run_frame(32'h0005_1000, 65, 25, 1'b1, ERR_SOURCE_FORMAT, 1);

    prepare_case(32'h0006_0000, 4096, 26);
    inject_bresp_burst = 0;
    inject_bresp_value = 2'b10;
    issue_command(32'h0006_0000, 4096);
    drive_payload(4096, 26, 0);
    wait_completion(1'b1, ERR_AXI_SLVERR);

    prepare_case(32'h0007_0000, 4096, 27);
    inject_bresp_burst = 1;
    inject_bresp_value = 2'b11;
    issue_command(32'h0007_0000, 4096);
    drive_payload(4096, 27, 0);
    wait_completion(1'b1, ERR_AXI_DECERR);

    $display("WIDE512_PHASE randomized_backpressure");
    random_backpressure = 1'b1;
    for (random_source = 0; random_source < 2000; random_source = random_source + 1) begin
        random_len = ((random_source * 1103515245 + 12345) & 12'hfff) + 1;
        random_addr = 32'h0010_0000 + ((random_source & 8'hff) << 13);
        run_frame(random_addr[31:0], random_len, random_source + 31,
                  1'b0, ERR_NONE, 0);
    end
    random_backpressure = 1'b0;

    $display("WIDE512_PHASE max_outstanding");
    prepare_case(32'h0040_0000, 4096, 55);
    random_backpressure = 1'b1;
    issue_command(32'h0040_0000, 4096);
    drive_payload(4096, 55, 0);
    wait_completion(1'b0, ERR_NONE);
    if (peak_outstanding != MAX_OUTSTANDING)
        fail("maximum outstanding depth was not reached");
    random_backpressure = 1'b0;

    $display("WIDE512_PHASE soft_reset_restart");
    prepare_case(32'h0050_0000, 4096, 61);
    issue_command(32'h0050_0000, 4096);
    repeat (12) @(posedge clk);
    @(negedge clk);
    soft_reset = 1'b1;
    s_payload_tvalid = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    soft_reset = 1'b0;
    repeat (2) @(posedge clk);
    if (busy || m_axi_awvalid || m_axi_wvalid || cpl_valid)
        fail("soft reset did not clear writer state");
    run_frame(32'h0051_0000, 127, 62, 1'b0, ERR_NONE, 0);

    $display("WIDE512_PHASE throughput_1mib");
    prepare_case(32'h0100_0000, 1048576, 71);
    issue_command(32'h0100_0000, 1048576);
    drive_payload(1048576, 71, 0);
    wait_completion(1'b0, ERR_NONE);
    active_window = last_w_cycle - first_w_cycle + 1;
    utilization_x100 = (w_count * 10000) / active_window;
    $display("WIDE512_THROUGHPUT bytes=%0d aw_bursts=%0d w_beats=%0d w_active_cycles=%0d writer_busy_cycles=%0d utilization_pct_x100=%0d avg_burst_beats_x1000=%0d aw_stall_cycles=%0d w_stall_cycles=%0d bytes_per_cycle_x1000=%0d estimated_GBps_200MHz_x1000=%0d peak_outstanding=%0d",
             1048576, aw_count, w_count, active_window, active_cycle_count, utilization_x100,
             (w_count * 1000) / aw_count, aw_stall_cycle_count, w_stall_cycle_count,
             (1048576 * 1000) / active_window,
             (1048576 * 200) / active_window,
             peak_outstanding);
    if (utilization_x100 < 9500)
        fail("steady-state W utilization is below 95 percent");

    $display("PASS tb_rtl_rx_payload_writer_512 cases=%0d", case_count);
    $finish;
end

endmodule
