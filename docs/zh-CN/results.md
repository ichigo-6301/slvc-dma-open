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
