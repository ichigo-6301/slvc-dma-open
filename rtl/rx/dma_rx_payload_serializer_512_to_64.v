`timescale 1ns/1ps

// Memory-domain serializer. One committed 512-bit payload entry is held while
// up to eight ordered 64-bit lanes are emitted. A replacement 512-bit entry
// can be accepted on the same cycle as the final lane to avoid an inter-entry
// bubble when the downstream writer remains ready.
module dma_rx_payload_serializer_512_to_64(
    input               clk,
    input               rstn,
    input               soft_reset,

    input               s_tvalid,
    output              s_tready,
    input      [511:0]  s_tdata,
    input      [63:0]   s_tkeep,
    input               s_tlast,

    output              m_tvalid,
    input               m_tready,
    output     [63:0]   m_tdata,
    output      [7:0]   m_tkeep,
    output              m_tlast,
    output      [3:0]   held_beats,
    output reg          format_error,
    output              busy
);

reg [511:0] data_q;
reg [63:0] keep_q;
reg last_q;
reg [3:0] lane_count_q;
reg [2:0] lane_index_q;
reg valid_q;

wire lane_last = valid_q && ({1'b0, lane_index_q} + 1'b1 >= lane_count_q);
wire m_fire = m_tvalid && m_tready;
wire s_fire = s_tvalid && s_tready;

assign m_tvalid = valid_q;
assign m_tdata = data_q[lane_index_q*64 +: 64];
assign m_tkeep = keep_q[lane_index_q*8 +: 8];
assign m_tlast = last_q && lane_last;
assign s_tready = !valid_q || (m_fire && lane_last);
assign held_beats = valid_q ? (lane_count_q - {1'b0, lane_index_q}) : 4'h0;
assign busy = valid_q;

function [3:0] lanes_for_keep;
    input [63:0] keep;
    integer lane_i;
    begin
        lanes_for_keep = 4'd1;
        for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1)
            if (keep[lane_i*8 +: 8] != 8'h00)
                lanes_for_keep = lane_i + 1;
    end
endfunction

function keep_is_contiguous;
    input [63:0] keep;
    reg [63:0] keep_plus_one;
    begin
        keep_plus_one = keep + 1'b1;
        keep_is_contiguous = (keep != 0) && ((keep & keep_plus_one) == 0);
    end
endfunction

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        data_q <= 512'h0;
        keep_q <= 64'h0;
        last_q <= 1'b0;
        lane_count_q <= 4'h0;
        lane_index_q <= 3'h0;
        valid_q <= 1'b0;
        format_error <= 1'b0;
    end else if (soft_reset) begin
        data_q <= 512'h0;
        keep_q <= 64'h0;
        last_q <= 1'b0;
        lane_count_q <= 4'h0;
        lane_index_q <= 3'h0;
        valid_q <= 1'b0;
        format_error <= 1'b0;
    end else begin
        if (s_fire) begin
            data_q <= s_tdata;
            keep_q <= s_tkeep;
            last_q <= s_tlast;
            lane_count_q <= lanes_for_keep(s_tkeep);
            lane_index_q <= 3'h0;
            valid_q <= 1'b1;
            if (!keep_is_contiguous(s_tkeep) ||
                (!s_tlast && (s_tkeep != 64'hffff_ffff_ffff_ffff)))
                format_error <= 1'b1;
        end else if (m_fire) begin
            if (lane_last) begin
                valid_q <= 1'b0;
                lane_index_q <= 3'h0;
            end else begin
                lane_index_q <= lane_index_q + 1'b1;
            end
        end
    end
end

endmodule
