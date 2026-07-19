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
| +0.059 ns | 0 | +0.059 ns | 0 | 37,874 | 42,365 | 44 | 3 | 0 |

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
