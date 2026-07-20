`timescale 1ns/1ps
`include "dma_defs.vh"

module tb;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    always #5 clk = ~clk;

    reg  [31:0] awaddr = 32'h0;
    reg         awvalid = 1'b0;
    wire        awready;
    reg  [31:0] wdata = 32'h0;
    reg  [3:0]  wstrb = 4'hf;
    reg         wvalid = 1'b0;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready = 1'b0;
    reg  [31:0] araddr = 32'h0;
    reg         arvalid = 1'b0;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready = 1'b0;

    reg core_busy = 1'b0;
    reg axi_busy = 1'b0;
    reg cdc_protocol_error = 1'b0;
    reg event_valid = 1'b0;
    reg event_ch_valid = 1'b0;
    reg [3:0] event_ch = 4'h0;
    reg [7:0] event_status_code = 8'h0;
    reg [31:0] event_aligned_len = 32'h0;
    reg [31:0] event_next_wr_ptr = 32'h0;
    reg event_inc_frame = 1'b0;
    reg event_inc_drop = 1'b0;
    reg event_inc_err = 1'b0;
    reg event_update_wr_ptr = 1'b0;
    reg [15:0] event_irq_mask = 16'h0;
    reg event_global_header_err = 1'b0;
    reg fc_status_valid = 1'b0;
    reg [3:0] fc_status_ch = 4'h0;
    reg fc_status_pause = 1'b0;
    reg fc_status_low = 1'b0;
    reg fc_status_full = 1'b0;
    reg fc_status_afull = 1'b0;
    reg fc_status_ovf = 1'b0;
    reg cq_commit_valid = 1'b0;
    reg [31:0] cq_next_ptr = 32'h0;
    reg [`DMA_MAX_CH-1:0] rx_ch_busy_flat = {`DMA_MAX_CH{1'b0}};
    reg [`DMA_MAX_CH-1:0] tx_ch_busy_flat = {`DMA_MAX_CH{1'b0}};
    reg tx_event_valid = 1'b0;
    reg [3:0] tx_event_ch = 4'h0;
    reg [7:0] tx_event_status_code = 8'h0;
    reg tx_event_inc_frame = 1'b0;
    reg tx_event_inc_err = 1'b0;
    reg tx_event_clear_start = 1'b0;
    reg tx_event_clear_stop = 1'b0;
    reg ufc_tx_busy = 1'b0;
    reg ufc_tx_done = 1'b0;
    reg ufc_tx_busy_reject = 1'b0;
    reg ufc_tx_done_event = 1'b0;
    reg ufc_rx_pending = 1'b0;
    reg ufc_rx_overrun = 1'b0;
    reg [7:0] ufc_rx_opcode = 8'h0;
    reg [15:0] ufc_rx_flow_id = 16'h0;
    reg [31:0] ufc_rx_arg0 = 32'h0;
    reg [31:0] ufc_rx_arg1 = 32'h0;
    reg ufc_rx_msg_event = 1'b0;

    wire global_enable;
    wire rx_enable;
    wire tx_enable;
    wire irq_enable;
    wire [31:0] cq_base_l;
    wire [31:0] cq_base_h;
    wire [31:0] cq_size;
    wire [31:0] cq_wr_ptr;
    wire [31:0] cq_rd_ptr;
    wire [`DMA_MAX_CH*32-1:0] rx_ctrl_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_cfg_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_base_l_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_base_h_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_size_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_max_len_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_wr_ptr_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_rd_ptr_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_used_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_high_wm_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_low_wm_flat;
    wire [`DMA_MAX_CH*32-1:0] rx_user_flat;
    wire [`DMA_MAX_CH*32-1:0] tx_ctrl_flat;
    wire [`DMA_MAX_CH*32-1:0] tx_cfg_flat;
    wire [`DMA_MAX_CH*32-1:0] tx_base_l_flat;
    wire [`DMA_MAX_CH*32-1:0] tx_base_h_flat;
    wire [`DMA_MAX_CH*32-1:0] tx_len_flat;
    wire [`DMA_MAX_CH*32-1:0] tx_status_flat;
    wire [`DMA_MAX_CH*32-1:0] tx_user_flat;
    wire ufc_enable;
    wire ufc_tx_start;
    wire [7:0] ufc_tx_opcode_cfg;
    wire [15:0] ufc_tx_flow_id_cfg;
    wire [31:0] ufc_tx_arg0_cfg;
    wire [31:0] ufc_tx_arg1_cfg;
    wire ufc_tx_clear_done;
    wire ufc_tx_clear_busy_reject;
    wire ufc_rx_clear_pending;
    wire ufc_rx_clear_overrun;
    wire soft_reset_pulse;
    wire ch_reset_pulse;
    wire [3:0] ch_reset_ch;
    wire irq;

    wire tx_csr_wr_valid;
    wire tx_csr_wr_ready;
    wire [3:0] tx_csr_wr_ch;
    wire [5:0] tx_csr_wr_off;
    wire [31:0] tx_csr_wdata;
    wire [3:0] tx_csr_wstrb;
    wire [1:0] tx_csr_bresp;
    wire tx_csr_wr_rsp_valid;
    wire [1:0] tx_csr_wr_rsp_kind;
    wire [7:0] tx_csr_wr_rsp_code;
    wire tx_csr_global_err;
    wire tx_csr_policy_irq;
    wire tx_csr_rd_valid;
    wire tx_csr_rd_ready;
    wire [3:0] tx_csr_rd_ch;
    wire [5:0] tx_csr_rd_off;
    wire tx_csr_rvalid;
    wire [31:0] tx_csr_rdata;
    wire [1:0] tx_csr_rresp;

    wire rx_csr_wr_valid;
    wire rx_csr_wr_ready;
    wire [3:0] rx_csr_wr_ch;
    wire [5:0] rx_csr_wr_off;
    wire [31:0] rx_csr_wdata;
    wire [3:0] rx_csr_wstrb;
    wire [1:0] rx_csr_bresp;
    wire rx_csr_wr_rsp_valid;
    wire [1:0] rx_csr_wr_rsp_kind;
    wire [7:0] rx_csr_wr_rsp_code;
    wire rx_csr_rd_valid;
    wire rx_csr_rd_ready;
    wire [3:0] rx_csr_rd_ch;
    wire [5:0] rx_csr_rd_off;
    wire rx_csr_rvalid;
    wire [31:0] rx_csr_rdata;
    wire [1:0] rx_csr_rresp;

    dma_axil_regs u_regs (
        .clk(clk),
        .rstn(rstn),
        .s_axil_awaddr(awaddr),
        .s_axil_awvalid(awvalid),
        .s_axil_awready(awready),
        .s_axil_wdata(wdata),
        .s_axil_wstrb(wstrb),
        .s_axil_wvalid(wvalid),
        .s_axil_wready(wready),
        .s_axil_bresp(bresp),
        .s_axil_bvalid(bvalid),
        .s_axil_bready(bready),
        .s_axil_araddr(araddr),
        .s_axil_arvalid(arvalid),
        .s_axil_arready(arready),
        .s_axil_rdata(rdata),
        .s_axil_rresp(rresp),
        .s_axil_rvalid(rvalid),
        .s_axil_rready(rready),
        .core_busy(core_busy),
        .axi_busy(axi_busy),
        .soft_reset_ready(1'b1),
        .soft_reset_quiescing(1'b0),
        .soft_reset_drain_done(1'b1),
        .cdc_protocol_error(cdc_protocol_error),
        .event_valid(event_valid),
        .event_ch_valid(event_ch_valid),
        .event_ch(event_ch),
        .event_status_code(event_status_code),
        .event_aligned_len(event_aligned_len),
        .event_next_wr_ptr(event_next_wr_ptr),
        .event_inc_frame(event_inc_frame),
        .event_inc_drop(event_inc_drop),
        .event_inc_err(event_inc_err),
        .event_update_wr_ptr(event_update_wr_ptr),
        .event_irq_mask(event_irq_mask),
        .event_global_header_err(event_global_header_err),
        .fc_status_valid(fc_status_valid),
        .fc_status_ch(fc_status_ch),
        .fc_status_pause(fc_status_pause),
        .fc_status_low(fc_status_low),
        .fc_status_full(fc_status_full),
        .fc_status_afull(fc_status_afull),
        .fc_status_ovf(fc_status_ovf),
        .cq_commit_valid(cq_commit_valid),
        .cq_next_ptr(cq_next_ptr),
        .rx_ch_busy_flat(rx_ch_busy_flat),
        .tx_ch_busy_flat(tx_ch_busy_flat),
        .tx_event_valid(tx_event_valid),
        .tx_event_ch(tx_event_ch),
        .tx_event_status_code(tx_event_status_code),
        .tx_event_inc_frame(tx_event_inc_frame),
        .tx_event_inc_err(tx_event_inc_err),
        .tx_event_clear_start(tx_event_clear_start),
        .tx_event_clear_stop(tx_event_clear_stop),
        .tx_desc_event_valid(1'b0),
        .tx_desc_event_ch(4'h0),
        .tx_desc_event_rd_ptr(32'h0),
        .tx_desc_event_status_code(8'h0),
        .tx_desc_event_inc_err(1'b0),
        .tx_csr_wr_valid(tx_csr_wr_valid),
        .tx_csr_wr_ready(tx_csr_wr_ready),
        .tx_csr_wr_ch(tx_csr_wr_ch),
        .tx_csr_wr_off(tx_csr_wr_off),
        .tx_csr_wdata(tx_csr_wdata),
        .tx_csr_wstrb(tx_csr_wstrb),
        .tx_csr_bresp(tx_csr_bresp),
        .tx_csr_wr_rsp_valid(tx_csr_wr_rsp_valid),
        .tx_csr_wr_rsp_kind(tx_csr_wr_rsp_kind),
        .tx_csr_wr_rsp_code(tx_csr_wr_rsp_code),
        .tx_csr_global_err(tx_csr_global_err),
        .tx_csr_policy_irq(tx_csr_policy_irq),
        .tx_csr_rd_valid(tx_csr_rd_valid),
        .tx_csr_rd_ready(tx_csr_rd_ready),
        .tx_csr_rd_ch(tx_csr_rd_ch),
        .tx_csr_rd_off(tx_csr_rd_off),
        .tx_csr_rvalid(tx_csr_rvalid),
        .tx_csr_rdata(tx_csr_rdata),
        .tx_csr_rresp(tx_csr_rresp),
        .tx_desc_csr_wr_ready(1'b1),
        .tx_desc_csr_bresp(2'b00),
        .tx_desc_csr_wr_rsp_valid(1'b0),
        .tx_desc_csr_wr_rsp_kind(2'b00),
        .tx_desc_csr_wr_rsp_code(8'h00),
        .tx_desc_csr_rd_ready(1'b1),
        .tx_desc_csr_rvalid(1'b0),
        .tx_desc_csr_rdata(32'h0),
        .tx_desc_csr_rresp(2'b00),
        .tx_desc_enable_flat(),
        .tx_tbl_irq_tx_completion(),
        .tx_tbl_irq_axi_error(),
        .tx_desc_csr_wr_valid(),
        .tx_desc_csr_wr_ch(),
        .tx_desc_csr_wr_off(),
        .tx_desc_csr_wdata(),
        .tx_desc_csr_wstrb(),
        .tx_desc_csr_rd_valid(),
        .tx_desc_csr_rd_ch(),
        .tx_desc_csr_rd_off(),
        .rx_csr_wr_valid(rx_csr_wr_valid),
        .rx_csr_wr_ready(rx_csr_wr_ready),
        .rx_csr_wr_ch(rx_csr_wr_ch),
        .rx_csr_wr_off(rx_csr_wr_off),
        .rx_csr_wdata(rx_csr_wdata),
        .rx_csr_wstrb(rx_csr_wstrb),
        .rx_csr_bresp(rx_csr_bresp),
        .rx_csr_wr_rsp_valid(rx_csr_wr_rsp_valid),
        .rx_csr_wr_rsp_kind(rx_csr_wr_rsp_kind),
        .rx_csr_wr_rsp_code(rx_csr_wr_rsp_code),
        .rx_csr_rd_valid(rx_csr_rd_valid),
        .rx_csr_rd_ready(rx_csr_rd_ready),
        .rx_csr_rd_ch(rx_csr_rd_ch),
        .rx_csr_rd_off(rx_csr_rd_off),
        .rx_csr_rvalid(rx_csr_rvalid),
        .rx_csr_rdata(rx_csr_rdata),
        .rx_csr_rresp(rx_csr_rresp),
        .global_enable(global_enable),
        .rx_enable(rx_enable),
        .tx_enable(tx_enable),
        .irq_enable(irq_enable),
        .cq_base_l(cq_base_l),
        .cq_base_h(cq_base_h),
        .cq_size(cq_size),
        .cq_wr_ptr(cq_wr_ptr),
        .cq_rd_ptr(cq_rd_ptr),
        .rx_ctrl_flat(rx_ctrl_flat),
        .rx_cfg_flat(rx_cfg_flat),
        .rx_base_l_flat(rx_base_l_flat),
        .rx_base_h_flat(rx_base_h_flat),
        .rx_size_flat(rx_size_flat),
        .rx_max_len_flat(rx_max_len_flat),
        .rx_wr_ptr_flat(rx_wr_ptr_flat),
        .rx_rd_ptr_flat(rx_rd_ptr_flat),
        .rx_used_flat(rx_used_flat),
        .rx_high_wm_flat(rx_high_wm_flat),
        .rx_low_wm_flat(rx_low_wm_flat),
        .rx_user_flat(rx_user_flat),
        .tx_ctrl_flat(tx_ctrl_flat),
        .tx_cfg_flat(tx_cfg_flat),
        .tx_base_l_flat(tx_base_l_flat),
        .tx_base_h_flat(tx_base_h_flat),
        .tx_len_flat(tx_len_flat),
        .tx_status_flat(tx_status_flat),
        .tx_user_flat(tx_user_flat),
        .tx_desc_ctrl_flat(),
        .tx_desc_base_l_flat(),
        .tx_desc_base_h_flat(),
        .tx_desc_size_flat(),
        .tx_desc_rd_ptr_flat(),
        .tx_desc_wr_ptr_flat(),
        .tx_desc_status_flat(),
        .ufc_enable(ufc_enable),
        .ufc_tx_start(ufc_tx_start),
        .ufc_tx_opcode_cfg(ufc_tx_opcode_cfg),
        .ufc_tx_flow_id_cfg(ufc_tx_flow_id_cfg),
        .ufc_tx_arg0_cfg(ufc_tx_arg0_cfg),
        .ufc_tx_arg1_cfg(ufc_tx_arg1_cfg),
        .ufc_tx_clear_done(ufc_tx_clear_done),
        .ufc_tx_clear_busy_reject(ufc_tx_clear_busy_reject),
        .ufc_tx_busy(ufc_tx_busy),
        .ufc_tx_done(ufc_tx_done),
        .ufc_tx_busy_reject(ufc_tx_busy_reject),
        .ufc_tx_done_event(ufc_tx_done_event),
        .ufc_rx_clear_pending(ufc_rx_clear_pending),
        .ufc_rx_clear_overrun(ufc_rx_clear_overrun),
        .ufc_rx_pending(ufc_rx_pending),
        .ufc_rx_overrun(ufc_rx_overrun),
        .ufc_rx_opcode(ufc_rx_opcode),
        .ufc_rx_flow_id(ufc_rx_flow_id),
        .ufc_rx_arg0(ufc_rx_arg0),
        .ufc_rx_arg1(ufc_rx_arg1),
        .ufc_rx_msg_event(ufc_rx_msg_event),
        .soft_reset_pending(),
        .soft_reset_request_pulse(),
        .soft_reset_pulse(soft_reset_pulse),
        .ch_reset_pulse(ch_reset_pulse),
        .ch_reset_ch(ch_reset_ch),
        .irq(irq)
    );

    dma_tx_channel_table u_tx_channel_table (
        .clk(clk),
        .rstn(rstn),
        .global_soft_reset(soft_reset_pulse),
        .csr_wr_valid(tx_csr_wr_valid),
        .csr_wr_ready(tx_csr_wr_ready),
        .csr_wr_ch(tx_csr_wr_ch),
        .csr_wr_off(tx_csr_wr_off),
        .csr_wdata(tx_csr_wdata),
        .csr_wstrb(tx_csr_wstrb),
        .csr_bresp(tx_csr_bresp),
        .csr_wr_rsp_valid(tx_csr_wr_rsp_valid),
        .csr_wr_rsp_kind(tx_csr_wr_rsp_kind),
        .csr_wr_rsp_code(tx_csr_wr_rsp_code),
        .csr_global_err(tx_csr_global_err),
        .csr_policy_irq(tx_csr_policy_irq),
        .csr_rd_valid(tx_csr_rd_valid),
        .csr_rd_ready(tx_csr_rd_ready),
        .csr_rd_ch(tx_csr_rd_ch),
        .csr_rd_off(tx_csr_rd_off),
        .csr_rvalid(tx_csr_rvalid),
        .csr_rdata(tx_csr_rdata),
        .csr_rresp(tx_csr_rresp),
        .tx_event_valid(tx_event_valid),
        .tx_event_ch(tx_event_ch),
        .tx_event_status_code(tx_event_status_code),
        .tx_event_inc_frame(tx_event_inc_frame),
        .tx_event_inc_err(tx_event_inc_err),
        .tx_event_clear_start(tx_event_clear_start),
        .tx_event_clear_stop(tx_event_clear_stop),
        .tx_ch_busy_flat(tx_ch_busy_flat),
        .tx_desc_enable_flat({`DMA_MAX_CH{1'b0}}),
        .irq_tx_completion(),
        .irq_axi_error(),
        .tx_ctrl_flat(), .tx_cfg_flat(), .tx_base_l_flat(), .tx_base_h_flat(),
        .tx_len_flat(), .tx_status_flat(), .tx_user_flat()
    );

    dma_rx_channel_table u_rx_channel_table (
        .clk(clk),
        .rstn(rstn),
        .global_soft_reset(soft_reset_pulse),
        .rx_ch_busy_flat(rx_ch_busy_flat),
        .csr_wr_valid(rx_csr_wr_valid),
        .csr_wr_ready(rx_csr_wr_ready),
        .csr_wr_ch(rx_csr_wr_ch),
        .csr_wr_off(rx_csr_wr_off),
        .csr_wdata(rx_csr_wdata),
        .csr_wstrb(rx_csr_wstrb),
        .csr_bresp(rx_csr_bresp),
        .csr_wr_rsp_valid(rx_csr_wr_rsp_valid),
        .csr_wr_rsp_kind(rx_csr_wr_rsp_kind),
        .csr_wr_rsp_code(rx_csr_wr_rsp_code),
        .ch_reset_pulse(), .ch_reset_ch(),
        .resume_scan_req_valid(1'b0),
        .resume_scan_req_ch(4'h0),
        .resume_scan_rsp_valid(),
        .resume_scan_rsp_ch(),
        .resume_scan_rsp_used(),
        .resume_scan_rsp_low_wm(),
        .resume_scan_rsp_size(),
        .resume_scan_rsp_flow_id(),
        .consumer_release_valid(), .consumer_release_ready(1'b1), .consumer_release_ch(),
        .consumer_release_delta(), .consumer_release_ptr(),
        .csr_rd_valid(rx_csr_rd_valid),
        .csr_rd_ready(rx_csr_rd_ready),
        .csr_rd_ch(rx_csr_rd_ch),
        .csr_rd_off(rx_csr_rd_off),
        .csr_rvalid(rx_csr_rvalid),
        .csr_rdata(rx_csr_rdata),
        .csr_rresp(rx_csr_rresp),
        .event_valid(event_valid),
        .event_ch_valid(event_ch_valid),
        .event_ch(event_ch),
        .event_status_code(event_status_code),
        .event_aligned_len(event_aligned_len),
        .event_next_wr_ptr(event_next_wr_ptr),
        .event_inc_frame(event_inc_frame),
        .event_inc_drop(event_inc_drop),
        .event_inc_err(event_inc_err),
        .event_update_wr_ptr(event_update_wr_ptr),
        .fc_status_valid(fc_status_valid), .fc_status_ch(fc_status_ch),
        .fc_status_pause(fc_status_pause), .fc_status_low(fc_status_low),
        .fc_status_full(fc_status_full), .fc_status_afull(fc_status_afull), .fc_status_ovf(fc_status_ovf),
        .rx_ctrl_flat(), .rx_cfg_flat(), .rx_base_l_flat(), .rx_base_h_flat(),
        .rx_size_flat(), .rx_max_len_flat(), .rx_wr_ptr_flat(), .rx_rd_ptr_flat(),
        .rx_used_flat(), .rx_high_wm_flat(), .rx_low_wm_flat(), .rx_user_flat()
    );

    task fail;
        input [255:0] msg;
        begin
            $display("Error: %0s", msg);
            $finish;
        end
    endtask

    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        integer guard;
        begin
            @(posedge clk);
            awaddr <= addr;
            wdata <= data;
            wstrb <= 4'hf;
            awvalid <= 1'b1;
            wvalid <= 1'b1;
            bready <= 1'b1;
            guard = 0;
            while (!(awready && wready)) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 100) fail("AXI-Lite write address/data timeout");
            end
            @(posedge clk);
            awvalid <= 1'b0;
            wvalid <= 1'b0;
            guard = 0;
            while (!bvalid) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 100) fail("AXI-Lite write response timeout");
            end
            if (bresp !== 2'b00) fail("AXI-Lite write response was not OKAY");
            @(posedge clk);
            bready <= 1'b0;
        end
    endtask

    task axil_read;
        input [31:0] addr;
        output [31:0] data;
        integer guard;
        begin
            @(posedge clk);
            araddr <= addr;
            arvalid <= 1'b1;
            rready <= 1'b1;
            guard = 0;
            while (!arready) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 100) fail("AXI-Lite read address timeout");
            end
            @(posedge clk);
            arvalid <= 1'b0;
            guard = 0;
            while (!rvalid) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 100) fail("AXI-Lite read data timeout");
            end
            if (rresp !== 2'b00) fail("AXI-Lite read response was not OKAY");
            data = rdata;
            @(posedge clk);
            rready <= 1'b0;
        end
    endtask

    task axil_read_with_rready_stall;
        input [31:0] addr;
        output [31:0] data;
        integer guard;
        reg [31:0] held_data;
        begin
            @(posedge clk);
            araddr <= addr;
            arvalid <= 1'b1;
            rready <= 1'b0;
            guard = 0;
            while (!arready) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 100) fail("stalled read address timeout");
            end
            @(posedge clk);
            arvalid <= 1'b0;
            guard = 0;
            while (!rvalid) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 100) fail("stalled read data timeout");
            end
            held_data = rdata;
            repeat (3) begin
                @(posedge clk);
                if (!rvalid) fail("rvalid dropped during rready stall");
                if (rdata !== held_data) fail("rdata changed during rready stall");
                if (arready) fail("arready asserted while read response outstanding");
            end
            rready <= 1'b1;
            @(posedge clk);
            data = held_data;
            rready <= 1'b0;
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

    task expect_no_x;
        input [31:0] value;
        input [255:0] name;
        begin
            if (^value === 1'bx) begin
                $display("Error: %0s contains X: %08x", name, value);
                $finish;
            end
        end
    endtask

    reg [31:0] rd;
    reg [31:0] rd2;
    reg [31:0] ch0;
    reg [31:0] tx0;

    initial begin
        repeat (5) @(posedge clk);
        rstn = 1'b1;
        repeat (8) @(posedge clk);

        axil_read(`DMA_REG_IP_ID, rd);
        expect_eq(rd, `DMA_IP_ID, "IP_ID");
        axil_read(`DMA_REG_VERSION, rd);
        expect_eq(rd, `DMA_VERSION, "VERSION");
        axil_read(`DMA_REG_FEATURE, rd);
        if (!rd[`DMA_FEATURE_RX] || !rd[`DMA_FEATURE_TX] ||
            !rd[`DMA_FEATURE_FC_PER_CH_INGRESS] || !rd[`DMA_FEATURE_FC_DDR_RING] ||
            rd[`DMA_FEATURE_SPLIT_FRAME_WRITE]) begin
            $display("Error: FEATURE_STATUS mismatch: %08x", rd);
            $finish;
        end

        ch0 = `DMA_RX_CH_BASE;
        tx0 = `DMA_TX_CH_BASE;
        axil_write(ch0 + `DMA_CH_CFG, 32'h0000_1151);
        axil_write(ch0 + `DMA_CH_BASE_L, 32'h0000_4000);
        axil_write(ch0 + `DMA_CH_SIZE, 32'h0000_2000);
        axil_write(ch0 + `DMA_CH_MAX_LEN, 32'h0000_1000);
        axil_write(ch0 + `DMA_RX_CH_HIGH_WM, 32'h0000_1800);
        axil_write(ch0 + `DMA_RX_CH_LOW_WM, 32'h0000_0800);
        axil_write(tx0 + `DMA_CH_CFG, 32'h1234_0011);
        axil_write(tx0 + `DMA_CH_BASE_L, 32'h0000_8000);
        axil_write(tx0 + `DMA_TX_CH_LEN, 32'h0000_0040);

        axil_read(ch0 + `DMA_CH_CFG, rd);
        expect_eq(rd, 32'h0000_1151, "RX_CH0_CFG");
        axil_read(ch0 + `DMA_RX_CH_HIGH_WM, rd);
        expect_eq(rd, 32'h0000_1800, "RX_CH0_HIGH_WM");
        axil_read(tx0 + `DMA_CH_CFG, rd);
        expect_eq(rd, 32'h1234_0011, "TX_CH0_CFG");
        axil_read(tx0 + `DMA_TX_CH_LEN, rd);
        expect_eq(rd, 32'h0000_0040, "TX_CH0_LEN");

        core_busy <= 1'b1;
        axi_busy <= 1'b1;
        rx_ch_busy_flat[0] <= 1'b1;
        tx_ch_busy_flat[0] <= 1'b1;
        repeat (4) @(posedge clk);
        axil_read(`DMA_REG_GLOBAL_STATUS, rd);
        expect_no_x(rd, "GLOBAL_STATUS busy mirror");
        if (!rd[1] || !rd[4]) begin
            $display("Error: busy bits not visible in GLOBAL_STATUS mirror: %08x", rd);
            $finish;
        end
        axil_read(ch0 + `DMA_CH_STATUS, rd);
        expect_no_x(rd, "RX_CH_STATUS busy mirror");
        if (!rd[`DMA_RX_STATUS_BUSY]) begin
            $display("Error: RX busy bit not visible in status mirror: %08x", rd);
            $finish;
        end
        axil_read(tx0 + `DMA_CH_STATUS, rd);
        expect_no_x(rd, "TX_CH_STATUS busy mirror");
        if (!rd[`DMA_TX_STATUS_BUSY]) begin
            $display("Error: TX busy bit not visible in status mirror: %08x", rd);
            $finish;
        end
        core_busy <= 1'b0;
        axi_busy <= 1'b0;
        rx_ch_busy_flat[0] <= 1'b0;
        tx_ch_busy_flat[0] <= 1'b0;

        event_valid <= 1'b1;
        event_ch_valid <= 1'b1;
        event_ch <= 4'h0;
        event_status_code <= `DMA_ST_FRAME_DONE;
        event_inc_frame <= 1'b1;
        event_irq_mask <= (16'h1 << `DMA_IRQ_RX_COMPLETION);
        @(posedge clk);
        event_valid <= 1'b0;
        event_ch_valid <= 1'b0;
        event_inc_frame <= 1'b0;
        event_irq_mask <= 16'h0;
        repeat (3) @(posedge clk);
        axil_read(`DMA_REG_IRQ_STATUS, rd);
        if (!rd[`DMA_IRQ_RX_COMPLETION]) begin
            $display("Error: IRQ_STATUS did not show RX completion event: %08x", rd);
            $finish;
        end
        axil_read(ch0 + `DMA_CH_FRAME_CNT, rd);
        expect_eq(rd, 32'h1, "RX_CH0_FRAME_CNT");

        axil_write(`DMA_REG_GLOBAL_CTRL,
                   (32'h1 << `DMA_GCTRL_GLOBAL_EN) |
                   (32'h1 << `DMA_GCTRL_IRQ_EN));
        axil_write(`DMA_REG_IRQ_MASK, 32'h1 << `DMA_IRQ_AXI_ERROR);
        @(negedge clk);
        cdc_protocol_error = 1'b1;
        repeat (4) @(posedge clk);
        axil_read(`DMA_REG_GLOBAL_STATUS, rd);
        if (!rd[`DMA_GSTATUS_CDC_PROTOCOL_ERROR])
            fail("CDC protocol error did not set GLOBAL_STATUS sticky bit");
        axil_read(`DMA_REG_DEBUG_STATE, rd);
        if (!rd[5]) fail("CDC protocol error was not visible in DEBUG_STATE");
        axil_read(`DMA_REG_ERR_CNT, rd);
        expect_eq(rd, 32'h1, "CDC protocol error count");
        axil_read(`DMA_REG_IRQ_STATUS, rd);
        if (!rd[`DMA_IRQ_AXI_ERROR] || !irq)
            fail("CDC protocol error did not raise AXI-error IRQ");
        repeat (5) @(posedge clk);
        axil_read(`DMA_REG_ERR_CNT, rd);
        expect_eq(rd, 32'h1, "level-held CDC error counted once");
        @(negedge clk);
        cdc_protocol_error = 1'b0;
        repeat (3) @(posedge clk);

        axil_read(`DMA_REG_IP_ID, rd);
        axil_read(`DMA_REG_VERSION, rd2);
        expect_eq(rd, `DMA_IP_ID, "back-to-back IP_ID");
        expect_eq(rd2, `DMA_VERSION, "back-to-back VERSION");

        axil_read_with_rready_stall(`DMA_REG_FEATURE, rd);
        expect_no_x(rd, "FEATURE stalled read");
        if (!rd[`DMA_FEATURE_TX]) fail("FEATURE stalled read lost TX bit");

        axil_read(32'h0000_0ff0, rd);
        expect_eq(rd, 32'h0, "illegal read");

        $display("OK: dma RTL v15 AXI-Lite read pipeline test passed.");
        $finish;
    end
endmodule
