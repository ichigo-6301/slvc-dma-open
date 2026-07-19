# 验证

release-bound regression 使用 Windows ModelSim SE-64 2020.4 和 IC_EDA Linux
Questa Sim-64 10.7c，覆盖 TX channel table、完整架构 throughput、hybrid RX
ingress、shared frame pool、parser、AXI-Lite read、TX CQ space、descriptor
queue/status 和 W prefetch FIFO。

该集合检查 payload 顺序、CQ count、descriptor 状态、backpressure、soft reset 和
最大连续 AXI W run。它是 directed regression，不等价于 coverage closure、formal
proof 或 CDC/RDC signoff。

运行入口为 `python3 flows/scripts/flowctl.py sim`，要求 Python 3.6 或更高版本。
runner 始终核对 10 个 frozen-core PASS marker；默认 adapter-enabled defconfig
再增加 4 个 adapter marker，共 14 项。可选 RX-wide defconfig 关闭 adapter，并
增加 2 个 wide-backend marker，共 12 项。每个双时钟 defconfig 关闭 adapter，
增加 1 个公共 CDC bridge marker 和 2 个 width-specific marker，共 13 项。冻结
release 的 evidence/source commit 仍位于 `provenance/` 和 `evidence/`；RX memory
backend 测量作为独立开发 profile 结果记录。
