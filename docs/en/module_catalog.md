# Module Catalog

Sources are grouped by responsibility under `rtl/include`, `rtl/common`, `rtl/rx`,
`rtl/tx`, `rtl/cq`, `rtl/control`, `rtl/integration`, `rtl/carrier`, and
`rtl/adapters`. The folders describe ownership and reading boundaries; module names,
interfaces, and compilation order remain defined by the source and `filelists/`.

| Group | Public modules | Role |
| --- | --- | --- |
| Integration | `slvc_dma_wrapper`, `frame_dma_wrapper` | System wrapper and complete OOC timing top. |
| RX path | `frame_dma_rx_top`, `dma_rx_parser`, `dma_rx_channel_match`, `dma_rx_payload_buffer`, `dma_rx_ingress_queue` | Parse SHDR64, classify/admit traffic, and stage RX payloads. |
| Shared storage | `dma_frame_shared_pool`, `dma_rx_frame_shared_adapter`, `dma_frame_payload_ram`, `dma_payload_beat_ram` | Shared payload storage, scheduling, and synchronous memory boundary. |
| Memory and CQ | `dma_axi_write_engine`, `dma_axi_write_engine_512`, `dma_axi_read_prefetch`, `dma_cq_writer`, `dma_cq_single_writer` | Default RX write, optional same-clock wide RX write, TX read/prefetch, and owner-last completion publication. |
| TX path | `dma_tx_channel_table`, `dma_tx_desc_channel_table`, `dma_tx_engine`, `dma_tx_header_builder` | Descriptor-controlled payload replay and SHDR64 reconstruction. |
| Control and boundaries | `dma_axil_regs`, `slvc_carrier_cdc_adapter`, `mcf_endpoint`, `dma_ufc_mailbox` | AXI4-Lite control, carrier CDC, source aggregation, and control-message handling. |
| Optional packet adapter | `dma_udp_ipv4_to_shdr64_adapter` | Fixed-profile 512-bit Ethernet II / IPv4 / UDP RX packet conversion to SHDR64. |
| Simulation support | `pattern/*`, `modelsim/*` | BFMs, scoreboards, reference helpers, testbenches, and public run scripts. |

The catalog describes the frozen 512-bit source set plus the optional adapter
P0 source. It is not a promise that
every module is a standalone product or that unlisted private modules are part
of the public dependency graph.

For source-level reading, start with the [Chinese RTL reading guide](../zh-CN/rtl_reading_guide.md),
which separates public tops, reusable datapath blocks, boundary adapters, and simulation support.
