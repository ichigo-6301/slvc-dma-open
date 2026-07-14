`timescale 1ns/1ps

module dma_axis_width_pack_512 #(
    parameter integer EXT_AXIS_DATA_WIDTH = 512,
    parameter integer CORE_AXIS_DATA_WIDTH = 512
)(
    input                                clk,
    input                                rstn,
    input      [EXT_AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input                                s_axis_tvalid,
    output                               s_axis_tready,
    output     [CORE_AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output                               m_axis_tvalid,
    input                                m_axis_tready
);

function integer clog2;
    input integer value;
    integer tmp;
    begin
        tmp = value - 1;
        clog2 = 0;
        while (tmp > 0) begin
            tmp = tmp >> 1;
            clog2 = clog2 + 1;
        end
    end
endfunction

function [CORE_AXIS_DATA_WIDTH-1:0] insert_segment;
    input [CORE_AXIS_DATA_WIDTH-1:0] data_in;
    input [EXT_AXIS_DATA_WIDTH-1:0]  seg_in;
    input integer                    seg_idx;
    integer bit_i;
    begin
        insert_segment = data_in;
        for (bit_i = 0; bit_i < EXT_AXIS_DATA_WIDTH; bit_i = bit_i + 1)
            insert_segment[(seg_idx * EXT_AXIS_DATA_WIDTH) + bit_i] = seg_in[bit_i];
    end
endfunction

localparam integer BEATS_PER_CORE = CORE_AXIS_DATA_WIDTH / EXT_AXIS_DATA_WIDTH;
localparam integer PACK_COUNT_W = (BEATS_PER_CORE <= 1) ? 1 : clog2(BEATS_PER_CORE + 1);

initial begin
    if (CORE_AXIS_DATA_WIDTH != 512)
        $fatal(1, "dma_axis_width_pack_512 requires CORE_AXIS_DATA_WIDTH=512");
    if (!((EXT_AXIS_DATA_WIDTH == 64) || (EXT_AXIS_DATA_WIDTH == 128) ||
          (EXT_AXIS_DATA_WIDTH == 256) || (EXT_AXIS_DATA_WIDTH == 512)))
        $fatal(1, "EXT_AXIS_DATA_WIDTH must be 64/128/256/512");
    if ((CORE_AXIS_DATA_WIDTH % EXT_AXIS_DATA_WIDTH) != 0)
        $fatal(1, "CORE_AXIS_DATA_WIDTH must be an integer multiple of EXT_AXIS_DATA_WIDTH");
end

generate
    if (EXT_AXIS_DATA_WIDTH == CORE_AXIS_DATA_WIDTH) begin : g_passthrough
        dma_axis_register_slice #(
            .DATA_WIDTH(CORE_AXIS_DATA_WIDTH)
        ) u_axis_register_slice (
            .clk(clk),
            .rstn(rstn),
            .s_axis_tdata(s_axis_tdata),
            .s_axis_tvalid(s_axis_tvalid),
            .s_axis_tready(s_axis_tready),
            .m_axis_tdata(m_axis_tdata),
            .m_axis_tvalid(m_axis_tvalid),
            .m_axis_tready(m_axis_tready)
        );
    end else begin : g_packer
        reg [CORE_AXIS_DATA_WIDTH-1:0] pack_data_q;
        reg [PACK_COUNT_W-1:0] pack_count_q;
        reg [CORE_AXIS_DATA_WIDTH-1:0] out_data_q;
        reg                            out_valid_q;

        wire input_ready_w = !out_valid_q || m_axis_tready || (pack_count_q < (BEATS_PER_CORE - 1));
        wire input_fire_w = s_axis_tvalid && input_ready_w;
        wire output_fire_w = out_valid_q && m_axis_tready;
        wire [CORE_AXIS_DATA_WIDTH-1:0] merged_data_w = insert_segment(pack_data_q, s_axis_tdata, pack_count_q);
        wire pack_complete_w = input_fire_w && (pack_count_q == (BEATS_PER_CORE - 1));

        assign s_axis_tready = input_ready_w;
        assign m_axis_tdata = out_data_q;
        assign m_axis_tvalid = out_valid_q;

        always @(posedge clk or negedge rstn) begin
            if (!rstn) begin
                pack_data_q <= {CORE_AXIS_DATA_WIDTH{1'b0}};
                pack_count_q <= {PACK_COUNT_W{1'b0}};
                out_data_q <= {CORE_AXIS_DATA_WIDTH{1'b0}};
                out_valid_q <= 1'b0;
            end else begin
                if (output_fire_w)
                    out_valid_q <= 1'b0;

                if (input_fire_w) begin
                    if (pack_complete_w) begin
                        out_data_q <= merged_data_w;
                        out_valid_q <= 1'b1;
                        pack_data_q <= {CORE_AXIS_DATA_WIDTH{1'b0}};
                        pack_count_q <= {PACK_COUNT_W{1'b0}};
                    end else begin
                        pack_data_q <= merged_data_w;
                        pack_count_q <= pack_count_q + 1'b1;
                    end
                end
            end
        end
    end
endgenerate

endmodule
