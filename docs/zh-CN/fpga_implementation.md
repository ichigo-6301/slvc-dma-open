# FPGA 实现

已核验实现为 Vivado 2018.3 source-level OOC：`frame_dma_wrapper`、
`xc7z100ffg900-2`、5.000 ns clock。三种实现策略均满足 setup/hold：Explore、
Performance_Explore 和 ExtraNetDelay_high。

选择 defconfig 后运行 `make fpga-ooc` 会调用公开的 native Tcl，结果仅写入
ignored `build/` 与 `reports/`。该流程不生成 Xilinx IP，不修改 BD，也不携带任何
器件库或 board project。
<!-- fpga-bram-publication:slvc_dma_u5_13ch_bram_architecture_comparison:start -->
## U5 13通道 BRAM 资源边界

补充比较绑定现有 U5 同步 Profile：`DMA_MAX_CH=16`、13 RX/13 TX active、512-bit 流接口、64-bit HP0、100 MHz。当前 wrapper 的物理 payload 容量为 `135168` bytes，由 16 个 8 KiB Fixed bank 与一个 4 KiB Shared Pool 组成；比较中的 13 路 FIFO 只覆盖 active channel，总 payload 容量为 106496 bytes，因此没有做容量归一化。

综合资源报告和层次 owner 只从既有受保护的 synthesis/routed checkpoint 读取；未修改 XPR、BD、RTL、SDK 或 bitstream。独立 FIFO、集中 bank 与 MCDMA 均在隔离 OOC 工程中生成。详情及输入工件 SHA-256 见 [Evidence package](../../evidence/fpga_resources/u5_13ch_bram_architecture/README.md)。

该比较只支持有界 BRAM 映射结论，不证明功能等价、完整面积优势或无限突发下零丢包。
<!-- fpga-bram-publication:slvc_dma_u5_13ch_bram_architecture_comparison:end -->
