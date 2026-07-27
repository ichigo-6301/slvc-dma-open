transcript on

proc require_env {name} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        error "Missing environment variable: $name"
    }
    return $::env($name)
}

set channels [require_env DMA_A3_CHANNELS]
set payload_words [require_env DMA_A3_PAYLOAD_WORDS]
set payload_aw [require_env DMA_A3_PAYLOAD_AW]
set payload_ram_source ../rtl/common/dma_payload_beat_ram.v
if {[info exists ::env(DMA_A3_PAYLOAD_RAM_SOURCE)] &&
    $::env(DMA_A3_PAYLOAD_RAM_SOURCE) ne ""} {
    set payload_ram_source $::env(DMA_A3_PAYLOAD_RAM_SOURCE)
}
set frame_payload_ram_source ../rtl/rx/dma_frame_payload_ram.v
if {[info exists ::env(DMA_A3_FRAME_PAYLOAD_RAM_SOURCE)] &&
    $::env(DMA_A3_FRAME_PAYLOAD_RAM_SOURCE) ne ""} {
    set frame_payload_ram_source $::env(DMA_A3_FRAME_PAYLOAD_RAM_SOURCE)
}
set frame_shared_pool_source ../rtl/rx/dma_frame_shared_pool.v
if {[info exists ::env(DMA_A3_FRAME_SHARED_POOL_SOURCE)] &&
    $::env(DMA_A3_FRAME_SHARED_POOL_SOURCE) ne ""} {
    set frame_shared_pool_source $::env(DMA_A3_FRAME_SHARED_POOL_SOURCE)
}
set defines [list \
    DMA_A3_PROFILE=1 \
    DMA_A3_CHANNELS=$channels \
    DMA_A3_PAYLOAD_WORDS=$payload_words \
    DMA_A3_PAYLOAD_AW=$payload_aw \
    DMA_A3_META_DEPTH=2 \
    DMA_A3_META_AW=1 \
    DMA_MAX_CH=$channels \
    DMA_RX_CH_NUM=$channels \
    DMA_TX_CH_NUM=$channels \
    DMA_RX_FC_INGRESS_PAYLOAD_WORDS=$payload_words \
    DMA_RX_FC_INGRESS_PAYLOAD_AW=$payload_aw \
    DMA_RX_FC_INGRESS_META_DEPTH=2 \
    DMA_RX_FC_INGRESS_META_AW=1]

proc compile_profile {defines payload_ram_source frame_payload_ram_source frame_shared_pool_source testbench} {
    if {[file exists work]} {
        vdel -lib work -all
    }
    vlib work
    vmap work work
    set cmd [list vlog +incdir+../rtl/include +incdir+../pattern]
    foreach def $defines {
        lappend cmd "+define+$def"
    }
    lappend cmd \
        $payload_ram_source \
        ../rtl/rx/dma_rx_fc_ingress_bank.v \
        $frame_payload_ram_source \
        $frame_shared_pool_source \
        ../rtl/rx/dma_rx_frame_shared_adapter.v \
        ../rtl/rx/dma_rx_ingress_source_selector.v \
        ../rtl/rx/dma_axi_write_engine_512.v \
        ../flows/asic/c2b4/rtl/dma_rx512_writer_route_top.v \
        ../flows/asic/c2b4/rtl/dma_rx512_memory_subsystem_top.v \
        $testbench
    eval $cmd
}

compile_profile $defines $payload_ram_source $frame_payload_ram_source $frame_shared_pool_source ../flows/asic/c2b4/sim/tb_dma_a3_ingress_profile.v
vsim work.tb_dma_a3_ingress_profile
onfinish stop
run -all
quit -sim

compile_profile $defines $payload_ram_source $frame_payload_ram_source $frame_shared_pool_source ../flows/asic/c2b4/sim/tb_dma_rx512_memory_subsystem.v
vsim work.tb_dma_rx512_memory_subsystem
onfinish stop
run -all
quit -sim

quit -f
