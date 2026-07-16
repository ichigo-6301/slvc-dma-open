# 模块目录

| 分组 | 公开模块 | 作用 |
| --- | --- | --- |
| 集成 | `slvc_dma_wrapper`, `frame_dma_wrapper` | 系统 wrapper 和完整 OOC timing top。 |
| RX path | `frame_dma_rx_top`, `dma_rx_parser`, `dma_rx_channel_match`, `dma_rx_payload_buffer`, `dma_rx_ingress_queue` | 解析 SHDR64、分类/admission traffic 并暂存 RX payload。 |
| Shared storage | `dma_frame_shared_pool`, `dma_rx_frame_shared_adapter`, `dma_frame_payload_ram`, `dma_payload_beat_ram` | shared payload storage、调度和同步 memory boundary。 |
| Memory and CQ | `dma_axi_write_engine`, `dma_axi_read_prefetch`, `dma_cq_writer`, `dma_cq_single_writer` | RX write、TX read/prefetch 和 owner-last completion publication。 |
| TX path | `dma_tx_channel_table`, `dma_tx_desc_channel_table`, `dma_tx_engine`, `dma_tx_header_builder` | descriptor-controlled payload replay 和 SHDR64 reconstruction。 |
| Control and boundaries | `dma_axil_regs`, `slvc_carrier_cdc_adapter`, `mcf_endpoint`, `dma_ufc_mailbox` | AXI4-Lite control、carrier CDC、source aggregation 和 control-message handling。 |
| 仿真支持 | `pattern/*`, `modelsim/*` | BFM、scoreboard、reference helper、testbench 和公开运行脚本。 |

该目录描述已发布的 512-bit source set，不承诺每个模块都是独立产品，也不表示未列出的
private module 位于公开 dependency graph 中。
