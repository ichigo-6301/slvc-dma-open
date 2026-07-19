# 验证矩阵

release-bound runner 要求每个测试同时给出 native zero-error summary 和一个精确 marker。

| Entry point | 主要行为 | Required marker |
| --- | --- | --- |
| `run_rtl_v33c_tx_channel_table.do` | TX channel ownership split | `PASS: v33c TX channel table ownership split directed test` |
| `run_rtl_v33e20a23_full_arch_throughput.do` | 完整架构 payload/CQ throughput 场景 | `E20A22_FULL_ARCH_THROUGHPUT_PASS` |
| `run_rtl_v33e20a_hybrid_rx_ingress_minimal.do` | Hybrid RX ingress admission | `OK: dma RTL v33e20a hybrid RX ingress minimal directed test passed.` |
| `run_rtl_v33e19_shared_frame_pool.do` | Shared frame-pool ordering 和 release | `OK: dma RTL v33e19 shared frame pool test passed.` |
| `run_rtl_v13_parser_pipeline.do` | Parser pipeline success/failure behavior | `PASS tb_rtl_v13_parser_pipeline` |
| `run_rtl_v15_axil_read_pipeline.do` | AXI4-Lite read pipeline | `OK: dma RTL v15 AXI-Lite read pipeline test passed.` |
| `run_rtl_v33e20a10_tx_cq_space_check_pipeline.do` | TX CQ-space decision pipeline | `PASS tb_rtl_v33e20a10_tx_cq_space_check_pipeline` |
| `run_rtl_v28_tx_descriptor_queue.do` | TX descriptor queue ordering | `OK: dma RTL v28 TX descriptor queue test passed.` |
| `run_rtl_v31_tx_desc_status_pipeline.do` | TX descriptor status readback | `SUMMARY: v31 TX descriptor status pipeline PASS` |
| `run_rtl_v33e20a23_w_prefetch_fifo.do` | Payload W prefetch 和 backpressure | `OK: dma RTL v33e20a23 W prefetch FIFO test passed.` |
| `run_rtl_v33e20a104_udp_to_shdr_directed.do` | UDP adapter 至 4096-byte boundary 与 parser compatibility | `PASS tb_rtl_v33e20a104_udp_to_shdr_directed cases=18 parser_checks=18` |
| `run_rtl_v33e20a105_udp_to_shdr_random.do` | 四 seed random packet、gap 与 stall scoreboard | `PASS tb_rtl_v33e20a105_udp_to_shdr_random seeds=13579bdf,2468ace1,51a7c0de,6d2b79f5 packets_per_seed=100 total=400` |
| `run_rtl_v33e20a106_udp_to_shdr_error_matrix.do` | 含 payload overflow 的固定 profile reject、reset recovery 与 stall stability；17 个显式非法包 Drop | `PASS tb_rtl_v33e20a106_udp_to_shdr_error_matrix cases=23 drops=17 accepts=23` |
| `run_rtl_v33e20a107_udp_to_dma_smoke.do` | UDP port 经两个 DMA channel 与 CQE 的 flow mapping | `PASS tb_rtl_v33e20a107_udp_to_dma_smoke packets=2 channels=2 cqes=2 ch0_full_then_ch1=1` |
| `run_rtl_rx_payload_writer_512.do` | Wide writer 长度、burst boundary、error、随机 stall、stress 与理想 model throughput | `PASS tb_rtl_rx_payload_writer_512 cases=2028` |
| `run_rtl_rx_payload_writer_512_integration.do` | Fixed-ingress/shared-pool source lock 与集成 wide RX write | `PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256` |

前十项始终属于 frozen core regression；最后四项仅在
`CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER=y` 时调度。默认 adapter-enabled defconfig
因此要求 14 个 marker，core-only defconfig 要求 10 个。该矩阵是 directed
verification。最后两项属于默认关闭的 RX-wide 开发 profile；
`configs/slvc_dma_512_rx_wide_defconfig` 关闭 adapter，并调度 10 项 core 加 2 项
wide marker，共 12 项。该矩阵不等价于 coverage closure、formal proof 或
CDC/RDC signoff。
