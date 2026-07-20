# 已核验结果

| Strategy | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Explore | +0.226 ns | +0.045 ns | 38,074 | 40,787 | 44 | 3 | 0 |
| Performance_Explore | +0.173 ns | +0.046 ns | 38,087 | 40,787 | 44 | 3 | 0 |
| ExtraNetDelay_high | +0.162 ns | +0.054 ns | 38,088 | 40,785 | 44 | 3 | 0 |

三组 TNS/THS 均为 0。最小 WNS `+0.162 ns`，未达到原先偏好的 `+0.300 ns` margin。
W prefetch smoke 的 long multi-burst case 观测到 48 个连续 512-bit AXI W beat。

所有 claim 的工具、固定 source commit、报告 checksum 与 caveat 位于
`provenance/` 和 `evidence/`。

## 可选 RX-Wide 开发 Profile

以下开发分支测量与上方冻结 RC1 claim 相互独立，只适用于
[可选同频 512-bit RX payload 后端](rx_payload_512_backend.md)。

新增两项 regression 在 Windows ModelSim 2020.4 和 Linux Questa 10.7c 均通过：

```text
PASS tb_rtl_rx_payload_writer_512 cases=2028
PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256
```

理想 memory model 的 1 MiB test 测得 64 byte/cycle、W channel active 利用率
100%、平均 burst 16 beat、峰值 outstanding 4。按 200 MHz 换算的 12.8 GB/s 是
RTL/model interface rate，不是板级 DDR throughput。

Vivado 2018.3 在 `xc7z100ffg900-2` 上以 5.000 ns 完成 `frame_dma_rx_top` 布局
布线：

| WNS | TNS | WHS | THS | LUT | FF | RAMB36 | RAMB18 | DSP |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| +0.089 ns | 0 | +0.069 ns | 0 | 38,045 | 42,514 | 44 | 3 | 0 |

同频综合网表审计得到 RX payload CDC cell 数为 0。Explore、
NoTimingRelaxation 和 MoreGlobalIterations 均通过 setup/hold，WNS 分别为
`+0.089`、`+0.088` 和 `+0.144 ns`。

## 可选双时钟 RX Memory Profile

以下开发分支结果不修改上方冻结 RC1 evidence。两个 profile 均在 Windows
ModelSim 2020.4 和 Linux Questa 10.7c 上通过 10 项 frozen-core test、1 条公共
CDC bridge command 和 2 条 width-specific command。每条 integration command
会额外输出 quiesce marker；Async64 backend command 现在还要求独立的 AW candidate
marker，因此 Async64 从 13 条 command 要求 15 个 marker，Async512 仍为 14 个。

| Profile | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Async64 | +0.109 ns | +0.065 ns | 39,554 | 43,562 | 52 | 4 | 0 |
| Async512 | +0.060 ns | +0.058 ns | 40,020 | 43,316 | 52 | 4 | 0 |

两个 Vivado 2018.3 routed run 均使用 5.000 ns `aclk`/`mem_clk`，TNS/THS 为 0，
无未约束 internal endpoint、无 Critical CDC entry，并通过 Gray-pointer bus-skew
检查。Async512 的三条 setup/hold 收敛策略 WNS 为
`+0.060/+0.084/+0.081 ns`。增加一级 registered AW plan candidate 后，Async64
四条实测策略全部收敛，WNS 为 `+0.138/+0.122/+0.109/+0.223 ns`，最小 WHS
为 `+0.065 ns`。流水化前的 `+0.004/+0.003/-0.019/-0.004 ns` 仍作为 timing
baseline 保留在 evidence 中，没有被覆盖。Vivado
flow 只对实际非 Gray crossing 使用 point-to-point exception，不使用会覆盖 4 条
项目 Gray max-delay constraint 的 blanket asynchronous clock group。理想 memory
test 分别持续输出 8 和 64 byte/cycle，W-channel 利用率 100%。Async64 的 1 MiB
测试发出 8,192 个 16-beat burst，并观察到 8,192 个 planner bubble cycle；4 个
outstanding burst 将这些 AW 间隔隐藏在 W channel 供数之外。同频 512 test 也独立
达到 64 byte/cycle、100% W-channel 利用率和 4 个 peak outstanding。

