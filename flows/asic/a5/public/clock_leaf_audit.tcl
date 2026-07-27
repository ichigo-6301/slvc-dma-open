foreach name {DMA_A5_CTS_PROFILE DMA_A5_CLOCK_PIN_COORDS_TCL
              DMA_A5_EXPECTED_CLOCK_LEAVES DMA_A5_CLOCK_LEAF_CELL} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing $name for A5 post-CTS clock-leaf audit"
  }
}
source $::env(DMA_A5_CLOCK_PIN_COORDS_TCL)
if {![info exists dma_a5_clock_pin_coords]} {
  error "A5 clock-pin coordinate dictionary is missing"
}

proc a5_audit_pin_xy {inst pin_name coordinates} {
  set master_name [[$inst getMaster] getName]
  lassign [dict get $coordinates $master_name $pin_name] px py
  set bbox [$inst getBBox]
  set x0 [ord::dbu_to_microns [$bbox xMin]]
  set y0 [ord::dbu_to_microns [$bbox yMin]]
  set width [ord::dbu_to_microns [expr {[$bbox xMax] - [$bbox xMin]}]]
  set height [ord::dbu_to_microns [expr {[$bbox yMax] - [$bbox yMin]}]]
  switch -- [$inst getOrient] {
    R0 { return [list [expr {$x0 + $px}] [expr {$y0 + $py}]] }
    MX { return [list [expr {$x0 + $px}] [expr {$y0 + $height - $py}]] }
    MY { return [list [expr {$x0 + $width - $px}] [expr {$y0 + $py}]] }
    R180 { return [list [expr {$x0 + $width - $px}] [expr {$y0 + $height - $py}]] }
    default { error "Unsupported A5 macro orientation [$inst getOrient]" }
  }
}
proc a5_audit_iterm {inst pin_name} {
  foreach iterm [$inst getITerms] {
    if {[[$iterm getMTerm] getName] eq $pin_name} { return $iterm }
  }
  error "Missing [$inst getName]/$pin_name"
}
proc a5_audit_leaf_name {index pin_name} {
  return [format "dma_a5_clk_leaf_%03d_%s" $index $pin_name]
}
proc a5_audit_find_leaf {block leaf_name} {
  set matches {}
  foreach inst [$block getInsts] {
    set name [$inst getName]
    if {$name eq $leaf_name || [string match "*/$leaf_name" $name]} {
      lappend matches $inst
    }
  }
  if {[llength $matches] != 1} {
    error "A5 found [llength $matches] post-CTS instances for $leaf_name"
  }
  return [lindex $matches 0]
}

set block [ord::get_db_block]
set macro_names {}
foreach inst [$block getInsts] {
  if {[dict exists $dma_a5_clock_pin_coords [[$inst getMaster] getName]]} {
    lappend macro_names [$inst getName]
  }
}
set macro_names [lsort $macro_names]
set expected $::env(DMA_A5_EXPECTED_CLOCK_LEAVES)
set leaf_cell $::env(DMA_A5_CLOCK_LEAF_CELL)
set audited 0
set max_distance 0.0
for {set macro_index 0} {$macro_index < [llength $macro_names]} {incr macro_index} {
  set macro [$block findInst [lindex $macro_names $macro_index]]
  foreach pin_name {clk0 clk1} {
    set leaf_name [a5_audit_leaf_name $macro_index $pin_name]
    set leaf [a5_audit_find_leaf $block $leaf_name]
    if {[[$leaf getMaster] getName] ne $leaf_cell} {
      error "A5 post-CTS leaf $leaf_name was replaced"
    }
    if {[$leaf getPlacementStatus] ne "FIRM"} {
      error "A5 post-CTS leaf $leaf_name lost FIRM state"
    }
    set macro_clock [a5_audit_iterm $macro $pin_name]
    set macro_net [$macro_clock getNet]
    set leaf_output [a5_audit_iterm $leaf Z]
    if {$macro_net eq "NULL" || [$leaf_output getNet] ne $macro_net} {
      error "A5 leaf $leaf_name no longer drives [$macro getName]/$pin_name"
    }
    set loads 0
    foreach sink [$macro_net getITerms] {
      if {[[$sink getMTerm] getIoType] eq "INPUT"} { incr loads }
    }
    if {$loads != 1} { error "A5 leaf $leaf_name drives $loads loads, expected 1" }
    set leaf_input [a5_audit_iterm $leaf A]
    if {[$leaf_input getNet] eq "NULL"} {
      error "A5 leaf $leaf_name has a dangling input"
    }
    lassign [a5_audit_pin_xy $macro $pin_name $dma_a5_clock_pin_coords] pin_x pin_y
    set bbox [$leaf getBBox]
    set leaf_x [ord::dbu_to_microns [expr {([$bbox xMin] + [$bbox xMax]) / 2}]]
    set leaf_y [ord::dbu_to_microns [expr {([$bbox yMin] + [$bbox yMax]) / 2}]]
    set distance [expr {abs($leaf_x - $pin_x) + abs($leaf_y - $pin_y)}]
    if {$distance > $max_distance} { set max_distance $distance }
    if {$distance > 20.0} {
      error "A5 post-CTS leaf $leaf_name moved $distance um from its macro pin"
    }
    incr audited
  }
}
if {$audited != $expected} {
  error "A5 post-CTS audited $audited leaves, expected $expected"
}
set all_leaf_count 0
foreach inst [$block getInsts] {
  if {[regexp {(^|/)dma_a5_clk_leaf_[0-9]+_clk[01]$} [$inst getName]]} {
    incr all_leaf_count
  }
}
if {$all_leaf_count != $expected} {
  error "A5 post-CTS database has $all_leaf_count named leaves, expected $expected"
}
puts "DMA_A5_CLOCK_LEAF_AUDIT_PASS profile=$::env(DMA_A5_CTS_PROFILE) leaves=$audited cell=$leaf_cell max_pin_leaf_distance_um=$max_distance stage=POST_CTS"
