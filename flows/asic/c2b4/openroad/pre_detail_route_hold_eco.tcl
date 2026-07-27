if {![info exists ::env(DMA_C2_REG_HOLD_ECO)] ||
    $::env(DMA_C2_REG_HOLD_ECO) ne "dc550_pnr450_eco1"} {
  error "C2 register hold ECO requires dc550_pnr450_eco1"
}

set hold_endpoints [list \
  {u_shared_ingress/pool_in_data_reg[0][68]/D} \
  {u_shared_ingress/pool_in_data_reg[0][74]/D} \
  {u_shared_ingress/pool_in_data_reg[1][67]/D} \
  {u_shared_ingress/pool_in_data_reg[0][80]/D} \
  {u_shared_ingress/pool_in_data_reg[1][47]/D} \
  {u_shared_ingress/pool_in_data_reg[0][47]/D} \
  {u_shared_ingress/pool_in_data_reg[0][73]/D} \
  {u_shared_ingress/pool_in_data_reg[1][72]/D} \
  {u_shared_ingress/pool_in_data_reg[0][48]/D} \
  {u_shared_ingress/pool_in_data_reg[1][78]/D} \
  {u_shared_ingress/pool_in_data_reg[1][68]/D} \
  {u_shared_ingress/ctx_read_pending_q_reg/D} \
  {u_fixed_ingress/payload_ram_wr_data_q_reg[251]/D} \
  {u_shared_ingress/u_pool/meta_wr_ptr_reg[0][0]/D} \
  {u_fixed_ingress/payload_ram_wr_data_q_reg[252]/D} \
  {u_shared_ingress/frame_valid_q_reg/D} \
  {u_fixed_ingress/meta_rd_ptr_reg[0][0]/D} \
  {u_fixed_ingress/payload_ram_wr_data_q_reg[91]/D} \
  {u_fixed_ingress/payload_ram_wr_data_q_reg[253]/D}]

# ECO1 left one 2.32 ps PrimeTime hold deficit at a new endpoint while retaining
# 1.09158 ns of setup slack.  Add only one stage on that audited path.
set residual_hold_endpoint \
  {u_shared_ingress/pool_in_data_reg[1][74]/D}

set clock_fanout_specs [list \
  [list clkbuf_11_853__f_clk/Z 24] \
  [list clkbuf_11_1194__f_clk/Z 24] \
  [list clkbuf_11_768__f_clk/Z 20] \
  [list clkbuf_11_1025__f_clk/Z 18] \
  [list clkbuf_11_1322__f_clk/Z 18] \
  [list clkbuf_11_852__f_clk/Z 17]]

foreach existing [get_cells -quiet {dma_c2_hold_eco_* dma_c2_clk_eco_*}] {
  error "C2 register hold ECO cannot be applied twice: $existing"
}

set block [ord::get_db_block]

proc dma_c2_insert_odb_buffer {block endpoint_name cell_name instance_name net_name} {
  set endpoint [get_pins -quiet $endpoint_name]
  if {[llength $endpoint] != 1} {
    error "Expected one C2 hold ECO endpoint: $endpoint_name"
  }
  set endpoint_iterm [sta::sta_to_db_pin $endpoint]
  if {$endpoint_iterm eq "NULL"} {
    error "Missing C2 hold ECO endpoint pin: $endpoint_name"
  }
  set source_net [$endpoint_iterm getNet]
  if {$source_net eq "NULL"} {
    error "Disconnected C2 hold ECO endpoint: $endpoint_name"
  }
  if {[$block findInst $instance_name] ne "NULL" ||
      [$block findNet $net_name] ne "NULL"} {
    error "C2 hold ECO object already exists: $instance_name/$net_name"
  }
  set master [[ord::get_db] findMaster $cell_name]
  if {$master eq "NULL"} {
    error "Missing C2 hold ECO master: $cell_name"
  }
  set buffer [odb::dbInst_create $block $master $instance_name]
  set buffer_input [$buffer findITerm A]
  set buffer_output [$buffer findITerm Z]
  if {$buffer_input eq "NULL" || $buffer_output eq "NULL"} {
    error "Unexpected C2 hold ECO buffer interface: $cell_name"
  }
  set delay_net [odb::dbNet_create $block $net_name]
  $endpoint_iterm disconnect
  odb::dbITerm_connect $endpoint_iterm $delay_net
  odb::dbITerm_connect $buffer_input $source_net
  odb::dbITerm_connect $buffer_output $delay_net

  # OpenDB-created instances have no placement seed.  Start beside the target
  # register and leave them movable so detailed_placement can legalize the ECO.
  set endpoint_instance [$endpoint_iterm getInst]
  set endpoint_bbox [$endpoint_instance getBBox]
  $buffer setLocation [$endpoint_bbox xMin] [$endpoint_bbox yMin]
  $buffer setPlacementStatus PLACED
}

