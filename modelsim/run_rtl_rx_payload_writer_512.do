transcript on
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../rtl/rx/dma_axi_write_engine_512.v \
    ../pattern/tb_rtl_rx_payload_writer_512.v
vsim -c work.tb_rtl_rx_payload_writer_512
onfinish stop
run -all
quit -f
