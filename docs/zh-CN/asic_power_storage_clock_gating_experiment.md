# ASIC 存储 Bank Clock Gating 研究：Mapped-DC 正结果

> [!WARNING]
> 本文是 branch-only 研究证据，分类为 `POSITIVE_MAPPED_DC / BRANCH_ONLY`。
> 它不属于 `main`、`v0.1.0-rc1` 或生产 Profile，也不建议合入 `main`。

## 1. 实验目的

本实验验证：当自动集成 Clock Gating 从 Writer 输出 Bank 扩展到占主要功耗的
register-expanded Payload 存储时，是否能获得有意义的收益。门控复用既有 Bank
写使能，RTL 合同保持不变。目标是有界、基于 Activity 的 Mapped-DC 配对比较，
不是发行版功耗 Claim。

## 2. Scope 与 Identity

Scope 为 `dma_rx512_memory_subsystem_top`：两通道、每通道 4 KiB fixed payload、
64 个 512-bit shared block、16-beat burst、4 outstanding 和 register-expanded
存储。S0/S1 使用同一生产 RTL closure、top、Profile、shared source set、
2.000000 ns 约束、Nangate45 typical library、确定性 workload 和功能 trace。

固定 commit 与 SHA-256 身份记录在
[manifest](../../evidence/asic_power_clock_gating_storage_positive/manifest.json)。
S0/S1 的 prepared-manifest hash 不同，是因为 flow-only test wrapper 按 variant
物化；这不代表生产 RTL 发生变化。

## 3. 为什么采用 S0/S1 配对

S0 使用普通 `compile_ultra`，S1 使用 `compile_ultra -gate_clock`，预期的工具差异
只有自动 ICG 插入。两个 mapped 实现各自生成 zero-delay GLS activity digest，
但共享 seed、workload、窗口、接口和规范化 trace 合同。本实验不使用跨频率或
不同 RTL 的功耗比较。

## 4. Activity Workload

所有 workload 使用 seed `71`；reset、配置及 4,096 个 warm-up cycle 不计入采样。
原始 VCD/SAIF 保持私有。

| Workload | 采样窗口 | 合同 |
| --- | ---: | --- |
| idle | 4,096 cycles | 无 transaction；energy/byte 不适用 |
| bursty | 4,096 cycles | 16 个 4 KiB frame；每 256-cycle interval 中 64 active、192 idle |
| saturated | 4,096 cycles | 1 MiB、16-beat burst、4 outstanding、ready-memory model |

RTL reference、S0 mapped GLS 与 S1 mapped GLS 的 ready/valid、AW/W/B、CQ、
byte count、可见 latency、throughput 和 peak outstanding trace 一致。S0/S1 的
input、sequential、overall 和 clock annotation 均为 100%；S1 ICG-enable
annotation 也为 100%。功能功耗测量固定 `power_test_en=0`，S1 test-enable smoke
同样通过。

## 5. Clock Gating Policy

Allowlist 只包含具有既有公共写使能的宽 Bank。metadata/control、读侧控制、AXI
控制、CDC 状态、reset handshake、completion、IRQ/error/status 和 whole-domain
gating 均排除。DC 使用 minimum width 32 bit、maximum gate fanout 128。

| 类别 | Eligible bits | Gated bits | Coverage |
| --- | ---: | ---: | ---: |
| Fixed payload banks | 65,536 | 65,536 | 100% |
| Shared payload banks | 32,768 | 32,768 | 100% |
| Shared keep banks | 4,096 | 4,096 | 100% |
| Writer WDATA/WSTRB banks | 576 | 576 | 100% |
| **合计** | **102,976** | **102,976** | **100%** |

S1 包含 837 个 `CLKGATETST_X1`。102,976 个 gated bit 占 S0 的 113,741 个
mapped register 的 `90.535515%`。ICG fanout、gating check、mapped electrical
和结构违例均为 0。

## 6. Mapped-DC 结果

| Metric | S0 | S1 | Candidate minus baseline |
| --- | ---: | ---: | ---: |
| 500 MHz setup WNS (ns) | +0.00336182 | +0.00553846 | +0.00217664 |
| Hold WNS (ns) | +0.0441018 | +0.0441018 | 0 |
| Total area (um^2) | 946,749.061998 | 749,598.107999 | `-20.823993%` |
| Combinational area (um^2) | 429,844.296002 | 229,293.596000 | `-46.656592%` |
| Sequential area (um^2) | 516,904.766000 | 520,304.512000 | `+0.657712%` |
| Cells | 472,128 | 253,412 | -218,716 |
| Registers | 113,741 | 113,752 | +11 |

