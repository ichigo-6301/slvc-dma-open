`timescale 1ns/1ps
`include "dma_defs.vh"

`ifndef DMA_A3_CHANNELS
`define DMA_A3_CHANNELS 4
`endif
`ifndef DMA_A3_PAYLOAD_WORDS
`define DMA_A3_PAYLOAD_WORDS 512
`endif
`ifndef DMA_A3_PAYLOAD_AW
`define DMA_A3_PAYLOAD_AW 9
`endif

module tb_dma_a3_config_contract;

integer checks = 0;

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

initial begin
    expect(`DMA_MAX_CH == `DMA_A3_CHANNELS, "DMA_MAX_CH mismatch");
    expect(`DMA_RX_CH_NUM == `DMA_A3_CHANNELS, "DMA_RX_CH_NUM mismatch");
    expect(`DMA_TX_CH_NUM == `DMA_A3_CHANNELS, "DMA_TX_CH_NUM mismatch");
    expect(`DMA_RX_CH_NUM <= `DMA_MAX_CH, "RX channel count exceeds maximum");
    expect(`DMA_TX_CH_NUM <= `DMA_MAX_CH, "TX channel count exceeds maximum");
    expect(`DMA_RX_FC_INGRESS_PAYLOAD_WORDS == `DMA_A3_PAYLOAD_WORDS,
           "payload word depth mismatch");
    expect(`DMA_RX_FC_INGRESS_PAYLOAD_AW == `DMA_A3_PAYLOAD_AW,
           "payload address width mismatch");
    expect(`DMA_RX_FC_INGRESS_META_DEPTH == 2, "metadata depth mismatch");
    expect(`DMA_RX_FC_INGRESS_META_AW == 1, "metadata address width mismatch");
    expect(`DMA_REG_RX_CH_NUM == 12'h018, "RX channel-count register moved");
    expect(`DMA_REG_TX_CH_NUM == 12'h01c, "TX channel-count register moved");
    expect(`DMA_REG_RX_CH_NUM != `DMA_REG_TX_CH_NUM,
           "RX/TX channel-count registers alias");
    expect((`DMA_A3_PAYLOAD_WORDS == (1 << `DMA_A3_PAYLOAD_AW)),
           "payload depth/address width are inconsistent");
    $display("PASS tb_dma_a3_config_contract channels=%0d payload_words=%0d payload_aw=%0d checks=%0d",
             `DMA_A3_CHANNELS, `DMA_A3_PAYLOAD_WORDS,
             `DMA_A3_PAYLOAD_AW, checks);
    $finish;
end

endmodule
