transcript on
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +define+DMA_ENABLE_AXI_WRITE_AW_PLAN_PIPELINE=1 +define+DMA_ENABLE_AXI_WRITE_W_PREFETCH_FIFO=1 +define+DMA_ENABLE_FRAME_SHARED_RD_REQ_QUEUE=1 +define+DMA_ENABLE_FRAME_SHARED_POOL_DRAIN_PIPELINE=1 +incdir+../rtl +incdir+../pattern \
    ../rtl/dma_axi_write_engine.v \
    ../pattern/tb_rtl_v33e20a23_w_prefetch_fifo.v
vsim work.tb
onfinish stop
run -all
quit -f
