transcript on
set DMA_COMPILE_DEFINES [list \
    +define+DMA_ENABLE_CQ_CMD_CREDIT=1 \
    +define+DMA_ENABLE_RX_AXIS_SKID=1 \
    +define+DMA_ENABLE_CQ_SINGLE_WRITER=1 \
    +define+DMA_ENABLE_TX_COUNTER_EVENT_LANES=1 \
    +define+DMA_ENABLE_RX_COUNTER_EVENT_LANES=1 \
    +define+DMA_ENABLE_RX_FC_ENQ_PIPELINE=1 \
    +define+DMA_ENABLE_TX_DESC_STATUS_EVENT_LANES=1 \
    +define+DMA_ENABLE_RX_MATCH_PIPELINE=1 \
    +define+DMA_ENABLE_AXI_WRITE_AW_PLAN_PIPELINE=1 \
    +define+DMA_ENABLE_AXI_WRITE_W_PREFETCH_FIFO=1 \
    +define+DMA_ENABLE_FRAME_SHARED_RD_REQ_QUEUE=1 \
    +define+DMA_ENABLE_FRAME_SHARED_POOL_DRAIN_PIPELINE=1]
do compile_dma_common.do
vlog {*}$DMA_COMPILE_DEFINES +incdir+../rtl/include +incdir+../rtl +incdir+../pattern ../pattern/tb_rtl_v33e20a22_full_arch_throughput.v
if {[info exists E20A22_SCENARIO]} {
    vsim work.tb +E20A22_SCENARIO=$E20A22_SCENARIO
} else {
    vsim work.tb
}
onfinish stop
run -all
quit -f
