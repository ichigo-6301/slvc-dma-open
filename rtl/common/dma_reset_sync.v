`timescale 1ns/1ps

// Asynchronous assertion and two-cycle synchronous deassertion for one clock
// domain. Each asynchronous domain owns an independent instance.
module dma_reset_sync(
    input  clk,
    input  arstn,
    output rstn
);

(* ASYNC_REG = "TRUE" *) reg [1:0] reset_pipe_q;

always @(posedge clk or negedge arstn) begin
    if (!arstn)
        reset_pipe_q <= 2'b00;
    else
        reset_pipe_q <= {reset_pipe_q[0], 1'b1};
end

assign rstn = reset_pipe_q[1];

endmodule
