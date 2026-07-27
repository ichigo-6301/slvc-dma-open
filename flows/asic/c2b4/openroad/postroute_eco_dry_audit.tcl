if {![info exists ::env(DMA_C2_REG_ECO_ODB)]} {
  error "DMA_C2_REG_ECO_ODB is required"
}
if {![info exists ::env(DMA_C2_REG_ECO_LIBERTY)]} {
  error "DMA_C2_REG_ECO_LIBERTY is required"
}
read_liberty $::env(DMA_C2_REG_ECO_LIBERTY)
read_db $::env(DMA_C2_REG_ECO_ODB)
set ::env(DMA_C2_REG_HOLD_ECO) dc550_pnr450_eco1
set ::env(DMA_C2_REG_ECO_DRY_AUDIT) 1
source [file join [file dirname [info script]] pre_detail_route_hold_eco.tcl]
