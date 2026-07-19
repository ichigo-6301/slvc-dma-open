transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog +define+DMA_RX_MEM_ASYNC512_PROFILE +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../rtl/common/dma_reset_sync.v \
    ../rtl/common/dma_async_fifo.v \
    ../rtl/common/dma_async_fifo_tech.v \
    ../rtl/rx/dma_rx_payload_cdc_bridge.v \
    ../rtl/rx/dma_axi_write_engine_512.v \
    ../pattern/tb_rtl_rx_mem_async_backend.v
vsim -c work.tb_rtl_rx_mem_async_backend
onfinish stop
run -all
quit -f
