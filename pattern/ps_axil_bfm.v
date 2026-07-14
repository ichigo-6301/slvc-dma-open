`timescale 1ns/1ps
`include "dma_sim_def.vh"

module ps_axil_bfm(
    output reg [31:0] s_axil_awaddr,
    output reg        s_axil_awvalid,
    input             s_axil_awready,
    output reg [31:0] s_axil_wdata,
    output reg [3:0]  s_axil_wstrb,
    output reg        s_axil_wvalid,
    input             s_axil_wready,
    input      [1:0]  s_axil_bresp,
    input             s_axil_bvalid,
    output reg        s_axil_bready,
    output reg [31:0] s_axil_araddr,
    output reg        s_axil_arvalid,
    input             s_axil_arready,
    input      [31:0] s_axil_rdata,
    input      [1:0]  s_axil_rresp,
    input             s_axil_rvalid,
    output reg        s_axil_rready,
    input             irq,
    input             clk,
    input             rstn
);

reg [31:0] cq_base;
reg [31:0] cq_size;
integer timeout_cycles;

initial begin
    s_axil_awaddr  = 32'h0;
    s_axil_awvalid = 1'b0;
    s_axil_wdata   = 32'h0;
    s_axil_wstrb   = 4'h0;
    s_axil_wvalid  = 1'b0;
    s_axil_bready  = 1'b0;
    s_axil_araddr  = 32'h0;
    s_axil_arvalid = 1'b0;
    s_axil_rready  = 1'b0;
    cq_base = 32'h0;
    cq_size = 32'h0;
    timeout_cycles = 20000;
end

function [31:0] ch_addr;
    input [11:0] base;
    input integer ch;
    input [11:0] off;
    begin
        ch_addr = base + (ch * `DMA_CH_STRIDE) + off;
    end
endfunction

function [7:0] mem_u8;
    input [31:0] addr;
    begin
        mem_u8 = `DMA_SYS_MEM_PATH[addr];
    end
endfunction

function [15:0] mem_u16;
    input [31:0] addr;
    begin
        mem_u16 = {mem_u8(addr + 1), mem_u8(addr)};
    end
endfunction

function [31:0] mem_u32;
    input [31:0] addr;
    begin
        mem_u32 = {mem_u8(addr + 3), mem_u8(addr + 2), mem_u8(addr + 1), mem_u8(addr)};
    end
endfunction

task fail_timeout;
    input [127:0] name;
    begin
        $display("%t Error: timeout in %0s", $time, name);
        $finish;
    end
endtask

task axil_write;
    input [31:0] addr;
    input [31:0] data;
    integer guard;
    begin
        guard = 0;
        @(posedge clk);
        s_axil_awaddr  <= addr;
        s_axil_awvalid <= 1'b1;
        s_axil_wdata   <= data;
        s_axil_wstrb   <= 4'hf;
        s_axil_wvalid  <= 1'b1;
        s_axil_bready  <= 1'b1;
        while (!(s_axil_awready && s_axil_wready && s_axil_awvalid && s_axil_wvalid)) begin
            @(posedge clk);
            guard = guard + 1;
            if (guard > timeout_cycles)
                fail_timeout("axil_write_aw_w");
        end
        s_axil_awvalid <= 1'b0;
        s_axil_wvalid  <= 1'b0;
        guard = 0;
        while (!s_axil_bvalid) begin
            @(posedge clk);
            guard = guard + 1;
            if (guard > timeout_cycles)
                fail_timeout("axil_write_b");
        end
        if (s_axil_bresp != 2'b00) begin
            $display("%t Error: AXI-Lite BRESP addr=%08x resp=%0d", $time, addr, s_axil_bresp);
            $finish;
        end
        @(posedge clk);
        s_axil_bready <= 1'b0;
    end
endtask

task axil_read;
    input [31:0] addr;
    output [31:0] data;
    integer guard;
    begin
        guard = 0;
        @(posedge clk);
        s_axil_araddr  <= addr;
        s_axil_arvalid <= 1'b1;
        s_axil_rready  <= 1'b1;
        while (!(s_axil_arready && s_axil_arvalid)) begin
            @(posedge clk);
            guard = guard + 1;
            if (guard > timeout_cycles)
                fail_timeout("axil_read_ar");
        end
        s_axil_arvalid <= 1'b0;
        guard = 0;
        while (!s_axil_rvalid) begin
            @(posedge clk);
            guard = guard + 1;
            if (guard > timeout_cycles)
                fail_timeout("axil_read_r");
        end
        data = s_axil_rdata;
        if (s_axil_rresp != 2'b00) begin
            $display("%t Error: AXI-Lite RRESP addr=%08x resp=%0d", $time, addr, s_axil_rresp);
            $finish;
        end
        @(posedge clk);
        s_axil_rready <= 1'b0;
    end
endtask

task dma_read_feature_status;
    output [31:0] feature;
    begin
        axil_read(`DMA_REG_FEATURE, feature);
    end
endtask

task dma_global_enable;
    input rx_en;
    input tx_en;
    input irq_en;
    input ufc_en;
    reg [31:0] value;
    begin
        value = (1 << `DMA_GCTRL_GLOBAL_EN);
        if (rx_en)
            value = value | (1 << `DMA_GCTRL_RX_EN);
        if (tx_en)
            value = value | (1 << `DMA_GCTRL_TX_EN);
        if (irq_en)
            value = value | (1 << `DMA_GCTRL_IRQ_EN);
        if (ufc_en)
            value = value | (1 << `DMA_GCTRL_UFC_EN);
        axil_write(`DMA_REG_GLOBAL_CTRL, value);
    end
endtask

task dma_config_cq;
    input [31:0] base_addr;
    input [31:0] size;
    begin
        cq_base = base_addr;
        cq_size = size;
        axil_write(`DMA_REG_CQ_BASE_L, base_addr);
        axil_write(`DMA_REG_CQ_BASE_H, 32'h0);
        axil_write(`DMA_REG_CQ_SIZE, size);
        axil_write(`DMA_REG_CQ_RD_PTR, 32'h0);
    end
endtask

task dma_config_rx_channel;
    input integer ch;
    input [31:0] base;
    input [31:0] size;
    input [31:0] max_len;
    input [15:0] flow_id;
    input [3:0]  policy;
    input [31:0] high_wm;
    input [31:0] low_wm;
    reg [31:0] cfg;
    reg [31:0] ctrl;
    begin
        cfg = {flow_id, 4'h0, 4'h0, policy, `DMA_TC_FC};
        ctrl = (1 << `DMA_RX_CTRL_ENABLE) |
               (1 << `DMA_RX_CTRL_CPL_EN) |
               (1 << `DMA_RX_CTRL_IRQ_EN) |
               (1 << `DMA_RX_CTRL_FC_EN);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_CFG), cfg);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_BASE_L), base);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_BASE_H), 32'h0);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_SIZE), size);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_MAX_LEN), max_len);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_RX_CH_HIGH_WM), high_wm);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_RX_CH_LOW_WM), low_wm);
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_CH_CTRL), ctrl);
    end
