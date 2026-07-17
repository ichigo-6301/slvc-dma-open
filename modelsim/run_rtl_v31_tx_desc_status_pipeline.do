transcript on

do compile_dma_common.do
vlog +incdir+../rtl/include +incdir+../rtl +incdir+../pattern ../pattern/tb_rtl_v31_tx_desc_status_pipeline.v
vsim work.tb
onfinish stop
run -all
if {[info exists RUN_ALL_MODE]} {
    return
}
quit -f
