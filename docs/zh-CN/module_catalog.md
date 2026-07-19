# 模块目录

源码按职责位于 `rtl/include`、`rtl/common`、`rtl/rx`、`rtl/tx`、`rtl/cq`、
`rtl/control`、`rtl/integration`、`rtl/carrier` 和 `rtl/adapters`。目录只表达模块
所有权与阅读边界，不改变模块名、接口或编译顺序；精确依赖顺序仍由 `filelists/` 定义。

| 分组 | 公开模块 | 作用 |
| --- | --- | --- |
| 集成 | `slvc_dma_wrapper`, `frame_dma_wrapper` | 系统 wrapper 和完整 OOC timing top。 |
| RX path | `frame_dma_rx_top`, `dma_rx_parser`, `dma_rx_channel_match`, `dma_rx_payload_buffer`, `dma_rx_ingress_queue` | 解析 SHDR64、分类/admission traffic 并暂存 RX payload。 |
| Shared storage | `dma_frame_shared_pool`, `dma_rx_frame_shared_adapter`, `dma_frame_payload_ram`, `dma_payload_beat_ram` | shared payload storage、调度和同步 memory boundary。 |
| Memory and CQ | `dma_axi_write_engine`, `dma_axi_write_engine_512`, `dma_axi_write_engine_64_stream`, `dma_axi_read_prefetch`, `dma_cq_writer`, `dma_cq_single_writer` | 默认 RX write、可选 64/512-bit RX writer、TX read/prefetch 和 owner-last completion publication。 |
| RX memory CDC | `dma_rx_payload_cdc_bridge`, `dma_rx_payload_serializer_512_to_64`, `dma_async_fifo_tech`, `dma_reset_sync` | tagged command/payload/completion 跨域、memory-domain serializer、技术封装和各域 reset release。 |
| TX path | `dma_tx_channel_table`, `dma_tx_desc_channel_table`, `dma_tx_engine`, `dma_tx_header_builder` | descriptor-controlled payload replay 和 SHDR64 reconstruction。 |
| Control and boundaries | `dma_axil_regs`, `slvc_carrier_cdc_adapter`, `mcf_endpoint`, `dma_ufc_mailbox` | AXI4-Lite control、carrier CDC、source aggregation 和 control-message handling。 |
| 可选 packet adapter | `dma_udp_ipv4_to_shdr64_adapter` | 将固定 profile 512-bit Ethernet II / IPv4 / UDP RX packet 转为 SHDR64。 |
| 仿真支持 | `pattern/*`, `modelsim/*` | BFM、scoreboard、reference helper、testbench 和公开运行脚本。 |

该目录描述 frozen 512-bit source set、可选 adapter 和 RX memory 开发源码，不承诺每个模块都是独立产品，也不表示未列出的
private module 位于公开 dependency graph 中。

源码级阅读请从[中文 RTL 阅读指南](rtl_reading_guide.md)开始；其中标出了公开 top、可复用
数据路径、边界适配器和仿真基础设施的推荐顺序。
