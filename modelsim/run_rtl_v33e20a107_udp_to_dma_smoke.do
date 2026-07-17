transcript on
set DMA_COMPILE_DEFINES [list \
    +define+DMA_ENABLE_RX_AXIS_SKID=1 \
    +define+DMA_ENABLE_CQ_SINGLE_WRITER=1 \
    +define+DMA_ENABLE_RX_COUNTER_EVENT_LANES=1 \
    +define+DMA_ENABLE_RX_MATCH_PIPELINE=1 \
    +define+DMA_ENABLE_AXI_WRITE_AW_PLAN_PIPELINE=1]
do compile_dma_common.do
vlog {*}$DMA_COMPILE_DEFINES +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../pattern/tb_rtl_v33e20a107_udp_to_dma_smoke.v
vsim work.tb
onfinish stop
run -all
unset DMA_COMPILE_DEFINES
if {[info exists RUN_ALL_MODE]} {
    return
}
quit -f
