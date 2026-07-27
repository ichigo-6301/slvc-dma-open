# DC can emit local constant nets with POWER/GROUND signal types. Normalize
# only the known local one_/zero_ names while preserving real supply nets.
if {![info exists ::env(DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS)]} {
  error "DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS is required"
}
if {![string is double -strict $::env(DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS)]} {
  error "Global-route hold margin must be numeric"
}
if {![info exists ::env(HOLD_SLACK_MARGIN)] ||
    ![string is double -strict $::env(HOLD_SLACK_MARGIN)]} {
  error "CTS hold margin is missing or non-numeric"
}

set cts_hold_margin [expr {double($::env(HOLD_SLACK_MARGIN))}]
set grt_hold_margin [expr {double($::env(DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS))}]
if {abs($cts_hold_margin - 0.060) > 0.000001} {
  error "Unexpected CTS hold margin: $cts_hold_margin"
}
if {abs($grt_hold_margin) > 0.000001} {
  error "Unexpected global-route hold margin: $grt_hold_margin"
}
set ::env(HOLD_SLACK_MARGIN) $::env(DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS)
puts [format "DMA_C4_REG_GRT_HOLD_MARGIN_PASS cts=%.3f grt=%.3f" \
  $cts_hold_margin $grt_hold_margin]

set normalized 0
set unexpected {}
set block [ord::get_db_block]

set placement_result [string trim [check_placement -verbose]]
if {$placement_result eq ""} {
  set placement_violations 0
} elseif {[string is integer -strict $placement_result]} {
  set placement_violations $placement_result
} else {
  error "Unexpected check_placement result: $placement_result"
}
if {$placement_violations != 0} {
  error "Register showcase pre-route placement violations: $placement_violations"
}

foreach net [$block getNets] {
  set name [$net getName]
  set sig_type [$net getSigType]
  if {$sig_type eq "POWER" || $sig_type eq "GROUND"} {
    if {$name eq "VDD" || $name eq "VSS"} {
      continue
    }
    if {[regexp {(^|/)(one_|zero_)} $name]} {
      $net setSigType SIGNAL
      incr normalized
    } else {
      lappend unexpected $name
    }
  }
}
if {[llength $unexpected] != 0} {
  error "Unexpected non-supply POWER/GROUND nets: $unexpected"
}
if {$normalized == 0} {
  error "Expected at least one DC local constant net to normalize"
}

puts "DMA_C4_REG_CONSTANT_NET_AUDIT_PASS normalized=$normalized placement_violations=0"
