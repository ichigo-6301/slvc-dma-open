`timescale 1ns/1ps
`include "dma_sim_def.vh"

module tb;

reg clk, rstn;
reg [7:0] sys_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] ref_mem [0:`DMA_SIM_MEM_BYTES-1];
reg [7:0] pkt_mem [0:`DMA_PKT_MEM_BYTES-1];

reg [511:0] udp_tdata;
reg [63:0] udp_tkeep;
reg udp_tvalid, udp_tlast;
wire udp_tready;
wire [511:0] sl_rx_tdata;
wire sl_rx_tvalid, sl_rx_tready;
wire adapter_accept, adapter_drop;
wire [7:0] adapter_drop_reason;

wire [511:0] sl_tx_tdata;
wire sl_tx_tvalid;
wire sl_tx_tready=1'b1;
wire irq;

wire [31:0] s_axil_awaddr; wire s_axil_awvalid,s_axil_awready;
wire [31:0] s_axil_wdata; wire [3:0] s_axil_wstrb;
wire s_axil_wvalid,s_axil_wready; wire [1:0] s_axil_bresp;
wire s_axil_bvalid,s_axil_bready;
wire [31:0] s_axil_araddr; wire s_axil_arvalid,s_axil_arready;
wire [31:0] s_axil_rdata; wire [1:0] s_axil_rresp;
wire s_axil_rvalid,s_axil_rready;

wire [31:0] m_axi_awaddr; wire [7:0] m_axi_awlen;
wire [2:0] m_axi_awsize; wire [1:0] m_axi_awburst;
wire m_axi_awvalid,m_axi_awready;
wire [63:0] m_axi_wdata; wire [7:0] m_axi_wstrb;
wire m_axi_wlast,m_axi_wvalid,m_axi_wready;
wire [1:0] m_axi_bresp; wire m_axi_bvalid,m_axi_bready;
wire [31:0] m_axi_araddr; wire [7:0] m_axi_arlen;
wire [2:0] m_axi_arsize; wire [1:0] m_axi_arburst;
wire m_axi_arvalid,m_axi_arready;
wire [63:0] m_axi_rdata; wire [1:0] m_axi_rresp;
wire m_axi_rlast,m_axi_rvalid,m_axi_rready;

wire ctrl_msg_tx_valid; wire [7:0] ctrl_msg_tx_opcode;
wire [15:0] ctrl_msg_tx_channel_id; wire [31:0] ctrl_msg_tx_arg0,ctrl_msg_tx_arg1;
wire ctrl_msg_rx_ready;

localparam [15:0] PORT0=16'h4000;
localparam [15:0] PORT1=16'h4001;
localparam [31:0] RX0_BASE=32'h0001_0000;
localparam [31:0] RX1_BASE=32'h0002_0000;
localparam [31:0] CQ_BASE=32'h0008_0000;
localparam [31:0] CQ_SIZE=32'd16;
localparam integer LEN0=80;
localparam integer LEN1=65;

integer i,errors,timeout,accept_count,drop_count;
reg [7:0] packet_bytes[0:255];
reg [7:0] expected0[0:127];
reg [7:0] expected1[0:127];
reg [31:0] rd;

dma_udp_ipv4_to_shdr64_adapter u_adapter(
    .clk(clk),.rstn(rstn),.soft_reset(1'b0),
    .s_axis_tdata(udp_tdata),.s_axis_tkeep(udp_tkeep),
    .s_axis_tvalid(udp_tvalid),.s_axis_tready(udp_tready),.s_axis_tlast(udp_tlast),
    .m_axis_tdata(sl_rx_tdata),.m_axis_tvalid(sl_rx_tvalid),.m_axis_tready(sl_rx_tready),
    .stat_accept(adapter_accept),.stat_drop(adapter_drop),.stat_drop_reason(adapter_drop_reason)
);

ps_axil_bfm u_ps(
    .s_axil_awaddr(s_axil_awaddr),.s_axil_awvalid(s_axil_awvalid),.s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),.s_axil_wstrb(s_axil_wstrb),.s_axil_wvalid(s_axil_wvalid),.s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),.s_axil_bvalid(s_axil_bvalid),.s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),.s_axil_arvalid(s_axil_arvalid),.s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),.s_axil_rresp(s_axil_rresp),.s_axil_rvalid(s_axil_rvalid),.s_axil_rready(s_axil_rready),
    .irq(irq),.clk(clk),.rstn(rstn)
);

