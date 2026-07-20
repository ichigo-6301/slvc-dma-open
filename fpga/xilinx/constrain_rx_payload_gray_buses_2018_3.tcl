# Explicit placement/routing bounds for project-owned generic Gray-pointer FIFOs.
# XPM payload FIFOs are intentionally excluded and retain Xilinx-owned constraints.

proc dma_generic_gray_fifo_cells {} {
    set generic_fifos {}
    foreach cell [get_cells -quiet -hier -filter {REF_NAME =~ dma_async_fifo*}] {
        set ref_name [get_property REF_NAME $cell]
        if {$ref_name eq "dma_async_fifo" ||
            [string match "dma_async_fifo__parameterized*" $ref_name]} {
            lappend generic_fifos $cell
        }
    }
    return [lsort -unique $generic_fifos]
}

proc dma_gray_destination_cells {fifo_cell register_stem} {
    set fifo_name [get_property NAME $fifo_cell]
    set result {}
    foreach cell [get_cells -quiet -hier -filter "NAME =~ *${register_stem}*"] {
        set cell_name [get_property NAME $cell]
        if {[string first "${fifo_name}/" $cell_name] == 0} {
            lappend result $cell
        }
    }
    return [lsort -unique $result]
}

proc dma_gray_source_cells {destination_cells bus_name} {
    set result {}
    foreach destination $destination_cells {
        set d_pins [get_pins -quiet -of_objects $destination -filter {REF_PIN_NAME == D}]
        if {[llength $d_pins] != 1} {
            error "$bus_name: expected one D pin for [get_property NAME $destination], got [llength $d_pins]"
        }
        set nets [get_nets -quiet -of_objects $d_pins]
        if {[llength $nets] != 1} {
            error "$bus_name: expected one data net for [get_property NAME $destination], got [llength $nets]"
        }
        set source_cells {}
        foreach driver [get_pins -quiet -leaf -of_objects $nets -filter {DIRECTION == OUT}] {
            if {[get_property REF_PIN_NAME $driver] eq "Q"} {
                lappend source_cells [get_cells -of_objects $driver]
            }
        }
        set source_cells [lsort -unique $source_cells]
        if {[llength $source_cells] != 1} {
            error "$bus_name: expected one source register for [get_property NAME $destination], got [llength $source_cells]"
        }
        lappend result [lindex $source_cells 0]
    }
    return [lsort -unique $result]
}

proc dma_cross_clock_endpoint_pins {
    source_clock destination_clock excluded_cells
} {
    set excluded_names {}
    foreach cell $excluded_cells {
        lappend excluded_names [get_property NAME $cell]
    }

    set paths [get_timing_paths -quiet \
        -from [get_clocks $source_clock] \
        -to [get_clocks $destination_clock] \
        -max_paths 100000 -nworst 1]
    if {[llength $paths] == 0} {
        error "No timed paths matched $source_clock->$destination_clock"
    }

    set result {}
    foreach path $paths {
        set endpoint_pin [get_pins -quiet [get_property ENDPOINT_PIN $path]]
        if {[llength $endpoint_pin] != 1} {
            error "$source_clock->$destination_clock: expected one endpoint pin"
        }
        set endpoint_cell [get_cells -of_objects $endpoint_pin]
        if {[llength $endpoint_cell] != 1} {
            error "$source_clock->$destination_clock: expected one endpoint cell"
        }
        if {[lsearch -exact $excluded_names \
                [get_property NAME $endpoint_cell]] < 0} {
            lappend result $endpoint_pin
        }
    }
    return [lsort -unique $result]
}

