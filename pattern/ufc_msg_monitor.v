`timescale 1ns/1ps
`include "dma_defs.vh"

module ufc_msg_monitor #(
    parameter integer TX_READY_STALL_MOD = 0
)(
    input             clk,
    input             rstn,
    input             ufc_tx_valid,
    output            ufc_tx_ready,
    input      [7:0]  ufc_tx_opcode,
    input      [15:0] ufc_tx_flow_id,
    input      [31:0] ufc_tx_arg0,
    input      [31:0] ufc_tx_arg1,
    output reg        ufc_rx_valid,
    input             ufc_rx_ready,
    output reg [7:0]  ufc_rx_opcode,
    output reg [15:0] ufc_rx_flow_id,
    output reg [31:0] ufc_rx_arg0,
    output reg [31:0] ufc_rx_arg1,
    output reg [31:0] pause_count,
    output reg [31:0] resume_count,
    output reg [7:0]  last_opcode,
    output reg [15:0] last_flow_id,
    output reg [31:0] last_arg0,
    output reg [31:0] last_arg1
);

integer cycle_count;
wire stall = (TX_READY_STALL_MOD > 1) && ((cycle_count % TX_READY_STALL_MOD) == (TX_READY_STALL_MOD - 1));
assign ufc_tx_ready = rstn && !stall;

task send_rx_msg;
    input [7:0] opcode;
    input [15:0] flow_id;
    input [31:0] arg0;
    input [31:0] arg1;
    integer guard;
    begin
        guard = 0;
        @(posedge clk);
        ufc_rx_opcode <= opcode;
        ufc_rx_flow_id <= flow_id;
        ufc_rx_arg0 <= arg0;
        ufc_rx_arg1 <= arg1;
        ufc_rx_valid <= 1'b1;
        while (!ufc_rx_ready && (guard < 1000)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        @(posedge clk);
        ufc_rx_valid <= 1'b0;
    end
endtask

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ufc_rx_valid <= 1'b0;
        ufc_rx_opcode <= 8'h0;
        ufc_rx_flow_id <= 16'h0;
        ufc_rx_arg0 <= 32'h0;
        ufc_rx_arg1 <= 32'h0;
        pause_count <= 32'h0;
        resume_count <= 32'h0;
        last_opcode <= 8'h0;
        last_flow_id <= 16'h0;
        last_arg0 <= 32'h0;
        last_arg1 <= 32'h0;
        cycle_count <= 0;
    end else begin
        cycle_count <= cycle_count + 1;
        if (ufc_rx_valid && ufc_rx_ready)
            ufc_rx_valid <= 1'b0;

        if (ufc_tx_valid && ufc_tx_ready) begin
            last_opcode <= ufc_tx_opcode;
            last_flow_id <= ufc_tx_flow_id;
            last_arg0 <= ufc_tx_arg0;
            last_arg1 <= ufc_tx_arg1;
            if (ufc_tx_opcode == `DMA_UFC_OP_PAUSE)
                pause_count <= pause_count + 1'b1;
            if (ufc_tx_opcode == `DMA_UFC_OP_RESUME)
                resume_count <= resume_count + 1'b1;
        end
    end
end

endmodule
