`timescale 1ns/1ps

// Flow-only width banking for the shared-pool register payload.
module dma_frame_payload_ram #(
    parameter integer BLOCK_NUM = 64,
    parameter integer BLOCK_AW = 6,
    parameter integer DATA_W = 512,
    parameter integer KEEP_W = 64
)(
    input  wire                clk,
    input  wire                wr_en,
    input  wire [BLOCK_AW-1:0] wr_addr,
    input  wire [DATA_W-1:0]   wr_data,
    input  wire [KEEP_W-1:0]   wr_keep,
    input  wire                rd_en,
    input  wire [BLOCK_AW-1:0] rd_addr,
    output reg  [DATA_W-1:0]   rd_data,
    output reg  [KEEP_W-1:0]   rd_keep
);

reg [127:0] payload_wb0_mem [0:63];
reg [127:0] payload_wb1_mem [0:63];
reg [127:0] payload_wb2_mem [0:63];
reg [127:0] payload_wb3_mem [0:63];
reg [63:0] keep_mem [0:63];

always @(posedge clk) begin
    if (wr_en) begin
        payload_wb0_mem[wr_addr] <= wr_data[127:0];
        payload_wb1_mem[wr_addr] <= wr_data[255:128];
        payload_wb2_mem[wr_addr] <= wr_data[383:256];
        payload_wb3_mem[wr_addr] <= wr_data[511:384];
        keep_mem[wr_addr] <= wr_keep;
    end
    if (rd_en) begin
        rd_data[127:0] <= payload_wb0_mem[rd_addr];
        rd_data[255:128] <= payload_wb1_mem[rd_addr];
        rd_data[383:256] <= payload_wb2_mem[rd_addr];
        rd_data[511:384] <= payload_wb3_mem[rd_addr];
        rd_keep <= keep_mem[rd_addr];
    end
end

endmodule
