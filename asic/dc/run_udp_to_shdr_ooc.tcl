set TOP dma_udp_ipv4_to_shdr64_adapter
set RTL_ROOT [file normalize [file join [file dirname [info script]] ../..]]
set REPORT_DIR [file normalize [file join $RTL_ROOT build dc_udp_to_shdr_ooc reports]]
set WORK_DIR [file normalize [file join $RTL_ROOT build dc_udp_to_shdr_ooc work]]

file mkdir $REPORT_DIR
file mkdir $WORK_DIR
define_design_lib WORK -path $WORK_DIR

if {![info exists ::env(DMA_DC_TARGET_LIBRARY)] || $::env(DMA_DC_TARGET_LIBRARY) eq ""} {
    error "DMA_DC_TARGET_LIBRARY must name the local standard-cell .db library"
}

set_app_var target_library $::env(DMA_DC_TARGET_LIBRARY)
set_app_var link_library "* $target_library"

set filelist [file join $RTL_ROOT filelists dma_udp_to_shdr_ooc.f]
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

analyze -format verilog -define SYNTHESIS $sources
elaborate $TOP
current_design $TOP
link
uniquify

source [file join [file dirname [info script]] dma_udp_to_shdr_ooc.sdc]
check_design > [file join $REPORT_DIR check_design.rpt]
check_timing > [file join $REPORT_DIR check_timing_precompile.rpt]

compile_ultra

redirect [file join $REPORT_DIR check_design_postcompile.rpt] {check_design}
redirect [file join $REPORT_DIR check_timing.rpt] {check_timing}
redirect [file join $REPORT_DIR qor.rpt] {report_qor}
redirect [file join $REPORT_DIR area.rpt] {report_area -hierarchy}
redirect [file join $REPORT_DIR cell.rpt] {report_cell}
redirect [file join $REPORT_DIR reference.rpt] {report_reference -hierarchy}
redirect [file join $REPORT_DIR timing_top20.rpt] {
    report_timing -delay_type max -max_paths 20 -nworst 1 -input_pins -nets
}
redirect [file join $REPORT_DIR constraints.rpt] {report_constraint -all_violators}
redirect [file join $REPORT_DIR power.rpt] {report_power}

set latch_cells [get_cells -hierarchical -filter "is_latch == true"]
set register_cells [all_registers]
set summary_fp [open [file join $REPORT_DIR summary.txt] w]
puts $summary_fp "top=$TOP"
puts $summary_fp "clock_period_ns=5.000"
puts $summary_fp "latch_count=[sizeof_collection $latch_cells]"
puts $summary_fp "register_count=[sizeof_collection $register_cells]"
close $summary_fp

exit
