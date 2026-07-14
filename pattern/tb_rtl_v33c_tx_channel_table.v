`timescale 1ns/1ps
`include "dma_defs.vh"

module tb;
reg clk = 1'b0;
reg rstn = 1'b0;
always #5 clk = ~clk;

reg         csr_wr_valid = 1'b0;
wire        csr_wr_ready;
reg [3:0]   csr_wr_ch = 4'h0;
reg [5:0]   csr_wr_off = 6'h0;
reg [31:0]  csr_wdata = 32'h0;
reg [3:0]   csr_wstrb = 4'hf;
wire [1:0]  csr_bresp;
wire        csr_wr_rsp_valid;
wire [1:0]  csr_wr_rsp_kind;
wire [7:0]  csr_wr_rsp_code;
wire        csr_global_err;
wire        csr_policy_irq;
reg         csr_rd_valid = 1'b0;
wire        csr_rd_ready;
reg [3:0]   csr_rd_ch = 4'h0;
reg [5:0]   csr_rd_off = 6'h0;
wire        csr_rvalid;
wire [31:0] csr_rdata;
wire [1:0]  csr_rresp;

reg         tx_event_valid = 1'b0;
reg [3:0]   tx_event_ch = 4'h0;
reg [7:0]   tx_event_status_code = 8'h0;
reg         tx_event_inc_frame = 1'b0;
reg         tx_event_inc_err = 1'b0;
reg         tx_event_clear_start = 1'b0;
reg         tx_event_clear_stop = 1'b0;
reg [`DMA_MAX_CH-1:0] tx_ch_busy_flat = {`DMA_MAX_CH{1'b0}};
reg [`DMA_MAX_CH-1:0] tx_desc_enable_flat = {`DMA_MAX_CH{1'b0}};
reg         global_soft_reset = 1'b0;

wire        irq_tx_completion;
wire        irq_axi_error;
wire [`DMA_MAX_CH*32-1:0] tx_ctrl_flat;
wire [`DMA_MAX_CH*32-1:0] tx_cfg_flat;
wire [`DMA_MAX_CH*32-1:0] tx_base_l_flat;
wire [`DMA_MAX_CH*32-1:0] tx_base_h_flat;
wire [`DMA_MAX_CH*32-1:0] tx_len_flat;
wire [`DMA_MAX_CH*32-1:0] tx_status_flat;
wire [`DMA_MAX_CH*32-1:0] tx_user_flat;

localparam [3:0] CH0 = 4'd0;
localparam [3:0] CH1 = 4'd1;
localparam [5:0] TX_CTRL_OFF      = `DMA_CH_CTRL;
localparam [5:0] TX_CFG_OFF       = `DMA_CH_CFG;
localparam [5:0] TX_BASE_L_OFF    = `DMA_CH_BASE_L;
localparam [5:0] TX_BASE_H_OFF    = `DMA_CH_BASE_H;
localparam [5:0] TX_LEN_OFF       = `DMA_TX_CH_LEN;
localparam [5:0] TX_STATUS_OFF    = `DMA_CH_STATUS;
localparam [5:0] TX_FRAME_CNT_OFF = `DMA_CH_FRAME_CNT;
localparam [5:0] TX_ERR_CNT_OFF   = `DMA_CH_ERR_CNT;
localparam [5:0] TX_USER_OFF      = `DMA_CH_USER;
localparam [1:0] CSR_WR_RSP_NONE    = 2'd0;
localparam [1:0] CSR_WR_RSP_PROTECT = 2'd1;

reg [31:0] rd;
reg [31:0] ctrl_run;
reg [31:0] err_before_ch0;
reg [31:0] err_before_ch1;

dma_tx_channel_table u_dut(
    .clk(clk),
    .rstn(rstn),
    .global_soft_reset(global_soft_reset),
    .csr_wr_valid(csr_wr_valid),
    .csr_wr_ready(csr_wr_ready),
    .csr_wr_ch(csr_wr_ch),
    .csr_wr_off(csr_wr_off),
    .csr_wdata(csr_wdata),
    .csr_wstrb(csr_wstrb),
    .csr_bresp(csr_bresp),
    .csr_wr_rsp_valid(csr_wr_rsp_valid),
    .csr_wr_rsp_kind(csr_wr_rsp_kind),
    .csr_wr_rsp_code(csr_wr_rsp_code),
    .csr_global_err(csr_global_err),
    .csr_policy_irq(csr_policy_irq),
    .csr_rd_valid(csr_rd_valid),
    .csr_rd_ready(csr_rd_ready),
    .csr_rd_ch(csr_rd_ch),
    .csr_rd_off(csr_rd_off),
    .csr_rvalid(csr_rvalid),
    .csr_rdata(csr_rdata),
    .csr_rresp(csr_rresp),
    .tx_event_valid(tx_event_valid),
    .tx_event_ch(tx_event_ch),
    .tx_event_status_code(tx_event_status_code),
    .tx_event_inc_frame(tx_event_inc_frame),
    .tx_event_inc_err(tx_event_inc_err),
    .tx_event_clear_start(tx_event_clear_start),
    .tx_event_clear_stop(tx_event_clear_stop),
    .tx_ch_busy_flat(tx_ch_busy_flat),
    .tx_desc_enable_flat(tx_desc_enable_flat),
    .irq_tx_completion(irq_tx_completion),
    .irq_axi_error(irq_axi_error),
    .tx_ctrl_flat(tx_ctrl_flat),
    .tx_cfg_flat(tx_cfg_flat),
    .tx_base_l_flat(tx_base_l_flat),
    .tx_base_h_flat(tx_base_h_flat),
    .tx_len_flat(tx_len_flat),
    .tx_status_flat(tx_status_flat),
    .tx_user_flat(tx_user_flat)
);

task fail;
    input [255:0] msg;
    begin
        $display("Error: %0s", msg);
        $finish;
    end
endtask

task expect_eq;
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

task expect_bit;
    input [31:0] word;
    input integer bit_idx;
    input bit_exp;
    input [255:0] name;
    begin
        if (word[bit_idx] !== bit_exp) begin
            $display("Error: %0s bit %0d expected %0d got %0d word=%08x",
                     name, bit_idx, bit_exp, word[bit_idx], word);
            $finish;
        end
    end
endtask

task csr_write;
    input [3:0] ch;
    input [5:0] off;
    input [31:0] data;
    input [1:0] exp_kind;
    input [7:0] exp_code;
    input exp_global_err;
    input exp_policy_irq;
    input [255:0] name;
    begin
        @(posedge clk);
        csr_wr_ch <= ch;
        csr_wr_off <= off;
        csr_wdata <= data;
        csr_wstrb <= 4'hf;
        csr_wr_valid <= 1'b1;
        @(posedge clk);
        csr_wr_valid <= 1'b0;
        @(negedge clk);
        if (!csr_wr_rsp_valid) begin
            $display("Error: %0s missing CSR write response", name);
            $finish;
        end
        if (csr_wr_rsp_kind !== exp_kind) begin
            $display("Error: %0s response kind expected %0d got %0d", name, exp_kind, csr_wr_rsp_kind);
            $finish;
        end
        if (csr_wr_rsp_code !== exp_code) begin
            $display("Error: %0s response code expected %02x got %02x", name, exp_code, csr_wr_rsp_code);
            $finish;
        end
        if (csr_global_err !== exp_global_err) begin
            $display("Error: %0s global_err expected %0d got %0d", name, exp_global_err, csr_global_err);
            $finish;
        end
        if (csr_policy_irq !== exp_policy_irq) begin
            $display("Error: %0s policy_irq expected %0d got %0d", name, exp_policy_irq, csr_policy_irq);
            $finish;
        end
    end
endtask

task csr_read;
    input [3:0] ch;
    input [5:0] off;
    output [31:0] data;
    begin
        @(posedge clk);
        csr_rd_ch <= ch;
        csr_rd_off <= off;
        csr_rd_valid <= 1'b1;
        @(posedge clk);
        csr_rd_valid <= 1'b0;
        @(negedge clk);
        if (!csr_rvalid)
            fail("missing CSR read response");
        data = csr_rdata;
    end
endtask

task post_event;
    input [3:0] ch;
    input [7:0] code;
    input inc_frame;
    input inc_err;
    input clear_start;
    input clear_stop;
    begin
        @(posedge clk);
        tx_event_ch <= ch;
        tx_event_status_code <= code;
        tx_event_inc_frame <= inc_frame;
        tx_event_inc_err <= inc_err;
        tx_event_clear_start <= clear_start;
        tx_event_clear_stop <= clear_stop;
        tx_event_valid <= 1'b1;
        @(posedge clk);
        #1;
        tx_event_valid <= 1'b0;
        tx_event_inc_frame <= 1'b0;
        tx_event_inc_err <= 1'b0;
        tx_event_clear_start <= 1'b0;
        tx_event_clear_stop <= 1'b0;
    end
endtask

task csr_write_with_event;
    input [3:0] csr_ch;
    input [5:0] off;
    input [31:0] data;
    input [1:0] exp_kind;
    input [7:0] exp_code;
    input exp_global_err;
    input exp_policy_irq;
    input [3:0] evt_ch;
    input [7:0] evt_code;
    input evt_inc_frame;
    input evt_inc_err;
    input [255:0] name;
    begin
        @(posedge clk);
        csr_wr_ch <= csr_ch;
        csr_wr_off <= off;
        csr_wdata <= data;
        csr_wstrb <= 4'hf;
        csr_wr_valid <= 1'b1;
        tx_event_ch <= evt_ch;
        tx_event_status_code <= evt_code;
        tx_event_inc_frame <= evt_inc_frame;
        tx_event_inc_err <= evt_inc_err;
        tx_event_clear_start <= 1'b0;
        tx_event_clear_stop <= 1'b0;
        tx_event_valid <= 1'b1;
        @(posedge clk);
        csr_wr_valid <= 1'b0;
        tx_event_valid <= 1'b0;
        tx_event_inc_frame <= 1'b0;
        tx_event_inc_err <= 1'b0;
        @(negedge clk);
        if (!csr_wr_rsp_valid)
            fail("missing simultaneous CSR write response");
        if (csr_wr_rsp_kind !== exp_kind) begin
            $display("Error: %0s response kind expected %0d got %0d", name, exp_kind, csr_wr_rsp_kind);
            $finish;
        end
        if (csr_wr_rsp_code !== exp_code) begin
            $display("Error: %0s response code expected %02x got %02x", name, exp_code, csr_wr_rsp_code);
            $finish;
        end
        if (csr_global_err !== exp_global_err)
            fail("simultaneous CSR global_err mismatch");
        if (csr_policy_irq !== exp_policy_irq)
            fail("simultaneous CSR policy_irq mismatch");
    end
endtask

initial begin
    ctrl_run = (32'h1 << `DMA_TX_CTRL_ENABLE) |
               (32'h1 << `DMA_TX_CTRL_CPL_EN) |
               (32'h1 << `DMA_TX_CTRL_IRQ_EN);

    repeat (4) @(posedge clk);
    rstn = 1'b1;
    repeat (2) @(posedge clk);

    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_eq(rd, 32'h1, "reset TX_STATUS");

    csr_write(CH0, TX_CFG_OFF, 32'h1234_0056, CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_CFG");
    csr_write(CH0, TX_BASE_L_OFF, 32'h0000_4000, CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_BASE_L");
    csr_write(CH0, TX_BASE_H_OFF, 32'h0000_0000, CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_BASE_H");
    csr_write(CH0, TX_LEN_OFF, 32'd256, CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_LEN");
    csr_write(CH0, TX_USER_OFF, 32'hcafe_beef, CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_USER");

    csr_read(CH0, TX_CFG_OFF, rd);
    expect_eq(rd, 32'h1234_0056, "TX_CFG readback");
    csr_read(CH0, TX_BASE_L_OFF, rd);
    expect_eq(rd, 32'h0000_4000, "TX_BASE_L readback");
    csr_read(CH0, TX_LEN_OFF, rd);
    expect_eq(rd, 32'd256, "TX_LEN readback");
    csr_read(CH0, TX_USER_OFF, rd);
    expect_eq(rd, 32'hcafe_beef, "TX_USER readback");

    csr_write(CH0, TX_CTRL_OFF, ctrl_run | (32'h1 << `DMA_TX_CTRL_START),
              CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_CTRL START");
    csr_read(CH0, TX_CTRL_OFF, rd);
    expect_bit(rd, `DMA_TX_CTRL_ENABLE, 1'b1, "ENABLE set");
    expect_bit(rd, `DMA_TX_CTRL_START, 1'b1, "START set");

    csr_write(CH0, TX_CFG_OFF, 32'hdead_beef, CSR_WR_RSP_PROTECT,
              `DMA_ST_CFG_PROTECT_ERR, 1'b1, 1'b1, "protected TX_CFG");
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_ERR_CNT_OFF, rd);
    expect_eq(rd, 32'd1, "protect increments TX_ERR_CNT");
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_eq(rd[23:16], `DMA_ST_CFG_PROTECT_ERR, "protect status code");

    post_event(CH0, `DMA_ST_TX_DONE, 1'b1, 1'b0, 1'b1, 1'b0);
    if (!irq_tx_completion)
        fail("DONE event did not pulse TX completion IRQ");
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_CTRL_OFF, rd);
    expect_bit(rd, `DMA_TX_CTRL_START, 1'b0, "START cleared by event");
    csr_read(CH0, TX_FRAME_CNT_OFF, rd);
    expect_eq(rd, 32'd1, "TX_FRAME_CNT increment");
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_bit(rd, `DMA_TX_STATUS_DONE, 1'b1, "DONE sticky bit");

    csr_write(CH0, TX_CTRL_OFF, ctrl_run | (32'h1 << `DMA_TX_CTRL_STOP),
              CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_CTRL STOP");
    csr_read(CH0, TX_CTRL_OFF, rd);
    expect_bit(rd, `DMA_TX_CTRL_STOP, 1'b1, "STOP set");
    post_event(CH0, `DMA_ST_TX_STOPPED, 1'b0, 1'b1, 1'b0, 1'b1);
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_CTRL_OFF, rd);
    expect_bit(rd, `DMA_TX_CTRL_STOP, 1'b0, "STOP cleared by event");
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_bit(rd, `DMA_TX_STATUS_ABORTED, 1'b1, "STOPPED sets aborted");

    post_event(CH0, `DMA_ST_AXI_READ_ERR, 1'b0, 1'b1, 1'b0, 1'b0);
    if (!irq_axi_error)
        fail("AXI_READ_ERR event did not pulse AXI error IRQ");
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_bit(rd, `DMA_TX_STATUS_READ_ERR, 1'b1, "READ_ERR sticky bit");

    post_event(CH0, `DMA_ST_TX_UNDERFLOW, 1'b0, 1'b1, 1'b0, 1'b0);
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_bit(rd, `DMA_TX_STATUS_UNDERFLOW, 1'b1, "UNDERFLOW sticky bit");

    post_event(CH0, `DMA_ST_TX_CQ_BLOCKED, 1'b0, 1'b1, 1'b0, 1'b0);
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_bit(rd, `DMA_TX_STATUS_CQ_BLOCKED, 1'b1, "CQ_BLOCKED sticky bit");
    expect_eq(rd[31:24], {4'h0, CH0}, "status channel id bits");

    tx_ch_busy_flat[CH0] = 1'b1;
    repeat (3) @(posedge clk);
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_bit(rd, `DMA_TX_STATUS_BUSY, 1'b1, "busy mirror set");
    expect_bit(rd, `DMA_TX_STATUS_IDLE, 1'b0, "idle mirror clear");
    tx_ch_busy_flat[CH0] = 1'b0;
    repeat (3) @(posedge clk);
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_bit(rd, `DMA_TX_STATUS_BUSY, 1'b0, "busy mirror clear");
    expect_bit(rd, `DMA_TX_STATUS_IDLE, 1'b1, "idle mirror set");

    csr_write(CH0, TX_CTRL_OFF, (32'h1 << `DMA_TX_CTRL_CLR_STAT),
              CSR_WR_RSP_NONE, 8'h00, 1'b0, 1'b0, "write TX_CTRL CLR_STAT");
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_eq(rd[23:16], 8'h00, "CLR_STAT clears code bits");

    tx_desc_enable_flat[CH1] = 1'b1;
    csr_write(CH1, TX_CTRL_OFF,
              (32'h1 << `DMA_TX_CTRL_ENABLE) | (32'h1 << `DMA_TX_CTRL_START),
              CSR_WR_RSP_PROTECT, `DMA_ST_UNSUPPORTED_FEATURE, 1'b1, 1'b1,
              "descriptor-enabled START");
    repeat (2) @(posedge clk);
    csr_read(CH1, TX_STATUS_OFF, rd);
    expect_eq(rd[23:16], `DMA_ST_UNSUPPORTED_FEATURE, "descriptor START rejection status");
    tx_desc_enable_flat[CH1] = 1'b0;

    csr_read(CH1, TX_ERR_CNT_OFF, err_before_ch1);
    csr_write_with_event(CH1, TX_CFG_OFF, 32'hfeed_0001,
                         CSR_WR_RSP_PROTECT, `DMA_ST_CFG_PROTECT_ERR, 1'b1, 1'b1,
                         CH1, `DMA_ST_AXI_READ_ERR, 1'b0, 1'b1,
                         "same-channel CSR protect plus TX event");
    repeat (4) @(posedge clk);
    csr_read(CH1, TX_ERR_CNT_OFF, rd);
    expect_eq(rd, err_before_ch1 + 32'd2, "same-channel counter accumulates +2");

    csr_read(CH0, TX_ERR_CNT_OFF, err_before_ch0);
    csr_read(CH1, TX_ERR_CNT_OFF, err_before_ch1);
    csr_write_with_event(CH0, TX_CFG_OFF, 32'hfeed_0002,
                         CSR_WR_RSP_PROTECT, `DMA_ST_CFG_PROTECT_ERR, 1'b1, 1'b1,
                         CH1, `DMA_ST_TX_UNDERFLOW, 1'b0, 1'b1,
                         "cross-channel CSR protect plus TX event");
    repeat (4) @(posedge clk);
    csr_read(CH0, TX_ERR_CNT_OFF, rd);
    expect_eq(rd, err_before_ch0 + 32'd1, "cross-channel CSR counter increments CH0");
    csr_read(CH1, TX_ERR_CNT_OFF, rd);
    expect_eq(rd, err_before_ch1 + 32'd1, "cross-channel event counter increments CH1");

    @(posedge clk);
    global_soft_reset <= 1'b1;
    @(posedge clk);
    global_soft_reset <= 1'b0;
    repeat (2) @(posedge clk);
    csr_read(CH0, TX_CTRL_OFF, rd);
    expect_eq(rd, 32'h0, "soft reset clears TX_CTRL");
    csr_read(CH0, TX_STATUS_OFF, rd);
    expect_eq(rd, 32'h1, "soft reset restores TX_STATUS");
    csr_read(CH0, TX_FRAME_CNT_OFF, rd);
    expect_eq(rd, 32'h0, "soft reset clears TX_FRAME_CNT");
    csr_read(CH0, TX_ERR_CNT_OFF, rd);
    expect_eq(rd, 32'h0, "soft reset clears TX_ERR_CNT");

    $display("PASS: v33c TX channel table ownership split directed test");
    $finish;
end

endmodule
