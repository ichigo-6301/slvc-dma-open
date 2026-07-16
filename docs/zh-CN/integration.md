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
