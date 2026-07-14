# 接口

`slvc_dma_wrapper` 提供 RX/TX shared-link AXI-Stream、AXI4-Lite control、AXI4
memory master、control-message interface 和 IRQ。当前 release profile 固定：

| Item | Value |
| --- | --- |
| Shared-link data width | 512 bit |
| Keep width | 64 bit |
| SHDR64 size | 64 byte |
| Maximum payload | 4096 byte |
| Timing top | `frame_dma_wrapper` |

AXI4-Lite 管理通道、descriptor、ring pointer、CQ 和状态。AXI memory master 负责
RX payload write 与 TX payload read。公开 RTL port list 是权威接口定义；本版本不
承诺参数化 128-bit profile。
