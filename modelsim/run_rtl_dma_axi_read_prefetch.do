transcript on
onerror {quit -code 1}
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../rtl/tx/dma_axi_read_prefetch.v \
    ../pattern/tb_rtl_dma_axi_read_prefetch.v
vsim -c work.tb_rtl_dma_axi_read_prefetch
onfinish stop
run -all
quit -f
