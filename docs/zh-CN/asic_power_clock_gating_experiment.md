# ASIC 自动 Clock Gating 功耗研究：负结果

> [!WARNING]
> 本文是 branch-only 研究证据，不属于 `main`、`v0.1.0-rc1` 或生产 Profile。结论为
> `NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED`；不建议修改生产 RTL。

## 1. 实验目的

本实验在固定的 C2B4 register-expanded RX512 子系统上评估自动集成 Clock Gating。
目标是在不改变设计合同的前提下，建立确定性 activity、基于 activity 的 Mapped-DC
功耗估计和有界物理门禁。它是工程研究记录，不是已发布的功耗结论。

## 2. Scope 与 Identity

Scope 为 `dma_rx512_memory_subsystem_top`：两通道、每通道 4 KiB fixed payload、64 个
shared block、4 个 outstanding burst 以及 register-expanded 存储。两点使用同一 A1
RTL closure、参数合同、source-set digest、2.000000 ns 约束、Nangate45 typical library
和 DC O-2018.06-SP1。

数据由固定 source/evidence revision 与 source、constraint、tool-script、activity、
artifact SHA-256 绑定，见 [manifest](../../evidence/asic_power_clock_gating_negative/manifest.json)。
这些标识只提供 provenance；本分支不公开 source checkout、原始 EDA 内容或商业 library
payload。

## 3. 为什么采用 G0/G1 配对

G0 使用普通 `compile_ultra`；G1 使用 `compile_ultra -gate_clock`。两点共享同一 RTL
closure、top、参数、library、constraint、compile script、workload 合同与规范化功能 trace，
预期的主要工具差异是自动 ICG 插入。每个 mapped 实现各自使用 annotation 后的 activity，
因此 activity digest 不同；不能把它表述成同一个 activity 文件。

## 4. Activity Workload

所有 workload 使用 seed `71`，reset、配置和 warm-up 均不进入采样窗口。公开包只保留
digest 与摘要，不公开 VCD 或 SAIF。

| Workload | 采样窗口 | 功能合同 |
| --- | ---: | --- |
| idle | 4,096 cycles | 无 transaction；energy/byte 不适用 |
| bursty | 4,096 cycles | 16 个 4 KiB frame；每 256-cycle interval 中 64 active、192 idle |
| saturated | 4,096 cycles | 1 MiB、16-beat burst、4 outstanding、ready-memory model；功耗窗口取稳态 |

Windows ModelSim 与 Linux Questa 均记录所需 marker，且每个 workload/variant 对应相同
的规范化功能 trace。G0/G1 的 input 与 sequential activity coverage 均为 100%；总体
non-default activity 分别为 97.14% 与 97.12%。

## 5. Clock-Gating Policy

G1 使用 `CLKGATETST_X1`、minimum width 32 bit、maximum gate fanout 64，并只允许
Writer 宽数据寄存器 bank。该 allowlist 得到 9 个 ICG 和 576 个 gated bit。CDC
synchronizer/pointer、reset handshake、AXI handshake control、completion、IRQ/error/status
和 whole-domain gating 均排除。

## 6. Mapped-DC 结果

| Metric | G0 | G1 | Candidate minus baseline |
| --- | ---: | ---: | ---: |
| ICG cells / gated bits | 0 / 0 | 9 / 576 | +9 / +576 |
| Total area (um^2) | 946,749.061998 | 946,078.741998 | `-0.070802%` |
| Combinational area (um^2) | 429,844.296002 | 429,072.630002 | `-0.179522%` |
| Sequential area (um^2) | 516,904.766000 | 517,006.112000 | `+0.019606%` |
| Registers | 113,741 | 113,753 | +12 |
| Setup WNS at 500 MHz (ns) | +0.00336182 | +0.00580668 | +0.00244486 |

Mapped-DC clock power 不是 CTS 后 Clock Tree Power。本表不建立 post-route 行为结论。

## 7. 功耗结果

| Workload | G0 dynamic (mW) | G1 dynamic (mW) | Dynamic delta | Clock + sequential delta |
| --- | ---: | ---: | ---: | ---: |
| idle | 390.002509 | 388.002647 | `-0.512782%` | `-0.514643%` |
| bursty | 393.790000 | 390.800000 | `-0.759288%` | `-0.737455%` |
| saturated | 391.210000 | 393.130000 | `+0.490785%` | `+0.473508%` |

bursty 不满足 3% total dynamic 与 8% clock plus sequential 的任一 Promotion Gate；
saturated dynamic 反而增加。bursty incremental total-energy 的算术结果为 `-25%`，但它
来自量化到 405/409 mW 与 403/406 mW 的 total-power 相减，是小残差计算，不是
promotion-grade 结果。

## 8. 物理实现尝试

| Frequency | G0 | G1 | 保留边界 |
| ---: | --- | --- | --- |
| 500 MHz | `BLOCKED_SETUP` | `NOT_STARTED_GATE_BLOCKED` | setup WNS `-0.0450512 ns`；15 项 max-fanout 违例 |
| 475 MHz | `BLOCKED_ELECTRICAL` | `NOT_STARTED_GATE_BLOCKED` | setup/hold closed；14 项 max-fanout 违例 |

baseline-first gate 在每次 G0 物理边界后阻止 G1 启动。不能把 G0 的物理失败归因于 G1，
因为 G1 physical 从未启动。没有共同 post-route G0/G1 频率，也没有 PrimeTime
post-route paired power。

## 9. 为什么没有继续 G2

有界 allowlist 已经命中预期的 576 个 eligible bit，未触发因识别率低而进行 RTL 整理的
条件。为了追逐很小的结果而扩大门控范围可能改变生产 RTL 合同，因此不启动 G2。

## 10. 负结果的技术解释

576 个 gated bit 约占 G1 的 113,753 个 register 的 `0.506%`。本轮 allowlist 主要覆盖
Writer 宽输出数据 bank。bursty 存在 idle window，出现小幅 Mapped-DC 变化是合理的；
saturated 时 gate 大部分时间开启，ICG 开销和 mapping perturbation 可能抵消收益。更大的
register-expanded storage 主导 sequential activity。这些现象不足以证明应该扩大门控或改动
产品 RTL。

## 11. 工程决策

- 分类：`NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED`。
- 生产 RTL 保持不变。
- 不启动 G2。
- 不产生 post-route paired-power 声明。
- 本分支不建议合入 `main`。

## 12. 声明与 Nonclaim

本证据是两通道 register-expanded C2B4 RX512 子系统的 Mapped-DC activity-based estimate。
它不是完整 DMA、SRAM、最大频率、CTS Clock Tree、post-route paired power、LEC/Formality、
foundry 或 silicon 结论。

## 13. 如何复核公开 Evidence

公开包不含商业原始日志、报告、netlist、DDC、SDC、ODB、SPEF、VCD、SAIF、library payload、
host、账号、license 或本地路径。使用以下命令复核机器可读记录：

```text
make power-research-check
```

该命令校验 [points.csv](../../evidence/asic_power_clock_gating_negative/points.csv)、重建并
校验 [comparisons.csv](../../evidence/asic_power_clock_gating_negative/comparisons.csv)、检查
[physical_attempts.csv](../../evidence/asic_power_clock_gating_negative/physical_attempts.csv)，
并运行 [branch-only validator](../../flows/scripts/validate_asic_power_clock_gating_experiment.py)。
