transcript on
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../rtl/common/dma_async_fifo.v \
    ../rtl/common/dma_async_fifo_tech.v \
    ../rtl/rx/dma_rx_payload_cdc_bridge.v \
    ../pattern/tb_rtl_rx_payload_cdc_bridge.v
vsim -c work.tb_rtl_rx_payload_cdc_bridge
onfinish stop
run -all
quit -f
