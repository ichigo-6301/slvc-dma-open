`timescale 1ns/1ps

module tb;

localparam integer INDEX_WIDTH = 12;
localparam integer MAX_OUTSTANDING = 4;
localparam integer RD_PIPE_DEPTH = 4;

reg clk = 1'b0;
reg rstn = 1'b0;
always #5 clk = ~clk;

reg             cmd_valid = 1'b0;
wire            cmd_ready;
reg      [31:0] cmd_addr = 32'h0;
reg      [31:0] cmd_len = 32'h0;
wire            done;
wire            error;
wire            rd_req;
wire [INDEX_WIDTH-1:0] rd_index;
reg             rd_valid = 1'b0;
reg      [63:0] rd_data = 64'h0;
wire [31:0]     m_axi_awaddr;
wire [7:0]      m_axi_awlen;
wire [2:0]      m_axi_awsize;
wire [1:0]      m_axi_awburst;
wire            m_axi_awvalid;
reg             m_axi_awready = 1'b1;
wire [63:0]     m_axi_wdata;
wire [7:0]      m_axi_wstrb;
wire            m_axi_wlast;
wire            m_axi_wvalid;
reg             m_axi_wready = 1'b1;
reg      [1:0]  m_axi_bresp = 2'b00;
reg             m_axi_bvalid = 1'b0;
wire            m_axi_bready;
wire            busy;

dma_axi_write_engine #(
    .INDEX_WIDTH(INDEX_WIDTH),
    .MAX_OUTSTANDING(MAX_OUTSTANDING)
) u_dut (
    .clk(clk),
    .rstn(rstn),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_addr(cmd_addr),
    .cmd_len(cmd_len),
    .done(done),
    .error(error),
    .rd_req(rd_req),
    .rd_index(rd_index),
    .rd_valid(rd_valid),
    .rd_data(rd_data),
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
    .busy(busy)
);

reg [INDEX_WIDTH-1:0] rd_pipe_index [0:RD_PIPE_DEPTH-1];
reg [RD_PIPE_DEPTH-1:0] rd_pipe_valid;
integer rd_latency = 1;
integer b_delay_cfg = 0;
integer b_delay_count = 0;
integer b_pending_count = 0;
integer aw_count = 0;
integer w_count = 0;
integer expected_w_index = 0;
integer current_w_run = 0;
integer max_w_run = 0;
integer rd_pipe_i;
integer cycle_count = 0;
integer b_pending_next;

task fail;
    input [255:0] msg;
    begin
        $display("Error: %0s", msg);
        $finish;
    end
endtask

function [63:0] data_for_index;
    input [INDEX_WIDTH-1:0] idx;
    begin
        data_for_index = {16'h23a1, {16-INDEX_WIDTH{1'b0}}, idx, 32'h5a5a_0000 | idx};
    end
endfunction

function [7:0] mask_for_bytes;
    input integer bytes;
    begin
        case (bytes)
        0: mask_for_bytes = 8'h00;
        1: mask_for_bytes = 8'h01;
        2: mask_for_bytes = 8'h03;
        3: mask_for_bytes = 8'h07;
        4: mask_for_bytes = 8'h0f;
        5: mask_for_bytes = 8'h1f;
        6: mask_for_bytes = 8'h3f;
        7: mask_for_bytes = 8'h7f;
        default: mask_for_bytes = 8'hff;
        endcase
    end
endfunction

task clear_bfm;
    integer i;
    begin
        cmd_valid = 1'b0;
        cmd_addr = 32'h0;
        cmd_len = 32'h0;
        rd_valid = 1'b0;
        rd_data = 64'h0;
        rd_pipe_valid = {RD_PIPE_DEPTH{1'b0}};
        m_axi_awready = 1'b1;
        m_axi_wready = 1'b1;
        m_axi_bresp = 2'b00;
        m_axi_bvalid = 1'b0;
        b_delay_cfg = 0;
        b_delay_count = 0;
        b_pending_count = 0;
        aw_count = 0;
        w_count = 0;
        expected_w_index = 0;
        current_w_run = 0;
        max_w_run = 0;
        cycle_count = 0;
        for (i = 0; i < RD_PIPE_DEPTH; i = i + 1)
            rd_pipe_index[i] = {INDEX_WIDTH{1'b0}};
    end
endtask

task apply_reset;
    begin
        @(negedge clk);
        rstn = 1'b0;
        clear_bfm();
        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);
    end
endtask

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        rd_valid <= 1'b0;
        rd_data <= 64'h0;
        rd_pipe_valid <= {RD_PIPE_DEPTH{1'b0}};
        m_axi_bvalid <= 1'b0;
        m_axi_bresp <= 2'b00;
        b_pending_count <= 0;
        b_delay_count <= 0;
    end else begin
        rd_valid <= rd_pipe_valid[rd_latency-1];
        rd_data <= data_for_index(rd_pipe_index[rd_latency-1]);
        for (rd_pipe_i = RD_PIPE_DEPTH-1; rd_pipe_i > 0; rd_pipe_i = rd_pipe_i - 1) begin
            rd_pipe_valid[rd_pipe_i] <= rd_pipe_valid[rd_pipe_i-1];
            rd_pipe_index[rd_pipe_i] <= rd_pipe_index[rd_pipe_i-1];
        end
        rd_pipe_valid[0] <= rd_req;
        rd_pipe_index[0] <= rd_index;

        b_pending_next = b_pending_count;
        if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
            b_pending_next = b_pending_next + 1;
        if (m_axi_bvalid && m_axi_bready) begin
            m_axi_bvalid <= 1'b0;
            m_axi_bresp <= 2'b00;
        end else if (!m_axi_bvalid && (b_pending_next != 0)) begin
            if (b_delay_count < b_delay_cfg) begin
                b_delay_count <= b_delay_count + 1;
            end else begin
                m_axi_bvalid <= 1'b1;
                m_axi_bresp <= 2'b00;
                b_pending_next = b_pending_next - 1;
                b_delay_count <= 0;
            end
        end
        b_pending_count <= b_pending_next;
    end
end

always @(posedge clk) begin
    if (rstn)
        cycle_count <= cycle_count + 1;

    if (rstn && m_axi_awvalid && m_axi_awready) begin
        if (m_axi_awsize !== 3'd3)
            fail("AWSIZE changed");
        if (m_axi_awburst !== 2'b01)
            fail("AWBURST changed");
        if (m_axi_awlen >= 8'd16)
            fail("AWLEN exceeds 16-word max burst");
        if ((m_axi_awaddr[11:0] + ((m_axi_awlen + 1'b1) << 3)) > 13'd4096)
            fail("AW burst crosses 4KB boundary");
        aw_count <= aw_count + 1;
    end

    if (rstn && m_axi_wvalid && m_axi_wready) begin
        if (m_axi_wdata !== data_for_index(expected_w_index[INDEX_WIDTH-1:0])) begin
            $display("Error: WDATA index %0d got %016x exp %016x",
                     expected_w_index, m_axi_wdata, data_for_index(expected_w_index[INDEX_WIDTH-1:0]));
            $finish;
        end
        expected_w_index <= expected_w_index + 1;
        w_count <= w_count + 1;
        current_w_run <= current_w_run + 1;
        if ((current_w_run + 1) > max_w_run)
            max_w_run <= current_w_run + 1;
    end else begin
        current_w_run <= 0;
    end
end

task start_cmd;
    input [31:0] addr;
    input [31:0] len_bytes;
    integer timeout;
    begin
        timeout = 0;
        @(negedge clk);
        cmd_addr = addr;
        cmd_len = len_bytes;
        cmd_valid = 1'b1;
        while (!cmd_ready) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout > 200)
                fail("cmd_ready timeout");
        end
        @(posedge clk);
        #1;
        cmd_valid = 1'b0;
    end
endtask

task wait_done_ok;
    integer timeout;
    begin : wait_ok
        timeout = 0;
        while (timeout < 20000) begin
            @(posedge clk);
            #1;
            if (done) begin
                if (error)
                    fail("unexpected error");
                disable wait_ok;
            end
            timeout = timeout + 1;
        end
        $display("Timeout state: busy=%0d active=%0d issue_left=%0d awvalid=%0d aw_plan=%0d burstq=%0d b_out=%0d pref_active=%0d pref_issue=%0d pref_return=%0d pref_out=%0d fifo=%0d out_en=%0d wvalid=%0d wlast=%0d pending_bursts=%0d",
                 busy,
                 u_dut.active,
                 u_dut.issue_bytes_left,
                 m_axi_awvalid,
                 u_dut.aw_plan_valid_q,
                 u_dut.burstq_count,
                 u_dut.b_outstanding_count,
                 u_dut.prefetch_active,
                 u_dut.prefetch_issue_count,
                 u_dut.prefetch_return_count,
                 u_dut.prefetch_rd_outstanding_count,
                 u_dut.w_fifo_count,
                 u_dut.prefetch_output_enabled,
                 m_axi_wvalid,
                 m_axi_wlast,
                 u_dut.w_pending_burst_count);
        fail("done timeout");
    end
endtask

task expect_counts;
    input integer exp_aw;
    input integer exp_w;
    begin
        if (aw_count != exp_aw) begin
            $display("Error: expected %0d AW got %0d", exp_aw, aw_count);
            $finish;
        end
        if (w_count != exp_w) begin
            $display("Error: expected %0d W got %0d", exp_w, w_count);
            $finish;
        end
    end
endtask

task print_case_summary;
    input [127:0] name;
    begin
        $display("E20A23_WRITER_SUMMARY case=%0s cycles=%0d w_count=%0d max_w_run=%0d w_fire_pct_x100=%0d",
                 name, cycle_count, w_count, max_w_run,
                 (cycle_count != 0) ? ((w_count * 10000) / cycle_count) : 0);
    end
endtask

initial begin
    clear_bfm();

    $display("E20A23_CASE T0 reset");
    apply_reset();
    if (m_axi_awvalid || m_axi_wvalid || done || error)
        fail("reset output not clean");

    $display("E20A23_CASE T1 exact_128_data_order");
    apply_reset();
    rd_latency = 1;
    start_cmd(32'h0000_1000, 32'd128);
    wait_done_ok();
    expect_counts(1, 16);
    print_case_summary("T1");
    if (max_w_run < 8)
        fail("prefetch did not create a sustained W run");

    $display("E20A23_CASE T2 long_multi_burst_data_order");
    apply_reset();
    rd_latency = 1;
    b_delay_cfg = 16;
    start_cmd(32'h0000_2000, 32'd1024);
    wait_done_ok();
    expect_counts(8, 128);
    print_case_summary("T2");
    if (max_w_run < 8)
        fail("long prefetch stream did not sustain a full payload block W run");

    $display("E20A23_CASE T3 wready_stall_fifo_fill");
    apply_reset();
    rd_latency = 1;
    m_axi_wready = 1'b0;
    start_cmd(32'h0000_3000, 32'd256);
    repeat (40) @(posedge clk);
    if (u_dut.w_fifo_count == 0)
        fail("prefetch FIFO did not fill during W stall");
    m_axi_wready = 1'b1;
    wait_done_ok();
    expect_counts(2, 32);
    print_case_summary("T3");

    $display("E20A23_CASE T4 rd_latency_2");
    apply_reset();
    rd_latency = 2;
    start_cmd(32'h0000_4000, 32'd256);
    wait_done_ok();
    expect_counts(2, 32);
    print_case_summary("T4");

    $display("E20A23_CASE T5 partial_tail");
    apply_reset();
    rd_latency = 1;
    start_cmd(32'h0000_5000, 32'd137);
    wait_done_ok();
    expect_counts(2, 18);
    print_case_summary("T5");

    $display("OK: dma RTL v33e20a23 W prefetch FIFO test passed.");
    $finish;
end

endmodule
