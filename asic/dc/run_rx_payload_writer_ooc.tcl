set RTL_ROOT [file normalize [file join [file dirname [info script]] ../..]]

if {![info exists ::env(DMA_DC_TARGET_LIBRARY)] || $::env(DMA_DC_TARGET_LIBRARY) eq ""} {
    error "DMA_DC_TARGET_LIBRARY must name the local standard-cell .db library"
}
if {![info exists ::env(DMA_DC_WRITER_PROFILE)]} {
    set PROFILE wide512
} else {
    set PROFILE $::env(DMA_DC_WRITER_PROFILE)
}
if {![info exists ::env(DMA_DC_CLOCK_PERIOD_NS)]} {
    set CLOCK_PERIOD 5.000
} else {
    set CLOCK_PERIOD $::env(DMA_DC_CLOCK_PERIOD_NS)
}

if {$PROFILE eq "wide512"} {
    set TOP dma_axi_write_engine_512
} elseif {$PROFILE eq "legacy64"} {
    set TOP dma_axi_write_engine
} else {
    error "DMA_DC_WRITER_PROFILE must be wide512 or legacy64"
}

set PERIOD_TAG [string map {. p} $CLOCK_PERIOD]
set RUN_ROOT [file normalize [file join $RTL_ROOT build dc_rx_payload_writer_ooc ${PROFILE}_${PERIOD_TAG}ns]]
set REPORT_DIR [file join $RUN_ROOT reports]
set WORK_DIR [file join $RUN_ROOT work]
file mkdir $REPORT_DIR
file mkdir $WORK_DIR
define_design_lib WORK -path $WORK_DIR

set_app_var target_library $::env(DMA_DC_TARGET_LIBRARY)
set_app_var link_library "* $target_library"
set_app_var search_path [concat $search_path [file join $RTL_ROOT rtl include]]

set filelist [file join $RTL_ROOT filelists dma_rx_payload_writer_dc_ooc.f]
set fp [open $filelist r]
set sources {}
while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
        continue
    }
    lappend sources [file join $RTL_ROOT $line]
}
close $fp

set defines {SYNTHESIS DMA_SYNTHESIS DMA_ENABLE_AXI_WRITE_AW_PLAN_PIPELINE=1 DMA_ENABLE_AXI_WRITE_W_PREFETCH_FIFO=1 DMA_ENABLE_FRAME_SHARED_RD_REQ_QUEUE=1}
if {![analyze -format verilog -define $defines $sources]} {
    error "RTL analyze failed"
}
if {![elaborate $TOP]} {
    error "RTL elaborate failed for $TOP"
}
current_design $TOP
if {![link]} {
    error "link failed for $TOP"
}
uniquify

create_clock -name writer_clk -period $CLOCK_PERIOD [get_ports clk]
set_clock_uncertainty -setup 0.200 [get_clocks writer_clk]
set_clock_uncertainty -hold 0.050 [get_clocks writer_clk]
set data_inputs [remove_from_collection [all_inputs] [get_ports {clk rstn}]]
set_input_delay 0.500 -clock writer_clk $data_inputs
set_input_delay 0.000 -clock writer_clk [get_ports rstn]
set_output_delay 0.500 -clock writer_clk [all_outputs]
set_false_path -from [get_ports rstn]
set_input_transition 0.100 $data_inputs
set_load 0.050 [all_outputs]
set_max_fanout 16 [current_design]
set_max_transition 0.500 [current_design]
set_fix_multiple_port_nets -all -buffer_constants

redirect [file join $REPORT_DIR check_design_precompile.rpt] {check_design}
redirect [file join $REPORT_DIR check_timing_precompile.rpt] {check_timing}

compile_ultra

redirect [file join $REPORT_DIR check_design.rpt] {check_design}
redirect [file join $REPORT_DIR check_timing.rpt] {check_timing}
redirect [file join $REPORT_DIR qor.rpt] {report_qor}
redirect [file join $REPORT_DIR area.rpt] {report_area -hierarchy}
redirect [file join $REPORT_DIR cell.rpt] {report_cell}
redirect [file join $REPORT_DIR reference.rpt] {report_reference -hierarchy}
redirect [file join $REPORT_DIR timing_setup_top20.rpt] {
    report_timing -delay_type max -max_paths 20 -nworst 1 -input_pins -nets
}
redirect [file join $REPORT_DIR timing_hold_top20.rpt] {
    report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins -nets
}
redirect [file join $REPORT_DIR constraints.rpt] {report_constraint -all_violators}

set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
set latch_cells [get_cells -hierarchical -filter "is_latch == true"]
set register_cells [all_registers]
set leaf_cells [get_cells -hierarchical -filter "is_hierarchical == false"]
set total_cell_area 0.0
foreach_in_collection leaf_cell $leaf_cells {
    set leaf_area [get_attribute -quiet $leaf_cell area]
    if {$leaf_area ne ""} {
        set total_cell_area [expr {$total_cell_area + $leaf_area}]
    }
}
set summary_fp [open [file join $REPORT_DIR summary.txt] w]
puts $summary_fp "profile=$PROFILE"
puts $summary_fp "top=$TOP"
puts $summary_fp "clock_period_ns=$CLOCK_PERIOD"
puts $summary_fp "setup_wns_ns=[get_attribute $setup_paths slack]"
puts $summary_fp "hold_wns_ns=[get_attribute $hold_paths slack]"
puts $summary_fp "total_cell_area=$total_cell_area"
puts $summary_fp "leaf_cell_count=[sizeof_collection $leaf_cells]"
puts $summary_fp "register_count=[sizeof_collection $register_cells]"
puts $summary_fp "latch_count=[sizeof_collection $latch_cells]"
close $summary_fp

write -format ddc -hierarchy -output [file join $RUN_ROOT ${TOP}.ddc]
exit