set dma_c2_eco_dry_audit [expr {
  [info exists ::env(DMA_C2_REG_ECO_DRY_AUDIT)] &&
  $::env(DMA_C2_REG_ECO_DRY_AUDIT) eq "1"
}]
if {!$dma_c2_eco_dry_audit} {
  global_route -start_incremental
}

set clock_index 0
foreach spec $clock_fanout_specs {
  lassign $spec driver_name expected_load_count
  if {![regexp {^(.+)/([^/]+)$} $driver_name -> instance_name pin_name]} {
    error "Malformed clock driver name: $driver_name"
  }
  set instance [$block findInst $instance_name]
  if {$instance eq "NULL"} {
    error "Missing clock driver instance: $instance_name"
  }
  set driver_iterm "NULL"
  foreach iterm [$instance getITerms] {
    if {[[$iterm getMTerm] getName] eq $pin_name} {
      set driver_iterm $iterm
    }
  }
  if {$driver_iterm eq "NULL"} {
    error "Missing clock driver pin: $driver_name"
  }
  set net [$driver_iterm getNet]
  if {$net eq "NULL"} {
    error "Clock driver is disconnected: $driver_name"
  }
  set load_names {}
  foreach load_iterm [$net getITerms] {
    if {$load_iterm eq $driver_iterm} {
      continue
    }
    set load_instance [$load_iterm getInst]
    set load_mterm [$load_iterm getMTerm]
    lappend load_names "[$load_instance getName]/[$load_mterm getName]"
  }
  set load_names [lsort -dictionary -unique $load_names]
  if {[llength $load_names] != $expected_load_count} {
    error "Clock fanout changed for $driver_name: [llength $load_names]"
  }
  set split [expr {($expected_load_count + 1) / 2}]
  set group_names [list \
    [lrange $load_names 0 [expr {$split - 1}]] \
    [lrange $load_names $split end]]
  set group_index 0
  foreach names $group_names {
    if {[llength $names] == 0 || [llength $names] > 12} {
      error "Invalid clock fanout ECO group for $driver_name"
    }
    set load_pins [get_pins -quiet $names]
    if {[llength $load_pins] != [llength $names]} {
      error "Clock fanout ECO load resolution failed for $driver_name"
    }
    insert_buffer \
      -buffer_cell CLKBUF_X3 \
      -load_pins $load_pins \
      -buffer_name dma_c2_clk_eco_${clock_index}_${group_index} \
      -net_name dma_c2_clk_eco_net_${clock_index}_${group_index}
    incr group_index
  }
  incr clock_index
}

set hold_index 0
foreach endpoint_name $hold_endpoints {
  for {set stage 0} {$stage < 2} {incr stage} {
    dma_c2_insert_odb_buffer $block $endpoint_name CLKBUF_X1 \
      dma_c2_hold_eco_${hold_index}_${stage} \
      dma_c2_hold_eco_net_${hold_index}_${stage}
  }
  incr hold_index
}
dma_c2_insert_odb_buffer $block $residual_hold_endpoint CLKBUF_X1 \
  dma_c2_hold_eco_${hold_index}_0 \
  dma_c2_hold_eco_net_${hold_index}_0

set clock_eco_cells {}
set hold_eco_cells {}
foreach eco_instance [$block getInsts] {
  set eco_name [$eco_instance getName]
  if {[string match dma_c2_clk_eco_* $eco_name]} {
    lappend clock_eco_cells $eco_name
  }
  if {[string match dma_c2_hold_eco_* $eco_name]} {
    lappend hold_eco_cells $eco_name
  }
}
set clock_eco_count [llength $clock_eco_cells]
set hold_eco_count [llength $hold_eco_cells]
if {$clock_eco_count != 12 || $hold_eco_count != 39} {
  error "Unexpected C2 register ECO cell count: clock=$clock_eco_count hold=$hold_eco_count cells=$hold_eco_cells"
}
foreach hold_eco_name $hold_eco_cells {
  set hold_eco_instance [$block findInst $hold_eco_name]
  if {[$hold_eco_instance getPlacementStatus] eq "NONE"} {
    error "C2 hold ECO cell has no placement seed: $hold_eco_name"
  }
}

if {$dma_c2_eco_dry_audit} {
  puts "DMA_C2_REGISTER_HOLD_ECO_DRY_AUDIT_PASS clock_buffers=12 hold_buffers=39"
  return
}

detailed_placement
global_route -end_incremental \
  -guide_file $::env(RESULTS_DIR)/route.guide \
  -congestion_report_file $::env(REPORTS_DIR)/congestion_post_dma_c2_hold_eco.rpt
estimate_parasitics -global_routing
report_check_types -violators -max_fanout -max_capacitance -max_slew \
  -digits 4 -max_count 1000 \
  > $::env(REPORTS_DIR)/dma_c2_hold_eco_electrical.rpt
puts "DMA_C2_REGISTER_HOLD_ECO_PASS clock_buffers=12 hold_buffers=39"
