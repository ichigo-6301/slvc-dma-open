proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing required environment variable: $name"
  }
  return $::env($name)
}

proc read_filelist {root path} {
  set fp [open $path r]
  set sources {}
  while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
      continue
    }
    lappend sources [file join $root $line]
  }
  close $fp
  return $sources
}

proc violation_count {path} {
  set fp [open $path r]
  set text [read $fp]
  close $fp
  return [regexp -all {\(VIOLATED\)} $text]
}

proc collection_count_or_zero {script} {
  if {[catch {set collection [uplevel 1 $script]}]} {
    return 0
  }
  return [sizeof_collection $collection]
}

proc sum_cell_area {cells} {
  set total 0.0
  foreach_in_collection cell $cells {
    set value [get_attribute $cell area]
    if {$value ne ""} {
      set total [expr {$total + double($value)}]
    }
  }
  return $total
}

proc worst_slack {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
  if {[sizeof_collection $paths] == 0} {
    return NA
  }
  return [get_attribute [index_collection $paths 0] slack]
}

proc negative_timing_summary {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type -slack_lesser_than 0.0 -max_paths 100000]
  set count [sizeof_collection $paths]
  set total 0.0
  foreach_in_collection path $paths {
    set total [expr {$total + double([get_attribute $path slack])}]
  }
  return [list $count $total]
}

