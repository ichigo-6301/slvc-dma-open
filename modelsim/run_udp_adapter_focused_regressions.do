transcript on

proc run_udp_adapter_focus {testbench label} {
    global DMA_COMPILE_DEFINES
    set DMA_COMPILE_DEFINES {}
    puts "============================================================"
    puts "UDP_ADAPTER_FOCUS: starting $label"
    puts "============================================================"
    do compile_dma_common.do
    vlog +incdir+../rtl +incdir+../pattern ../pattern/$testbench
    vsim work.tb
    onfinish stop
    run -all
    quit -sim
    unset DMA_COMPILE_DEFINES
    puts "UDP_ADAPTER_FOCUS: completed $label"
}

run_udp_adapter_focus tb_rtl_v13_parser_pipeline.v parser_pipeline
run_udp_adapter_focus tb_rtl_v14_admission_pipeline.v rx_admission
run_udp_adapter_focus tb_rtl_v18_slvc_wrapper_compat.v slvc_wrapper
run_udp_adapter_focus tb_rtl_v25_ring_cq_error_matrix.v ring_cq_error
run_udp_adapter_focus tb_rtl_v22_mcf_pause_resume.v flow_control_pause_resume

puts "SUMMARY: UDP adapter focused parser/wrapper/RX/CQ/flow-control regressions PASS"
quit -f
