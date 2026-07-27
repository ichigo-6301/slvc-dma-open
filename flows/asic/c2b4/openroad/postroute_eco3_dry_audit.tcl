foreach name {DMA_C2_REG_ECO_ODB DMA_C2_REG_ECO_LIBERTY} {
  if {![info exists ::env($name)]} {
    error "$name is required"
  }
}
read_liberty $::env(DMA_C2_REG_ECO_LIBERTY)
read_db $::env(DMA_C2_REG_ECO_ODB)
set ::env(DMA_C2_REG_HOLD_ECO) dc550_pnr450_eco3
set ::env(DMA_C2_REG_ECO_DRY_AUDIT) 1
source [file join [file dirname [info script]] pre_detail_route_hold_eco3.tcl]
