transcript on
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog +define+DMA_RX_WIDE_PAYLOAD_PROFILE +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../rtl/rx/dma_rx_parser.v \
    ../rtl/rx/dma_rx_parser_pipe.v \
    ../rtl/rx/dma_rx_channel_match.v \
    ../rtl/rx/dma_rx_payload_buffer.v \
    ../rtl/rx/dma_rx_ingress_queue.v \
    ../rtl/common/dma_payload_beat_ram.v \
    ../rtl/rx/dma_rx_fc_ingress_bank.v \
    ../rtl/rx/dma_rx_fc_ctrl.v \
    ../rtl/rx/dma_axi_write_engine.v \
    ../rtl/rx/dma_axi_write_engine_512.v \
    ../rtl/tx/dma_tx_header_builder.v \
    ../rtl/tx/dma_axi_read_prefetch.v \
    ../rtl/tx/dma_tx_engine.v \
    ../rtl/cq/dma_cq_writer.v \
    ../rtl/cq/dma_cq_single_writer.v \
    ../rtl/rx/dma_rx_write_arbiter.v \
    ../rtl/control/dma_ufc_mailbox.v \
    ../rtl/control/dma_axil_regs.v \
    ../rtl/tx/dma_tx_channel_table.v \
    ../rtl/rx/dma_rx_channel_table.v \
    ../rtl/tx/dma_tx_desc_channel_table.v \
    ../rtl/rx/dma_frame_payload_ram.v \
    ../rtl/rx/dma_frame_shared_pool.v \
    ../rtl/rx/dma_rx_frame_shared_adapter.v \
    ../rtl/rx/dma_rx_ingress_source_selector.v \
    ../rtl/integration/frame_dma_rx_top.v \
    ../pattern/dma_ref_model.v \
    ../pattern/axi_lite_master_model.v \
    ../pattern/rx_axis_bfm.v \
    ../pattern/axi64_slave_model.v \
    ../pattern/axi512_write_slave_model.v \
    ../pattern/tb_rtl_v33e20a_hybrid_rx_ingress_minimal.v

vsim work.tb
onfinish stop
run -all
quit -f
