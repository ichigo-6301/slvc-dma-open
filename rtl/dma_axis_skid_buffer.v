`timescale 1ns/1ps

module dma_axis_skid_buffer #(
    parameter integer DATA_WIDTH = 512
)(
    input                       clk,
    input                       rstn,
    input                       soft_reset,
    input      [DATA_WIDTH-1:0] s_axis_tdata,
    input                       s_axis_tvalid,
    output                      s_axis_tready,
    output     [DATA_WIDTH-1:0] m_axis_tdata,
    output                      m_axis_tvalid,
    input                       m_axis_tready
);

reg [DATA_WIDTH-1:0] data_mem [0:3];
reg [1:0] wr_ptr_q;
reg [1:0] rd_ptr_q;
reg [2:0] count_q;
reg s_ready_q;

wire write_fire = s_axis_tvalid && s_ready_q;
wire read_fire = (count_q != 3'd0) && m_axis_tready;

reg [2:0] count_next;

assign s_axis_tready = s_ready_q;
assign m_axis_tvalid = (count_q != 3'd0);
assign m_axis_tdata = data_mem[rd_ptr_q];

always @(*) begin
    count_next = count_q;
    case ({write_fire, read_fire})
    2'b10: if (count_q != 3'd4) count_next = count_q + 1'b1;
    2'b01: if (count_q != 3'd0) count_next = count_q - 1'b1;
    default: count_next = count_q;
    endcase
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        wr_ptr_q <= 2'd0;
        rd_ptr_q <= 2'd0;
        count_q <= 3'd0;
        s_ready_q <= 1'b1;
    end else if (soft_reset) begin
        wr_ptr_q <= 2'd0;
        rd_ptr_q <= 2'd0;
        count_q <= 3'd0;
        s_ready_q <= 1'b1;
    end else begin
        if (write_fire) begin
            data_mem[wr_ptr_q] <= s_axis_tdata;
            wr_ptr_q <= wr_ptr_q + 1'b1;
        end
        if (read_fire)
            rd_ptr_q <= rd_ptr_q + 1'b1;
        count_q <= count_next;
        s_ready_q <= (count_q < 3'd3);
    end
end

endmodule
