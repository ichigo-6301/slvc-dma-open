if {![info exists ::env(DMA_C2_REG_HOLD_ECO)] ||
    $::env(DMA_C2_REG_HOLD_ECO) ne "dc550_pnr450_eco3"} {
  error "C2 register incremental hold ECO requires dc550_pnr450_eco3"
}

set residual_endpoints [list \
  {u_fixed_ingress/payload_ram_wr_data_q_reg[278]/D} \
  {u_shared_ingress/pool_in_data_reg[0][46]/D}]
set block [ord::get_db_block]

proc dma_c2_insert_incremental_buffer {block endpoint_name instance_name net_name} {
  set endpoint [get_pins -quiet $endpoint_name]
  if {[llength $endpoint] != 1} {
    error "Expected one C2 incremental hold endpoint: $endpoint_name"
  }
  set endpoint_iterm [sta::sta_to_db_pin $endpoint]
  if {$endpoint_iterm eq "NULL"} {
    error "Missing C2 incremental hold endpoint pin: $endpoint_name"
  }
  set source_net [$endpoint_iterm getNet]
  if {$source_net eq "NULL"} {
    error "Disconnected C2 incremental hold endpoint: $endpoint_name"
  }
  if {[$block findInst $instance_name] ne "NULL" ||
      [$block findNet $net_name] ne "NULL"} {
    error "C2 incremental hold object already exists: $instance_name/$net_name"
  }
  set master [[ord::get_db] findMaster CLKBUF_X1]
  if {$master eq "NULL"} {
    error "Missing C2 incremental hold master: CLKBUF_X1"
  }
  set buffer [odb::dbInst_create $block $master $instance_name]
  set buffer_input [$buffer findITerm A]
  set buffer_output [$buffer findITerm Z]
  if {$buffer_input eq "NULL" || $buffer_output eq "NULL"} {
    error "Unexpected C2 incremental hold buffer interface"
  }
  set delay_net [odb::dbNet_create $block $net_name]
  $endpoint_iterm disconnect
  odb::dbITerm_connect $endpoint_iterm $delay_net
  odb::dbITerm_connect $buffer_input $source_net
  odb::dbITerm_connect $buffer_output $delay_net

  set endpoint_instance [$endpoint_iterm getInst]
  set endpoint_bbox [$endpoint_instance getBBox]
  $buffer setLocation [$endpoint_bbox xMin] [$endpoint_bbox yMin]
  $buffer setPlacementStatus PLACED
}

proc dma_c2_eco_counts {block} {
  set clock_count 0
  set hold_count 0
  foreach instance [$block getInsts] {
    set name [$instance getName]
    if {[string match dma_c2_clk_eco_* $name]} {
      incr clock_count
    }
    if {[string match dma_c2_hold_eco_* $name]} {
      incr hold_count
    }
  }
  return [list $clock_count $hold_count]
}

lassign [dma_c2_eco_counts $block] initial_clock_count initial_hold_count
if {$initial_clock_count != 12 || $initial_hold_count != 39} {
  error "Unexpected ECO2 input inventory: clock=$initial_clock_count hold=$initial_hold_count"
}

set dma_c2_eco_dry_audit [expr {
  [info exists ::env(DMA_C2_REG_ECO_DRY_AUDIT)] &&
  $::env(DMA_C2_REG_ECO_DRY_AUDIT) eq "1"
}]
if {!$dma_c2_eco_dry_audit} {
  global_route -start_incremental
}

set residual_index 0
foreach endpoint_name $residual_endpoints {
  dma_c2_insert_incremental_buffer $block $endpoint_name \
    dma_c2_hold_eco_pt2_${residual_index} \
    dma_c2_hold_eco_pt2_net_${residual_index}
  incr residual_index
}

lassign [dma_c2_eco_counts $block] final_clock_count final_hold_count
if {$final_clock_count != 12 || $final_hold_count != 41} {
  error "Unexpected ECO3 inventory: clock=$final_clock_count hold=$final_hold_count"
}
foreach index {0 1} {
  set instance [$block findInst dma_c2_hold_eco_pt2_${index}]
  if {$instance eq "NULL" || [$instance getPlacementStatus] eq "NONE"} {
    error "C2 incremental hold buffer lacks a placement seed: $index"
  }
}

if {$dma_c2_eco_dry_audit} {
  puts "DMA_C2_REGISTER_HOLD_ECO3_DRY_AUDIT_PASS clock_buffers=12 hold_buffers=41"
  return
}

detailed_placement
global_route -end_incremental \
  -guide_file $::env(RESULTS_DIR)/route.guide \
  -congestion_report_file $::env(REPORTS_DIR)/congestion_post_dma_c2_hold_eco3.rpt
estimate_parasitics -global_routing
report_check_types -violators -max_fanout -max_capacitance -max_slew \
  -digits 4 -max_count 1000 \
  > $::env(REPORTS_DIR)/dma_c2_hold_eco3_electrical.rpt
puts "DMA_C2_REGISTER_HOLD_ECO3_PASS clock_buffers=12 hold_buffers=41"
