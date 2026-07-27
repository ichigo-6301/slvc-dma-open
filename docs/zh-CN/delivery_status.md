# Delivery 状态

| Stage | 状态 | 公开边界 |
| --- | --- | --- |
| Directed RTL regression | verified | core/adapter、writer、async64/async512 与 C2 focused suite 已在各自 evidence-bound commit 上通过 Windows ModelSim 和 IC_EDA Questa。 |
| Optional adapter regression | verified | 四项 adapter test 已在两个 simulator host 通过；修复后的 23-case matrix 为 `cases=23 drops=17 accepts=23`。 |
| FPGA OOC implementation | verified | 历史 Vivado 2018.3 结果保持冻结；独立 Vivado 2022.2 async64 run 达到 200 MHz routed OOC timing，并保留 52 条分类 warning。 |
| 可选 RX memory profile | verified development | 同频 512、async64 和 async512 已通过 profile regression 与 routed OOC；不改变 RC1。 |
| Adapter ASIC frontend | verified | adapter-only DC OOC 达到 5.000 ns；不是 full-DMA 或 signoff evidence。 |
| Carrier CDC | partial | 已有 directed behavior；尚无完整 CDC/RDC signoff 或 waiver package。 |
| C2B4 register ASIC | verified stage / partial profile | DC 完成 550 MHz mapped handoff；OpenROAD/OpenRCX/PT 以 same-run hash 闭合内部 450 MHz nominal point。它是两通道 memory subsystem，不是 C4B4 或完整 DMA。 |
| SRAM A5 clock delivery | verified stage / blocked profile | 单宏 canary 已闭合 slew、route、extraction、setup 与 hold；proxy minimum-pulse 阻止 C4B4 执行。 |
| Foundry signoff STA | not claimed | 未分发 IO model、OCV/MMMC、signoff extraction、foundry-qualified SRAM 或 silicon evidence。 |
| Board validation | not claimed | 精确 public release commit 不声明 board-level result。 |
| Lossless 10G operation | not claimed | 本 release 不是完成的 board-level 10G production validation。 |

公开仓库不分发 PDK payload、physical abstract、生成网表、tool log、license 或私有
path。C2 evidence 记录 same-run artifact hash，但不分发 payload；SRAM A5 必须先完成
independent pulse characterization 才能提升其物理 profile。

异步 RX memory profile 已有结构 CDC report 和 reset-contract test，但不属于完整
ASIC CDC/RDC signoff 与 waiver package。