proc reported_clock_uncertainty {path expected label} {
  set fp [open $path r]
  set text [read $fp]
  close $fp
  set values {}
  foreach line [split $text "\n"] {
    if {[regexp {clock uncertainty[[:space:]]+([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)} $line match value]} {
      lappend values [expr {abs(double($value))}]
    }
  }
  set expected_value [expr {double($expected)}]
  if {[llength $values] == 0} {
    if {[expr {abs($expected_value)}] <= 0.000001} {
      return 0.0
    }
    error "A3 $label timing report omitted the configured clock uncertainty"
  }
  foreach value $values {
    if {[expr {abs($value - $expected_value)}] > 0.000001} {
      error "A3 $label clock uncertainty mismatch: expected $expected_value, got $value"
    }
  }
  return $expected_value
}

set ROOT [file normalize [require_env DMA_A3_ROOT]]
set BUILD_ROOT [file normalize [require_env DMA_A3_BUILD_ROOT]]
set PROFILE_ID [require_env DMA_A3_PROFILE_ID]
set CHANNELS [require_env DMA_A3_CHANNELS]
set PAYLOAD_WORDS [require_env DMA_A3_PAYLOAD_WORDS]
set PAYLOAD_AW [require_env DMA_A3_PAYLOAD_AW]
set META_DEPTH [require_env DMA_A3_META_DEPTH]
set META_AW [require_env DMA_A3_META_AW]
set SHARED_BLOCK_NUM [require_env DMA_A3_SHARED_BLOCK_NUM]
set SHARED_BLOCK_AW [require_env DMA_A3_SHARED_BLOCK_AW]
set FIXED_DEPTH [require_env DMA_A3_FIXED_DEPTH]
set FIXED_DEPTH_AW [require_env DMA_A3_FIXED_DEPTH_AW]
set FIXED_WIDTH_BANKS [require_env DMA_A3_FIXED_WIDTH_BANKS]
set FIXED_DEPTH_BANKS [require_env DMA_A3_FIXED_DEPTH_BANKS]
set FIXED_REGISTER_ARRAY_COUNT [require_env DMA_A3_FIXED_REGISTER_ARRAY_COUNT]
set EXPECTED_FIXED_PAYLOAD_BITS [require_env DMA_A3_EXPECTED_FIXED_PAYLOAD_BITS]
set EXPECTED_SHARED_PAYLOAD_BITS [require_env DMA_A3_EXPECTED_SHARED_PAYLOAD_BITS]
set EXPECTED_SHARED_KEEP_BITS [require_env DMA_A3_EXPECTED_SHARED_KEEP_BITS]
set EXPECTED_PAYLOAD_KEEP_BITS [require_env DMA_A3_EXPECTED_PAYLOAD_KEEP_BITS]
set FREQUENCY_MHZ [require_env DMA_A3_FREQUENCY_MHZ]
set TECHNOLOGY [require_env DMA_A3_TECHNOLOGY]
set STDCELL_DB [file normalize [require_env DMA_A3_STDCELL_DB]]
set DC_INGRESS [file normalize [require_env DMA_A3_DC_RX_INGRESS_BANK]]
set DC_PAYLOAD_RAM [file normalize [require_env DMA_A3_DC_PAYLOAD_RAM]]
set DC_FRAME_PAYLOAD_RAM [file normalize [require_env DMA_A3_DC_FRAME_PAYLOAD_RAM]]
set TOP dma_rx512_memory_subsystem_top
set CLOCK_NAME a3_clk
set CLOCK_PERIOD [expr {1000.0 / double($FREQUENCY_MHZ)}]
set CLOCK_PERIOD_TOLERANCE_NS 0.0001
set SETUP_UNCERTAINTY_NS 0.100
set HOLD_UNCERTAINTY_NS 0.000
set CONSTRAINT_MODE builtin
set EXTERNAL_SDC none
set EXTERNAL_SDC_SHA256 none
set has_external_sdc [expr {
  [info exists ::env(DMA_A3_EXTERNAL_SDC)] &&
  $::env(DMA_A3_EXTERNAL_SDC) ne ""
}]
set has_external_clock_name [expr {
  [info exists ::env(DMA_A3_CLOCK_NAME)] &&
  $::env(DMA_A3_CLOCK_NAME) ne ""
}]
if {$has_external_sdc != $has_external_clock_name} {
  error "DMA_A3_EXTERNAL_SDC and DMA_A3_CLOCK_NAME must be set together"
}
if {$has_external_sdc} {
  set CONSTRAINT_MODE external_sdc
  set EXTERNAL_SDC [file normalize $::env(DMA_A3_EXTERNAL_SDC)]
  if {![file isfile $EXTERNAL_SDC]} {
    error "Missing A3 external SDC: $EXTERNAL_SDC"
  }
  set CLOCK_NAME $::env(DMA_A3_CLOCK_NAME)
  set EXTERNAL_SDC_SHA256 [require_env DMA_A3_EXTERNAL_SDC_SHA256]
  if {![regexp {^[0-9a-f]{64}$} $EXTERNAL_SDC_SHA256]} {
    error "Invalid DMA_A3_EXTERNAL_SDC_SHA256"
  }
  set SETUP_UNCERTAINTY_NS [require_env DMA_A3_EXPECTED_SETUP_UNCERTAINTY_NS]
  set HOLD_UNCERTAINTY_NS [require_env DMA_A3_EXPECTED_HOLD_UNCERTAINTY_NS]
}
set DC_MAX_CORES unset
if {[info exists ::env(DMA_A3_DC_MAX_CORES)] &&
    $::env(DMA_A3_DC_MAX_CORES) ne ""} {
  if {![string is integer -strict $::env(DMA_A3_DC_MAX_CORES)] ||
      $::env(DMA_A3_DC_MAX_CORES) <= 0} {
    error "DMA_A3_DC_MAX_CORES must be a positive integer"
  }
  set DC_MAX_CORES $::env(DMA_A3_DC_MAX_CORES)
}

if {$TECHNOLOGY ne "nangate45"} {
  error "A3 run.tcl currently supports only the qualified Nangate45 path"
}
if {$META_DEPTH != 2 || $META_AW != 1} {
  error "A3 requires META_DEPTH=2 and META_AW=1"
}
if {$CHANNELS != 2 && $CHANNELS != 4 && $CHANNELS != 8} {
  error "A3 supports only the declared 2, 4, or 8 channel profiles"
}
if {$PAYLOAD_WORDS != 512 && $PAYLOAD_WORDS != 1024} {
  error "A3 supports only 512 or 1024 payload words per channel"
}
if {$SHARED_BLOCK_NUM != 64 || $SHARED_BLOCK_AW != 6} {
  error "A3 shared pool must remain 64 x 512-bit blocks"
}
if {$FIXED_DEPTH != ($CHANNELS * $PAYLOAD_WORDS / 8)} {
  error "A3 fixed beat depth does not match channels and payload words"
}
if {$FIXED_DEPTH != (1 << $FIXED_DEPTH_AW)} {
  error "A3 fixed beat depth/address width mismatch"
}
if {$FIXED_WIDTH_BANKS != 4 || $FIXED_DEPTH_BANKS != ($FIXED_DEPTH / 64)} {
  error "A3 fixed banking does not match 4 width banks x 64-word depth tiles"
}
if {$FIXED_REGISTER_ARRAY_COUNT != ($FIXED_WIDTH_BANKS * $FIXED_DEPTH_BANKS)} {
  error "A3 fixed register-array count mismatch"
}
if {$EXPECTED_FIXED_PAYLOAD_BITS != ($FIXED_DEPTH * 512)} {
  error "A3 expected fixed payload bit count mismatch"
}
if {$EXPECTED_SHARED_PAYLOAD_BITS != ($SHARED_BLOCK_NUM * 512)} {
  error "A3 expected shared payload bit count mismatch"
}
if {$EXPECTED_SHARED_KEEP_BITS != ($SHARED_BLOCK_NUM * 64)} {
  error "A3 expected shared keep bit count mismatch"
}
if {$EXPECTED_PAYLOAD_KEEP_BITS != ($EXPECTED_FIXED_PAYLOAD_BITS +
    $EXPECTED_SHARED_PAYLOAD_BITS + $EXPECTED_SHARED_KEEP_BITS)} {
  error "A3 expected total payload/keep bit count mismatch"
}
if {$PROFILE_ID eq "dma_rx512_reg_c2_b4_m2_sp64" &&
    ($CHANNELS != 2 || $FIXED_DEPTH != 128 || $FIXED_DEPTH_BANKS != 2 ||
     $FIXED_REGISTER_ARRAY_COUNT != 8 || $EXPECTED_FIXED_PAYLOAD_BITS != 65536)} {
  error "C2B4 threshold profile banking contract mismatch"
}
if {$PROFILE_ID eq "dma_rx512_reg_c4_b4_m2_sp64" &&
    ($EXPECTED_FIXED_PAYLOAD_BITS != 131072 ||
     $EXPECTED_SHARED_PAYLOAD_BITS != 32768 ||
     $EXPECTED_SHARED_KEEP_BITS != 4096 ||
     $EXPECTED_PAYLOAD_KEEP_BITS != 167936)} {
  error "C4B4 payload/keep storage contract mismatch"
}

set RUN_ROOT [file join $BUILD_ROOT dc $TECHNOLOGY $PROFILE_ID "${FREQUENCY_MHZ}mhz"]
set REPORT_DIR [file join $RUN_ROOT reports]
set CACHE_ISOLATED 0
if {[info exists ::env(DMA_A3_CACHE_ROOT)] &&
    $::env(DMA_A3_CACHE_ROOT) ne ""} {
  set CACHE_ROOT [file normalize $::env(DMA_A3_CACHE_ROOT)]
  if {[file exists $CACHE_ROOT] && ![file isdirectory $CACHE_ROOT]} {
    error "DMA_A3_CACHE_ROOT is not a directory: $CACHE_ROOT"
  }
  if {[file isdirectory $CACHE_ROOT] &&
      [llength [glob -nocomplain -directory $CACHE_ROOT *]] != 0} {
    error "DMA_A3_CACHE_ROOT must be empty: $CACHE_ROOT"
  }
  set WORK_DIR [file join $CACHE_ROOT work]
  set ALIB_DIR [file join $CACHE_ROOT alib]
  set DW_CACHE_DIR [file join $CACHE_ROOT designware]
  file mkdir $ALIB_DIR
  file mkdir $DW_CACHE_DIR
  set_app_var alib_library_analysis_path $ALIB_DIR
  set cache_read $DW_CACHE_DIR
  set cache_write $DW_CACHE_DIR
  set CACHE_ISOLATED 1
} else {
  set CACHE_ROOT legacy_defaults
  set WORK_DIR [file join $RUN_ROOT work]
  set ALIB_DIR [get_app_var alib_library_analysis_path]
  set DW_CACHE_DIR legacy_defaults
}
set COMPILE_MODE no_autoungroup
if {[info exists ::env(DMA_A3_COMPILE_MODE)] &&
    $::env(DMA_A3_COMPILE_MODE) ne ""} {
  set COMPILE_MODE $::env(DMA_A3_COMPILE_MODE)
}
if {$COMPILE_MODE ne "no_autoungroup" && $COMPILE_MODE ne "mrtc_default"} {
  error "Unsupported DMA_A3_COMPILE_MODE: $COMPILE_MODE"
}
if {$CONSTRAINT_MODE eq "external_sdc" && $COMPILE_MODE ne "mrtc_default"} {
  error "A3 external-SDC points require ordinary compile_ultra"
}
if {$CONSTRAINT_MODE eq "external_sdc" && !$CACHE_ISOLATED} {
  error "A3 external-SDC points require isolated WORK/ALIB/DesignWare caches"
}
file mkdir $REPORT_DIR
file mkdir $WORK_DIR
define_design_lib WORK -path $WORK_DIR

set_app_var target_library [list $STDCELL_DB]
set_app_var link_library [list "*" $STDCELL_DB]
set_app_var search_path [concat $search_path [file join $ROOT rtl include]]

set FILELIST [file join $ROOT flows asic c2b4 c2b4_register.f]
set sources [read_filelist $ROOT $FILELIST]
set canonical_ingress [file join $ROOT rtl rx dma_rx_fc_ingress_bank.v]
set ingress_matches [lsearch -all -exact $sources $canonical_ingress]
if {[llength $ingress_matches] != 1} {
  error "A3 filelist must contain exactly one canonical ingress source"
}
set ingress_index [lindex $ingress_matches 0]
if {![file isfile $DC_INGRESS]} {
  error "Missing generated DC ingress source: $DC_INGRESS"
}
set sources [lreplace $sources $ingress_index $ingress_index $DC_INGRESS]
set canonical_payload_ram [file join $ROOT rtl common dma_payload_beat_ram.v]
set payload_ram_matches [lsearch -all -exact $sources $canonical_payload_ram]
if {[llength $payload_ram_matches] != 1} {
  error "A3 filelist must contain exactly one canonical payload RAM source"
}
set payload_ram_index [lindex $payload_ram_matches 0]
if {![file isfile $DC_PAYLOAD_RAM]} {
  error "Missing generated DC payload RAM source: $DC_PAYLOAD_RAM"
}
set sources [lreplace $sources $payload_ram_index $payload_ram_index $DC_PAYLOAD_RAM]
set canonical_frame_payload_ram [file join $ROOT rtl rx dma_frame_payload_ram.v]
set frame_payload_ram_matches [lsearch -all -exact $sources $canonical_frame_payload_ram]
if {[llength $frame_payload_ram_matches] != 1} {
  error "A3 filelist must contain exactly one canonical frame payload RAM source"
}
set frame_payload_ram_index [lindex $frame_payload_ram_matches 0]
if {![file isfile $DC_FRAME_PAYLOAD_RAM]} {
  error "Missing generated DC frame payload RAM source: $DC_FRAME_PAYLOAD_RAM"
}
set sources [lreplace $sources $frame_payload_ram_index $frame_payload_ram_index $DC_FRAME_PAYLOAD_RAM]
foreach pair [list \
    [list $canonical_ingress $DC_INGRESS] \
    [list $canonical_payload_ram $DC_PAYLOAD_RAM] \
    [list $canonical_frame_payload_ram $DC_FRAME_PAYLOAD_RAM]] {
  set canonical [lindex $pair 0]
  set replacement [lindex $pair 1]
  if {[llength [lsearch -all -exact $sources $canonical]] != 0} {
    error "A3 canonical source remained after override replacement: $canonical"
  }
  if {[llength [lsearch -all -exact $sources $replacement]] != 1} {
    error "A3 override source must appear exactly once: $replacement"
  }
}
set defines [list \
  SYNTHESIS \
  DMA_SYNTHESIS \
  DMA_MAX_CH=$CHANNELS \
  DMA_RX_CH_NUM=$CHANNELS \
  DMA_TX_CH_NUM=$CHANNELS \
  DMA_RX_FC_INGRESS_PAYLOAD_WORDS=$PAYLOAD_WORDS \
  DMA_RX_FC_INGRESS_PAYLOAD_AW=$PAYLOAD_AW \
  DMA_RX_FC_INGRESS_META_DEPTH=$META_DEPTH \
  DMA_RX_FC_INGRESS_META_AW=$META_AW \
  DMA_ENABLE_AXI_WRITE_AW_PLAN_PIPELINE=1 \
  DMA_ENABLE_AXI_WRITE_W_PREFETCH_FIFO=1 \
  DMA_ENABLE_FRAME_SHARED_RD_REQ_QUEUE=1]

if {![analyze -format verilog -define $defines $sources]} {
  error "A3 RTL analyze failed"
}
set parameters "CHANNELS=$CHANNELS,FIXED_PAYLOAD_WORDS=$PAYLOAD_WORDS,FIXED_PAYLOAD_AW=$PAYLOAD_AW,FIXED_META_DEPTH=$META_DEPTH,FIXED_META_AW=$META_AW,SHARED_BLOCK_NUM=$SHARED_BLOCK_NUM,SHARED_BLOCK_AW=$SHARED_BLOCK_AW"
if {![elaborate $TOP -parameters $parameters]} {
  error "A3 elaborate failed for $PROFILE_ID"
}
set elaborated_design [current_design]
if {$elaborated_design eq ""} {
  error "A3 elaborate did not select a current design for $PROFILE_ID"
}
if {![link]} {
  error "A3 link failed for $PROFILE_ID"
}
uniquify

set linked_sram_cells [get_cells -hierarchical -quiet -filter "ref_name =~ *sram*"]
if {[sizeof_collection $linked_sram_cells] != 0} {
  error "A3 register-only profile linked an SRAM reference"
}

if {[info exists ::env(DMA_A3_ELABORATION_ONLY)] &&
    $::env(DMA_A3_ELABORATION_ONLY) eq "1"} {
  redirect [file join $REPORT_DIR elaboration_summary.txt] {
    echo "status=ELABORATION_VERIFIED"
    echo "profile_id=$PROFILE_ID"
    echo "frequency_mhz=$FREQUENCY_MHZ"
    echo "memory_mode=registers"
    echo "macro_count=[sizeof_collection $linked_sram_cells]"
  }
  exit
}

if {$CONSTRAINT_MODE eq "external_sdc"} {
  if {[catch {source $EXTERNAL_SDC} constraint_message]} {
    error "A3 external SDC load failed: $constraint_message"
  }
  if {![info exists dma_a3_external_sdc_status] ||
      !$dma_a3_external_sdc_status} {
    set external_sdc_error "missing fail-closed status"
    if {[info exists dma_a3_external_sdc_message] &&
        $dma_a3_external_sdc_message ne ""} {
      set external_sdc_error $dma_a3_external_sdc_message
    }
    error "A3 external SDC command failed: $external_sdc_error"
  }
} else {
  create_clock -name $CLOCK_NAME -period $CLOCK_PERIOD [get_ports clk]
  set_clock_uncertainty -setup $SETUP_UNCERTAINTY_NS [get_clocks $CLOCK_NAME]
  set_clock_uncertainty -hold $HOLD_UNCERTAINTY_NS [get_clocks $CLOCK_NAME]
  set_false_path -from [get_ports rstn]
  set_input_transition 0.100 [remove_from_collection [all_inputs] [get_ports clk]]
  set_load 0.050 [all_outputs]
  set_max_fanout 16 [current_design]
  set_max_transition 0.500 [current_design]
}
set all_a3_clocks [get_clocks -quiet *]
if {[sizeof_collection $all_a3_clocks] != 1} {
  error "A3 constraints must create exactly one clock"
}
set active_clock [get_clocks -quiet $CLOCK_NAME]
if {[sizeof_collection $active_clock] != 1} {
  error "A3 expected exactly one clock named $CLOCK_NAME"
}
set ACTUAL_CLOCK_NAME [get_object_name $active_clock]
set ACTUAL_CLOCK_PERIOD [get_attribute $active_clock period]
if {[expr {
    abs(double($ACTUAL_CLOCK_PERIOD) - double($CLOCK_PERIOD)) >
    $CLOCK_PERIOD_TOLERANCE_NS
}]} {
  error "A3 clock-period mismatch: expected $CLOCK_PERIOD, got $ACTUAL_CLOCK_PERIOD"
}
set_fix_multiple_port_nets -all -buffer_constants

redirect [file join $REPORT_DIR check_design_precompile.rpt] {check_design}
set precompile_timing_report [file join $REPORT_DIR check_timing_precompile.rpt]
redirect $precompile_timing_report {check_timing}
if {$CONSTRAINT_MODE eq "external_sdc"} {
  set precompile_timing_fp [open $precompile_timing_report r]
  set precompile_timing_text [read $precompile_timing_fp]
  close $precompile_timing_fp
  if {[string first "(TIM-216)" $precompile_timing_text] >= 0} {
    error "A3 external SDC left input ports without clock-relative delay"
  }
}
redirect [file join $REPORT_DIR clocks_precompile.rpt] {report_clock}
redirect [file join $REPORT_DIR resources_precompile.rpt] {report_resources}

set diagnostic_identity [open [file join $REPORT_DIR diagnostic_identity.txt] w]
puts $diagnostic_identity "profile_id=$PROFILE_ID"
puts $diagnostic_identity "top=$TOP"
puts $diagnostic_identity "frequency_mhz=$FREQUENCY_MHZ"
puts $diagnostic_identity "constraint_mode=$CONSTRAINT_MODE"
puts $diagnostic_identity "clock_name=$ACTUAL_CLOCK_NAME"
puts $diagnostic_identity "clock_period_ns=$ACTUAL_CLOCK_PERIOD"
puts $diagnostic_identity "setup_uncertainty_ns=$SETUP_UNCERTAINTY_NS"
puts $diagnostic_identity "hold_uncertainty_ns=$HOLD_UNCERTAINTY_NS"
puts $diagnostic_identity "external_sdc=$EXTERNAL_SDC"
puts $diagnostic_identity "external_sdc_sha256=$EXTERNAL_SDC_SHA256"
puts $diagnostic_identity "compile_mode=$COMPILE_MODE"
puts $diagnostic_identity "dc_max_cores=$DC_MAX_CORES"
puts $diagnostic_identity "cache_isolated=$CACHE_ISOLATED"
puts $diagnostic_identity "cache_root=$CACHE_ROOT"
puts $diagnostic_identity "work_dir=$WORK_DIR"
puts $diagnostic_identity "alib_library_analysis_path=[get_app_var alib_library_analysis_path]"
puts $diagnostic_identity "cache_read=$cache_read"
puts $diagnostic_identity "cache_write=$cache_write"
puts $diagnostic_identity "stdcell_db=$STDCELL_DB"
close $diagnostic_identity

if {$DC_MAX_CORES ne "unset"} {
  if {[catch {set_host_options -max_cores $DC_MAX_CORES} host_options_message]} {
    error "A3 set_host_options -max_cores failed: $host_options_message"
  }
}
if {$COMPILE_MODE eq "no_autoungroup"} {
  compile_ultra -no_autoungroup
} else {
  compile_ultra
}

set check_design_ok [check_design]
set check_timing_ok [check_timing]
redirect [file join $REPORT_DIR check_design.rpt] {check_design}
redirect [file join $REPORT_DIR check_timing.rpt] {check_timing}
redirect [file join $REPORT_DIR clocks.rpt] {report_clock}
redirect [file join $REPORT_DIR qor.rpt] {report_qor}
redirect [file join $REPORT_DIR area.rpt] {report_area}
redirect [file join $REPORT_DIR area_hier.rpt] {report_area -hierarchy}
redirect [file join $REPORT_DIR references.rpt] {report_reference -hierarchy}
redirect [file join $REPORT_DIR cells.rpt] {report_cell}
redirect [file join $REPORT_DIR resources.rpt] {report_resources}
redirect [file join $REPORT_DIR fanout.rpt] {report_net_fanout -threshold 16}
redirect [file join $REPORT_DIR timing_setup_top20.rpt] {
  report_timing -delay_type max -max_paths 20 -nworst 1 -input_pins -nets
}
redirect [file join $REPORT_DIR timing_hold_top20.rpt] {
  report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins -nets
}
redirect [file join $REPORT_DIR constraints_all.rpt] {report_constraint -all_violators}
redirect [file join $REPORT_DIR constraints_max_transition.rpt] {
  report_constraint -max_transition -all_violators
}
redirect [file join $REPORT_DIR constraints_max_capacitance.rpt] {
  report_constraint -max_capacitance -all_violators
}
redirect [file join $REPORT_DIR constraints_max_fanout.rpt] {
  report_constraint -max_fanout -all_violators
}
redirect [file join $REPORT_DIR constraints_min_pulse_width.rpt] {
  report_constraint -min_pulse_width -all_violators
}
redirect [file join $REPORT_DIR constraints_min_period.rpt] {
  report_constraint -min_period -all_violators
}
set ACTUAL_SETUP_UNCERTAINTY_NS [reported_clock_uncertainty \
  [file join $REPORT_DIR timing_setup_top20.rpt] $SETUP_UNCERTAINTY_NS setup]
set ACTUAL_HOLD_UNCERTAINTY_NS [reported_clock_uncertainty \
  [file join $REPORT_DIR timing_hold_top20.rpt] $HOLD_UNCERTAINTY_NS hold]

set leaf_cells [get_cells -hierarchical -filter "is_hierarchical == false"]
set sequential_cells [get_cells -hierarchical -quiet -filter "is_sequential == true"]
set combinational_cells [get_cells -hierarchical -quiet -filter "is_combinational == true"]
set buffer_cells [get_cells -hierarchical -quiet -filter "is_buffer == true"]
set inverter_cells [get_cells -hierarchical -quiet -filter "is_inverter == true"]
set register_cells [all_registers]
set latch_cells [get_cells -hierarchical -quiet -filter "is_latch == true"]
set fixed_payload_regs [get_cells -hierarchical -quiet -filter "is_sequential == true && full_name =~ *u_fixed_ingress/u_payload_ram/*mem_reg*"]
set shared_payload_regs [get_cells -hierarchical -quiet -filter "is_sequential == true && full_name =~ *u_shared_ingress/u_pool/u_payload_ram/payload_wb*_mem_reg*"]
set shared_keep_regs [get_cells -hierarchical -quiet -filter "is_sequential == true && full_name =~ *u_shared_ingress/u_pool/u_payload_ram/keep_mem_reg*"]
set mapped_fixed_payload_register_count [sizeof_collection $fixed_payload_regs]
set mapped_shared_payload_register_count [sizeof_collection $shared_payload_regs]
set mapped_shared_keep_register_count [sizeof_collection $shared_keep_regs]
set mapped_payload_keep_register_count [expr {
  $mapped_fixed_payload_register_count +
  $mapped_shared_payload_register_count +
  $mapped_shared_keep_register_count
}]
set ram_named_cells [get_cells -hierarchical -quiet -filter "ref_name =~ *sram* || ref_name =~ *SRAM* || ref_name =~ *RAM*"]
set macro_cells [filter_collection $ram_named_cells "is_hierarchical == false"]
set clocked_register_cells [all_registers -clock $CLOCK_NAME]
set unclocked_sync_endpoint_count [expr {
  [sizeof_collection $register_cells] - [sizeof_collection $clocked_register_cells]
}]

set setup_wns [worst_slack max]
set hold_wns [worst_slack min]
set setup_negative [negative_timing_summary max]
set hold_negative [negative_timing_summary min]
set setup_violation_count [lindex $setup_negative 0]
set setup_tns [lindex $setup_negative 1]
set hold_violation_count [lindex $hold_negative 0]
set hold_tns [lindex $hold_negative 1]
set max_transition_violations [violation_count [file join $REPORT_DIR constraints_max_transition.rpt]]
set max_capacitance_violations [violation_count [file join $REPORT_DIR constraints_max_capacitance.rpt]]
set max_fanout_violations [violation_count [file join $REPORT_DIR constraints_max_fanout.rpt]]
set min_pulse_width_violations [violation_count [file join $REPORT_DIR constraints_min_pulse_width.rpt]]
set min_period_violations [violation_count [file join $REPORT_DIR constraints_min_period.rpt]]
set design_rule_violations [expr {
  $max_transition_violations + $max_capacitance_violations +
  $max_fanout_violations + $min_pulse_width_violations +
  $min_period_violations
}]
set unresolved_reference_count [collection_count_or_zero {
  get_cells -hierarchical -quiet -filter "is_unresolved == true"
}]
# DC O-2018.06 does not support the newer get_designs -hierarchy query and
# has no reliable cell-level black-box attribute.  Keep the MRTC/A1
# fail-closed method: link/check_design, unresolved references, and exact
# expected memory-reference gates.
set unexpected_blackbox_count 0
set blackbox_audit_method link_check_design_unresolved_refs

redirect [file join $REPORT_DIR fixed_payload_registers.rpt] {
  echo "expected_fixed_payload_bits=$EXPECTED_FIXED_PAYLOAD_BITS"
  echo "mapped_fixed_payload_register_count=$mapped_fixed_payload_register_count"
  report_cell $fixed_payload_regs
}
redirect [file join $REPORT_DIR payload_registers.rpt] {
  echo "expected_fixed_payload_bits=$EXPECTED_FIXED_PAYLOAD_BITS"
  echo "expected_shared_payload_bits=$EXPECTED_SHARED_PAYLOAD_BITS"
  echo "expected_shared_keep_bits=$EXPECTED_SHARED_KEEP_BITS"
  echo "expected_payload_keep_bits=$EXPECTED_PAYLOAD_KEEP_BITS"
  echo "mapped_fixed_payload_register_count=$mapped_fixed_payload_register_count"
  echo "mapped_shared_payload_register_count=$mapped_shared_payload_register_count"
  echo "mapped_shared_keep_register_count=$mapped_shared_keep_register_count"
  echo "mapped_payload_keep_register_count=$mapped_payload_keep_register_count"
  echo "shared_payload_registers_begin"
  report_cell $shared_payload_regs
  echo "shared_keep_registers_begin"
  report_cell $shared_keep_regs
}
redirect [file join $REPORT_DIR blackboxes.rpt] {
  echo "unexpected_blackbox_count=$unexpected_blackbox_count"
  echo "unresolved_reference_count=$unresolved_reference_count"
  echo "macro_count=[sizeof_collection $macro_cells]"
}
redirect [file join $REPORT_DIR unclocked_sync_endpoints.rpt] {
  echo "unclocked_sync_endpoint_count=$unclocked_sync_endpoint_count"
}

set gate_status DC_QUALIFIED
set gate_reason none
if {!$check_design_ok} {
  set gate_status FLOW_BLOCKED
  set gate_reason check_design
} elseif {!$check_timing_ok} {
  set gate_status FLOW_BLOCKED
  set gate_reason check_timing
} elseif {$unresolved_reference_count != 0} {
  set gate_status FLOW_BLOCKED
  set gate_reason unresolved_reference
} elseif {$unexpected_blackbox_count != 0} {
  set gate_status FLOW_BLOCKED
  set gate_reason unexpected_blackbox
} elseif {$unclocked_sync_endpoint_count != 0} {
  set gate_status FLOW_BLOCKED
  set gate_reason unclocked_synchronous_endpoint
} elseif {[sizeof_collection $latch_cells] != 0} {
  set gate_status FLOW_BLOCKED
  set gate_reason inferred_latch
} elseif {[sizeof_collection $macro_cells] != 0} {
  set gate_status FLOW_BLOCKED
  set gate_reason unexpected_macro
} elseif {$mapped_fixed_payload_register_count != $EXPECTED_FIXED_PAYLOAD_BITS} {
  set gate_status FLOW_BLOCKED
  set gate_reason fixed_payload_register_count_mismatch
} elseif {$mapped_shared_payload_register_count != $EXPECTED_SHARED_PAYLOAD_BITS} {
  set gate_status FLOW_BLOCKED
  set gate_reason shared_payload_register_count_mismatch
} elseif {$mapped_shared_keep_register_count != $EXPECTED_SHARED_KEEP_BITS} {
  set gate_status FLOW_BLOCKED
  set gate_reason shared_keep_register_count_mismatch
} elseif {$mapped_payload_keep_register_count != $EXPECTED_PAYLOAD_KEEP_BITS} {
  set gate_status FLOW_BLOCKED
  set gate_reason total_payload_keep_register_count_mismatch
} elseif {$setup_wns ne "NA" && $setup_wns < 0.0} {
  set gate_status PARTIAL
  set gate_reason negative_setup_slack
} elseif {$hold_wns ne "NA" && $hold_wns < 0.0} {
  set gate_status PARTIAL
  set gate_reason negative_hold_slack
} elseif {$setup_tns < 0.0 || $hold_tns < 0.0} {
  set gate_status PARTIAL
  set gate_reason negative_total_slack
} elseif {$design_rule_violations != 0} {
  set gate_status PARTIAL
  set gate_reason design_rule_violations
}

set summary [open [file join $REPORT_DIR summary.txt] w]
puts $summary "profile_id=$PROFILE_ID"
puts $summary "top=$TOP"
puts $summary "technology=$TECHNOLOGY"
puts $summary "memory_mode=registers"
puts $summary "macro_count=[sizeof_collection $macro_cells]"
puts $summary "channels=$CHANNELS"
puts $summary "payload_words=$PAYLOAD_WORDS"
puts $summary "payload_aw=$PAYLOAD_AW"
puts $summary "meta_depth=$META_DEPTH"
puts $summary "meta_aw=$META_AW"
puts $summary "frequency_mhz=$FREQUENCY_MHZ"
puts $summary "constraint_mode=$CONSTRAINT_MODE"
puts $summary "clock_name=$ACTUAL_CLOCK_NAME"
puts $summary "clock_period_ns=$ACTUAL_CLOCK_PERIOD"
puts $summary "setup_uncertainty_ns=$ACTUAL_SETUP_UNCERTAINTY_NS"
puts $summary "hold_uncertainty_ns=$ACTUAL_HOLD_UNCERTAINTY_NS"
puts $summary "external_sdc_sha256=$EXTERNAL_SDC_SHA256"
puts $summary "compile_mode=$COMPILE_MODE"
puts $summary "cache_isolated=$CACHE_ISOLATED"
puts $summary "dc_max_cores=$DC_MAX_CORES"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "setup_tns_ns=$setup_tns"
puts $summary "setup_violation_count=$setup_violation_count"
puts $summary "hold_wns_ns=$hold_wns"
puts $summary "hold_tns_ns=$hold_tns"
puts $summary "hold_violation_count=$hold_violation_count"
puts $summary "check_design_ok=$check_design_ok"
puts $summary "check_timing_ok=$check_timing_ok"
puts $summary "unresolved_reference_count=$unresolved_reference_count"
puts $summary "unexpected_blackbox_count=$unexpected_blackbox_count"
puts $summary "blackbox_audit_method=$blackbox_audit_method"
puts $summary "unclocked_sync_endpoint_count=$unclocked_sync_endpoint_count"
puts $summary "latch_count=[sizeof_collection $latch_cells]"
puts $summary "max_transition_violation_count=$max_transition_violations"
puts $summary "max_capacitance_violation_count=$max_capacitance_violations"
puts $summary "max_fanout_violation_count=$max_fanout_violations"
puts $summary "min_pulse_width_violation_count=$min_pulse_width_violations"
puts $summary "min_period_violation_count=$min_period_violations"
puts $summary "design_rule_violation_count=$design_rule_violations"
puts $summary "leaf_cell_count=[sizeof_collection $leaf_cells]"
puts $summary "combinational_cell_count=[sizeof_collection $combinational_cells]"
puts $summary "sequential_cell_count=[sizeof_collection $sequential_cells]"
puts $summary "register_bit_count=[sizeof_collection $register_cells]"
puts $summary "buffer_cell_count=[sizeof_collection $buffer_cells]"
puts $summary "inverter_cell_count=[sizeof_collection $inverter_cells]"
puts $summary "total_cell_area=[sum_cell_area $leaf_cells]"
puts $summary "combinational_area=[sum_cell_area $combinational_cells]"
puts $summary "sequential_area=[sum_cell_area $sequential_cells]"
puts $summary "expected_fixed_payload_bits=$EXPECTED_FIXED_PAYLOAD_BITS"
puts $summary "expected_shared_payload_bits=$EXPECTED_SHARED_PAYLOAD_BITS"
puts $summary "expected_shared_keep_bits=$EXPECTED_SHARED_KEEP_BITS"
puts $summary "expected_payload_keep_bits=$EXPECTED_PAYLOAD_KEEP_BITS"
puts $summary "mapped_fixed_payload_register_count=$mapped_fixed_payload_register_count"
puts $summary "mapped_shared_payload_register_count=$mapped_shared_payload_register_count"
puts $summary "mapped_shared_keep_register_count=$mapped_shared_keep_register_count"
puts $summary "mapped_payload_keep_register_count=$mapped_payload_keep_register_count"
puts $summary "fixed_payload_preserved=[expr {$mapped_fixed_payload_register_count == $EXPECTED_FIXED_PAYLOAD_BITS}]"
puts $summary "shared_payload_preserved=[expr {$mapped_shared_payload_register_count == $EXPECTED_SHARED_PAYLOAD_BITS}]"
puts $summary "shared_keep_preserved=[expr {$mapped_shared_keep_register_count == $EXPECTED_SHARED_KEEP_BITS}]"
puts $summary "payload_preserved=[expr {$mapped_payload_keep_register_count == $EXPECTED_PAYLOAD_KEEP_BITS}]"
puts $summary "gate_status=$gate_status"
puts $summary "gate_reason=$gate_reason"
close $summary

write -format verilog -hierarchy -output [file join $RUN_ROOT ${TOP}.mapped.v]
write -format ddc -hierarchy -output [file join $RUN_ROOT ${TOP}.ddc]
write_sdc [file join $RUN_ROOT ${TOP}.mapped.sdc]

if {$gate_status eq "FLOW_BLOCKED"} {
  error "A3 DC flow gate failed: $gate_reason"
}
exit
