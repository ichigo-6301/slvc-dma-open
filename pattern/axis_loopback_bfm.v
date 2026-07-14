`timescale 1ns/1ps

module axis_loopback_bfm #(
    parameter integer LOOP_LATENCY = 0,
    parameter integer TX_STALL_MOD = 0,
    parameter integer RX_GAP_MOD   = 0,
    parameter integer FIFO_DEPTH   = 16
)(
    input             clk,
    input             rstn,
    input      [511:0] tx_axis_tdata,
    input              tx_axis_tvalid,
    output             tx_axis_tready,
    output reg [511:0] rx_axis_tdata,
    output reg         rx_axis_tvalid,
    input              rx_axis_tready,
    output reg [31:0]  tx_beat_count,
    output reg [31:0]  rx_beat_count
);

reg [511:0] fifo_data [0:FIFO_DEPTH-1];
reg [31:0]  fifo_delay [0:FIFO_DEPTH-1];
integer wr_ptr;
integer rd_ptr;
integer count;
integer cycle_count;
integer i;
reg push_fire;
reg pop_fire;

wire fifo_full = (count == FIFO_DEPTH);
wire tx_stall = (TX_STALL_MOD > 1) && ((cycle_count % TX_STALL_MOD) == (TX_STALL_MOD - 1));
wire rx_gap = (RX_GAP_MOD > 1) && ((cycle_count % RX_GAP_MOD) == (RX_GAP_MOD - 1));
assign tx_axis_tready = rstn && !fifo_full && !tx_stall;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        rx_axis_tdata <= 512'h0;
        rx_axis_tvalid <= 1'b0;
        tx_beat_count <= 32'h0;
        rx_beat_count <= 32'h0;
        wr_ptr <= 0;
        rd_ptr <= 0;
        count <= 0;
        cycle_count <= 0;
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            fifo_data[i] <= 512'h0;
            fifo_delay[i] <= 32'h0;
        end
    end else begin
        cycle_count <= cycle_count + 1;
        push_fire = tx_axis_tvalid && tx_axis_tready;
        pop_fire = rx_axis_tvalid && rx_axis_tready;

        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            if (fifo_delay[i] != 0)
                fifo_delay[i] <= fifo_delay[i] - 1'b1;
        end

        if (push_fire) begin
            fifo_data[wr_ptr] <= tx_axis_tdata;
            fifo_delay[wr_ptr] <= LOOP_LATENCY;
            wr_ptr <= (wr_ptr + 1) % FIFO_DEPTH;
            tx_beat_count <= tx_beat_count + 1'b1;
        end

        if (pop_fire) begin
            rx_axis_tvalid <= 1'b0;
            rx_beat_count <= rx_beat_count + 1'b1;
            rd_ptr <= (rd_ptr + 1) % FIFO_DEPTH;
        end else if (!rx_axis_tvalid && (count != 0) && (fifo_delay[rd_ptr] == 0) && !rx_gap) begin
            rx_axis_tdata <= fifo_data[rd_ptr];
            rx_axis_tvalid <= 1'b1;
        end

        case ({push_fire, pop_fire})
        2'b10: count <= count + 1;
        2'b01: count <= count - 1;
        default: count <= count;
        endcase
    end
end

endmodule