proc dma_constrain_rx_payload_gray_buses {limit_ns manifest_path profile_name} {
    if {$limit_ns <= 0.0} {
        error "Gray bus constraint limit must be positive, got $limit_ns"
    }

    set generic_fifos [dma_generic_gray_fifo_cells]
    if {[llength $generic_fifos] == 0} {
        error "No project-owned generic Gray FIFO instances matched"
    }

    set records {}
    set constrained_bus_count 0
    set source_register_count 0
    set destination_register_count 0
    set project_gray_destinations {}

    foreach fifo $generic_fifos {
        set fifo_name [get_property NAME $fifo]
        foreach direction {
            {write_aclk_to_mem m_wgray_sync1_reg}
            {read_mem_to_aclk s_rgray_sync1_reg}
        } {
            lassign $direction direction_name destination_stem
            set bus_name "${fifo_name}:${direction_name}"
            set destinations [dma_gray_destination_cells $fifo $destination_stem]
            if {[llength $destinations] == 0} {
                error "$bus_name: no first-stage Gray synchronizer registers matched"
            }
            set sources [dma_gray_source_cells $destinations $bus_name]
            if {[llength $sources] == 0} {
                error "$bus_name: no Gray source registers matched"
            }
            if {[llength $sources] != [llength $destinations]} {
                error "$bus_name: source/destination width mismatch [llength $sources]/[llength $destinations]"
            }

            set source_clock_pins [get_pins -quiet -of_objects $sources -filter {REF_PIN_NAME == C}]
            set destination_data_pins [get_pins -quiet -of_objects $destinations -filter {REF_PIN_NAME == D}]
            if {[llength $source_clock_pins] != [llength $sources]} {
                error "$bus_name: source clock-pin count mismatch"
            }
            if {[llength $destination_data_pins] != [llength $destinations]} {
                error "$bus_name: destination data-pin count mismatch"
            }

            set_max_delay -datapath_only $limit_ns -from $sources -to $destinations
            set_bus_skew -from $source_clock_pins -to $destination_data_pins $limit_ns

            incr constrained_bus_count
            incr source_register_count [llength $sources]
            incr destination_register_count [llength $destinations]
            lappend project_gray_destinations {*}$destinations
            lappend records [list $fifo_name $direction_name \
                                  [llength $sources] [llength $destinations]]
        }
    }

    set project_gray_destinations [lsort -unique $project_gray_destinations]
    set xpm_gray_destinations [get_cells -quiet -hier -filter {
        NAME =~ *dest_graysync_ff_reg*
    }]
    if {[llength $xpm_gray_destinations] == 0} {
        error "No XPM Gray synchronizer destinations matched"
    }
    set protected_gray_destinations [lsort -unique [concat \
        $project_gray_destinations $xpm_gray_destinations]]

    # Keep Gray source-to-sync1 paths under their max-delay constraints. Cut
    # only actual non-Gray crossing endpoints so broad clock-group or
    # all-register exceptions cannot override those bounds or replicate into
    # unrelated single-domain logic.
    set aclk_to_mem_false_endpoints [dma_cross_clock_endpoint_pins \
        aclk mem_clk $protected_gray_destinations]
    set mem_to_aclk_false_endpoints [dma_cross_clock_endpoint_pins \
        mem_clk aclk $protected_gray_destinations]
    if {[llength $aclk_to_mem_false_endpoints] == 0 ||
        [llength $mem_to_aclk_false_endpoints] == 0} {
        error "Point-to-point CDC false-path endpoint set is empty"
    }
    set_false_path -from [get_clocks aclk] -to $aclk_to_mem_false_endpoints
    set_false_path -from [get_clocks mem_clk] -to $mem_to_aclk_false_endpoints

    set manifest [open $manifest_path w]
    puts $manifest "schema_version: 1"
    puts $manifest "profile: $profile_name"
    puts $manifest "constraint_limit_ns: [format %.3f $limit_ns]"
    puts $manifest "generic_fifo_instance_count: [llength $generic_fifos]"
    puts $manifest "constrained_buses: $constrained_bus_count"
    puts $manifest "source_register_count: $source_register_count"
    puts $manifest "destination_register_count: $destination_register_count"
    puts $manifest "set_max_delay_constraint_count: $constrained_bus_count"
    puts $manifest "set_bus_skew_constraint_count: $constrained_bus_count"
    puts $manifest "unconstrained_gray_bus_count: 0"
    puts $manifest "clock_crossing_constraint_mode: point_to_point_false_paths"
    puts $manifest "project_gray_destination_register_count: [llength $project_gray_destinations]"
    puts $manifest "xpm_gray_destination_register_count: [llength $xpm_gray_destinations]"
    puts $manifest "protected_gray_destination_register_count: [llength $protected_gray_destinations]"
    puts $manifest "aclk_to_mem_false_path_endpoint_count: [llength $aclk_to_mem_false_endpoints]"
    puts $manifest "mem_to_aclk_false_path_endpoint_count: [llength $mem_to_aclk_false_endpoints]"
    puts $manifest "reported_max_delay_constraint_count: pending_route"
    puts $manifest "reported_bus_skew_constraint_count: pending_route"
    puts $manifest "bus_skew_violation_count: pending_route"
    puts $manifest "overridden_max_delay_warning_count: pending_methodology"
    puts $manifest "suboptimal_sync_chain_warning_count: pending_methodology"
    puts $manifest "buses:"
    foreach record $records {
        lassign $record fifo_name direction_name source_count destination_count
        puts $manifest "  - fifo: $fifo_name"
        puts $manifest "    direction: $direction_name"
        puts $manifest "    source_register_count: $source_count"
        puts $manifest "    destination_register_count: $destination_count"
    }
    close $manifest

    puts "GRAY_CONSTRAINT_MANIFEST profile=$profile_name buses=$constrained_bus_count sources=$source_register_count destinations=$destination_register_count limit_ns=[format %.3f $limit_ns]"
    return [list $constrained_bus_count $source_register_count $destination_register_count]
}

