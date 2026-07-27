# ASIC 实现

本仓库公开两类 RX512 memory-subsystem 研究 profile 的可复现 flow adapter 与有界
evidence，不分发工艺库、生成网表、implementation database、SPEF 或商业工具日志。
本地工具路径应从
[`flows/config/toolchain.mk.example`](../../flows/config/toolchain.mk.example)
创建 ignored 配置。

## C2B4 Register-Expanded Profile

<!-- claim:slvc_dma_c2b4_n45_register_postroute_450 maturity:verified -->

`dma_rx512_reg_c2_b4_m2_sp64` 保留 4 KiB 最大帧契约，使用 2 channels、metadata
depth 2 和 64 个 shared block。flow-only memory binding 将 65,536 bit fixed
payload 与 36,864 bit shared payload/keep 映射为 13 个 register array，不实例化
SRAM macro。

| 阶段 | 配置 | 结果 |
| --- | --- | --- |
| DC stress | 600 MHz，setup/hold uncertainty 0.200/0.050 ns | `TIMING_FAIL`，setup WNS `-0.0554587 ns`；不是工具 fatal |
| DC handoff | 550 MHz，普通 `compile_ultra` | setup/hold WNS `+0.000284/+0.044102 ns`；113,741 registers；102,400 payload/keep bits 保留 |
| OpenROAD/OpenRCX | 450 MHz，mapped-netlist handoff | detail-route DRC `0`、antenna `0`、electrical violation `0` |
| PrimeTime | 同一次 route 的 V/SDC/SPEF | setup/hold WNS `+0.041322/+0.000341 ns`；TNS `0`；同步 endpoint coverage 100% |

公开 flow 明确分开综合和后端时钟：550 MHz DC mapped netlist 交给 450 MHz 物理
目标。physical SDC 使用 0.200 ns setup uncertainty 与 0 ns hold uncertainty；后者
是无 OCV/jitter 模型的 nominal single-corner 假设，不是 signoff margin。

OpenROAD 通过 `SYNTH_NETLIST_FILES` 读取 DC 网表并禁用 RTL/Yosys 输入。公开 hold
ECO 绑定测量网表 SHA 和精确 endpoint manifest，默认不会应用到其它网表。evidence
保留同一次 ODB、routed Verilog、SDC 与 SPEF 哈希，但不分发这些产物。

该 verified implementation point 只适用于两通道 RX512 memory subsystem，不是
C4B4、完整 DMA、Fmax、功耗、IO timing、OCV/MMMC、foundry signoff 或 silicon
validation。

## SRAM A5 研究

<!-- claim:slvc_dma_sram_a5_clock_delivery_canary maturity:verified -->
<!-- claim:slvc_dma_sram_a5_256_area_reduction maturity:verified -->

SRAM 路线整体明确为 `partial/blocked`。512x128 1RW1R OpenRAM 模型在 TT、1.1 V、
25 C 下完成有界 transistor-level 4x4 characterization。单宏 routed boundary canary
证明 `d200` CTS 加每个 macro clock pin 一个 `CLKBUF_X3` leaf，可将最差 macro
clock slew 从 `86.384 ps` 降到 `16.434 ps`；setup/hold WNS 为
`+0.372516/+0.171934 ns`，detail-route DRC、antenna 和 Liberty table extrapolation
均为 0。

当前 blocker 不是 clock skew 或 clock slew。现有 OpenRAM proxy model 给出的 high/low
minimum pulse 均为 1.5625 ns；300 MHz 约束下可用 pulse 约为 1.4667 ns，因此 canary
仍有 4 条 minimum-pulse violation。流程没有删除、修改或 waive Liberty 约束，也没有
启动 C4B4 SRAM DC/P&R/PT。

生成的 256x128 macro 面积比 512x128 低 37.7383%，但 minimum-pulse 没有改善，且
full 4x4 characterization 未完成。因此这里只声明生成面积结果，不声明 performance、
power 或集成 PPA 改善；independent true-pulse characterization 与 macro DRC/LVS/PEX
仍未闭合。

## 复现边界

公开命令提供 source manifest、约束、mapped-netlist handoff contract、extraction/STA
检查、模型审计和 dry-run。使用者需自行提供兼容的固定 ORFS 环境、Nangate45
Liberty/DB 与商业工具。公开摘要用 SHA-256 绑定测量源码、脚本、库和未分发 handoff；
sanitized public driver 可复现方法，但不冒充每个私有执行 wrapper 的字节级副本。