axi_ddr_mem_model u_ddr(
    .aclk(clk),.arstn(rstn),
    .awaddr(m_axi_awaddr),.awlen(m_axi_awlen),.awsize(m_axi_awsize),.awburst(m_axi_awburst),
    .awvalid(m_axi_awvalid),.awready(m_axi_awready),
    .wdata(m_axi_wdata),.wstrb(m_axi_wstrb),.wlast(m_axi_wlast),.wvalid(m_axi_wvalid),.wready(m_axi_wready),
    .bresp(m_axi_bresp),.bvalid(m_axi_bvalid),.bready(m_axi_bready),
    .araddr(m_axi_araddr),.arlen(m_axi_arlen),.arsize(m_axi_arsize),.arburst(m_axi_arburst),
    .arvalid(m_axi_arvalid),.arready(m_axi_arready),
    .rdata(m_axi_rdata),.rresp(m_axi_rresp),.rlast(m_axi_rlast),.rvalid(m_axi_rvalid),.rready(m_axi_rready)
);

slvc_dma_wrapper u_dma(
    .sl_rx_aclk(clk),.sl_rx_aresetn(rstn),
    .sl_rx_tdata(sl_rx_tdata),.sl_rx_tvalid(sl_rx_tvalid),.sl_rx_tready(sl_rx_tready),
    .sl_tx_aclk(clk),.sl_tx_aresetn(rstn),
    .sl_tx_tdata(sl_tx_tdata),.sl_tx_tvalid(sl_tx_tvalid),.sl_tx_tready(sl_tx_tready),
    .s_axil_awaddr(s_axil_awaddr),.s_axil_awvalid(s_axil_awvalid),.s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),.s_axil_wstrb(s_axil_wstrb),.s_axil_wvalid(s_axil_wvalid),.s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),.s_axil_bvalid(s_axil_bvalid),.s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),.s_axil_arvalid(s_axil_arvalid),.s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),.s_axil_rresp(s_axil_rresp),.s_axil_rvalid(s_axil_rvalid),.s_axil_rready(s_axil_rready),
    .m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),.m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready),
    .ctrl_msg_tx_valid(ctrl_msg_tx_valid),.ctrl_msg_tx_ready(1'b1),
    .ctrl_msg_tx_opcode(ctrl_msg_tx_opcode),.ctrl_msg_tx_channel_id(ctrl_msg_tx_channel_id),
    .ctrl_msg_tx_arg0(ctrl_msg_tx_arg0),.ctrl_msg_tx_arg1(ctrl_msg_tx_arg1),
    .ctrl_msg_rx_valid(1'b0),.ctrl_msg_rx_ready(ctrl_msg_rx_ready),
    .ctrl_msg_rx_opcode(8'h0),.ctrl_msg_rx_channel_id(16'h0),
    .ctrl_msg_rx_arg0(32'h0),.ctrl_msg_rx_arg1(32'h0),.irq(irq)
);

initial begin clk=0; forever #5 clk=~clk; end

function [7:0] mem_u8;
    input [31:0] addr;
    begin mem_u8=sys_mem[addr]; end
endfunction
function [15:0] mem_u16;
    input [31:0] addr;
    begin mem_u16={sys_mem[addr+1],sys_mem[addr]}; end
endfunction
function [31:0] mem_u32;
    input [31:0] addr;
    begin mem_u32={sys_mem[addr+3],sys_mem[addr+2],sys_mem[addr+1],sys_mem[addr]}; end
endfunction

task fail;
    input [1023:0] msg;
    begin errors=errors+1; $display("[ERR] %0s @%0t",msg,$time); end
endtask

task build_packet;
    input integer payload_len;
    input [15:0] port;
    input integer salt;
    output integer wire_len;
    integer j,ip_len,udp_len;
    begin
        ip_len=28+payload_len; udp_len=8+payload_len;
        wire_len=42+payload_len; if(wire_len<60) wire_len=60;
        for(j=0;j<256;j=j+1) packet_bytes[j]=0;
        for(j=0;j<12;j=j+1) packet_bytes[j]=8'h70+j;
        packet_bytes[12]=8'h08; packet_bytes[13]=8'h00; packet_bytes[14]=8'h45;
        packet_bytes[16]=(ip_len>>8)&8'hff; packet_bytes[17]=ip_len&8'hff;
        packet_bytes[20]=8'h40; packet_bytes[21]=0; packet_bytes[22]=8'h40; packet_bytes[23]=8'h11;
        packet_bytes[26]=8'h0a; packet_bytes[29]=1; packet_bytes[30]=8'h0a; packet_bytes[33]=2;
        packet_bytes[34]=8'h20; packet_bytes[35]=salt[7:0];
        packet_bytes[36]=port[15:8]; packet_bytes[37]=port[7:0];
        packet_bytes[38]=(udp_len>>8)&8'hff; packet_bytes[39]=udp_len&8'hff;
        for(j=0;j<payload_len;j=j+1) packet_bytes[42+j]=(j*19+salt*31+5)&8'hff;
    end
endtask

task drive_packet;
    input integer wire_len;
    integer offset,lane,n;
    reg [511:0] beat;
    reg [63:0] keep;
    begin
        offset=0;
        @(negedge clk);
        while(offset<wire_len) begin
            n=wire_len-offset; if(n>64)n=64; beat=0; keep=0;
            for(lane=0;lane<n;lane=lane+1) begin beat[lane*8 +: 8]=packet_bytes[offset+lane]; keep[lane]=1; end
            udp_tdata=beat; udp_tkeep=keep;
            udp_tlast=(offset+n==wire_len); udp_tvalid=1;
            timeout=0;
            while(!udp_tready&&timeout<50000) begin timeout=timeout+1; @(negedge clk); end
            if(!udp_tready) fail("UDP input ready timeout");
            @(negedge clk);
            offset=offset+n;
        end
        udp_tvalid=0; udp_tdata=0; udp_tkeep=0; udp_tlast=0;
    end
endtask

task wait_cq_count;
    input [31:0] expected;
    begin
        timeout=0; rd=0;
        while(rd!=expected&&timeout<50000) begin
            u_ps.axil_read(`DMA_REG_CQ_WR_PTR,rd);
            if(rd!=expected) begin timeout=timeout+1; @(posedge clk); end
        end
        if(rd!=expected) fail("CQ write pointer timeout");
    end
endtask

task check_cqe;
    input integer index;
    input [7:0] channel;
    input [15:0] flow;
    input [31:0] length;
    input [31:0] address;
    reg [31:0] base;
    begin
        base=CQ_BASE+index*`DMA_CQE_BYTES;
        if(mem_u32(base+`DMA_CQE_MAGIC_OFF)!==`DMA_CQE_MAGIC) fail("CQE magic mismatch");
        if(mem_u32(base+`DMA_CQE_OWNER_OFF)===0) fail("CQE owner not published");
        if(mem_u8(base+`DMA_CQE_DIRECTION_OFF)!==`DMA_CQE_DIR_RX) fail("CQE direction mismatch");
        if(mem_u8(base+`DMA_CQE_STATUS_OFF)!==`DMA_ST_FRAME_DONE) fail("CQE status mismatch");
        if(mem_u8(base+`DMA_CQE_CHANNEL_ID_OFF)!==channel) fail("CQE channel mismatch");
        if(mem_u16(base+`DMA_CQE_FLOW_ID_OFF)!==flow) fail("CQE flow mismatch");
        if(mem_u32(base+`DMA_CQE_LENGTH_OFF)!==length) fail("CQE length mismatch");
        if(mem_u32(base+`DMA_CQE_ADDR_OFF)!==address) fail("CQE address mismatch");
    end
endtask

always @(posedge clk) begin
    if(rstn) begin
        if(adapter_accept) accept_count<=accept_count+1;
        if(adapter_drop) begin drop_count<=drop_count+1; fail("adapter dropped valid smoke packet"); end
    end
end

integer wire_len;
initial begin
    rstn=0; udp_tdata=0; udp_tkeep=0; udp_tvalid=0; udp_tlast=0;
    errors=0; accept_count=0; drop_count=0;
    for(i=0;i<`DMA_SIM_MEM_BYTES;i=i+1) begin sys_mem[i]=0; ref_mem[i]=0; end
    for(i=0;i<`DMA_PKT_MEM_BYTES;i=i+1) pkt_mem[i]=0;
    repeat(10) @(posedge clk); rstn=1; repeat(5) @(posedge clk);

    u_ddr.clear_region(RX0_BASE,256); u_ddr.clear_region(RX1_BASE,4096);
    u_ddr.clear_region(CQ_BASE,CQ_SIZE*`DMA_CQE_BYTES);
    u_ps.axil_write(`DMA_REG_IRQ_MASK,32'hffff_ffff);
    u_ps.dma_config_cq(CQ_BASE,CQ_SIZE);
    u_ps.dma_config_rx_channel(0,RX0_BASE,32'd128,32'd4096,PORT0,
                               `DMA_RX_POL_QUEUE_WITH_FC,32'd64,32'd0);
    u_ps.dma_config_rx_channel(1,RX1_BASE,32'd4096,32'd4096,PORT1,
                               `DMA_RX_POL_QUEUE_WITH_FC,32'd2048,32'd1024);
    u_ps.dma_global_enable(1'b1,1'b1,1'b0,1'b1);

    build_packet(LEN0,PORT0,1,wire_len);
    for(i=0;i<LEN0;i=i+1) expected0[i]=packet_bytes[42+i];
    drive_packet(wire_len);
    wait_cq_count(1);

    build_packet(LEN1,PORT1,2,wire_len);
    for(i=0;i<LEN1;i=i+1) expected1[i]=packet_bytes[42+i];
    drive_packet(wire_len);
    wait_cq_count(2);

    check_cqe(0,8'd0,PORT0,LEN0,RX0_BASE);
    check_cqe(1,8'd1,PORT1,LEN1,RX1_BASE);
    for(i=0;i<LEN0;i=i+1) if(sys_mem[RX0_BASE+i]!==expected0[i]) fail("channel 0 DDR payload mismatch");
    for(i=0;i<LEN1;i=i+1) if(sys_mem[RX1_BASE+i]!==expected1[i]) fail("channel 1 DDR payload mismatch");
    if(sys_mem[RX0_BASE-1]!==0||sys_mem[RX1_BASE-1]!==0) fail("protocol header leaked before payload base");

    u_ps.axil_read(`DMA_RX_CH_BASE+0*`DMA_CH_STRIDE+`DMA_CH_USED,rd);
    if(rd!==32'd128) fail("channel 0 did not reach full aligned occupancy");
    u_ps.axil_read(`DMA_RX_CH_BASE+1*`DMA_CH_STRIDE+`DMA_CH_USED,rd);
    if(rd!==32'd128) fail("channel 1 occupancy mismatch after channel 0 full");

    repeat(20) @(posedge clk);
    if(errors==0&&accept_count==2&&drop_count==0) begin
        $display("Errors: 0, Warnings: 0");
        $display("PASS tb_rtl_v33e20a107_udp_to_dma_smoke packets=2 channels=2 cqes=2 ch0_full_then_ch1=1");
    end else begin
        $display("Errors: %0d accepts=%0d drops=%0d",errors,accept_count,drop_count);
        $fatal(1,"tb_rtl_v33e20a107_udp_to_dma_smoke failed");
    end
    $finish;
end

initial begin #20000000; $fatal(1,"tb_rtl_v33e20a107_udp_to_dma_smoke timeout"); end

endmodule