proc dma_finalize_rx_payload_gray_manifest {
    manifest_path bus_skew_report exception_report expected_bus_count constraint_limit
} {
    if {![file exists $bus_skew_report] || [file size $bus_skew_report] == 0} {
        error "Gray bus-skew report is missing or empty: $bus_skew_report"
    }
    if {![file exists $exception_report] || [file size $exception_report] == 0} {
        error "Gray timing-exception report is missing or empty: $exception_report"
    }
    set report [open $bus_skew_report r]
    set report_text [read $report]
    close $report
    if {[string first "Bus Skew Report Summary" $report_text] < 0} {
        error "Gray bus-skew report contains no constraint summary"
    }
    set reported_bus_count [regexp -all -line \
        {^set_bus_skew[^\r\n]+u_(cmd|cpl)_fifo[^\r\n]*$} $report_text]
    if {$reported_bus_count != $expected_bus_count} {
        error "Gray bus-skew report contains $reported_bus_count constraints, expected $expected_bus_count"
    }
    set violation_count [regexp -all -nocase {Slack \(VIOLATED\)} $report_text]

    set exception [open $exception_report r]
    set exception_text [read $exception]
    close $exception
    set reported_max_delay_count 0
    foreach line [split $exception_text "\n"] {
        if {[regexp {^set_max_delay ([0-9.]+) -datapath_only} \
                    [string trimright $line "\r"] match delay]} {
            if {[expr {abs($delay - $constraint_limit)}] < 0.0005} {
                incr reported_max_delay_count
            }
        }
    }
    if {[string first "u_cmd_fifo" $exception_text] < 0 ||
        [string first "u_cpl_fifo" $exception_text] < 0} {
        error "Gray timing-exception report does not cover both generic FIFOs"
    }
    if {$reported_max_delay_count != $expected_bus_count} {
        error "Gray timing-exception report contains $reported_max_delay_count project max-delay constraints, expected $expected_bus_count"
    }

    set manifest [open $manifest_path r]
    set manifest_text [read $manifest]
    close $manifest
    regsub {reported_max_delay_constraint_count: pending_route} $manifest_text \
           "reported_max_delay_constraint_count: $reported_max_delay_count" manifest_text
    regsub {reported_bus_skew_constraint_count: pending_route} $manifest_text \
           "reported_bus_skew_constraint_count: $reported_bus_count" manifest_text
    regsub {bus_skew_violation_count: pending_route} $manifest_text \
           "bus_skew_violation_count: $violation_count" manifest_text
    set manifest [open $manifest_path w]
    puts -nonewline $manifest $manifest_text
    close $manifest

    if {$violation_count != 0} {
        error "Gray bus-skew report contains $violation_count violation(s)"
    }
    puts "PASS tb_rtl_rx_payload_gray_constraint_manifest violations=0"
}

proc dma_finalize_rx_payload_gray_methodology {manifest_path methodology_report} {
    if {![file exists $methodology_report] || [file size $methodology_report] == 0} {
        error "Gray methodology report is missing or empty: $methodology_report"
    }
    set report [open $methodology_report r]
    set report_text [read $report]
    close $report

    set overridden_count [regexp -all -line \
        {^TIMING-24#[0-9]+ Warning} $report_text]
    set placement_warning_count [regexp -all -line \
        {^PDRC-190#[0-9]+ Warning} $report_text]

    set manifest [open $manifest_path r]
    set manifest_text [read $manifest]
    close $manifest
    regsub {overridden_max_delay_warning_count: pending_methodology} \
        $manifest_text \
        "overridden_max_delay_warning_count: $overridden_count" manifest_text
    regsub {suboptimal_sync_chain_warning_count: pending_methodology} \
        $manifest_text \
        "suboptimal_sync_chain_warning_count: $placement_warning_count" manifest_text
    set manifest [open $manifest_path w]
    puts -nonewline $manifest $manifest_text
    close $manifest

    if {$overridden_count != 0} {
        error "Methodology report contains $overridden_count overridden max-delay warning(s)"
    }
    puts "PASS tb_rtl_rx_payload_gray_methodology overridden_max_delay=0"
}
