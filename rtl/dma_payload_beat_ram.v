`timescale 1ns/1ps

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
    output reg [DATA_WIDTH-1:0] rd_data
);

(* ram_style = RAM_STYLE *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

always @(posedge clk) begin
    if (wr_en)
        mem[wr_addr] <= wr_data;
    if (rd_en)
        rd_data <= mem[rd_addr];
end

endmodule
