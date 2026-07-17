create_clock -name adapter_clk -period 5.000 [get_ports clk]

set_clock_uncertainty -setup 0.200 [get_clocks adapter_clk]
set_clock_uncertainty -hold  0.050 [get_clocks adapter_clk]
set_input_delay  0.500 -clock adapter_clk \
    [remove_from_collection [all_inputs] [get_ports {clk rstn}]]
set_input_delay  0.000 -clock adapter_clk [get_ports rstn]
set_output_delay 0.500 -clock adapter_clk [all_outputs]

set_false_path -from [get_ports rstn]
set_max_fanout 16 [current_design]
set_max_transition 0.500 [current_design]

if {[info exists ::env(DMA_DC_DRIVING_CELL)] && $::env(DMA_DC_DRIVING_CELL) ne ""} {
    set_driving_cell -lib_cell $::env(DMA_DC_DRIVING_CELL) \
        [remove_from_collection [all_inputs] [get_ports {clk rstn}]]
} else {
    set_input_transition 0.100 \
        [remove_from_collection [all_inputs] [get_ports {clk rstn}]]
}

if {[info exists ::env(DMA_DC_OUTPUT_LOAD)] && $::env(DMA_DC_OUTPUT_LOAD) ne ""} {
    set_load $::env(DMA_DC_OUTPUT_LOAD) [all_outputs]
} else {
    set_load 0.050 [all_outputs]
}
