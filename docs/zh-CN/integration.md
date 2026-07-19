# 集成指南

`slvc_dma_wrapper` 是固定 `slvc_dma_v1_512` profile 的公开系统集成顶层。
`frame_dma_wrapper` 暴露相同的功能接口，并且是 FPGA OOC timing top。公开 wrapper
拒绝除 512-bit 之外的宽度。

## 接口分组

| 分组 | Public wrapper 信号 | 合同 |
| --- | --- | --- |
| Shared-link RX | `sl_rx_*` | 输入 DMA 的 512-bit、SHDR64-framed segment stream。长度和帧边界由 segment protocol 携带，不使用 AXIS `TLAST`。 |
| Shared-link TX | `sl_tx_*` | 由已配置 TX descriptor 产生的 512-bit replay stream。 |
| Control | `s_axil_*` | 32-bit AXI4-Lite，用于 channel、descriptor、ring、CQ、status 和 IRQ 配置。 |
| Memory | `m_axi_*` | 32-bit address、64-bit AXI4 master，用于 RX payload write 和 TX payload read。 |
| Control message | `ctrl_msg_{tx,rx}_*` | 可选的 valid/ready flow-control message 边界。 |
| Interrupt | `irq` | completion/status 通知；软件仍通过 AXI4-Lite 读取和确认状态。 |

`sl_rx_aclk` 与 `sl_rx_aresetn` 驱动 RX、AXI4-Lite 和 AXI memory-side logic。
`sl_tx_aclk` 与 `sl_tx_aresetn` 驱动 TX shared-link boundary。carrier 时钟跨域应由
`slvc_carrier_cdc_adapter` 处理，不能直接把异步时钟连接到 wrapper。

## 可选同频 Wide RX Memory Boundary

`configs/slvc_dma_512_rx_wide_defconfig` 选择以 `frame_dma_rx_top` 为 OOC top 的
开发 profile。定义 `DMA_RX_WIDE_PAYLOAD_PROFILE` 后，该 top 增加 write-only
`m_axi_rx_payload_*` AXI4 master：32-bit address、512-bit WDATA 和 64-bit WSTRB。
RX destination address 必须按 64 byte 对齐。冻结的 `slvc_dma_wrapper` 接口及默认
64-bit AXI master 保持不变。

该 profile 是同频实现：RX ingress store、source selector、writer 和外部 memory
slave 都使用 `aclk`。若 memory clock 异步，必须先增加 command、512-bit payload
和 completion CDC FIFO，不能直接连接。详见
[wide-backend profile 指南](rx_payload_512_backend.md)。

## 可选 Ethernet Packet Boundary

只有上游提供带 `TKEEP`/`TLAST` 的 512-bit Ethernet II packet AXI4-Stream 时，
才在 `sl_rx_*` 前放置 `dma_udp_ipv4_to_shdr64_adapter`。MAC 必须移除 preamble、
SFD 和 FCS。除非显式插入 CDC boundary，否则 adapter 与 DMA RX 必须处于同一
clock/reset domain。adapter 输出不带 `TKEEP`/`TLAST`；`slvc_dma_wrapper` 通过
SHDR64 `payload_len` 获取 segment boundary。

UDP destination port 会成为 `SHDR64.flow_id`。接收 packet 前应先为该 flow ID 配置
现有 DMA channel table。`stat_drop` 是 diagnostic status；P0 不提供 late error 后的
packet rollback。

## 最小 Bring-Up 顺序

1. 保持两个 wrapper reset 有效，再先释放 RX/control domain 并开始设备配置。
2. 通过 AXI4-Lite 配置选定 channel、RX/TX ring state、descriptor，以及 completion
   queue ownership/consumer state。
3. 使能路径后输入合法的 SHDR64-framed RX traffic，或提交 TX descriptor。
4. 仅在 owner/valid 可见后消费 completion entry；CQ body 会先于 ownership publication
   写入。
5. 通过 AXI4-Lite 确认状态并推进软件拥有的 ring/CQ state，之后才复用关联 buffer 或
   completion entry。

本指南不是 board-design recipe。MAC/PHY、generated FPGA IP、software driver 和 10G
lossless behavior 均不属于公开 release；RTL port list 仍是最终接口定义。
