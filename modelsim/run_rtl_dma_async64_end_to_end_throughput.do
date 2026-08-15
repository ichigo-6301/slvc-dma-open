if {[info exists ::env(DMA_TP_TRANSCRIPT)] && $::env(DMA_TP_TRANSCRIPT) ne ""} {
    transcript file $::env(DMA_TP_TRANSCRIPT)
}
transcript on

set local_modelsim_ini [file normalize modelsim.ini]
if {![file exists $local_modelsim_ini]} {
    exec vmap -c
}
set ::env(MODELSIM) $local_modelsim_ini

set DMA_COMPILE_DEFINES [list \
    +define+DMA_MAX_CH=16 \
    +define+DMA_RX_CH_NUM=16 \
    +define+DMA_TX_CH_NUM=16 \
    +define+DMA_RX_MEM_ASYNC_PROFILE=1 \
    +define+DMA_RX_MEM_ASYNC64_PROFILE=1 \
    +define+DMA_SIM_MEM_BYTES=16777216 \
    +define+DMA_PKT_MEM_BYTES=4194304 \
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
vlog {*}$DMA_COMPILE_DEFINES \
    +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../pattern/axi_hp0_dual_master_64_model.v \
    ../pattern/tb_rtl_dma_async64_end_to_end_throughput.v

set shared_service 1
set response_latency 16
set service_percent 100
set mem_phase_ns 3
foreach {name default_value} {
    DMA_TP_SHARED_SERVICE 1
    DMA_TP_RESPONSE_LATENCY 16
    DMA_TP_SERVICE_PERCENT 100
    DMA_TP_MEM_PHASE_NS 3
} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        if {$name eq "DMA_TP_SHARED_SERVICE"} { set shared_service $::env($name) }
        if {$name eq "DMA_TP_RESPONSE_LATENCY"} { set response_latency $::env($name) }
        if {$name eq "DMA_TP_SERVICE_PERCENT"} { set service_percent $::env($name) }
        if {$name eq "DMA_TP_MEM_PHASE_NS"} { set mem_phase_ns $::env($name) }
    }
}

set sim_args [list \
    -gHP0_SHARED_SERVICE=$shared_service \
    -gHP0_RESPONSE_LATENCY=$response_latency \
    -gHP0_SERVICE_PERCENT=$service_percent \
    -gMEM_PHASE_NS=$mem_phase_ns]
if {[info exists ::env(DMA_TP_CASE)] && $::env(DMA_TP_CASE) ne ""} {
    lappend sim_args "+DMA_TP_CASE=$::env(DMA_TP_CASE)"
}
if {[info exists ::env(DMA_TP_FRAMES)] && $::env(DMA_TP_FRAMES) ne ""} {
    lappend sim_args "+DMA_TP_FRAMES=$::env(DMA_TP_FRAMES)"
}
if {[info exists ::env(DMA_TP_PAYLOAD_BYTES)] && $::env(DMA_TP_PAYLOAD_BYTES) ne ""} {
    lappend sim_args "+DMA_TP_PAYLOAD_BYTES=$::env(DMA_TP_PAYLOAD_BYTES)"
}

eval [linsert $sim_args 0 vsim work.tb]
onfinish stop
run -all
quit -f
