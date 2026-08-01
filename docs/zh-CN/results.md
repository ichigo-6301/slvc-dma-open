# 已核验结果

## 结果解释

- `verified` 只适用于表中固定 source、profile、tool 和 workload，不代表所有参数组合。
- RTL ideal-memory throughput、FPGA routed OOC、DC synthesis estimate 和 post-route PrimeTime 是不同方法学，不能直接混为一个 PPA 结论。
- 频率是已测试通过的固定点，不是 Fmax。
- C2B4 是两通道 RX512 memory subsystem，不是 C4B4 或完整 DMA。
- 公开仓库不声明板级 DDR/10G、功耗、IO timing、OCV/MMMC、foundry signoff 或 silicon readiness。

所有 source commit、工具身份、artifact SHA-256 与 caveat 位于 `evidence/` 和 `provenance/`。

## RTL 功能与接口吞吐

<!-- claim:slvc_dma_rx_payload_cdc_regression maturity:verified -->
<!-- claim:slvc_dma_rx_payload_cdc_ideal_throughput maturity:verified -->
<!-- claim:slvc_dma_channel_admission_isolation_directed maturity:verified -->

Windows ModelSim 2020.4 与 Linux Questa 10.7c 均通过 frozen core、adapter、same-clock 512、async64、async512 和 C2 focused regression 的各自固定 marker。

| 测试 | 固定结果 | 解释边界 |
| --- | --- | --- |
| 512-bit writer | `PASS tb_rtl_rx_payload_writer_512 cases=2028` | 长度、tail、4 KiB、outstanding、backpressure、error、reset 与 throughput |
| Writer integration | `directed_lengths=18 mixed_frames=256` | fixed/shared source selection 与完成顺序 |
| Channel admission | `packets=2 channels=2 cqes=2 ch0_full_then_ch1=1` | 只证明 channel 0 ring full 时 channel 1 的一项 directed progress 场景 |
| CDC bridge | `frames=452 bytes=925001 clock_profiles=6 clock_stops=2` | directed/deterministic stress，不是完整 CDC/RDC signoff |
| Async backend stress | async64/async512 各 `2000` frames | 覆盖 response error、clock/reset 和 random backpressure |

理想 1 MiB memory model 的接口吞吐为：

| Profile | AXI bytes/cycle | W 利用率 | Peak outstanding | 200 MHz interface rate |
| --- | ---: | ---: | ---: | ---: |
| Same-clock 512 | 64 | 100% | 4 | 12.8 GB/s |
| Async64 | 8 | 100% | 4 | 1.6 GB/s |
| Async512 | 64 | 100% | 4 | 12.8 GB/s |

Async64 发出 8,192 个 16-beat burst，并观察到 8,192 个 planner bubble cycle；4 个 outstanding slot 把这些 AW 间隔隐藏在 W channel 供数之外。这些都是 ready memory model 下的 RTL/interface rate，不是板级 DDR 实测。

证据：[RX memory regression](../../evidence/slvc_dma_rx_payload_cdc_regression_summary.yaml) · [Adapter regression](../../evidence/slvc_dma_udp_adapter_regression_summary.yaml)

## FPGA Routed OOC

### Vivado 2022.2 Async64

<!-- claim:slvc_dma_async64_vivado_2022_2_ooc_200m maturity:verified -->

| Profile | WNS | TNS | WHS | THS | LUT | FF | BRAM tiles | DRC warning entries |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Async64, 200 MHz | +0.152 ns | 0 | +0.059 ns | 0 | 39,299 | 43,671 | 54 | 52 |

该 run 使用 Vivado 2022.2、`xc7z100ffg900-2`、5.000 ns `aclk/mem_clk` 和 `ExtraNetDelay_high / AggressiveExplore / Explore`。failed/unrouted/partially routed net 均为 0；4 条 Gray bus constraint 全部通过，worst bus-skew slack 为 +4.431 ns。

52 条 OOC DRC warning 已按 CHECK/RBOR/REQP/RTSTAT/ZPS7 分类保留，因此不声明 zero-DRC、bitstream 或 board implementation。该结果不与 Vivado 2018.3 数值直接合并。

证据：[Vivado 2022.2 Async64 summary](../../evidence/slvc_dma_async64_vivado_2022_2_ooc_summary.yaml)

### Vivado 2018.3 RX Memory Development Profiles

