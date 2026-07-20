`timescale 1ns/1ps
`include "dma_defs.vh"
`include "dma_sim_def.vh"

module tb;

localparam integer MAX_CH = `DMA_MAX_CH;
localparam [3:0] CH0 = 4'd0;
localparam [3:0] CH1 = 4'd1;

localparam [3:0] ST_IDLE           = 4'd0;
localparam [3:0] ST_START_SETUP    = 4'd2;
localparam [3:0] ST_HEADER         = 4'd3;
localparam [3:0] ST_DONE           = 4'd8;
localparam [3:0] ST_DESC_PARSE     = 4'd11;
localparam [3:0] ST_DESC_HOLD      = 4'd12;
localparam [3:0] ST_CQ_CHECK_USED  = 4'd14;
localparam [3:0] ST_CQ_CHECK_SPACE = 4'd15;

reg clk = 1'b0;
reg rstn = 1'b0;
always #5 clk = ~clk;
reg [7:0] sys_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] ref_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] pkt_mem [0:`DMA_PKT_MEM_BYTES-1];

reg global_enable = 1'b0;
reg tx_enable = 1'b0;
reg quiesce = 1'b0;
reg soft_reset = 1'b0;
reg [MAX_CH*32-1:0] tx_ctrl_flat = {(MAX_CH*32){1'b0}};
reg [MAX_CH*32-1:0] tx_cfg_flat = {(MAX_CH*32){1'b0}};
reg [MAX_CH*32-1:0] tx_base_l_flat = {(MAX_CH*32){1'b0}};
reg [MAX_CH*32-1:0] tx_base_h_flat = {(MAX_CH*32){1'b0}};
reg [MAX_CH*32-1:0] tx_len_flat = {(MAX_CH*32){1'b0}};
reg [MAX_CH-1:0] tx_desc_enable_flat = {MAX_CH{1'b0}};
reg [MAX_CH-1:0] tx_desc_ready_flat = {MAX_CH{1'b0}};

wire       tx_desc_ctx_req;
wire [3:0] tx_desc_ctx_ch;
reg        tx_desc_ctx_valid = 1'b0;
reg [31:0] tx_desc_ctx_ctrl = 32'h0;
reg [31:0] tx_desc_ctx_base_l = 32'h0;
reg [31:0] tx_desc_ctx_base_h = 32'h0;
reg [31:0] tx_desc_ctx_size = 32'h0;
reg [31:0] tx_desc_ctx_rd_ptr = 32'h0;
reg [31:0] tx_desc_ctx_wr_ptr = 32'h0;
reg [31:0] tx_desc_ctx_status = 32'h0;
reg [31:0] tx_desc_ctx_err_cnt = 32'h0;
wire       tx_desc_active_valid;
wire [3:0] tx_desc_active_ch;
reg        tx_desc_active_stop = 1'b0;

reg [31:0] cq_size = 32'h0;
reg [31:0] cq_wr_ptr = 32'h0;
reg [31:0] cq_rd_ptr = 32'h0;
reg [31:0] cq_reserved_count = 32'h0;
wire       cq_reserve_inc;
wire       busy;
wire       drain_idle;
wire [MAX_CH-1:0] tx_ch_busy_flat;

wire       event_valid;
wire [3:0] event_ch;
wire [7:0] event_status_code;
wire       event_inc_frame;
wire       event_inc_err;
wire       event_clear_start;
wire       event_clear_stop;

wire       tx_desc_evt_valid;
wire [3:0] tx_desc_evt_ch;
wire [31:0] tx_desc_evt_rd_ptr;
wire       tx_desc_evt_update_rd_ptr;
wire [7:0] tx_desc_evt_status_code;
wire       tx_desc_evt_update_status;
wire       tx_desc_evt_inc_err;
wire       tx_desc_evt_clear_busy;
wire       tx_desc_evt_set_busy;

wire       cqe_req_valid;
reg        cqe_req_ready = 1'b1;
wire [3:0] cqe_ch;
wire [3:0] cqe_tc;
wire [3:0] cqe_policy;
wire [15:0] cqe_flow_id;
wire [15:0] cqe_msg_id;
wire [31:0] cqe_addr;
wire [31:0] cqe_len;
wire [31:0] cqe_aligned_len;
wire [31:0] cqe_frame_seq;
wire [7:0] cqe_status_code;
wire [15:0] cqe_flags;

wire [31:0] m_axi_araddr;
wire [7:0]  m_axi_arlen;
wire [2:0]  m_axi_arsize;
wire [1:0]  m_axi_arburst;
wire        m_axi_arvalid;
wire        m_axi_arready;
wire [63:0] m_axi_rdata;
wire [1:0]  m_axi_rresp;
wire        m_axi_rlast;
wire        m_axi_rvalid;
wire        m_axi_rready;
wire [511:0] tx_axis_tdata;
wire         tx_axis_tvalid;
reg          tx_axis_tready = 1'b1;

integer reserve_pulse_count = 0;
integer event_count = 0;
integer desc_evt_count = 0;
reg [7:0] last_event_code = 8'h0;
reg [3:0] last_event_ch = 4'h0;
reg       last_event_inc_err = 1'b0;
reg [7:0] last_desc_evt_code = 8'h0;
reg [3:0] last_desc_evt_ch = 4'h0;
reg [31:0] last_desc_evt_rd_ptr = 32'h0;
reg       last_desc_evt_inc_err = 1'b0;
reg       last_desc_evt_update_status = 1'b0;
reg       last_desc_evt_clear_busy_log = 1'b0;
reg [511:0] held_tx_data = 512'h0;
integer event_before = 0;
integer tx_wait_guard = 0;
integer soft_reset_pulse_count = 0;
integer soft_reset_pulse_before = 0;

axi64_slave_model u_mem (
    .aclk(clk),
    .arstn(rstn),
    .awaddr(32'h0),
    .awlen(8'h0),
    .awsize(3'h0),
    .awburst(2'h0),
    .awvalid(1'b0),
    .awready(),
    .wdata(64'h0),
    .wstrb(8'h0),
    .wlast(1'b0),
    .wvalid(1'b0),
    .wready(),
    .bresp(),
    .bvalid(),
    .bready(1'b0),
    .araddr(m_axi_araddr),
    .arlen(m_axi_arlen),
    .arsize(m_axi_arsize),
    .arburst(m_axi_arburst),
    .arvalid(m_axi_arvalid),
    .arready(m_axi_arready),
    .rdata(m_axi_rdata),
    .rresp(m_axi_rresp),
    .rlast(m_axi_rlast),
    .rvalid(m_axi_rvalid),
    .rready(m_axi_rready)
);

dma_tx_engine u_dut (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .quiesce(quiesce),
    .global_enable(global_enable),
    .tx_enable(tx_enable),
    .tx_ctrl_flat(tx_ctrl_flat),
    .tx_cfg_flat(tx_cfg_flat),
    .tx_base_l_flat(tx_base_l_flat),
    .tx_base_h_flat(tx_base_h_flat),
    .tx_len_flat(tx_len_flat),
    .tx_desc_enable_flat(tx_desc_enable_flat),
    .tx_desc_ready_flat(tx_desc_ready_flat),
    .tx_desc_ctx_req(tx_desc_ctx_req),
    .tx_desc_ctx_ch(tx_desc_ctx_ch),
    .tx_desc_ctx_valid(tx_desc_ctx_valid),
    .tx_desc_ctx_ctrl(tx_desc_ctx_ctrl),
    .tx_desc_ctx_base_l(tx_desc_ctx_base_l),
    .tx_desc_ctx_base_h(tx_desc_ctx_base_h),
    .tx_desc_ctx_size(tx_desc_ctx_size),
    .tx_desc_ctx_rd_ptr(tx_desc_ctx_rd_ptr),
    .tx_desc_ctx_wr_ptr(tx_desc_ctx_wr_ptr),
    .tx_desc_ctx_status(tx_desc_ctx_status),
    .tx_desc_ctx_err_cnt(tx_desc_ctx_err_cnt),
    .tx_desc_active_valid(tx_desc_active_valid),
    .tx_desc_active_ch(tx_desc_active_ch),
    .tx_desc_active_stop(tx_desc_active_stop),
    .cq_size(cq_size),
    .cq_wr_ptr(cq_wr_ptr),
    .cq_rd_ptr(cq_rd_ptr),
    .cq_reserved_count(cq_reserved_count),
    .cq_reserve_inc(cq_reserve_inc),
    .busy(busy),
    .drain_idle(drain_idle),
    .tx_ch_busy_flat(tx_ch_busy_flat),
    .event_valid(event_valid),
    .event_ch(event_ch),
    .event_status_code(event_status_code),
    .event_inc_frame(event_inc_frame),
    .event_inc_err(event_inc_err),
    .event_clear_start(event_clear_start),
    .event_clear_stop(event_clear_stop),
    .tx_desc_evt_valid(tx_desc_evt_valid),
    .tx_desc_evt_ch(tx_desc_evt_ch),
    .tx_desc_evt_rd_ptr(tx_desc_evt_rd_ptr),
    .tx_desc_evt_update_rd_ptr(tx_desc_evt_update_rd_ptr),
    .tx_desc_evt_status_code(tx_desc_evt_status_code),
    .tx_desc_evt_update_status(tx_desc_evt_update_status),
    .tx_desc_evt_inc_err(tx_desc_evt_inc_err),
    .tx_desc_evt_clear_busy(tx_desc_evt_clear_busy),
    .tx_desc_evt_set_busy(tx_desc_evt_set_busy),
    .cqe_req_valid(cqe_req_valid),
    .cqe_req_ready(cqe_req_ready),
    .cqe_ch(cqe_ch),
    .cqe_tc(cqe_tc),
    .cqe_policy(cqe_policy),
    .cqe_flow_id(cqe_flow_id),
    .cqe_msg_id(cqe_msg_id),
    .cqe_addr(cqe_addr),
    .cqe_len(cqe_len),
    .cqe_aligned_len(cqe_aligned_len),
    .cqe_frame_seq(cqe_frame_seq),
    .cqe_status_code(cqe_status_code),
    .cqe_flags(cqe_flags),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .tx_axis_tdata(tx_axis_tdata),
    .tx_axis_tvalid(tx_axis_tvalid),
    .tx_axis_tready(tx_axis_tready)
);

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        reserve_pulse_count <= 0;
        event_count <= 0;
        desc_evt_count <= 0;
        last_event_code <= 8'h0;
        last_event_ch <= 4'h0;
        last_event_inc_err <= 1'b0;
        last_desc_evt_code <= 8'h0;
        last_desc_evt_ch <= 4'h0;
        last_desc_evt_rd_ptr <= 32'h0;
        last_desc_evt_inc_err <= 1'b0;
        last_desc_evt_update_status <= 1'b0;
        last_desc_evt_clear_busy_log <= 1'b0;
        soft_reset_pulse_count <= 0;
    end else begin
        if (soft_reset)
            soft_reset_pulse_count <= soft_reset_pulse_count + 1;
        if (cq_reserve_inc)
            reserve_pulse_count <= reserve_pulse_count + 1;
        if (event_valid) begin
            event_count <= event_count + 1;
            last_event_code <= event_status_code;
            last_event_ch <= event_ch;
            last_event_inc_err <= event_inc_err;
        end
        if (tx_desc_evt_valid) begin
            desc_evt_count <= desc_evt_count + 1;
            last_desc_evt_code <= tx_desc_evt_status_code;
            last_desc_evt_ch <= tx_desc_evt_ch;
            last_desc_evt_rd_ptr <= tx_desc_evt_rd_ptr;
            last_desc_evt_inc_err <= tx_desc_evt_inc_err;
            last_desc_evt_update_status <= tx_desc_evt_update_status;
            last_desc_evt_clear_busy_log <= tx_desc_evt_clear_busy;
        end
    end
end

task fail;
    input [255:0] msg;
    begin
        $display("Error: %0s", msg);
        $finish;
    end
endtask

task expect_true;
    input cond;
    input [255:0] name;
    begin
        if (!cond)
            fail(name);
    end
endtask

task expect_eq32;
    input [31:0] got;
    input [31:0] exp;
    input [255:0] name;
    begin
        if (got !== exp) begin
            $display("Error: %0s expected %08x got %08x", name, exp, got);
            $finish;
        end
    end
endtask

task expect_eq8;
    input [7:0] got;
    input [7:0] exp;
    input [255:0] name;
    begin
        if (got !== exp) begin
            $display("Error: %0s expected %02x got %02x", name, exp, got);
            $finish;
        end
    end
endtask

task expect_eq4;
    input [3:0] got;
    input [3:0] exp;
    input [255:0] name;
    begin
        if (got !== exp) begin
            $display("Error: %0s expected %0d got %0d", name, exp, got);
            $finish;
        end
    end
endtask

task wait_cycles;
    input integer n;
    integer idx;
    begin
        for (idx = 0; idx < n; idx = idx + 1)
            @(posedge clk);
        #1;
    end
endtask

task wait_state;
    input [3:0] exp_state;
    input integer limit;
    integer timeout;
    begin
        timeout = 0;
        while ((u_dut.state != exp_state) && (timeout < limit)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= limit) begin
            $display("Error: timeout waiting state=%0d current=%0d", exp_state, u_dut.state);
            $finish;
        end
        #1;
    end
endtask

task wait_event_count;
    input integer exp_count;
    input integer limit;
    integer timeout;
    begin
        timeout = 0;
        while ((event_count < exp_count) && (timeout < limit)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= limit) begin
            $display("Error: timeout waiting event_count=%0d current=%0d", exp_count, event_count);
            $finish;
        end
    end
endtask

task wait_desc_evt_count;
    input integer exp_count;
    input integer limit;
    integer timeout;
    begin
        timeout = 0;
        while ((desc_evt_count < exp_count) && (timeout < limit)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= limit) begin
            $display("Error: timeout waiting desc_evt_count=%0d current=%0d", exp_count, desc_evt_count);
            $finish;
        end
    end
endtask

task clear_inputs;
    begin
        global_enable = 1'b0;
        tx_enable = 1'b0;
        quiesce = 1'b0;
        soft_reset = 1'b0;
        tx_ctrl_flat = {(MAX_CH*32){1'b0}};
        tx_cfg_flat = {(MAX_CH*32){1'b0}};
        tx_base_l_flat = {(MAX_CH*32){1'b0}};
        tx_base_h_flat = {(MAX_CH*32){1'b0}};
        tx_len_flat = {(MAX_CH*32){1'b0}};
        tx_desc_enable_flat = {MAX_CH{1'b0}};
        tx_desc_ready_flat = {MAX_CH{1'b0}};
        tx_desc_ctx_valid = 1'b0;
        tx_desc_ctx_ctrl = 32'h0;
        tx_desc_ctx_base_l = 32'h0;
        tx_desc_ctx_base_h = 32'h0;
        tx_desc_ctx_size = 32'h0;
        tx_desc_ctx_rd_ptr = 32'h0;
        tx_desc_ctx_wr_ptr = 32'h0;
        tx_desc_ctx_status = 32'h0;
        tx_desc_ctx_err_cnt = 32'h0;
        tx_desc_active_stop = 1'b0;
        cq_size = 32'h0;
        cq_wr_ptr = 32'h0;
        cq_rd_ptr = 32'h0;
        cq_reserved_count = 32'h0;
        cqe_req_ready = 1'b1;
        tx_axis_tready = 1'b1;
    end
endtask

task apply_reset;
    integer idx;
    begin
        rstn = 1'b0;
        clear_inputs();
        for (idx = 0; idx < `DMA_SIM_MEM_BYTES; idx = idx + 1)
            `DMA_SYS_MEM_PATH[idx] = 8'h0;
        wait_cycles(4);
        rstn = 1'b1;
        wait_cycles(2);
    end
endtask

task set_word;
    inout [MAX_CH*32-1:0] bus;
    input integer ch;
    input [31:0] val;
    begin
        bus[ch*32 +: 32] = val;
    end
endtask

task prep_start_setup;
    input [3:0] ch;
    input cpl;
    input [31:0] len_word;
    input [31:0] addr_word;
    input [31:0] cq_size_word;
    input [31:0] cq_wr_word;
    input [31:0] cq_rd_word;
    input [31:0] cq_reserved_word;
    begin
        @(negedge clk);
        tx_axis_tready = 1'b0;
        set_word(tx_ctrl_flat, ch, (32'h1 << `DMA_TX_CTRL_ENABLE));
        set_word(tx_len_flat, ch, len_word);
        cq_size = cq_size_word;
        cq_wr_ptr = cq_wr_word;
        cq_rd_ptr = cq_rd_word;
        cq_reserved_count = cq_reserved_word;
        u_dut.state = ST_START_SETUP;
        u_dut.active_ch = ch;
        u_dut.active_tc = `DMA_TC_FC;
        u_dut.active_policy = `DMA_TX_POL_SINGLE_SHOT;
        u_dut.active_tag = 16'h0123;
        u_dut.active_addr = addr_word;
        u_dut.active_len = len_word;
        u_dut.active_aligned_len = (len_word + 32'd63) & 32'hffff_ffc0;
        u_dut.remaining_bytes = len_word;
        u_dut.rd_addr = addr_word;
        u_dut.final_status = `DMA_ST_TX_DONE;
        u_dut.cpl_en = cpl;
        u_dut.desc_mode = 1'b0;
    end
endtask

task prep_desc_parse;
    input [3:0] ch;
    input cpl;
    input [31:0] len_word;
    input [31:0] addr_word;
    input [31:0] frame_seq_word;
    input [31:0] tx_len_limit_word;
    input [31:0] cq_size_word;
    input [31:0] cq_wr_word;
    input [31:0] cq_rd_word;
    input [31:0] cq_reserved_word;
    begin
        @(negedge clk);
        tx_axis_tready = 1'b0;
        set_word(tx_ctrl_flat, ch, (32'h1 << `DMA_TX_CTRL_ENABLE));
        set_word(tx_len_flat, ch, tx_len_limit_word);
        cq_size = cq_size_word;
        cq_wr_ptr = cq_wr_word;
        cq_rd_ptr = cq_rd_word;
        cq_reserved_count = cq_reserved_word;
        u_dut.state = ST_DESC_PARSE;
        u_dut.active_ch = ch;
        u_dut.desc_mode = 1'b1;
        u_dut.cpl_en = cpl;
        u_dut.frame_seq_counter = 32'h20;
        u_dut.final_status = `DMA_ST_OK;
        u_dut.active_desc_next_rd_ptr = 32'h80;
        u_dut.desc_buf = 512'h0;
        u_dut.desc_buf[`DMA_TX_DESC_OWNER_VALID] = 1'b1;
        u_dut.desc_buf[8*8 +: 16] = 16'h4567;
        u_dut.desc_buf[12*8 +: 32] = len_word;
        u_dut.desc_buf[16*8 +: 32] = addr_word;
        u_dut.desc_buf[20*8 +: 32] = 32'h0;
        u_dut.desc_buf[24*8 +: 32] = frame_seq_word;
        u_dut.desc_buf[28*8 +: 32] = 32'h89ab_cdef;
        u_dut.desc_buf[32*8 +: 32] = 32'h0123_4567;
        u_dut.desc_buf[36*8 +: 32] = 32'h55aa_3300;
        u_dut.desc_buf[130:128] = 3'h0;
    end
