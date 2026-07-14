`timescale 1ns/1ps

module axi_lite_master_model(
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
    input             clk,
    input             rstn
);

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
end

task axil_write;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    begin
        @(posedge clk);
        s_axil_awaddr  <= addr;
        s_axil_awvalid <= 1'b1;
        s_axil_wdata   <= data;
        s_axil_wstrb   <= strb;
        s_axil_wvalid  <= 1'b1;
        s_axil_bready  <= 1'b1;
        while (!(s_axil_awready && s_axil_wready && s_axil_awvalid && s_axil_wvalid))
            @(posedge clk);
        s_axil_awvalid <= 1'b0;
        s_axil_wvalid <= 1'b0;
        while (!s_axil_bvalid)
            @(posedge clk);
        if (s_axil_bresp != 2'b00)
            $display("%t Error: AXI-Lite write response addr=%08x resp=%0d", $time, addr, s_axil_bresp);
        @(posedge clk);
        s_axil_bready <= 1'b0;
    end
endtask

task axil_read;
    input [31:0] addr;
    output [31:0] data;
    begin
        @(posedge clk);
        s_axil_araddr  <= addr;
        s_axil_arvalid <= 1'b1;
        s_axil_rready  <= 1'b1;
        while (!(s_axil_arready && s_axil_arvalid))
            @(posedge clk);
        s_axil_arvalid <= 1'b0;
        while (!s_axil_rvalid)
            @(posedge clk);
        data = s_axil_rdata;
        if (s_axil_rresp != 2'b00)
            $display("%t Error: AXI-Lite read response addr=%08x resp=%0d", $time, addr, s_axil_rresp);
        @(posedge clk);
        s_axil_rready <= 1'b0;
    end
endtask

endmodule
