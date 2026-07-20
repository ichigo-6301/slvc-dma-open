# Routed dual-clock OOC implementation for optional RX payload memory profiles.
# The sourcing wrapper must set ASYNC_PROFILE to async64 or async512.

if {![info exists ASYNC_PROFILE] || $ASYNC_PROFILE ni {async64 async512}} {
    error "ASYNC_PROFILE must be async64 or async512"
}
if {![info exists DMA_ROOT]} {
    if {[info exists ::env(DMA_ROOT)]} {
        set DMA_ROOT $::env(DMA_ROOT)
    } else {
        set script_dir [file dirname [file normalize [info script]]]
        set DMA_ROOT [file normalize [file join $script_dir .. ..]]
    }
}
if {![info exists PART]} { set PART xc7z100ffg900-2 }
if {![info exists PLACE_DIRECTIVE]} {
    if {[info exists ::env(PLACE_DIRECTIVE)]} { set PLACE_DIRECTIVE $::env(PLACE_DIRECTIVE) } else { set PLACE_DIRECTIVE Explore }
}
if {![info exists PHYS_OPT_DIRECTIVE]} {
    if {[info exists ::env(PHYS_OPT_DIRECTIVE)]} { set PHYS_OPT_DIRECTIVE $::env(PHYS_OPT_DIRECTIVE) } else { set PHYS_OPT_DIRECTIVE Explore }
}
if {![info exists ROUTE_DIRECTIVE]} {
    if {[info exists ::env(ROUTE_DIRECTIVE)]} { set ROUTE_DIRECTIVE $::env(ROUTE_DIRECTIVE) } else { set ROUTE_DIRECTIVE Explore }
}
if {![info exists REPORT_TAG]} {
    if {[info exists ::env(REPORT_TAG)]} { set REPORT_TAG $::env(REPORT_TAG) } else { set REPORT_TAG current }
}
if {[info exists ::env(DMA_ACLK_PERIOD_NS)]} {
    set ACLK_PERIOD $::env(DMA_ACLK_PERIOD_NS)
} else {
    set ACLK_PERIOD 5.000
}
if {[info exists ::env(DMA_MEM_CLOCK_PERIOD_NS)]} {
    set MEM_CLK_PERIOD $::env(DMA_MEM_CLOCK_PERIOD_NS)
} else {
    set MEM_CLK_PERIOD 5.000
}

set DMA_ROOT [file normalize $DMA_ROOT]
set rtl_dir [file join $DMA_ROOT rtl]
set filelist_path [file join $DMA_ROOT filelists dma_slvc_fpga_ooc.f]
set report_dir [file join $DMA_ROOT reports vivado_rx_payload_${ASYNC_PROFILE}_ooc_2018_3 $REPORT_TAG]
set checkpoint_dir [file join $DMA_ROOT build vivado_rx_payload_${ASYNC_PROFILE}_ooc_2018_3 $REPORT_TAG]
file mkdir $report_dir
file mkdir $checkpoint_dir

create_project -in_memory -part $PART
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_FIFO} [current_project]
set width_define [expr {$ASYNC_PROFILE eq "async64" ? "DMA_RX_MEM_ASYNC64_PROFILE" : "DMA_RX_MEM_ASYNC512_PROFILE"}]
set rtl_defines [list \
    DMA_RX_MEM_ASYNC_PROFILE \
    DMA_ASYNC_FIFO_XPM \
    $width_define \
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

create_clock -name aclk -period $ACLK_PERIOD [get_ports aclk]
create_clock -name mem_clk -period $MEM_CLK_PERIOD [get_ports mem_clk]
create_clock -name aclk_io_launch -period $ACLK_PERIOD
create_clock -name mem_clk_io_launch -period $MEM_CLK_PERIOD
set_clock_groups -asynchronous \
    -group [get_clocks {aclk aclk_io_launch}] \
    -group [get_clocks {mem_clk mem_clk_io_launch}]
set gray_constraint_limit [expr {min($ACLK_PERIOD, $MEM_CLK_PERIOD)}]
set gray_constraint_manifest [file join $report_dir rx_payload_${ASYNC_PROFILE}_gray_constraints.yaml]
source [file join $DMA_ROOT fpga xilinx constrain_rx_payload_gray_buses_2018_3.tcl]
set gray_constraint_result [dma_constrain_rx_payload_gray_buses \
    $gray_constraint_limit $gray_constraint_manifest $ASYNC_PROFILE]
set gray_constraint_bus_count [lindex $gray_constraint_result 0]
set gray_fifo_cells [dma_generic_gray_fifo_cells]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports aclk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports mem_clk]
set_false_path -from [get_ports {aresetn mem_aresetn tx_axis_aresetn}]
set_clock_latency -source -early 1.500 [get_clocks {aclk_io_launch mem_clk_io_launch}]
set_clock_latency -source -late 1.500 [get_clocks {aclk_io_launch mem_clk_io_launch}]

