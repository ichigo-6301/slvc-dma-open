proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing required environment variable: $name"
  }
  return $::env($name)
}

proc require_file {path label} {
  if {![file isfile $path] || [file size $path] == 0} {
    error "Missing $label: $path"
  }
}

proc worst_slack {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
  if {[sizeof_collection $paths] == 0} { return NA }
  return [get_attribute [index_collection $paths 0] slack]
}

proc negative_path_stats {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type \
    -slack_lesser_than 0.0 -max_paths 100000]
  set count [sizeof_collection $paths]
  set tns 0.0
  foreach_in_collection path $paths {
    set slack [get_attribute $path slack]
    if {$slack < 0.0} { set tns [expr {$tns + $slack}] }
  }
  return [list $count $tns]
}

proc write_negative_path_manifest {delay_type path} {
  set paths [get_timing_paths -delay_type $delay_type \
    -slack_lesser_than 0.0 -max_paths 100000]
  set stream [open $path w]
  puts $stream "hold_slack_ns\tsetup_slack_ns\tstartpoint\tendpoint"
  foreach_in_collection timing_path $paths {
    set slack [get_attribute $timing_path slack]
    set startpoint [get_attribute $timing_path startpoint]
    set endpoint [get_attribute $timing_path endpoint]
    set setup_paths [get_timing_paths -delay_type max -to $endpoint -max_paths 1]
    if {[sizeof_collection $setup_paths] != 1} {
      error "PrimeTime hold endpoint has no unique setup path"
    }
    set setup_slack [get_attribute [index_collection $setup_paths 0] slack]
    puts $stream [format "%.9f\t%.9f\t%s\t%s" $slack $setup_slack \
      [get_object_name $startpoint] [get_object_name $endpoint]]
  }
  close $stream
  return [sizeof_collection $paths]
}

proc violation_count {path} {
  set stream [open $path r]
  set text [read $stream]
  close $stream
  return [regexp -all {\(VIOLATED\)} $text]
}

proc parasitic_report_counts {path} {
  set stream [open $path r]
  set text [read $stream]
  close $stream
  set total -1
  set pin_to_pin 0
  set structural 0
  foreach line [split $text "\n"] {
    if {[regexp {^\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*$} $line -> value]} {
      set total $value
    } elseif {[regexp {^\s*-\s+Pin to pin nets\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*$} $line -> value]} {
      incr pin_to_pin $value
    } elseif {[regexp {^\s*-\s+(Driverless|Loadless) nets\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*$} $line -> kind value]} {
      incr structural $value
    }
  }
  if {$total < 0} { error "PrimeTime annotated-parasitics total row is missing" }
  if {$total != $pin_to_pin + $structural} {
    error "PrimeTime annotated-parasitics categories do not add up"
  }
  return [list $total $pin_to_pin $structural]
}

proc audit_unannotated_structural_nets {path expected_total} {
  set nets [get_nets -hierarchical * -filter "has_valid_parasitics == false"]
  set audit_count [sizeof_collection $nets]
  set active_count 0
  set clock_count 0
  set stream [open $path w]
  puts $stream "# Exact structural nets omitted from SPEF; pin-to-pin nets are forbidden."
  foreach_in_collection net $nets {
    set drivers [get_attribute $net number_of_leaf_drivers]
    set loads [get_attribute $net number_of_leaf_loads]
    set is_clock [get_attribute $net is_clock_network]
    if {$drivers > 0 && $loads > 0} { incr active_count }
    if {$is_clock} { incr clock_count }
    puts $stream "net=[get_object_name $net]\tdrivers=$drivers\tloads=$loads\tclock=$is_clock"
  }
  close $stream
  if {$audit_count != $expected_total} {
    error "PrimeTime structural-net audit count does not match annotation report"
  }
  return [list $audit_count $active_count $clock_count]
}

set output_dir [file normalize [require_env DMA_C4_REG_PT_OUTPUT]]
set top [require_env DMA_C4_REG_TOP]
set frequency [require_env DMA_C4_REG_FREQUENCY_MHZ]
set expected_period [require_env DMA_C4_REG_CLOCK_PERIOD_NS]
set period_tolerance [require_env DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS]
set expected_payload_bits [require_env DMA_C4_REG_EXPECTED_PAYLOAD_BITS]
set stdcell_db [file normalize [require_env DMA_C4_REG_STDCELL_DB]]
set netlist [file normalize [require_env DMA_C4_REG_POSTROUTE_NETLIST]]
set routed_sdc [file normalize [require_env DMA_C4_REG_POSTROUTE_SDC]]
set constraint_sdc [file normalize [require_env DMA_C4_REG_CONSTRAINT_SDC]]
set spef [file normalize [require_env DMA_C4_REG_POSTROUTE_SPEF]]
set driver_model [file normalize [require_env DMA_C4_REG_INPUT_DRIVER_TCL]]
file mkdir $output_dir
foreach {path label} [list $stdcell_db DB $netlist netlist \
                            $routed_sdc routed_SDC \
                            $constraint_sdc complete_constraint_SDC \
                            $spef SPEF $driver_model driver_model] {
  require_file $path $label
}