endtask

task dma_config_tx_channel;
    input integer ch;
    input [31:0] base;
    input [31:0] len;
    input [15:0] flow_id;
    input [3:0]  traffic_class;
    input [3:0]  policy;
    reg [31:0] cfg;
    begin
        cfg = {flow_id, 4'h0, 4'h0, policy, traffic_class};
        axil_write(ch_addr(`DMA_TX_CH_BASE, ch, `DMA_CH_CFG), cfg);
        axil_write(ch_addr(`DMA_TX_CH_BASE, ch, `DMA_CH_BASE_L), base);
        axil_write(ch_addr(`DMA_TX_CH_BASE, ch, `DMA_CH_BASE_H), 32'h0);
        axil_write(ch_addr(`DMA_TX_CH_BASE, ch, `DMA_TX_CH_LEN), len);
    end
endtask

task dma_start_tx;
    input integer ch;
    reg [31:0] ctrl;
    begin
        ctrl = (1 << `DMA_TX_CTRL_ENABLE) |
               (1 << `DMA_TX_CTRL_START) |
               (1 << `DMA_TX_CTRL_CPL_EN) |
               (1 << `DMA_TX_CTRL_IRQ_EN);
        axil_write(ch_addr(`DMA_TX_CH_BASE, ch, `DMA_CH_CTRL), ctrl);
    end
endtask

task dma_poll_cq;
    input [7:0] expected_direction;
    input [7:0] expected_status;
    reg [31:0] addr;
    reg [31:0] len;
    reg [7:0]  ch;
    reg [15:0] flow_id;
    begin
        dma_poll_cq_detail(expected_direction, expected_status, ch, flow_id, len, addr);
    end
endtask

task dma_poll_cq_detail;
    input [7:0] expected_direction;
    input [7:0] expected_status;
    output [7:0] channel_id;
    output [15:0] flow_id;
    output [31:0] length;
    output [31:0] payload_addr;
    integer poll;
    integer idx;
    reg found;
    reg [31:0] cqe_addr;
    reg [31:0] dbg;
    begin
        poll = 0;
        found = 1'b0;
        channel_id = 8'h0;
        flow_id = 16'h0;
        length = 32'h0;
        payload_addr = 32'h0;
        while (!found && (poll < timeout_cycles)) begin
            for (idx = 0; idx < cq_size; idx = idx + 1) begin
                cqe_addr = cq_base + (idx * `DMA_CQE_BYTES);
                if ((mem_u32(cqe_addr + `DMA_CQE_MAGIC_OFF) == `DMA_CQE_MAGIC) &&
                    (mem_u32(cqe_addr + `DMA_CQE_OWNER_OFF) != 32'h0) &&
                    (mem_u8(cqe_addr + `DMA_CQE_DIRECTION_OFF) == expected_direction) &&
                    (mem_u8(cqe_addr + `DMA_CQE_STATUS_OFF) == expected_status)) begin
                    found = 1'b1;
                    channel_id = mem_u8(cqe_addr + `DMA_CQE_CHANNEL_ID_OFF);
                    flow_id = mem_u16(cqe_addr + `DMA_CQE_FLOW_ID_OFF);
                    length = mem_u32(cqe_addr + `DMA_CQE_LENGTH_OFF);
                    payload_addr = mem_u32(cqe_addr + `DMA_CQE_ADDR_OFF);
                end
            end
            if (!found) begin
                repeat (5) @(posedge clk);
                poll = poll + 5;
            end
        end
        if (!found) begin
            $display("Error: CQE not found dir=%02x status=%02x", expected_direction, expected_status);
            for (idx = 0; idx < cq_size; idx = idx + 1) begin
                cqe_addr = cq_base + (idx * `DMA_CQE_BYTES);
                if (mem_u32(cqe_addr + `DMA_CQE_MAGIC_OFF) == `DMA_CQE_MAGIC) begin
                    $display("Info: CQE[%0d] owner=%08x dir=%02x status=%02x ch=%02x flow=%04x len=%0d addr=%08x",
                             idx,
                             mem_u32(cqe_addr + `DMA_CQE_OWNER_OFF),
                             mem_u8(cqe_addr + `DMA_CQE_DIRECTION_OFF),
                             mem_u8(cqe_addr + `DMA_CQE_STATUS_OFF),
                             mem_u8(cqe_addr + `DMA_CQE_CHANNEL_ID_OFF),
                             mem_u16(cqe_addr + `DMA_CQE_FLOW_ID_OFF),
                             mem_u32(cqe_addr + `DMA_CQE_LENGTH_OFF),
                             mem_u32(cqe_addr + `DMA_CQE_ADDR_OFF));
                end
            end
            axil_read(`DMA_REG_IRQ_STATUS, dbg);
            $display("Info: IRQ_STATUS=%08x", dbg);
            axil_read(ch_addr(`DMA_RX_CH_BASE, 0, `DMA_CH_STATUS), dbg);
            $display("Info: RX0_STATUS=%08x", dbg);
            axil_read(ch_addr(`DMA_RX_CH_BASE, 0, `DMA_CH_USED), dbg);
            $display("Info: RX0_USED=%08x", dbg);
            axil_read(ch_addr(`DMA_RX_CH_BASE, 0, `DMA_CH_ERR_CNT), dbg);
            $display("Info: RX0_ERR_CNT=%08x", dbg);
            $finish;
        end
    end
endtask

task dma_release_rx_buffer;
    input integer ch;
    input [31:0] new_rd_ptr;
    begin
        axil_write(ch_addr(`DMA_RX_CH_BASE, ch, `DMA_RX_CH_RD_PTR), new_rd_ptr);
    end
endtask

task dma_clear_irq;
    input [31:0] mask;
    begin
        axil_write(`DMA_REG_IRQ_STATUS, mask);
    end
endtask

task dma_wait_irq;
    input integer timeout;
    integer poll;
    begin
        poll = 0;
        while (!irq && (poll < timeout)) begin
            @(posedge clk);
            poll = poll + 1;
        end
        if (poll >= timeout) begin
            $display("Error: timeout waiting IRQ");
            $finish;
        end
    end
endtask

endmodule
