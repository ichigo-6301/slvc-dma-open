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
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +incdir+../rtl/include \
    +define+DMA_A3_CHANNELS=$channels \
    +define+DMA_A3_PAYLOAD_WORDS=$payload_words \
    +define+DMA_A3_PAYLOAD_AW=$payload_aw \
    +define+DMA_MAX_CH=$channels \
    +define+DMA_RX_CH_NUM=$channels \
    +define+DMA_TX_CH_NUM=$channels \
    +define+DMA_RX_FC_INGRESS_PAYLOAD_WORDS=$payload_words \
    +define+DMA_RX_FC_INGRESS_PAYLOAD_AW=$payload_aw \
    +define+DMA_RX_FC_INGRESS_META_DEPTH=2 \
    +define+DMA_RX_FC_INGRESS_META_AW=1 \
    ../flows/asic/c2b4/sim/tb_dma_a3_config_contract.v
vsim work.tb_dma_a3_config_contract
onfinish stop
run -all
quit -f
