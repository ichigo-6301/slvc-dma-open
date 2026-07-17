# 可选 UDP/IPv4 RX Adapter

`dma_udp_ipv4_to_shdr64_adapter` 是 frozen 512-bit SLVC DMA RX 输入之前的可选
兼容层。它将一个 Ethernet II、IPv4、UDP packet 转换为一个 SHDR64 segment，
不修改 DMA core、channel table、register map、descriptor format 或 CQE ABI。

```text
512-bit packet AXI4-Stream
  -> dma_udp_ipv4_to_shdr64_adapter
  -> 512-bit SHDR64 stream
  -> slvc_dma_wrapper
```

上游 MAC 必须移除 preamble、SFD 和 FCS，并在同一 clock/reset domain 中提供完整
packet。P0 profile 支持 EtherType IPv4、version 4、IHL 5、UDP protocol 17、无分片，
payload 上限为 4096 bytes。VLAN、IPv6、IPv4 options、fragment reassembly、UDP
checksum validation 和 Ethernet FCS handling 不属于本模块。

映射规则为 `SHDR64.flow_id = UDP destination port`。现有 DMA channel table 继续
负责 flow-to-channel 与 DDR context 选择。

## 数据路径

UDP payload 从 byte 42 开始。adapter 使用固定 22-byte carry 与 42-byte merge，
不使用通用 barrel shifter。SHDR64 header CRC 以六个 8-byte chunk 计算，随后传输一个
64-byte SHDR64 header beat。启动后，在两侧持续 ready 时，大 payload 可保持每周期
一个 512-bit output beat。backpressure 期间 output register 保持稳定。

在 200 MHz 且无 stall 时，zero-byte UDP payload 的 packet interval 为 8 cycles，
本地上界为 25 Mpacket/s；64-byte payload 的 interval 为 10 cycles，本地上界为
20 Mpacket/s。这些数值尚未计入 MAC overhead 和 downstream stall，不是网络 packet
rate 保证。

第一拍可判定的错误会抑制全部输出并产生一次 drop pulse。SHDR 或 payload 已发布后
才发现的错误会被报告，但 P0 不回滚已接受输出。本地 soft reset 会放弃半包，上游边界
必须从新的 packet boundary 重新开始。

## Evidence 边界

四项 adapter test 已在 ModelSim SE-64 2020.4 与 Questa Sim-64 10.7c 通过：
18 个覆盖至 4096 bytes 的 directed/parser case、400 个 deterministic-random
packet、包含 17 个显式非法包 Drop 和 23 个成功 Accept 的 23-case
error/reset/stall matrix，以及
two-channel adapter-to-DMA smoke。

5.000 ns adapter-only Design Compiler OOC 报告 +0.39 ns WNS、0 TNS、3746 个 leaf
cell、909 个 register、0 latch 和 11744.32 library area unit。最差路径是 8-byte CRC
chunk select/XOR cone。该结果只是 adapter frontend synthesis，不是完整 DMA 面积、
physical design、extracted STA、power signoff、board-level 10G 或 lossless UDP evidence。

受控 OOC script 需要未跟踪的 `DMA_DC_TARGET_LIBRARY`。公开仓库不分发 standard-cell
library、mapped design、generated report 或 private path。
