# FPGA 实现

已核验实现为 Vivado 2018.3 source-level OOC：`frame_dma_wrapper`、
`xc7z100ffg900-2`、5.000 ns clock。三种实现策略均满足 setup/hold：Explore、
Performance_Explore 和 ExtraNetDelay_high。

运行 `python3 flows/scripts/flowctl.py fpga-ooc` 会调用公开的 native Tcl，结果仅写入
ignored `build/` 与 `reports/`。该流程不生成 Xilinx IP，不修改 BD，也不携带任何
器件库或 board project。
