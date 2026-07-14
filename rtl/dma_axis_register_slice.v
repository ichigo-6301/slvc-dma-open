`timescale 1ns/1ps

module dma_axis_register_slice #(
    parameter DATA_WIDTH = 512
)(
    input                   clk,
    input                   rstn,
    input  [DATA_WIDTH-1:0] s_axis_tdata,
    input                   s_axis_tvalid,
    output                  s_axis_tready,
    output [DATA_WIDTH-1:0] m_axis_tdata,
    output                  m_axis_tvalid,
    input                   m_axis_tready
);

reg [DATA_WIDTH-1:0] data_reg;
reg valid_reg;

assign s_axis_tready = !valid_reg || m_axis_tready;
assign m_axis_tdata = data_reg;
assign m_axis_tvalid = valid_reg;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        data_reg <= {DATA_WIDTH{1'b0}};
        valid_reg <= 1'b0;
    end else if (s_axis_tready) begin
        valid_reg <= s_axis_tvalid;
        if (s_axis_tvalid)
            data_reg <= s_axis_tdata;
    end
end

endmodule