set_app_var search_path [concat [list [file dirname $stdcell_db]] [get_app_var search_path]]
set_app_var target_library [list $stdcell_db]
set_app_var link_path [list "*" $stdcell_db]
read_verilog $netlist
current_design $top
if {![link_design $top]} { error "PrimeTime link_design failed" }
set link_ok 1
if {[catch {read_sdc $routed_sdc} message]} {
  error "PrimeTime routed read_sdc failed: $message"
}
set clocks [get_clocks -quiet a1_clk]
if {[sizeof_collection $clocks] != 1} { error "PrimeTime expected one a1_clk" }
set routed_period [get_attribute $clocks period]
set routed_period_delta [expr {$routed_period - $expected_period}]
if {$period_tolerance <= 0.0 || $period_tolerance > 0.000050} {
  error "PrimeTime clock-period tolerance is outside the approved rounding window"
}
if {[expr {abs($routed_period_delta)}] > $period_tolerance} {
  error "PrimeTime routed clock-period mismatch: $routed_period"
}
remove_clock $clocks
unset -nocomplain dma_a3_external_sdc_status dma_a3_external_sdc_message
if {[catch {source $constraint_sdc} message]} {
  error "PrimeTime complete-constraint source failed: $message"
}
if {![info exists dma_a3_external_sdc_status]} {
  error "PrimeTime complete-constraint SDC omitted its fail-closed status"
}
if {!$dma_a3_external_sdc_status} {
  set constraint_message "missing diagnostic"
  if {[info exists dma_a3_external_sdc_message]} {
    set constraint_message $dma_a3_external_sdc_message
  }
  error "PrimeTime complete-constraint SDC failed: $constraint_message"
}
set constraint_sdc_ok 1
set clocks [get_clocks -quiet a1_clk]
if {[sizeof_collection $clocks] != 1} {
  error "PrimeTime complete-constraint SDC expected one a1_clk"
}
set actual_period [get_attribute $clocks period]
set period_delta [expr {$actual_period - $expected_period}]
if {[expr {abs($period_delta)}] > 0.000001} {
  error "PrimeTime complete-constraint clock-period mismatch: $actual_period"
}
source $driver_model
if {[catch {read_parasitics $spef} message]} {
  error "PrimeTime read_parasitics failed: $message"
}
set read_parasitics_ok 1
set_propagated_clock $clocks
set check_timing_ok [check_timing]
redirect -file [file join $output_dir check_timing.rpt] {check_timing -verbose}
update_timing

set register_cells [all_registers]
set clocked_register_cells [all_registers -clock a1_clk]
set register_count [sizeof_collection $register_cells]
set clocked_register_count [sizeof_collection $clocked_register_cells]
set unclocked_count [expr {$register_count - $clocked_register_count}]
set coverage [expr {$register_count > 0 ? \
  100.0 * $clocked_register_count / $register_count : 0.0}]
if {$register_count < $expected_payload_bits} {
  error "PrimeTime linked too few registers for the selected profile"
}

redirect -file [file join $output_dir setup_timing.rpt] {
  report_timing -delay_type max -slack_lesser_than 999 \
    -max_paths 20 -input_pins -nets
}
redirect -file [file join $output_dir hold_timing.rpt] {
  report_timing -delay_type min -slack_lesser_than 999 \
    -max_paths 20 -input_pins -nets
}
redirect -file [file join $output_dir analysis_coverage.rpt] {report_analysis_coverage}
redirect -file [file join $output_dir annotated_parasitics.rpt] {
  report_annotated_parasitics -check
}
set parasitic_counts [parasitic_report_counts \
  [file join $output_dir annotated_parasitics.rpt]]
set unannotated_parasitic_net_count [lindex $parasitic_counts 0]
set unannotated_pin_to_pin_net_count [lindex $parasitic_counts 1]
set unannotated_structural_net_count [lindex $parasitic_counts 2]
set structural_audit [audit_unannotated_structural_nets \
  [file join $output_dir unannotated_structural_nets.rpt] \
  $unannotated_parasitic_net_count]