以下 profile 均使用 `xc7z100ffg900-2` 和 5.000 ns。它们是独立开发结果，不覆盖上方 2022.2 run。

| Profile | WNS | TNS | WHS | THS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Same-clock 512 | +0.089 ns | 0 | +0.069 ns | 0 | 38,045 | 42,514 | 44 | 3 | 0 |
| Async64 | +0.109 ns | 0 | +0.065 ns | 0 | 39,554 | 43,562 | 52 | 4 | 0 |
| Async512 | +0.060 ns | 0 | +0.058 ns | 0 | 40,020 | 43,316 | 52 | 4 | 0 |

同频 netlist 中 RX payload CDC cell 数为 0。两个 async profile 无未约束 internal endpoint、无 Critical CDC entry，并通过 Gray-pointer bus-skew 检查。Async64 的四条优化后 strategy WNS 为 `+0.138/+0.122/+0.109/+0.223 ns`，流水化前的 `+0.004/+0.003/-0.019/-0.004 ns` 仍作为 baseline evidence 保留。

### 冻结 Core Vivado 2018.3

| Strategy | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Explore | +0.226 ns | +0.045 ns | 38,074 | 40,787 | 44 | 3 | 0 |
| Performance_Explore | +0.173 ns | +0.046 ns | 38,087 | 40,787 | 44 | 3 | 0 |
| ExtraNetDelay_high | +0.162 ns | +0.054 ns | 38,088 | 40,785 | 44 | 3 | 0 |

三组 routed OOC 的 TNS/THS 均为 0。Optional UDP adapter 不在 `frame_dma_wrapper` 内，因此这些 core 资源不包含 adapter logic。

## ASIC C2B4 Register-Expanded

<!-- claim:slvc_dma_c2b4_n45_register_postroute_450 maturity:verified -->

Profile `dma_rx512_reg_c2_b4_m2_sp64` 使用 2 channels、每通道 4 KiB fixed payload、metadata depth 2 和 64-block shared pool。102,400 payload/keep bits 全部保留为 register，SRAM macro 数为 0。

| Stage | Target | Setup WNS/TNS | Hold WNS/TNS | 其它门禁 |
| --- | ---: | --- | --- | --- |
| Design Compiler handoff | 550 MHz | +0.000284 ns / 0 | +0.044102 ns / 0 | 113,741 registers；design-rule violation 0 |
| OpenROAD/OpenRCX/PrimeTime | 450 MHz | +0.041322 ns / 0 | +0.000341 ns / 0 | route DRC 0；antenna 0；electrical 0；coverage 100% |

600 MHz DC stress 的 setup WNS/TNS 为 `-0.0554587 ns / -5.93551556 ns`，388 条 violating path；这是 timing fail，不是工具崩溃。550 MHz mapped netlist 才是物理实现 handoff。

同次 450 MHz route 的物理指标：

| Die | Core | Standard-cell area | Cell count | Core utilization |
| --- | --- | ---: | ---: | ---: |
| 1684.865 x 1684.865 um (`2.83877 mm^2`) | 1644.640 x 1643.600 um (`2.70313 mm^2`) | `1.04207 mm^2` | 555,849 | 38.5506% |

该 block 只包含 RX512 memory subsystem。PrimeTime 使用 nominal single corner 和 0 ns physical hold uncertainty；结果不包含 top-level IO timing、OCV/MMMC、功耗或 foundry extraction。

证据：[C2B4 same-run post-route summary](../../evidence/slvc_dma_c2b4_n45_register_postroute_summary.yaml)

## ASIC Paired-DC 对比

以下对比统一使用 Design Compiler O-2018.06-SP1、同一 Nangate45 typical
library DB，并在每组 baseline/candidate 间保持完全相同的约束。
`points.csv` 是数值真源，表中差值均由公开 validator 使用 Decimal 重算。

<!-- claim:slvc_dma_writer_reservation_component_paired_dc maturity:verified -->

| 对比与范围 | 周期 | Baseline -> candidate | 结果 |
| --- | ---: | --- | --- |
| Writer reservation，组件级 OOC | 1.500 ns | W0 -> W1 | 标准单元总面积 `7526.204 -> 6926.640`（`-7.966353%`）；组合面积 `-15.838902%`；两点均 setup 闭合 |

该 Writer 结果只适用于 `dma_axi_write_engine_512`，不能外推为 C2B4
子系统或完整 DMA 面积变化。