选定 worst setup path 分别属于同频 reset distribution、async64 ingress payload
RAM address route，以及 async512 RX/FC resume calculation。原
`issue_beats_left_q -> m_axi_awaddr/CE` 路径已从全部优化后 top-100 report 消失；
MoreGlobalIterations 中仍可看到 `issue_beats_left_q -> aw_candidate_valid_q` 的
planner 内部路径，但其 slack 为 `+0.268 ns`，不是全局最差路径。quiesce 与 CDC
protocol-error detection 均未进入这些路径。相对 `79a5366` 资源基线，当前 async64
LUT 增加 0.21%，async512 仍增加 2.21%，BRAM/DSP 不变。相对流水化前的 Async64，
当前实现减少 848 LUT、增加 11 FF。

Design Compiler 5.000 ns OOC 重新编译 Async64，source/memory setup WNS 为
`+2.948/+1.682 ns`，hold WNS `+0.039 ns`，setup violation 为 0，cell area
172,104.93、register 20,602、latch 0。相对流水化前 Async64，area 增加 0.231%，
register 增加 0.204%。Async512 源码未变化，因此保留已有
`+3.011/+1.393 ns`、170,410.51-area 结果，不表述为本轮新 run。generic FIFO
array 已计入两个结果；这些数值不是 macro-backed ASIC area，也不能与 writer-only
综合直接比较。详见[双时钟后端指南](rx_payload_cdc_backends.md)。

## 同频 Writer-Only DC Sweep

writer-only Design Compiler OOC sweep 使用 O-2018.06-SP1、Nangate45 typical、
0.200 ns setup uncertainty、0.050 ns hold uncertainty，各点 I/O 假设一致：

| Target period | Setup WNS | Hold WNS | Cell area | Leaf cells |
| ---: | ---: | ---: | ---: | ---: |
| 5.000 ns | +2.059 ns | +0.047 ns | 6,860.41 | 3,352 |
| 4.000 ns | +1.059 ns | +0.047 ns | 6,860.41 | 3,352 |
| 3.333 ns | +0.393 ns | +0.047 ns | 6,860.67 | 3,352 |
| 2.500 ns | +0.028 ns | +0.047 ns | 6,579.24 | 2,764 |
| 2.400 ns | +0.086 ns | +0.047 ns | 6,581.37 | 2,785 |
| 2.250 ns | +0.038 ns | +0.047 ns | 6,966.01 | 3,393 |
| 2.000 ns | +0.013 ns | +0.046 ns | 6,669.95 | 2,795 |
| 1.800 ns | +0.015 ns | +0.046 ns | 6,692.29 | 2,863 |
| 1.500 ns | +0.013 ns | +0.046 ns | 6,795.24 | 2,975 |
| 1.250 ns | -0.033 ns | +0.046 ns | 7,195.57 | 3,622 |

在 5.000 ns 下，可比 legacy 64-bit writer 配置为 12,548.55 total cell area、
5,706 leaf cell、1,678 register 和 30 logic level；wide writer 为 6,860.41 area、
3,352 leaf cell、832 register 和 37 logic level。该 writer-only 结果不能推广成
“位宽越宽面积越小”：legacy 对比配置启用了 16x64-bit prefetch FIFO，且两者均不
包含完整 DMA 或物理 memory。

sweep 会针对每个 target 重新 compile，因此 area/slack 非单调属于预期。1.500 ns
是最后一个 setup-closed 测试点，1.250 ns 是首个失败点；该结论不是 routed ASIC
Fmax、physical implementation 或 signoff evidence。
