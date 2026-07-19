# Routed OOC implementation for the optional same-clock 512-bit RX payload path.

if {![info exists DMA_ROOT]} {
    if {[info exists ::env(DMA_ROOT)]} {
        set DMA_ROOT $::env(DMA_ROOT)
    } else {
        set script_dir [file dirname [file normalize [info script]]]
        set DMA_ROOT [file normalize [file join $script_dir .. ..]]
    }
}
if {![info exists PART]} { set PART xc7z100ffg900-2 }
if {![info exists PLACE_DIRECTIVE]} { set PLACE_DIRECTIVE Explore }
if {![info exists PHYS_OPT_DIRECTIVE]} { set PHYS_OPT_DIRECTIVE Explore }
if {![info exists ROUTE_DIRECTIVE]} { set ROUTE_DIRECTIVE Explore }
if {![info exists REPORT_TAG]} {
    if {[info exists ::env(REPORT_TAG)]} { set REPORT_TAG $::env(REPORT_TAG) } else { set REPORT_TAG current }
}

set DMA_ROOT [file normalize $DMA_ROOT]
set rtl_dir [file join $DMA_ROOT rtl]
set filelist_path [file join $DMA_ROOT filelists dma_slvc_fpga_ooc.f]
set report_dir [file join $DMA_ROOT reports vivado_rx_payload_512_ooc_2018_3 $REPORT_TAG]
set checkpoint_dir [file join $DMA_ROOT build vivado_rx_payload_512_ooc_2018_3 $REPORT_TAG]
file mkdir $report_dir
file mkdir $checkpoint_dir

create_project -in_memory -part $PART
set_property target_language Verilog [current_project]
set rtl_defines [list \
    DMA_RX_WIDE_PAYLOAD_PROFILE \
    DMA_ENABLE_CQ_CMD_CREDIT=1 \
    DMA_ENABLE_RX_AXIS_SKID=1 \
    DMA_ENABLE_CQ_SINGLE_WRITER=1 \
    DMA_ENABLE_TX_COUNTER_EVENT_LANES=1 \
    DMA_ENABLE_RX_COUNTER_EVENT_LANES=1 \
    DMA_ENABLE_RX_FC_ENQ_PIPELINE=1 \
    DMA_ENABLE_TX_DESC_STATUS_EVENT_LANES=1 \
    DMA_ENABLE_RX_MATCH_PIPELINE=1 \
    DMA_ENABLE_AXI_WRITE_AW_PLAN_PIPELINE=1 \
    DMA_ENABLE_AXI_WRITE_W_PREFETCH_FIFO=1 \
    DMA_ENABLE_FRAME_SHARED_RD_REQ_QUEUE=1 \
    DMA_ENABLE_FRAME_SHARED_POOL_DRAIN_PIPELINE=1]
set_property verilog_define $rtl_defines [current_fileset]

set rtl_files {}
set fh [open $filelist_path r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line] || [string match "*.vh" $line]} { continue }
    lappend rtl_files [file join $DMA_ROOT $line]
}
close $fh
read_verilog [file join $rtl_dir include dma_defs.vh]
read_verilog $rtl_files
synth_design -top frame_dma_rx_top -part $PART -mode out_of_context

create_clock -name aclk -period 5.000 [get_ports aclk]
create_clock -name aclk_io_launch -period 5.000
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports aclk]
set_clock_latency -source -early 1.500 [get_clocks aclk_io_launch]
set_clock_latency -source -late 1.500 [get_clocks aclk_io_launch]

foreach port [get_ports -quiet -filter {DIRECTION == IN}] {
    set name [get_property NAME $port]
    if {$name ni {aclk tx_axis_aclk aresetn tx_axis_aresetn}} {
        set_input_delay -max 0.500 -clock aclk_io_launch $port
        set_input_delay -min 0.100 -clock aclk_io_launch $port
    }
}
foreach port [get_ports -quiet -filter {DIRECTION == OUT}] {
    set name [get_property NAME $port]
    set_output_delay -max 0.500 -clock aclk $port
    set_output_delay -min 0.000 -clock aclk $port
}

report_utilization -file [file join $report_dir rx_payload_512_synth_utilization.rpt]
opt_design
place_design -directive $PLACE_DIRECTIVE
phys_opt_design -directive $PHYS_OPT_DIRECTIVE
route_design -directive $ROUTE_DIRECTIVE
write_checkpoint -force [file join $checkpoint_dir rx_payload_512_routed.dcp]
report_utilization -file [file join $report_dir rx_payload_512_routed_utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir rx_payload_512_routed_utilization_hier.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
    -file [file join $report_dir rx_payload_512_timing_summary.rpt]
report_timing -delay_type max -max_paths 100 -nworst 1 -unique_pins \
    -path_type full_clock_expanded -file [file join $report_dir rx_payload_512_timing_top100_unique.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 -unique_pins \
    -path_type full_clock_expanded -file [file join $report_dir rx_payload_512_hold_top20_unique.rpt]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $report_dir rx_payload_512_high_fanout.rpt]
report_drc -file [file join $report_dir rx_payload_512_drc.rpt]
report_methodology -file [file join $report_dir rx_payload_512_methodology.rpt]
puts "RX payload 512 OOC implementation complete. Reports: $report_dir"
