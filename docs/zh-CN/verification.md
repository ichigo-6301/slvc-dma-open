# 验证

release-bound regression 使用 ModelSim SE-64 2020.4，覆盖 TX channel table、完整
架构 throughput、hybrid RX ingress、shared frame pool、parser、AXI-Lite read、TX
CQ space、descriptor queue/status 和 W prefetch FIFO。

该集合检查 payload 顺序、CQ count、descriptor 状态、backpressure、soft reset 和
最大连续 AXI W run。它是 directed regression，不等价于 coverage closure、formal
proof 或 CDC/RDC signoff。

运行入口为 `python flows/scripts/flowctl.py sim`。证据及 source commit 位于
`provenance/` 和 `evidence/`。
