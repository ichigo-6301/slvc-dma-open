transcript on
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog +incdir+../rtl +incdir+../pattern \
    ../rtl/dma_rx_parser.v \
    ../rtl/dma_rx_parser_pipe.v \
    ../rtl/dma_rx_channel_match.v \
    ../rtl/dma_rx_payload_buffer.v \
    ../rtl/dma_rx_ingress_queue.v \
    ../rtl/dma_payload_beat_ram.v \
    ../rtl/dma_rx_fc_ingress_bank.v \
    ../rtl/dma_rx_fc_ctrl.v \
    ../rtl/dma_axi_write_engine.v \
    ../rtl/dma_tx_header_builder.v \
    ../rtl/dma_axi_read_prefetch.v \
    ../rtl/dma_tx_engine.v \
    ../rtl/dma_cq_writer.v \
    ../rtl/dma_rx_write_arbiter.v \
    ../rtl/dma_ufc_mailbox.v \
    ../rtl/dma_axil_regs.v \
    ../rtl/dma_tx_channel_table.v \
    ../rtl/dma_rx_channel_table.v \
    ../rtl/dma_tx_desc_channel_table.v \
    ../rtl/dma_frame_payload_ram.v \
    ../rtl/dma_frame_shared_pool.v \
    ../rtl/dma_rx_frame_shared_adapter.v \
    ../rtl/dma_rx_ingress_source_selector.v \
    ../rtl/frame_dma_rx_top.v \
    ../pattern/dma_ref_model.v \
    ../pattern/axi_lite_master_model.v \
    ../pattern/rx_axis_bfm.v \
    ../pattern/axi64_slave_model.v \
    ../pattern/tb_rtl_v33e20a_hybrid_rx_ingress_minimal.v

vsim work.tb
onfinish stop
run -all
quit -f
