if {![info exists ::env(DMA_C2_REG_ECO_ODB)]} {
  error "DMA_C2_REG_ECO_ODB is required"
}

read_db $::env(DMA_C2_REG_ECO_ODB)
set block [ord::get_db_block]
set driver_names [list \
  clkbuf_11_853__f_clk/Z \
  clkbuf_11_1194__f_clk/Z \
  clkbuf_11_768__f_clk/Z \
  clkbuf_11_1025__f_clk/Z \
  clkbuf_11_1322__f_clk/Z \
  clkbuf_11_852__f_clk/Z]

foreach driver_name $driver_names {
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
  puts "driver=$driver_name net=[$net getName] loads=[llength $load_names]"
  foreach load_name $load_names {
    puts "load=$driver_name\t$load_name"
  }
}

puts "DMA_C2_REGISTER_POSTROUTE_ECO_INVENTORY_PASS drivers=6"
