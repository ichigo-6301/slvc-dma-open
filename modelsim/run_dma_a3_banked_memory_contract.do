transcript on

proc require_env {name} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        error "Missing environment variable: $name"
    }
    return $::env($name)
}

set payload_ram_source [require_env DMA_A3_PAYLOAD_RAM_SOURCE]
set frame_payload_ram_source [require_env DMA_A3_FRAME_PAYLOAD_RAM_SOURCE]
set fixed_depth [require_env DMA_A3_FIXED_DEPTH]
set fixed_depth_aw [require_env DMA_A3_FIXED_DEPTH_AW]
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +define+DMA_A3_FIXED_DEPTH=$fixed_depth \
    +define+DMA_A3_FIXED_DEPTH_AW=$fixed_depth_aw \
    $payload_ram_source \
    $frame_payload_ram_source \
    ../flows/asic/c2b4/sim/tb_dma_a3_banked_memory_contract.v
vsim work.tb_dma_a3_banked_memory_contract
onfinish stop
run -all
quit -f