endtask

initial begin
    $display("E20A10_CASE T0 reset");
    apply_reset();
    expect_eq4(u_dut.state, ST_IDLE, "T0 idle state");
    expect_true(!u_dut.cq_check_consume_q, "T0 consume clear");
    expect_true(!u_dut.cq_space_ok_q, "T0 space ok clear");
    expect_eq32(u_dut.cq_used_entries_q, 32'h0, "T0 used clear");

    $display("E20A10_CASE T1 normal_cpl_space_ok");
    apply_reset();
    prep_start_setup(CH0, 1'b1, 32'd64, 32'h0000_2000, 32'd16, 32'd3, 32'd0, 32'd1);
    wait_state(ST_CQ_CHECK_USED, 10);
    expect_eq32(u_dut.cq_check_size_q, 32'd16, "T1 size snapshot");
    expect_eq32(u_dut.cq_check_wr_ptr_q, 32'd3, "T1 wr snapshot");
    expect_eq32(u_dut.cq_check_rd_ptr_q, 32'd0, "T1 rd snapshot");
    wait_state(ST_CQ_CHECK_SPACE, 10);
    expect_eq32(u_dut.cq_used_entries_q, 32'd3, "T1 used entries");
    wait_cycles(2);
    expect_eq4(u_dut.state, ST_HEADER, "T1 reaches header");
    wait_cycles(1);
    expect_true(u_dut.cq_space_ok_q, "T1 space ok");
    expect_eq32(reserve_pulse_count, 32'd1, "T1 reserve pulse once");

    $display("E20A10_CASE T2 normal_cpl_blocked");
    apply_reset();
    prep_start_setup(CH0, 1'b1, 32'd64, 32'h0000_2000, 32'd4, 32'd3, 32'd0, 32'd0);
    wait_state(ST_DONE, 12);
    expect_eq8(u_dut.final_status, `DMA_ST_TX_CQ_BLOCKED, "T2 final_status");
    expect_eq32(reserve_pulse_count, 32'd0, "T2 reserve suppressed");
    wait_event_count(1, 10);
    expect_eq8(last_event_code, `DMA_ST_TX_CQ_BLOCKED, "T2 event code");
    expect_true(last_event_inc_err, "T2 event inc err");

    $display("E20A10_CASE T3 desc_cpl_space_ok");
    apply_reset();
    prep_desc_parse(CH1, 1'b1, 32'd96, 32'h0000_3000, 32'h0000_0055, 32'd256, 32'd16, 32'd2, 32'd0, 32'd0);
    wait_state(ST_CQ_CHECK_USED, 10);
    expect_true(u_dut.cq_check_from_desc_q, "T3 from desc");
    wait_state(ST_CQ_CHECK_SPACE, 10);
    expect_eq32(u_dut.cq_used_entries_q, 32'd2, "T3 used entries");
    wait_cycles(2);
    expect_eq4(u_dut.state, ST_HEADER, "T3 reaches header");
    wait_cycles(1);
    expect_eq32(u_dut.frame_seq_counter, 32'h21, "T3 frame seq increment");
    expect_eq8(u_dut.final_status, `DMA_ST_TX_DONE, "T3 final status");
    expect_eq32(reserve_pulse_count, 32'd1, "T3 reserve pulse");

    $display("E20A10_CASE T4 desc_cpl_blocked");
    apply_reset();
    prep_desc_parse(CH1, 1'b1, 32'd96, 32'h0000_3000, 32'h0000_0077, 32'd256, 32'd4, 32'd3, 32'd0, 32'd0);
    wait_state(ST_DONE, 12);
    expect_eq32(u_dut.frame_seq_counter, 32'h20, "T4 frame seq held");
    expect_eq8(u_dut.final_status, `DMA_ST_TX_CQ_BLOCKED, "T4 blocked status");
    wait_desc_evt_count(1, 10);
    expect_eq8(last_desc_evt_code, `DMA_ST_TX_CQ_BLOCKED, "T4 desc event code");
    expect_eq4(last_desc_evt_ch, CH1, "T4 desc event ch");
    expect_true(last_desc_evt_inc_err, "T4 desc event inc err");
    expect_eq32(last_desc_evt_rd_ptr, 32'h80, "T4 desc rd ptr");

    $display("E20A10_CASE T5 no_cpl_bypass");
    apply_reset();
    prep_start_setup(CH0, 1'b0, 32'd64, 32'h0000_2000, 32'd16, 32'd3, 32'd0, 32'd0);
    wait_cycles(1);
    expect_eq4(u_dut.state, ST_HEADER, "T5 direct header");
    expect_eq32(reserve_pulse_count, 32'd0, "T5 no reserve");

    $display("E20A10_CASE T6 zero_len_preserve");
    apply_reset();
    prep_start_setup(CH0, 1'b1, 32'd0, 32'h0000_2000, 32'd16, 32'd3, 32'd0, 32'd0);
    wait_cycles(1);
    expect_eq4(u_dut.state, ST_HEADER, "T6 zero len header");
    expect_eq32(reserve_pulse_count, 32'd0, "T6 no reserve");

    $display("E20A10_CASE T7 wrap_used_entries");
    apply_reset();
    prep_start_setup(CH0, 1'b1, 32'd64, 32'h0000_2000, 32'd16, 32'd2, 32'd10, 32'd0);
    wait_state(ST_CQ_CHECK_SPACE, 10);
    expect_eq32(u_dut.cq_used_entries_q, 32'd8, "T7 wrap used");

    $display("E20A10_CASE T8 reserved_count_blocks");
    apply_reset();
    prep_start_setup(CH0, 1'b1, 32'd64, 32'h0000_2000, 32'd16, 32'd2, 32'd0, 32'd13);
    wait_state(ST_CQ_CHECK_SPACE, 10);
    wait_event_count(1, 12);
    expect_true(!u_dut.cq_space_ok_q, "T8 space not ok");
    expect_eq8(last_event_code, `DMA_ST_TX_CQ_BLOCKED, "T8 blocked event");
    expect_eq32(reserve_pulse_count, 32'd0, "T8 no reserve");

    $display("E20A10_CASE T9 pointer_snapshot");
    apply_reset();
    prep_start_setup(CH0, 1'b1, 32'd64, 32'h0000_2000, 32'd16, 32'd4, 32'd1, 32'd0);
    wait_state(ST_CQ_CHECK_USED, 10);
    cq_size = 32'd2;
    cq_wr_ptr = 32'd0;
    cq_rd_ptr = 32'd0;
    cq_reserved_count = 32'd1;
    expect_eq32(u_dut.cq_check_size_q, 32'd16, "T9 size held");
    expect_eq32(u_dut.cq_check_wr_ptr_q, 32'd4, "T9 wr held");
    expect_eq32(u_dut.cq_check_rd_ptr_q, 32'd1, "T9 rd held");
    wait_state(ST_CQ_CHECK_SPACE, 10);
    expect_eq32(u_dut.cq_used_entries_q, 32'd3, "T9 used from snapshot");
    wait_cycles(2);
    expect_eq4(u_dut.state, ST_HEADER, "T9 header from snapshot");
    wait_cycles(1);
    expect_eq32(reserve_pulse_count, 32'd1, "T9 reserve from snapshot");

    $display("E20A10_CASE T10 no_duplicate_reserve");
    apply_reset();
    prep_start_setup(CH0, 1'b1, 32'd64, 32'h0000_2000, 32'd16, 32'd3, 32'd0, 32'd0);
    wait_state(ST_HEADER, 12);
    wait_cycles(5);
    expect_eq32(reserve_pulse_count, 32'd1, "T10 reserve only once");

    $display("E20A10_CASE T11 descriptor_status_preserved");
    apply_reset();
    prep_desc_parse(CH1, 1'b1, 32'd96, 32'h0000_3000, 32'h0000_0099, 32'd256, 32'd16, 32'd1, 32'd0, 32'd0);
    wait_state(ST_HEADER, 12);
    expect_eq8(u_dut.final_status, `DMA_ST_TX_DONE, "T11 success status");
    expect_eq32(u_dut.active_frame_seq, 32'h0000_0099, "T11 active frame seq");

    $display("E20A10_CASE T12 tx_desc_fix_preserved_interface");
    apply_reset();
    prep_desc_parse(CH1, 1'b1, 32'd96, 32'h0000_3000, 32'h0000_00aa, 32'd256, 32'd4, 32'd3, 32'd0, 32'd0);
    wait_desc_evt_count(1, 16);
    expect_true(last_desc_evt_update_status, "T12 desc status update pulse");
    expect_true(last_desc_evt_clear_busy_log, "T12 desc clear busy pulse");
    expect_true(last_desc_evt_inc_err, "T12 desc inc err pulse");

    $display("E20A10_CASE T13 quiesce_cancels_pending_start_and_descriptor");
    apply_reset();
    @(negedge clk);
    global_enable = 1'b1;
    tx_enable = 1'b1;
    set_word(tx_ctrl_flat, CH0,
             (32'h1 << `DMA_TX_CTRL_ENABLE) |
             (32'h1 << `DMA_TX_CTRL_START));
    tx_desc_enable_flat[CH1] = 1'b1;
    tx_desc_ready_flat[CH1] = 1'b1;
    @(posedge clk);
    @(negedge clk);
    quiesce = 1'b1;
    wait_cycles(4);
    expect_eq4(u_dut.state, ST_IDLE, "T13 state remains idle");
    expect_true(drain_idle, "T13 scheduler drain idle");
    expect_true(!tx_desc_ctx_req, "T13 descriptor launch suppressed");
    expect_true(!tx_axis_tvalid, "T13 TX frame launch suppressed");
    expect_true(!u_dut.tx_sched_req_valid_q &&
                !u_dut.tx_sched_grant_valid_q &&
                !u_dut.tx_sched_meta_valid_q,
                "T13 pending scheduler pipeline cleared");

    $display("E20A10_CASE T14 quiesce_drains_active_tx_and_blocks_next_descriptor");
    apply_reset();
    event_before = event_count;
    prep_start_setup(CH0, 1'b0, 32'd64, 32'h0000_2400,
                     32'd0, 32'd0, 32'd0, 32'd0);
    tx_wait_guard = 0;
    while (!tx_axis_tvalid && (tx_wait_guard < 200)) begin
        @(posedge clk);
        tx_wait_guard = tx_wait_guard + 1;
    end
    if (tx_wait_guard >= 200) begin
        $display("Error: T14 TX launch timeout state=%0d req=%0d grant=%0d meta=%0d arvalid=%0d rvalid=%0d",
                 u_dut.state, u_dut.tx_sched_req_valid_q,
                 u_dut.tx_sched_grant_valid_q, u_dut.tx_sched_meta_valid_q,
                 m_axi_arvalid, m_axi_rvalid);
        $finish;
    end
    held_tx_data = tx_axis_tdata;
    @(negedge clk);
    quiesce = 1'b1;
    tx_desc_enable_flat[CH1] = 1'b1;
    tx_desc_ready_flat[CH1] = 1'b1;
    repeat (4) begin
        @(posedge clk);
        #1;
        expect_true(tx_axis_tvalid, "T14 active TX valid held during stall");
        expect_true(tx_axis_tdata === held_tx_data,
                    "T14 active TX data stable during stall");
        expect_true(!drain_idle, "T14 active TX keeps drain busy");
        expect_true(!tx_desc_ctx_req,
                    "T14 next descriptor remains blocked while quiescing");
    end
    @(negedge clk);
    tx_axis_tready = 1'b1;
    wait_event_count(event_before + 1, 200);
    wait_state(ST_IDLE, 40);
    wait_cycles(3);
    expect_true(drain_idle, "T14 drain idle after accepted TX completes");
    expect_eq32(event_count, event_before + 1,
                "T14 exactly one accepted TX completion");
    expect_true(!tx_desc_ctx_req,
                "T14 descriptor launch remains suppressed after drain");

    soft_reset_pulse_before = soft_reset_pulse_count;
    @(negedge clk);
    soft_reset = 1'b1;
    @(negedge clk);
    soft_reset = 1'b0;
    wait_cycles(3);
    expect_eq32(soft_reset_pulse_count, soft_reset_pulse_before + 1,
                "T14 exactly one local soft reset");
    expect_eq4(u_dut.state, ST_IDLE, "T14 soft reset returns idle");
    expect_true(drain_idle, "T14 remains drain idle after soft reset");
    repeat (6) begin
        @(posedge clk);
        #1;
        expect_true(!tx_desc_ctx_req,
                    "T14 sustained descriptor demand remains suppressed");
    end

    @(negedge clk);
    tx_desc_enable_flat[CH1] = 1'b0;
    tx_desc_ready_flat[CH1] = 1'b0;
    quiesce = 1'b0;
    event_before = event_count;
    prep_start_setup(CH0, 1'b0, 32'd64, 32'h0000_2800,
                     32'd0, 32'd0, 32'd0, 32'd0);
    tx_wait_guard = 0;
    while (!tx_axis_tvalid && (tx_wait_guard < 200)) begin
        @(posedge clk);
        tx_wait_guard = tx_wait_guard + 1;
    end
    if (tx_wait_guard >= 200)
        fail("T14 clean restart TX launch timeout");
    @(negedge clk);
    tx_axis_tready = 1'b1;
    wait_event_count(event_before + 1, 200);
    wait_state(ST_IDLE, 40);
    expect_eq32(event_count, event_before + 1,
                "T14 clean restart completion");

    $display("PASS tb_rtl_v33e20a10_tx_cq_space_check_pipeline");
    $finish;
end

endmodule
