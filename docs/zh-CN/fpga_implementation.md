# FPGA 实现

已核验实现为 Vivado 2018.3 source-level OOC：`frame_dma_wrapper`、
`xc7z100ffg900-2`、5.000 ns clock。三种实现策略均满足 setup/hold：Explore、
Performance_Explore 和 ExtraNetDelay_high。

选择 defconfig 后运行 `make fpga-ooc` 会调用公开的 native Tcl，结果仅写入
ignored `build/` 与 `reports/`。该流程不生成 Xilinx IP，不修改 BD，也不携带任何
器件库或 board project。

## U5 板级证据层级

<!-- claim:slvc_dma_u5_sync_hp0_loopback_board_throughput maturity:partial -->

| 维度 | 状态 | 固定边界 |
| --- | --- | --- |
| Source / RTL simulation / synthesis / implementation / bitstream | verified | Vivado 2018.3，XC7Z100，13 RX/13 TX，同步 PL 本地回环 |
| Timing | partial | 100 MHz 固定工作点；不声明 Fmax |
| Board smoke / workload validation | partial | `FPGA_DEBUGGER_TRANSCRIBED_SINGLE_RUN`；post-start completion window；1024 x 4 KiB；无重复性统计 |
| Source-to-binary traceability | not retained | 公开复现实例未与私有 ELF 或 bitstream 建立密码学构建绑定 |

公开仓库保存 source-only 复现实例、人工转录的 debugger 字段记录、脱敏启动摘录、派生公式以及外部 bitstream/ELF 哈希；不声明已保留 source-to-binary 构建链，也不提交 bitstream、ELF、完整 SDK 日志或 JTAG 身份。[查看证据包](../../evidence/fpga_emulation/u5_sync_hp0_loopback/README.md)。