两点 setup/hold TNS 均为 0，timing、electrical、latch、unresolved reference、
GTECH 和 unclocked register 违例均为 0。这是单个 500 MHz mapped point，不是
Fmax。较大的组合面积变化与 DC 将逐 bit recirculation mux 替换为共享 ICG 一致；
它是该 register-expanded profile 的 mapped 结果，不是 RTL 面积或 SRAM Claim。

## 7. 基于 Activity 的功耗结果

| Workload | S0 dynamic (mW) | S1 dynamic (mW) | Dynamic delta | Clock + sequential delta |
| --- | ---: | ---: | ---: | ---: |
| idle | 212.00 | 26.90 | `-87.311321%` | `-87.337797%` |
| bursty | 389.33 | 47.07 | `-87.909999%` | `-89.531364%` |
| saturated | 387.81 | 49.27 | `-87.295325%` | `-89.293144%` |

预设门禁为：gated-state coverage 至少 20%；bursty dynamic 不高于 -10%；
saturated dynamic 不恶化超过 +1%；total area 不恶化超过 +2%。S1 同时通过四项。

| Workload | Dynamic E/B S0 -> S1 (pJ/B) | Delta | Incremental total E/B S0 -> S1 (pJ/B) | Delta |
| --- | ---: | ---: | ---: | ---: |
| bursty | 70.787273 -> 8.558182 | `-87.909999%` | 32.181818 -> 3.672727 | `-88.587571%` |
| saturated | 57.057103 -> 7.248920 | `-87.295325%` | 25.747126 -> 3.310345 | `-87.142857%` |

Dynamic power 是主比较指标。DC hierarchy total-power 字段只有三位有效数字，
validator 只允许明确的 1.1 mW 独立 half-LSB 和界限；incremental total energy
保持为次要结果。

## 8. 物理实现边界

本轮没有运行 P&R、CTS、OpenRCX 或 PrimeTime，S0/S1 都没有 post-route paired
power、routed timing、congestion、clock tree、DRC、antenna 或物理 electrical
结果。Mapped-DC clock power 不是 CTS 后 Clock Tree Power。

## 9. 为什么不需要 G2

Flow 在不修改 RTL 的情况下识别了全部 allowlisted bit，因此没有触发
gating-friendly RTL 整理。仅为扩大数字而门控 control、CDC、reset 或整个 clock
domain 会超出本实验边界。

## 10. 为什么与早期负结果不同

早期不可变的[负结果实验](https://github.com/ichigo-6301/slvc-dma-open/commit/78d4d3336270d4d01c4731050e9eea7fe8e47497)
只门控 576-bit Writer 输出 Bank，约占 mapped register state 的 0.506%；其 bursty
dynamic 改善不足 1%，物理 baseline 也在 G1 前被阻断。本实验增加 102,400 个已经
具有原生 Bank-select 写使能的 Payload/Keep bit，使 gated-state coverage 达到
90.535515%。

saturated 仍有明显下降是合理的：接口持续传输不等于全部 register-expanded Bank
每拍更新，写入时只有被选择的 Payload Bank 需要 clock edge。该解释只适用于当前
mapped hierarchy，不能建立 post-CTS 行为结论。

## 11. 工程决策

- 分类：`POSITIVE_MAPPED_DC / BRANCH_ONLY`。
- 预定义 Mapped-DC Promotion Gate 全部通过。
- 生产 RTL 保持不变。
- 不需要 G2 RTL 调整。
- 不产生 P&R 或 post-route power Claim。
- 不建议合入 `main`。

## 12. Claim 与 Nonclaim

本分支只支持两通道 register-expanded C2B4 RX512 子系统的有界、基于 Activity 的
Mapped-DC 结果。它不支持完整 DMA、SRAM、Fmax、P&R、CTS Clock Tree、post-route
power、MMMC/OCV、power integrity、thermal、foundry、signoff 或 silicon 结论。
没有 LEC/Formality PASS；zero-delay mapped GLS 是有界功能证据，不是形式等价。

## 13. 如何复核公开 Evidence

公开包只保留摘要，以及 logical artifact ID、byte size 和 SHA-256；不含商业原始
日志/报告、DDC、netlist、SDC、VCD、SAIF、library payload、host、账号、license
或本地路径。运行：

```text
make power-research-check
```

可直接检查 [points.csv](../../evidence/asic_power_clock_gating_storage_positive/points.csv)、
由 Decimal 生成的 [comparisons.csv](../../evidence/asic_power_clock_gating_storage_positive/comparisons.csv)、
[category census](../../evidence/asic_power_clock_gating_storage_positive/category_census.csv)、
[verification records](../../evidence/asic_power_clock_gating_storage_positive/verification.csv)
和 [branch-only validator](../../flows/scripts/validate_asic_power_storage_clock_gating_experiment.py)。
