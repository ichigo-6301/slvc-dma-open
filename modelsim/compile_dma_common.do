if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

if {![info exists DMA_COMPILE_DEFINES]} {
    set DMA_COMPILE_DEFINES {}
}

set rtl_files {}
set fp [open "../filelists/dma_rtl.f" r]
while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} {
        continue
    }
    if {[string index $line 0] eq "#"} {
        continue
    }
    lappend rtl_files "../$line"
}
close $fp

set common_models [list \
    ../pattern/dma_ref_model.v \
    ../pattern/axi_lite_master_model.v \
    ../pattern/rx_axis_bfm.v \
    ../pattern/axi64_slave_model.v \
    ../pattern/ps_axil_bfm.v \
    ../pattern/axi_ddr_mem_model.v \
    ../pattern/axis_loopback_bfm.v \
    ../pattern/ufc_msg_monitor.v \
    ../pattern/aurora_ufc_bfm.v \
]

set vlog_cmd [concat [list vlog] $DMA_COMPILE_DEFINES [list +incdir+../rtl/include +incdir+../rtl +incdir+../pattern] $rtl_files $common_models]
eval $vlog_cmd
