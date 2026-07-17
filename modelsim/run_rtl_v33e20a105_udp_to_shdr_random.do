transcript on
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog +incdir+../rtl +incdir+../pattern \
    ../rtl/dma_udp_ipv4_to_shdr64_adapter.v \
    ../pattern/tb_rtl_v33e20a105_udp_to_shdr_random.v
vsim work.tb
onfinish stop
run -all
if {[info exists RUN_ALL_MODE]} {
    return
}
quit -f
