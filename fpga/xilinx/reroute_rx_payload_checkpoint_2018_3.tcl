# Reroute an already placed RX payload OOC checkpoint with an independent
# route directive while regenerating the complete auditable report set.

foreach required {PROFILE INPUT_DCP REPORT_TAG ROUTE_DIRECTIVE} {
    if {![info exists ::env($required)] || $::env($required) eq ""} {
        error "$required must be set"
    }
}

set PROFILE $::env(PROFILE)
if {$PROFILE ni {same512 async64 async512}} {
    error "PROFILE must be same512, async64, or async512"
}
set DMA_ROOT [file normalize [file join [file dirname [info script]] .. ..]]
set INPUT_DCP [file normalize $::env(INPUT_DCP)]
set REPORT_TAG $::env(REPORT_TAG)
set ROUTE_DIRECTIVE $::env(ROUTE_DIRECTIVE)

if {$PROFILE eq "same512"} {
    set report_root vivado_rx_payload_512_ooc_2018_3
    set stem rx_payload_512
} else {
    set report_root vivado_rx_payload_${PROFILE}_ooc_2018_3
    set stem rx_payload_${PROFILE}
}
set report_dir [file join $DMA_ROOT reports $report_root $REPORT_TAG]
set checkpoint_dir [file join $DMA_ROOT build $report_root $REPORT_TAG]
file mkdir $report_dir
file mkdir $checkpoint_dir

open_checkpoint $INPUT_DCP
route_design -unroute
route_design -directive $ROUTE_DIRECTIVE
write_checkpoint -force [file join $checkpoint_dir ${stem}_routed.dcp]

report_utilization -file [file join $report_dir ${stem}_routed_utilization.rpt]
report_utilization -hierarchical \
    -file [file join $report_dir ${stem}_routed_utilization_hier.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose \
    -file [file join $report_dir ${stem}_timing_summary.rpt]
report_timing -delay_type max -max_paths 100 -nworst 1 -unique_pins \
    -path_type full_clock_expanded \
    -file [file join $report_dir ${stem}_timing_top100_unique.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 -unique_pins \
    -path_type full_clock_expanded \
    -file [file join $report_dir ${stem}_hold_top20_unique.rpt]

if {$PROFILE eq "same512"} {
    if {![info exists ::env(INPUT_CDC_ABSENCE)] ||
        $::env(INPUT_CDC_ABSENCE) eq ""} {
        error "INPUT_CDC_ABSENCE must be set for same512"
    }
    file copy -force [file normalize $::env(INPUT_CDC_ABSENCE)] \
        [file join $report_dir rx_payload_512_cdc_absence.rpt]
} else {
    report_cdc -details -from [get_clocks aclk] -to [get_clocks mem_clk] \
        -file [file join $report_dir ${stem}_cdc_aclk_to_mem.rpt]
    report_cdc -details -from [get_clocks mem_clk] -to [get_clocks aclk] \
        -file [file join $report_dir ${stem}_cdc_mem_to_aclk.rpt]

    source [file join $DMA_ROOT fpga xilinx \
        constrain_rx_payload_gray_buses_2018_3.tcl]
    set gray_fifo_cells [dma_generic_gray_fifo_cells]
    if {[llength $gray_fifo_cells] != 2} {
        error "expected two generic Gray FIFO instances, got [llength $gray_fifo_cells]"
    }
    set bus_skew_report [file join $report_dir ${stem}_bus_skew.rpt]
    set exception_report [file join $report_dir ${stem}_exceptions.rpt]
    report_bus_skew -warn_on_violation -cells $gray_fifo_cells \
        -file $bus_skew_report
    report_exceptions -write_valid_exceptions -file $exception_report
    report_exceptions -coverage \
        -file [file join $report_dir ${stem}_exception_coverage.rpt]

    if {![info exists ::env(INPUT_GRAY_MANIFEST)] ||
        $::env(INPUT_GRAY_MANIFEST) eq ""} {
        error "INPUT_GRAY_MANIFEST must be set for asynchronous profiles"
    }
    set gray_manifest [file join $report_dir ${stem}_gray_constraints.yaml]
    file copy -force [file normalize $::env(INPUT_GRAY_MANIFEST)] $gray_manifest
    set manifest [open $gray_manifest r]
    set manifest_text [read $manifest]
    close $manifest
    regsub {reported_max_delay_constraint_count: [^\r\n]+} $manifest_text \
        {reported_max_delay_constraint_count: pending_route} manifest_text
    regsub {reported_bus_skew_constraint_count: [^\r\n]+} $manifest_text \
        {reported_bus_skew_constraint_count: pending_route} manifest_text
    regsub {bus_skew_violation_count: [^\r\n]+} $manifest_text \
        {bus_skew_violation_count: pending_route} manifest_text
    regsub {overridden_max_delay_warning_count: [^\r\n]+} $manifest_text \
        {overridden_max_delay_warning_count: pending_methodology} manifest_text
    regsub {suboptimal_sync_chain_warning_count: [^\r\n]+} $manifest_text \
        {suboptimal_sync_chain_warning_count: pending_methodology} manifest_text
    set manifest [open $gray_manifest w]
    puts -nonewline $manifest $manifest_text
    close $manifest
    dma_finalize_rx_payload_gray_manifest \
        $gray_manifest $bus_skew_report $exception_report 4 5.000
}

report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $report_dir ${stem}_high_fanout.rpt]
report_drc -file [file join $report_dir ${stem}_drc.rpt]
set methodology_report [file join $report_dir ${stem}_methodology.rpt]
report_methodology -file $methodology_report
if {$PROFILE ne "same512"} {
    dma_finalize_rx_payload_gray_methodology \
        $gray_manifest $methodology_report
}
puts "RX payload reroute complete profile=$PROFILE directive=$ROUTE_DIRECTIVE reports=$report_dir"
