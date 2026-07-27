`timescale 1ns/1ps

// Flow-only register banking for bounded DC elaboration.
// The production RTL remains unchanged; this module preserves its
// synchronous read and nonblocking read-during-write behavior.
module dma_payload_beat_ram #(
    parameter DATA_WIDTH = 512,
    parameter DEPTH      = 128,
    parameter ADDR_WIDTH = 7,
    parameter RAM_STYLE  = "block"
)(
    input                       clk,
    input                       wr_en,
    input      [ADDR_WIDTH-1:0] wr_addr,
    input      [DATA_WIDTH-1:0] wr_data,
    input                       rd_en,
    input      [ADDR_WIDTH-1:0] rd_addr,
    output     [DATA_WIDTH-1:0] rd_data
);

reg [127:0] wb0_db0_mem [0:63];
reg [127:0] wb0_db1_mem [0:63];
reg [127:0] wb0_rd_data;
always @(posedge clk) begin
    if (wr_en) begin
        case (wr_addr[6:6])
            1'd0: wb0_db0_mem[wr_addr[5:0]] <= wr_data[127:0];
            1'd1: wb0_db1_mem[wr_addr[5:0]] <= wr_data[127:0];
            default: ;
        endcase
    end
    if (rd_en) begin
        case (rd_addr[6:6])
            1'd0: wb0_rd_data <= wb0_db0_mem[rd_addr[5:0]];
            1'd1: wb0_rd_data <= wb0_db1_mem[rd_addr[5:0]];
            default: ;
        endcase
    end
end
assign rd_data[127:0] = wb0_rd_data;

reg [127:0] wb1_db0_mem [0:63];
reg [127:0] wb1_db1_mem [0:63];
reg [127:0] wb1_rd_data;
always @(posedge clk) begin
    if (wr_en) begin
        case (wr_addr[6:6])
            1'd0: wb1_db0_mem[wr_addr[5:0]] <= wr_data[255:128];
            1'd1: wb1_db1_mem[wr_addr[5:0]] <= wr_data[255:128];
            default: ;
        endcase
    end
    if (rd_en) begin
        case (rd_addr[6:6])
            1'd0: wb1_rd_data <= wb1_db0_mem[rd_addr[5:0]];
            1'd1: wb1_rd_data <= wb1_db1_mem[rd_addr[5:0]];
            default: ;
        endcase
    end
end
assign rd_data[255:128] = wb1_rd_data;

reg [127:0] wb2_db0_mem [0:63];
reg [127:0] wb2_db1_mem [0:63];
reg [127:0] wb2_rd_data;
always @(posedge clk) begin
    if (wr_en) begin
        case (wr_addr[6:6])
            1'd0: wb2_db0_mem[wr_addr[5:0]] <= wr_data[383:256];
            1'd1: wb2_db1_mem[wr_addr[5:0]] <= wr_data[383:256];
            default: ;
        endcase
    end
    if (rd_en) begin
        case (rd_addr[6:6])
            1'd0: wb2_rd_data <= wb2_db0_mem[rd_addr[5:0]];
            1'd1: wb2_rd_data <= wb2_db1_mem[rd_addr[5:0]];
            default: ;
        endcase
    end
end
assign rd_data[383:256] = wb2_rd_data;

reg [127:0] wb3_db0_mem [0:63];
reg [127:0] wb3_db1_mem [0:63];
reg [127:0] wb3_rd_data;
always @(posedge clk) begin
    if (wr_en) begin
        case (wr_addr[6:6])
            1'd0: wb3_db0_mem[wr_addr[5:0]] <= wr_data[511:384];
            1'd1: wb3_db1_mem[wr_addr[5:0]] <= wr_data[511:384];
            default: ;
        endcase
    end
    if (rd_en) begin
        case (rd_addr[6:6])
            1'd0: wb3_rd_data <= wb3_db0_mem[rd_addr[5:0]];
            1'd1: wb3_rd_data <= wb3_db1_mem[rd_addr[5:0]];
            default: ;
        endcase
    end
end
assign rd_data[511:384] = wb3_rd_data;

endmodule