set unannotated_structural_audit_count [lindex $structural_audit 0]
set unannotated_active_net_count [lindex $structural_audit 1]
set unannotated_clock_net_count [lindex $structural_audit 2]
redirect -file [file join $output_dir qor.rpt] {report_qor}
redirect -file [file join $output_dir clock.rpt] {report_clock}
redirect -file [file join $output_dir constraints_all.rpt] {
  report_constraint -all_violators
}
foreach {name option} [list max_transition -max_transition \
                            max_capacitance -max_capacitance \
                            max_fanout -max_fanout \
                            min_pulse_width -min_pulse_width \
                            min_period -min_period] {
  redirect -file [file join $output_dir constraints_${name}.rpt] \
    [list report_constraint $option -all_violators]
}

set setup_wns [worst_slack max]
set hold_wns [worst_slack min]
set setup_stats [negative_path_stats max]
set hold_stats [negative_path_stats min]
set hold_manifest_count [write_negative_path_manifest min \
  [file join $output_dir hold_violators.tsv]]
if {$hold_manifest_count != [lindex $hold_stats 0]} {
  error "PrimeTime hold manifest count does not match timing statistics"
}
foreach name [list max_transition max_capacitance max_fanout \
                   min_pulse_width min_period] {
  set ${name}_count [violation_count [file join $output_dir constraints_${name}.rpt]]
}

set gate_status PASS
set gate_reason none
if {$unannotated_pin_to_pin_net_count != 0 ||
    $unannotated_parasitic_net_count != $unannotated_structural_net_count ||
    $unannotated_structural_audit_count != $unannotated_structural_net_count ||
    $unannotated_active_net_count != 0 || $unannotated_clock_net_count != 0} {
  set gate_status FAIL; set gate_reason parasitic_annotation
} elseif {!$check_timing_ok || $unclocked_count != 0 || $coverage < 100.0} {
  set gate_status FAIL; set gate_reason timing_coverage
} elseif {$setup_wns eq "NA" || $setup_wns < 0.0 || [lindex $setup_stats 0] != 0} {
  set gate_status FAIL; set gate_reason setup_timing
} elseif {$hold_wns eq "NA" || $hold_wns < 0.0 || [lindex $hold_stats 0] != 0} {
  set gate_status FAIL; set gate_reason hold_timing
} elseif {$max_transition_count + $max_capacitance_count + $max_fanout_count + \
          $min_pulse_width_count + $min_period_count != 0} {
  set gate_status FAIL; set gate_reason electrical_constraints
}

set summary [open [file join $output_dir summary.txt] w]
foreach {key value} [list frequency_mhz $frequency clock_period_ns $actual_period \
  requested_clock_period_ns $expected_period clock_period_delta_ns $period_delta \
  routed_clock_period_ns $routed_period \
  routed_clock_period_delta_ns $routed_period_delta \
  clock_period_tolerance_ns $period_tolerance \
  link_ok $link_ok constraint_sdc_ok $constraint_sdc_ok \
  read_parasitics_ok $read_parasitics_ok \
  unannotated_parasitic_net_count $unannotated_parasitic_net_count \
  unannotated_pin_to_pin_net_count $unannotated_pin_to_pin_net_count \
  unannotated_structural_net_count $unannotated_structural_net_count \
  unannotated_structural_audit_count $unannotated_structural_audit_count \
  unannotated_active_net_count $unannotated_active_net_count \
  unannotated_clock_net_count $unannotated_clock_net_count \
  check_timing_ok $check_timing_ok register_count $register_count \
  clocked_register_count $clocked_register_count \
  unclocked_sync_endpoint_count $unclocked_count \
  synchronous_endpoint_coverage_percent $coverage \
  setup_wns_ns $setup_wns setup_tns_ns [lindex $setup_stats 1] \
  setup_violation_count [lindex $setup_stats 0] hold_wns_ns $hold_wns \
  hold_tns_ns [lindex $hold_stats 1] hold_violation_count [lindex $hold_stats 0] \
  max_transition_violation_count $max_transition_count \
  max_capacitance_violation_count $max_capacitance_count \
  max_fanout_violation_count $max_fanout_count \
  min_pulse_width_violation_count $min_pulse_width_count \
  min_period_violation_count $min_period_count gate_status $gate_status \
  gate_reason $gate_reason] {
  puts $summary "$key=$value"
}
close $summary
if {$gate_status ne "PASS"} {
  error "C4B4 register PrimeTime gate failed: $gate_reason"
}
puts "DMA_C4_REGISTER_PRIMETIME_PASS frequency_mhz=$frequency"
quit
