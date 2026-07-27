proc fail {message} {
  echo "ERROR: $message"
  exit 2
}

proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    fail "Missing required environment variable: $name"
  }
  return $::env($name)
}

set db_path [require_env DMA_A5_LC_OUTPUT_DB]
set report_path [require_env DMA_A5_LC_AUDIT_REPORT]
set library_name [require_env DMA_A5_LC_LIBRARY_NAME]
set expected_cell [require_env DMA_A5_LC_EXPECTED_CELL]

if {[catch {read_db $db_path} read_message]} {
  fail "Compiled DB readback failed: $read_message"
}

set loaded_libraries [get_libs -quiet $library_name]
if {[sizeof_collection $loaded_libraries] != 1} {
  fail "Compiled DB readback did not load library '$library_name'"
}
set loaded_cells [get_lib_cells -quiet "${library_name}/${expected_cell}"]
if {[sizeof_collection $loaded_cells] != 1} {
  fail "Compiled DB readback did not load cell '${library_name}/${expected_cell}'"
}

set clk0_count 0
set clk1_count 0
set dout1_0_count 0
set clk0_capacitance ""
set clk1_capacitance ""
set dout1_0_max_capacitance ""
foreach_in_collection pin [get_lib_pins -of_objects $loaded_cells] {
  set pin_name [get_object_name $pin]
  if {$pin_name eq "clk0"} {
    incr clk0_count
    set clk0_capacitance [get_attribute $pin capacitance]
  } elseif {$pin_name eq "clk1"} {
    incr clk1_count
    set clk1_capacitance [get_attribute $pin capacitance]
  } elseif {$pin_name eq {dout1[0]}} {
    incr dout1_0_count
    set dout1_0_max_capacitance [get_attribute $pin max_capacitance]
  }
}
if {$clk0_count != 1 || $clk1_count != 1 || $dout1_0_count != 1} {
  fail "Compiled DB readback did not expose the expected clock/output sentinel pins"
}

if {[catch {
  redirect -file $report_path {
    echo "expected_library=$library_name"
    echo "expected_cell=$expected_cell"
    echo "loaded_library_count=[sizeof_collection $loaded_libraries]"
    echo "loaded_cell_count=[sizeof_collection $loaded_cells]"
    echo "loaded_library_object=[get_object_name $loaded_libraries]"
    echo "loaded_cell_object=[get_object_name $loaded_cells]"
    echo "time_unit=[get_attribute $loaded_libraries time_unit]"
    echo "capacitive_load_unit=[get_attribute $loaded_libraries capacitive_load_unit]"
    echo "nom_voltage=[get_attribute $loaded_libraries nom_voltage]"
    echo "nom_temperature=[get_attribute $loaded_libraries nom_temperature]"
    echo "clk0_capacitance=$clk0_capacitance"
    echo "clk1_capacitance=$clk1_capacitance"
    echo "dout1_0_max_capacitance=$dout1_0_max_capacitance"
    list_libs
    report_lib $library_name
    echo "report_status=PASS"
  }
} report_message]} {
  fail "Compiled DB audit report failed: $report_message"
}
if {![file isfile $report_path] || [file size $report_path] == 0} {
  fail "Library Compiler did not create the DB audit report"
}
puts "DMA_A5_LC_DB_READBACK_PASS db=$db_path report=$report_path"
exit 0
