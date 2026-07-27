foreach name {DMA_A5_CTS_PROFILE DMA_A5_CLOCK_PIN_COORDS_TCL
              DMA_A5_EXPECTED_CLOCK_LEAVES DMA_A5_CLOCK_LEAF_CELL} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing $name for A5 clock-leaf insertion"
  }
}
source $::env(DMA_A5_CLOCK_PIN_COORDS_TCL)
if {![info exists dma_a5_clock_pin_coords]} {
  error "A5 clock-pin coordinate dictionary is missing"
}

proc a5_snap_x {microns} {
  return [expr {20.14 + round(($microns - 20.14) / 0.19) * 0.19}]
}
proc a5_snap_y {microns} {
  return [expr {22.4 + round(($microns - 22.4) / 1.4) * 1.4}]
}
proc a5_pin_xy {inst pin_name coordinates} {
  set master_name [[$inst getMaster] getName]
  if {![dict exists $coordinates $master_name $pin_name]} {
    error "No clock coordinate for $master_name/$pin_name"
  }
  lassign [dict get $coordinates $master_name $pin_name] px py
  set bbox [$inst getBBox]
  set x0 [ord::dbu_to_microns [$bbox xMin]]
  set y0 [ord::dbu_to_microns [$bbox yMin]]
  set width [ord::dbu_to_microns [expr {[$bbox xMax] - [$bbox xMin]}]]
  set height [ord::dbu_to_microns [expr {[$bbox yMax] - [$bbox yMin]}]]
  set orient [$inst getOrient]
  switch -- $orient {
    R0 { set x [expr {$x0 + $px}]; set y [expr {$y0 + $py}] }
    MX { set x [expr {$x0 + $px}]; set y [expr {$y0 + $height - $py}] }
    MY { set x [expr {$x0 + $width - $px}]; set y [expr {$y0 + $py}] }
    R180 { set x [expr {$x0 + $width - $px}]; set y [expr {$y0 + $height - $py}] }
    default { error "Unsupported A5 macro orientation $orient" }
  }
  return [list $x $y $x0 $y0 $width $height]
}
proc a5_iterm {inst pin_name} {
  foreach iterm [$inst getITerms] {
    if {[[$iterm getMTerm] getName] eq $pin_name} { return $iterm }
  }
  error "Missing [$inst getName]/$pin_name"
}
proc a5_leaf_name {index pin_name} {
  return [format "dma_a5_clk_leaf_%03d_%s" $index $pin_name]
}
proc a5_clock_buffers {block} {
  set result [dict create]
  foreach inst [$block getInsts] {
    if {[[$inst getMaster] getName] eq $::env(DMA_A5_CLOCK_LEAF_CELL)} {
      dict set result [$inst getName] $inst
    }
  }
  return $result
}

set block [ord::get_db_block]
set macro_names {}
foreach inst [$block getInsts] {
  set master_name [[$inst getMaster] getName]
  if {[dict exists $dma_a5_clock_pin_coords $master_name]} {
    lappend macro_names [$inst getName]
  }
}
set macro_names [lsort $macro_names]
set expected $::env(DMA_A5_EXPECTED_CLOCK_LEAVES)
if {[llength $macro_names] * 2 != $expected} {
  error "A5 clock-leaf macro inventory implies [expr {[llength $macro_names] * 2}] leaves, expected $expected"
}

set leaf_cell $::env(DMA_A5_CLOCK_LEAF_CELL)
set inserted 0
set max_distance 0.0
for {set macro_index 0} {$macro_index < [llength $macro_names]} {incr macro_index} {
  set macro [$block findInst [lindex $macro_names $macro_index]]
  foreach pin_name {clk0 clk1} {
    set iterm [a5_iterm $macro $pin_name]
    set source_net [$iterm getNet]
    if {$source_net eq "NULL"} { error "A5 macro clock pin has no net" }
    lassign [a5_pin_xy $macro $pin_name $dma_a5_clock_pin_coords] \
      pin_x pin_y macro_x macro_y macro_width macro_height
    set macro_center_x [expr {$macro_x + 0.5 * $macro_width}]
    set gap 5.0
    if {$pin_x <= $macro_center_x} {
      set insert_x [expr {$macro_x - 10.0}]
    } else {
      set insert_x [expr {$macro_x + $macro_width + $gap}]
    }
    set insert_y $pin_y
    set leaf_name [a5_leaf_name $macro_index $pin_name]
    set leaf_net_name "${leaf_name}_to_macro"
    set sta_pin [get_pins -quiet "[$macro getName]/$pin_name"]
    if {[llength $sta_pin] != 1} {
      error "A5 cannot resolve STA pin [$macro getName]/$pin_name"
    }
    set before [a5_clock_buffers $block]
    insert_buffer -buffer_cell $leaf_cell -net [get_nets [$source_net getName]] \
      -load_pins $sta_pin -location [list $insert_x $insert_y] \
      -buffer_name $leaf_name -net_name $leaf_net_name
    set after [a5_clock_buffers $block]
    set new_names {}
    foreach candidate [dict keys $after] {
      if {![dict exists $before $candidate]} { lappend new_names $candidate }
    }
    if {[llength $new_names] != 1} {
      error "A5 insert_buffer created [llength $new_names] new $leaf_cell instances"
    }
    set leaf [dict get $after [lindex $new_names 0]]
    if {![$leaf rename $leaf_name]} {
      error "A5 could not rename clock leaf to $leaf_name"
    }
    set leaf_output [a5_iterm $leaf Z]
    set leaf_net [$leaf_output getNet]
    if {$leaf_net eq "NULL" || ![$leaf_net rename $leaf_net_name]} {
      error "A5 could not rename clock leaf net to $leaf_net_name"
    }
    set leaf_width [ord::dbu_to_microns [[$leaf getMaster] getWidth]]
    set leaf_height [ord::dbu_to_microns [[$leaf getMaster] getHeight]]
    if {$pin_x <= $macro_center_x} {
      set target_x [expr {$macro_x - $gap - $leaf_width}]
    } else {
      set target_x [expr {$macro_x + $macro_width + $gap}]
    }
    set target_x [a5_snap_x $target_x]
    set target_y [a5_snap_y [expr {$pin_y - 0.5 * $leaf_height}]]
    set dbu [$block getDbUnitsPerMicron]
    set row_index [expr {round(($target_y - 22.4) / 1.4)}]
    set orient [expr {$row_index % 2 == 0 ? "R0" : "MX"}]
    $leaf setOrient $orient
    $leaf setLocation [expr {round($target_x * $dbu)}] \
      [expr {round($target_y * $dbu)}]
    $leaf setPlacementStatus FIRM
    set center_x [expr {$target_x + 0.5 * $leaf_width}]
    set center_y [expr {$target_y + 0.5 * $leaf_height}]
    set distance [expr {abs($center_x - $pin_x) + abs($center_y - $pin_y)}]
    if {$distance > $max_distance} { set max_distance $distance }
    if {$distance > 20.0} {
      error "A5 clock leaf $leaf_name is $distance um from its macro pin"
    }
    incr inserted
  }
}
if {$inserted != $expected} {
  error "A5 inserted $inserted clock leaves, expected $expected"
}
puts "DMA_A5_CLOCK_LEAF_INSERT_PASS profile=$::env(DMA_A5_CTS_PROFILE) leaves=$inserted cell=$leaf_cell max_pin_leaf_distance_um=$max_distance stage=PRE_CTS"