<!-- claim:slvc_dma_c2b4_writer_subsystem_paired_dc maturity:verified -->

| 对比与范围 | 周期 | Baseline -> candidate | 结果 |
| --- | ---: | --- | --- |
| C2B4 寄存器展开 RX512 子系统 | 1.818182 ns | W0 -> W1 | 两点均 setup 闭合；Writer 层级面积 `4637.976 -> 7160.720`（`+54.393209%`）；setup WNS `+0.001498 -> +0.000959 ns` |

W0 已经闭合固定 550 MHz 测试点，而 W1 增加 Writer 层级面积并降低时序余量，
因此不满足子系统 promotion 条件。W2 仅作为数值 anchor 匹配，不称为历史
handoff 的方法学一致复现。

<!-- claim:slvc_dma_shared_pool_scheduler_paired_dc maturity:verified -->

| 对比与范围 | 周期 | Baseline -> candidate | 结果 |
| --- | ---: | --- | --- |
| 寄存器展开 Shared Pool 组件级 OOC | 2.500 ns | P6 -> P7 | setup WNS `+0.001163 -> +0.008876 ns`（改善 `7.71332 ps`）；寄存器 `+52`；总面积 `+0.019194%` |

Shared Pool 对比量化了调度流水带来的时序余量改善，并同时披露寄存器和面积成本；
该结果不是 SRAM macro PPA。

证据：[脱敏 ASIC paired-DC 数据包](../../evidence/asic_paired_dc/README.md)

## SRAM A5 Research

<!-- claim:slvc_dma_sram_a5_clock_delivery_canary maturity:verified -->
<!-- claim:slvc_dma_sram_a5_256_area_reduction maturity:verified -->

SRAM A5 保持 `partial/blocked`：

| 项目 | 已完成结果 | 未闭合边界 |
| --- | --- | --- |
| 512x128 model | TT/1.1 V/25 C transistor-level trimmed-SPICE 4x4 table；80 ps / 4.182 fF 覆盖 | analytical/OpenRAM reference flow；macro DRC/LVS/PEX 未闭合 |
| Clock delivery canary | `d200 + macro_x3` 将 macro clock slew `86.384 -> 16.434 ps`；setup/hold 正 slack；DRC/antenna/RC-004 0 | 4 条 proxy min-pulse violation |
| 256x128 generation | macro area `195801.79 -> 121909.43 um^2`，降低 37.7383% | full 4x4 characterization、性能和功耗未验证 |

两类 macro 的 proxy high/low minimum pulse 都是 1.5625 ns。该值阻止 300 MHz C4B4 启动；independent true-pulse characterization 尚未完成，不能以 waiver 或文本替换升级模型。

证据：[SRAM A5 development summary](../../evidence/slvc_dma_sram_a5_development_summary.yaml)

## Design Compiler Frontend Reference

Async64 在 5.000 ns OOC synthesis 中 source/memory setup WNS 为 `+2.948/+1.682 ns`，hold WNS `+0.039 ns`，area 172,104.93、register 20,602、latch 0。Async512 源码未变化，保留已有 `+3.011/+1.393 ns` setup WNS 和 170,410.51 area。generic FIFO array 已计入，不能解释为 macro-backed ASIC PPA。

Writer-only OOC sweep 使用 O-2018.06-SP1、Nangate45 typical、0.200 ns setup uncertainty 和 0.050 ns hold uncertainty：

| Target period | Setup WNS | Hold WNS | Cell area | Leaf cells |
| ---: | ---: | ---: | ---: | ---: |
| 5.000 ns | +2.059 ns | +0.047 ns | 6,860.41 | 3,352 |
| 3.333 ns | +0.393 ns | +0.047 ns | 6,860.67 | 3,352 |
| 2.500 ns | +0.028 ns | +0.047 ns | 6,579.24 | 2,764 |
| 2.000 ns | +0.013 ns | +0.046 ns | 6,669.95 | 2,795 |
| 1.500 ns | +0.013 ns | +0.046 ns | 6,795.24 | 2,975 |
| 1.250 ns | -0.033 ns | +0.046 ns | 7,195.57 | 3,622 |

每个 target 都重新 compile，因此 area/slack 非单调是预期行为。1.500 ns 是最后一个 setup-closed 测试点，1.250 ns 是首个失败点；这不是 routed Fmax 或完整 DMA 结果。