foreach port [get_ports -quiet -filter {DIRECTION == IN}] {
    set name [get_property NAME $port]
    if {$name in {aclk mem_clk tx_axis_aclk aresetn mem_aresetn tx_axis_aresetn}} {
        continue
    }
    if {[string match "m_axi_rx_payload_*" $name]} {
        set_input_delay -max 0.500 -clock mem_clk_io_launch $port
        set_input_delay -min 0.100 -clock mem_clk_io_launch $port
    } else {
        set_input_delay -max 0.500 -clock aclk_io_launch $port
        set_input_delay -min 0.100 -clock aclk_io_launch $port
    }
}
foreach port [get_ports -quiet -filter {DIRECTION == OUT}] {
    set name [get_property NAME $port]
    if {[string match "m_axi_rx_payload_*" $name]} {
        set_output_delay -max 0.500 -clock mem_clk $port
        set_output_delay -min 0.000 -clock mem_clk $port
    } else {
        set_output_delay -max 0.500 -clock aclk $port
        set_output_delay -min 0.000 -clock aclk $port
    }
}

report_utilization -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_synth_utilization.rpt]
opt_design
place_design -directive $PLACE_DIRECTIVE
phys_opt_design -directive $PHYS_OPT_DIRECTIVE
route_design -directive $ROUTE_DIRECTIVE
write_checkpoint -force [file join $checkpoint_dir rx_payload_${ASYNC_PROFILE}_routed.dcp]
report_utilization -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_routed_utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_routed_utilization_hier.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
    -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_timing_summary.rpt]
report_timing -delay_type max -max_paths 100 -nworst 1 -unique_pins \
    -path_type full_clock_expanded -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_timing_top100_unique.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 -unique_pins \
    -path_type full_clock_expanded -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_hold_top20_unique.rpt]
report_cdc -details -from [get_clocks aclk] -to [get_clocks mem_clk] \
    -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_cdc_aclk_to_mem.rpt]
report_cdc -details -from [get_clocks mem_clk] -to [get_clocks aclk] \
    -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_cdc_mem_to_aclk.rpt]
set gray_bus_skew_report [file join $report_dir rx_payload_${ASYNC_PROFILE}_bus_skew.rpt]
set gray_exception_report [file join $report_dir rx_payload_${ASYNC_PROFILE}_exceptions.rpt]
report_bus_skew -warn_on_violation -cells $gray_fifo_cells -file $gray_bus_skew_report
report_exceptions -write_valid_exceptions -file $gray_exception_report
report_exceptions -coverage \
    -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_exception_coverage.rpt]
dma_finalize_rx_payload_gray_manifest \
    $gray_constraint_manifest $gray_bus_skew_report $gray_exception_report \
    $gray_constraint_bus_count $gray_constraint_limit
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_high_fanout.rpt]
report_drc -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_drc.rpt]
report_methodology -file [file join $report_dir rx_payload_${ASYNC_PROFILE}_methodology.rpt]
puts "RX payload $ASYNC_PROFILE OOC implementation complete. Reports: $report_dir"
