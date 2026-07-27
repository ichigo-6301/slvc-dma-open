set dma_c4_clock_inputs [get_ports -quiet clk]
if {[sizeof_collection $dma_c4_clock_inputs] != 1} {
  error "C4B4 PrimeTime expected one clock input"
}
set_driving_cell -lib_cell CLKBUF_X3 -pin Z \
  -input_transition_rise 0.100 -input_transition_fall 0.100 \
  $dma_c4_clock_inputs

set dma_c4_nonclock_inputs [remove_from_collection [all_inputs] $dma_c4_clock_inputs]
if {[sizeof_collection $dma_c4_nonclock_inputs] == 0} {
  error "C4B4 PrimeTime found no non-clock inputs"
}
set_driving_cell -lib_cell BUF_X1 -pin Z \
  -input_transition_rise 0.100 -input_transition_fall 0.100 \
  $dma_c4_nonclock_inputs
puts "DMA_C4_REGISTER_PT_INPUT_DRIVER_PASS"
