transcript on
onerror {quit -code 1}
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +define+DMA_ENABLE_FRAME_SHARED_POOL_DRAIN_PIPELINE=1 +incdir+../rtl +incdir+../pattern ../rtl/dma_frame_payload_ram.v ../rtl/dma_frame_shared_pool.v ../pattern/tb_rtl_v33e19_shared_frame_pool.v
vsim work.tb
onfinish stop
run -all
quit -f
