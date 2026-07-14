`timescale 1ns/1ps
`include "dma_sim_def.vh"

module rx_axis_bfm(
    output reg [511:0] rx_axis_tdata,
    output reg         rx_axis_tvalid,
    input              rx_axis_tready,
    input              clk,
    input              rstn
);

integer byte_i;

initial begin
    rx_axis_tdata  = 512'h0;
    rx_axis_tvalid = 1'b0;
end

task send_beat;
    input [511:0] beat;
    begin
        @(negedge clk);
        rx_axis_tdata  = beat;
        rx_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!rx_axis_tready)
            @(posedge clk);
        @(negedge clk);
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata  = 512'h0;
    end
endtask

task send_beat_force;
    input [511:0] beat;
    begin
        @(negedge clk);
        rx_axis_tdata  = beat;
        rx_axis_tvalid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rx_axis_tvalid = 1'b0;
        rx_axis_tdata  = 512'h0;
    end
endtask

task send_frame;
    input [511:0] header_beat;
    input [31:0] payload_src_addr;
    input [31:0] payload_len;
    integer sent;
    integer idx;
    reg [511:0] beat;
    begin
        send_beat(header_beat);
        sent = 0;
        while (sent < payload_len) begin
            beat = 512'h0;
            for (idx = 0; idx < 64; idx = idx + 1) begin
                if ((sent + idx) < payload_len)
                    beat[idx*8 +: 8] = `DMA_PKT_MEM_PATH[payload_src_addr + sent + idx];
            end
            send_beat(beat);
            sent = sent + 64;
        end
    end
endtask

task send_frame_force;
    input [511:0] header_beat;
    input [31:0] payload_src_addr;
    input [31:0] payload_len;
    integer sent;
    integer idx;
    reg [511:0] beat;
    begin
        send_beat_force(header_beat);
        sent = 0;
        while (sent < payload_len) begin
            beat = 512'h0;
            for (idx = 0; idx < 64; idx = idx + 1) begin
                if ((sent + idx) < payload_len)
                    beat[idx*8 +: 8] = `DMA_PKT_MEM_PATH[payload_src_addr + sent + idx];
            end
            send_beat_force(beat);
            sent = sent + 64;
        end
    end
endtask

endmodule
