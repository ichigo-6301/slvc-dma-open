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
| `run_rtl_v33e20a10_tx_cq_space_check_pipeline.do` | TX CQ-space decision、active-TX drain、持续 descriptor demand 抑制、一次本地 soft reset 和干净重启 | `PASS tb_rtl_v33e20a10_tx_cq_space_check_pipeline` |
| `run_rtl_v28_tx_descriptor_queue.do` | TX descriptor queue ordering | `OK: dma RTL v28 TX descriptor queue test passed.` |
| `run_rtl_v31_tx_desc_status_pipeline.do` | TX descriptor status readback | `SUMMARY: v31 TX descriptor status pipeline PASS` |
| `run_rtl_v33e20a23_w_prefetch_fifo.do` | Payload W prefetch 和 backpressure | `OK: dma RTL v33e20a23 W prefetch FIFO test passed.` |
| `run_rtl_v33e20a104_udp_to_shdr_directed.do` | UDP adapter 至 4096-byte boundary 与 parser compatibility | `PASS tb_rtl_v33e20a104_udp_to_shdr_directed cases=18 parser_checks=18` |
| `run_rtl_v33e20a105_udp_to_shdr_random.do` | 四 seed random packet、gap 与 stall scoreboard | `PASS tb_rtl_v33e20a105_udp_to_shdr_random seeds=13579bdf,2468ace1,51a7c0de,6d2b79f5 packets_per_seed=100 total=400` |
| `run_rtl_v33e20a106_udp_to_shdr_error_matrix.do` | 含 payload overflow 的固定 profile reject、reset recovery 与 stall stability；17 个显式非法包 Drop | `PASS tb_rtl_v33e20a106_udp_to_shdr_error_matrix cases=23 drops=17 accepts=23` |
| `run_rtl_v33e20a107_udp_to_dma_smoke.do` | UDP port 经两个 DMA channel 与 CQE 的 flow mapping | `PASS tb_rtl_v33e20a107_udp_to_dma_smoke packets=2 channels=2 cqes=2 ch0_full_then_ch1=1` |
| `run_rtl_rx_payload_writer_512.do` | Wide writer 长度、burst boundary、error、随机 stall、stress 与理想 model throughput | `PASS tb_rtl_rx_payload_writer_512 cases=2028` |
| `run_rtl_rx_payload_writer_512_integration.do` | Fixed-ingress/shared-pool source lock 与集成 wide RX write | `PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256` |
| `run_rtl_rx_payload_cdc_bridge.do` | Command/payload/completion CDC、tag、FIFO 压力、6 种 clock profile、clock stop 和 5 个可达 protocol-error 场景 | `PASS tb_rtl_rx_payload_cdc_bridge frames=452 bytes=925001 source_stalls=327 fifo_empty=169 peak_payload_level=32 clock_profiles=6 clock_stops=2 protocol_error_cases=5` |
| `run_rtl_rx_mem_async64_backend.do` | Async64 长度、4 KiB 拆分、response error、1/2/7/31-cycle AW stall、source-credit 边界、同周期事件、2,000-frame stress 和 throughput | `PASS tb_rtl_async64_aw_planner candidate_stage=1 aw_stalls=1,2,7,31 source_credit=0,short,exact,surplus four_k_offsets=000,f80,fc0,ff0,ff8`<br/>`PASS tb_rtl_rx_mem_async64_backend stress_frames=2000 clock_profiles=6 clock_stops=2` |
| `run_rtl_rx_mem_async64_integration.do` | Async64 fixed/shared 顺序，以及 RX、buffered header、AXI/CQ、clock stop、重复 reset 与 UFC 场景下的有界 quiesce/drain | `PASS tb_rtl_rx_mem_async64_integration directed_lengths=18 mixed_frames=256 soft_reset_drain=1`<br/>`PASS tb_rtl_rx_payload_soft_reset_quiesce scenarios=collect,multi_queue,aw_w_b,cq,clock_stop,repeat,ufc,buffered_header` |
| `run_rtl_rx_mem_async512_backend.do` | Async512 长度、4 KiB 拆分、response error、backpressure、2,000-frame stress 和 throughput | `PASS tb_rtl_rx_mem_async512_backend stress_frames=2000 clock_profiles=6 clock_stops=2` |
| `run_rtl_rx_mem_async512_integration.do` | Async512 fixed/shared 顺序，以及 RX、buffered header、AXI/CQ、clock stop、重复 reset 与 UFC 场景下的有界 quiesce/drain | `PASS tb_rtl_rx_mem_async512_integration directed_lengths=18 mixed_frames=256 soft_reset_drain=1`<br/>`PASS tb_rtl_rx_payload_soft_reset_quiesce scenarios=collect,multi_queue,aw_w_b,cq,clock_stop,repeat,ufc,buffered_header` |

前十项始终属于 frozen core regression；最后四项仅在
`CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER=y` 时调度。默认 adapter-enabled defconfig
因此要求 14 个 marker，core-only defconfig 要求 10 个。该矩阵是 directed
verification。两项 wide-writer test 属于默认关闭的同频开发 profile；
`configs/slvc_dma_512_rx_wide_defconfig` 关闭 adapter，并调度 10 项 core 加 2 项
wide marker，共 12 项。每个异步 defconfig 调度 10 项 core 和 3 条 RX test command；
integration command 要求两个 marker。Async64 backend command 还要求 AW-planner
marker，因此 RX 部分共 5 个、完整 profile 共 15 个；Async512 仍为 4 个 RX marker、
总计 14 个。该矩阵不等价于 coverage closure、formal proof 或完整 CDC/RDC signoff。
