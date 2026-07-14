transcript on

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog +incdir+../rtl +incdir+../pattern \
    ../rtl/dma_axis_register_slice.v \
    ../rtl/dma_rx_parser_pipe.v \
    ../pattern/tb_rtl_v13_parser_pipeline.v

vsim work.tb
onfinish stop
run -all
quit -sim
quit -f
