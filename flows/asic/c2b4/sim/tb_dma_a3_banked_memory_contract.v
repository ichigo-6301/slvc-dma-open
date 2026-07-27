`timescale 1ns/1ps

`ifndef DMA_A3_FIXED_DEPTH
`define DMA_A3_FIXED_DEPTH 128
`endif
`ifndef DMA_A3_FIXED_DEPTH_AW
`define DMA_A3_FIXED_DEPTH_AW 7
`endif

module tb_dma_a3_banked_memory_contract;

localparam integer FIXED_DEPTH = `DMA_A3_FIXED_DEPTH;
localparam integer FIXED_AW = `DMA_A3_FIXED_DEPTH_AW;
localparam integer DEPTH_BANKS = FIXED_DEPTH / 64;
localparam integer ARRAY_COUNT = 4 * DEPTH_BANKS;

reg clk = 1'b0;
always #5 clk = ~clk;

reg fixed_wr_en = 1'b0;
reg [FIXED_AW-1:0] fixed_wr_addr = {FIXED_AW{1'b0}};
reg [511:0] fixed_wr_data = 512'h0;
reg fixed_rd_en = 1'b0;
reg [FIXED_AW-1:0] fixed_rd_addr = {FIXED_AW{1'b0}};
wire [511:0] fixed_rd_data;

reg shared_wr_en = 1'b0;
reg [5:0] shared_wr_addr = 6'h0;
reg [511:0] shared_wr_data = 512'h0;
reg [63:0] shared_wr_keep = 64'h0;
reg shared_rd_en = 1'b0;
reg [5:0] shared_rd_addr = 6'h0;
wire [511:0] shared_rd_data;
wire [63:0] shared_rd_keep;

integer checks = 0;
integer index;
reg [511:0] old_value;
reg [511:0] new_value;
reg [511:0] width_pattern;

dma_payload_beat_ram #(
    .DATA_WIDTH(512),
    .DEPTH(FIXED_DEPTH),
    .ADDR_WIDTH(FIXED_AW)
) u_fixed (
    .clk(clk),
    .wr_en(fixed_wr_en),
    .wr_addr(fixed_wr_addr),
    .wr_data(fixed_wr_data),
    .rd_en(fixed_rd_en),
    .rd_addr(fixed_rd_addr),
    .rd_data(fixed_rd_data)
);

dma_frame_payload_ram #(
    .BLOCK_NUM(64),
    .BLOCK_AW(6),
    .DATA_W(512),
    .KEEP_W(64)
) u_shared (
    .clk(clk),
    .wr_en(shared_wr_en),
    .wr_addr(shared_wr_addr),
    .wr_data(shared_wr_data),
    .wr_keep(shared_wr_keep),
    .rd_en(shared_rd_en),
    .rd_addr(shared_rd_addr),
    .rd_data(shared_rd_data),
    .rd_keep(shared_rd_keep)
);

function [511:0] pattern;
    input [7:0] seed;
    integer lane;
    begin
        pattern = 512'h0;
        for (lane = 0; lane < 4; lane = lane + 1)
            pattern[lane*128 +: 128] = {
                seed, lane[7:0], 16'hc2b4, 32'h1020_3040,
                32'h5060_7080, 32'h90a0_b0c0
            };
    end
endfunction

task expect;
    input condition;
    input [511:0] message;
    begin
        if (!condition) begin
            $display("Error: %0s", message);
            $finish;
        end
        checks = checks + 1;
    end
endtask

task fixed_write;
    input integer address;
    input [511:0] data;
    begin
        @(negedge clk);
        fixed_wr_en = 1'b1;
        fixed_wr_addr = address[FIXED_AW-1:0];
        fixed_wr_data = data;
        @(posedge clk);
        @(negedge clk);
        fixed_wr_en = 1'b0;
    end
endtask

task fixed_read_check;
    input integer address;
    input [511:0] expected;
    begin
        @(negedge clk);
        fixed_rd_en = 1'b1;
        fixed_rd_addr = address[FIXED_AW-1:0];
        @(posedge clk);
        @(negedge clk);
        fixed_rd_en = 1'b0;
        expect(fixed_rd_data === expected, "fixed banked RAM read mismatch");
    end
endtask

task shared_write;
    input integer address;
    input [511:0] data;
    input [63:0] keep;
    begin
        @(negedge clk);
        shared_wr_en = 1'b1;
        shared_wr_addr = address[5:0];
        shared_wr_data = data;
        shared_wr_keep = keep;
        @(posedge clk);
        @(negedge clk);
        shared_wr_en = 1'b0;
    end
endtask

task shared_read_check;
    input integer address;
    input [511:0] expected_data;
    input [63:0] expected_keep;
    begin
        @(negedge clk);
        shared_rd_en = 1'b1;
        shared_rd_addr = address[5:0];
        @(posedge clk);
        @(negedge clk);
        shared_rd_en = 1'b0;
        expect(shared_rd_data === expected_data, "shared payload read mismatch");
        expect(shared_rd_keep === expected_keep, "shared keep read mismatch");
    end
endtask

initial begin
    if ((FIXED_DEPTH % 64) != 0 || FIXED_DEPTH != (1 << FIXED_AW))
        expect(1'b0, "fixed depth banking contract mismatch");
    repeat (3) @(posedge clk);

    for (index = 0; index < DEPTH_BANKS; index = index + 1) begin
        fixed_write(index * 64, pattern(8'h10 + index * 2));
        fixed_write(index * 64 + 63, pattern(8'h11 + index * 2));
    end
    for (index = 0; index < DEPTH_BANKS; index = index + 1) begin
        fixed_read_check(index * 64, pattern(8'h10 + index * 2));
        fixed_read_check(index * 64 + 63, pattern(8'h11 + index * 2));
    end

    old_value = pattern(8'ha1);
    new_value = pattern(8'ha2);
    fixed_write(5, old_value);
    fixed_write(6, pattern(8'hb1));
    @(negedge clk);
    fixed_wr_en = 1'b1;
    fixed_wr_addr = 5;
    fixed_wr_data = new_value;
    fixed_rd_en = 1'b1;
    fixed_rd_addr = 6;
    @(posedge clk);
    @(negedge clk);
    fixed_wr_en = 1'b0;
    fixed_rd_en = 1'b0;
    expect(fixed_rd_data === pattern(8'hb1),
           "different-address simultaneous read/write mismatch");

    @(negedge clk);
    fixed_wr_en = 1'b1;
    fixed_wr_addr = 5;
    fixed_wr_data = pattern(8'ha3);
    fixed_rd_en = 1'b1;
    fixed_rd_addr = 5;
    @(posedge clk);
    @(negedge clk);
    fixed_wr_en = 1'b0;
    fixed_rd_en = 1'b0;
    expect(fixed_rd_data === new_value,
           "fixed same-address read/write did not return old data");
    fixed_read_check(5, pattern(8'ha3));

    shared_write(0, pattern(8'h20), 64'hffff_ffff_ffff_ffff);
    shared_write(63, pattern(8'h2f), 64'h0000_0000_0000_ffff);
    shared_read_check(0, pattern(8'h20), 64'hffff_ffff_ffff_ffff);
    shared_read_check(63, pattern(8'h2f), 64'h0000_0000_0000_ffff);

    shared_write(7, pattern(8'h70), 64'h00ff_00ff_00ff_00ff);
    @(negedge clk);
    shared_wr_en = 1'b1;
    shared_wr_addr = 7;
    shared_wr_data = pattern(8'h71);
    shared_wr_keep = 64'h0f0f_0f0f_0f0f_0f0f;
    shared_rd_en = 1'b1;
    shared_rd_addr = 7;
    @(posedge clk);
    @(negedge clk);
    shared_wr_en = 1'b0;
    shared_rd_en = 1'b0;
    expect(shared_rd_data === pattern(8'h70),
           "shared same-address read/write did not return old payload");
    expect(shared_rd_keep === 64'h00ff_00ff_00ff_00ff,
           "shared same-address read/write did not return old keep");
    shared_read_check(7, pattern(8'h71), 64'h0f0f_0f0f_0f0f_0f0f);

    width_pattern = pattern(8'he0);
    for (index = 0; index < 4; index = index + 1)
        expect(width_pattern[index*128 +: 128] !==
               width_pattern[((index + 1) & 3)*128 +: 128],
               "width-bank pattern slices are not distinct");

    $display("PASS tb_dma_a3_banked_memory_contract depth=%0d width_banks=4 depth_banks=%0d arrays=%0d checks=%0d",
             FIXED_DEPTH, DEPTH_BANKS, ARRAY_COUNT, checks);
    $finish;
end

endmodule
