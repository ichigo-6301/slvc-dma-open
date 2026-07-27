# Generated C2B4 register showcase constraint. Do not edit.
set dma_a3_external_sdc_status 0
set dma_a3_external_sdc_message ""
if {![catch {
  create_clock -name a1_clk -period 1.818182 [get_ports clk]
  set_clock_uncertainty -setup 0.200 [get_clocks a1_clk]
  set_clock_uncertainty -hold 0.050 [get_clocks a1_clk]
  set register_nonclock_inputs [remove_from_collection [all_inputs] [get_ports clk]]
  set_input_delay 0.500 -clock a1_clk $register_nonclock_inputs
  set_input_transition 0.100 $register_nonclock_inputs
  set_output_delay 0.500 -clock a1_clk [all_outputs]
  set_load 0.050 [all_outputs]
  set_false_path -from [get_ports rstn]
  set_max_fanout 16 [current_design]
  set_max_transition 0.500 [current_design]
} dma_a3_external_sdc_message]} {
  set dma_a3_external_sdc_status 1
}
