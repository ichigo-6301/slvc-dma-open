transcript on

if {[catch {exec rg -n "tx_desc_err_cnt_csr_evt_valid_q|tx_desc_err_cnt_desc_evt_valid_q" ../rtl/dma_tx_desc_channel_table.v} tx_desc_fix_hits] != 0} {
    echo "Error: E20A.8 TX descriptor delayed err counter fix not found"
    quit -code 1
}

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +incdir+../rtl +incdir+../pattern \
    ../rtl/dma_tx_header_builder.v \
    ../rtl/dma_axi_read_prefetch.v \
    ../rtl/dma_tx_engine.v \
    ../pattern/axi64_slave_model.v \
    ../pattern/tb_rtl_v33e20a10_tx_cq_space_check_pipeline.v
vsim work.tb
onfinish stop
run -all
if {[info exists RUN_ALL_MODE]} {
    return
}
quit -f
