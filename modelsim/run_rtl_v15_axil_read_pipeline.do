transcript on

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../rtl/control/dma_axil_regs.v \
    ../rtl/tx/dma_tx_channel_table.v \
    ../rtl/rx/dma_rx_channel_table.v \
    ../pattern/tb_rtl_v15_axil_read_pipeline.v

vsim work.tb
onfinish stop
run -all
quit -f
