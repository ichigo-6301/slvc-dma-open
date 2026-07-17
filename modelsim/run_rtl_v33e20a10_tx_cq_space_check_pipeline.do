transcript on

quietly set tx_desc_table_path ../rtl/tx/dma_tx_desc_channel_table.v
if {[catch {open $tx_desc_table_path r} tx_desc_table_fh]} {
    echo "Error: cannot open $tx_desc_table_path"
    quit -code 1
}
quietly set tx_desc_table_source [read $tx_desc_table_fh]
close $tx_desc_table_fh
foreach required_symbol {
    tx_desc_err_cnt_csr_evt_valid_q
    tx_desc_err_cnt_desc_evt_valid_q
} {
    if {[string first $required_symbol $tx_desc_table_source] < 0} {
        echo "Error: E20A.8 TX descriptor delayed err counter fix missing $required_symbol"
        quit -code 1
    }
}

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work
vlog +incdir+../rtl/include +incdir+../rtl +incdir+../pattern \
    ../rtl/tx/dma_tx_header_builder.v \
    ../rtl/tx/dma_axi_read_prefetch.v \
    ../rtl/tx/dma_tx_engine.v \
    ../pattern/axi64_slave_model.v \
    ../pattern/tb_rtl_v33e20a10_tx_cq_space_check_pipeline.v
vsim work.tb
onfinish stop
run -all
if {[info exists RUN_ALL_MODE]} {
    return
}
quit -f
