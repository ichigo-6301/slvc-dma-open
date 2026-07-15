# SLVC DMA

[English](README.en.md)

SLVC DMA 是面向共享高速链路的 512-bit 虚拟通道 DMA IP。多个上游源先复用为带
SHDR64 header 的共享 segment stream，DMA 依据 channel metadata 将 payload 写入
DDR ring，并通过 CQ 向软件发布完成事件。

## 当前公开版本

`v0.1.0-rc1` 发布 `slvc_dma_wrapper`、`frame_dma_wrapper`、可选 carrier adapter
和 MCF companion。该版本冻结的是 512-bit Aurora-compatible profile，不宣称已经
实现通用 128-bit profile、板级 10G 无丢包或 ASIC signoff。

## 已核验内容

- 选定 10 项 ModelSim directed regression；
- Vivado 2018.3、`xc7z100ffg900-2`、5.000 ns OOC 三种实现策略均无 setup/hold
  违规，最小 WNS 为 `+0.162 ns`；
- RX dispatch、TX replay、AXI-Lite control、DDR ring、CQ owner-last publication
  和 512-bit payload writer。

完整数值、限制和证据见 [结果](docs/zh-CN/results.md)、[验证](docs/zh-CN/verification.md)
与 [限制](docs/zh-CN/limitations.md)。

## 快速开始

```text
python3 flows/scripts/flowctl.py defconfig --source configs/slvc_dma_512_defconfig
python3 flows/scripts/flowctl.py show-config
python3 flows/scripts/flowctl.py sim-dry-run
python3 flows/scripts/flowctl.py fpga-ooc-dry-run
```

公开 runner 要求 Python 3.6 或更高版本。`sim` 需要 ModelSim/Questa；
`fpga-ooc` 需要 Vivado 2018.3。工具路径与本地环境变量仅放在 ignored
`flows/local/`。Windows 若只有 `python.exe`，可将上述 `python3` 替换为
`python`。发布前验证步骤见
[FRESH_CLONE_VALIDATION.md](FRESH_CLONE_VALIDATION.md)。
