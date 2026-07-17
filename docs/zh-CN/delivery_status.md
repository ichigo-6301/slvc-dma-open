# Delivery 状态

| Stage | 状态 | 公开边界 |
| --- | --- | --- |
| Directed RTL regression | verified | 十项 release-bound test 已在 Windows ModelSim 和 IC_EDA Questa 通过。 |
| Optional adapter regression | verified | 四项 adapter test 已在两个 simulator host 通过；修复后的 23-case matrix 为 `cases=23 drops=17 accepts=23`。 |
| FPGA OOC implementation | verified | 三种 Vivado 2018.3 strategy 均满足 200 MHz OOC setup/hold。 |
| Adapter ASIC frontend | verified | adapter-only DC OOC 达到 5.000 ns；不是 full-DMA 或 signoff evidence。 |
| Carrier CDC | partial | 已有 directed behavior；尚无完整 CDC/RDC signoff 或 waiver package。 |
| Full DMA ASIC frontend | planned | 后续 library-bound full-DMA synthesis profile 需要独立 evidence。 |
| Physical implementation | blocked | 尚缺可复现 handoff 所需的 validated standard-cell 和 SRAM macro physical view。 |
| Signoff STA | planned | 需要 routed netlist、constraints、parasitics 和匹配 library。 |
| Board validation | not claimed | 精确 public release commit 不声明 board-level result。 |
| Lossless 10G operation | not claimed | 本 release 不是完成的 board-level 10G production validation。 |

physical blocker 有意保持通用。仓库不会公开 PDK payload、physical abstract、tool log、
license、path 或 proprietary integration detail。恢复需要单独的 prerequisite audit 和新的
profile-bound evidence。
