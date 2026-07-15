# 验证

release-bound regression 使用 Windows ModelSim SE-64 2020.4 和 IC_EDA Linux
Questa Sim-64 10.7c，覆盖 TX channel table、完整架构 throughput、hybrid RX
ingress、shared frame pool、parser、AXI-Lite read、TX CQ space、descriptor
queue/status 和 W prefetch FIFO。

该集合检查 payload 顺序、CQ count、descriptor 状态、backpressure、soft reset 和
最大连续 AXI W run。它是 directed regression，不等价于 coverage closure、formal
proof 或 CDC/RDC signoff。

运行入口为 `python3 flows/scripts/flowctl.py sim`，要求 Python 3.6 或更高版本。
runner 会核对 10 个唯一 PASS marker。证据及 source commit 位于 `provenance/`
和 `evidence/`。
