# Verification Matrix

The release-bound runner requires the native zero-error summary and one exact
marker per test.

| Entry point | Primary behavior | Required marker |
| --- | --- | --- |
| `run_rtl_v33c_tx_channel_table.do` | TX channel ownership split | `PASS: v33c TX channel table ownership split directed test` |
| `run_rtl_v33e20a23_full_arch_throughput.do` | Full architecture payload/CQ throughput scenarios | `E20A22_FULL_ARCH_THROUGHPUT_PASS` |
| `run_rtl_v33e20a_hybrid_rx_ingress_minimal.do` | Hybrid RX ingress admission | `OK: dma RTL v33e20a hybrid RX ingress minimal directed test passed.` |
| `run_rtl_v33e19_shared_frame_pool.do` | Shared frame-pool ordering and release | `OK: dma RTL v33e19 shared frame pool test passed.` |
| `run_rtl_v13_parser_pipeline.do` | Parser pipeline success/failure behavior | `PASS tb_rtl_v13_parser_pipeline` |
| `run_rtl_v15_axil_read_pipeline.do` | AXI4-Lite read pipeline | `OK: dma RTL v15 AXI-Lite read pipeline test passed.` |
| `run_rtl_v33e20a10_tx_cq_space_check_pipeline.do` | TX CQ-space decision pipeline | `PASS tb_rtl_v33e20a10_tx_cq_space_check_pipeline` |
| `run_rtl_v28_tx_descriptor_queue.do` | TX descriptor queue ordering | `OK: dma RTL v28 TX descriptor queue test passed.` |
| `run_rtl_v31_tx_desc_status_pipeline.do` | TX descriptor status readback | `SUMMARY: v31 TX descriptor status pipeline PASS` |
| `run_rtl_v33e20a23_w_prefetch_fifo.do` | Payload W prefetch and backpressure | `OK: dma RTL v33e20a23 W prefetch FIFO test passed.` |
| `run_rtl_v33e20a104_udp_to_shdr_directed.do` | UDP adapter boundaries through 4096 bytes and parser compatibility | `PASS tb_rtl_v33e20a104_udp_to_shdr_directed cases=18 parser_checks=18` |
| `run_rtl_v33e20a105_udp_to_shdr_random.do` | Four-seed random packet, gap, and stall scoreboard | `PASS tb_rtl_v33e20a105_udp_to_shdr_random seeds=13579bdf,2468ace1,51a7c0de,6d2b79f5 packets_per_seed=100 total=400` |
| `run_rtl_v33e20a106_udp_to_shdr_error_matrix.do` | Fixed-profile rejects including payload overflow, reset recovery, and stall stability; 17 explicit invalid-packet drops | `PASS tb_rtl_v33e20a106_udp_to_shdr_error_matrix cases=23 drops=17 accepts=23` |
| `run_rtl_v33e20a107_udp_to_dma_smoke.do` | UDP-port flow mapping through two DMA channels and CQEs | `PASS tb_rtl_v33e20a107_udp_to_dma_smoke packets=2 channels=2 cqes=2 ch0_full_then_ch1=1` |
| `run_rtl_rx_payload_writer_512.do` | Wide writer lengths, burst boundaries, errors, random stalls, stress, and ideal-model throughput | `PASS tb_rtl_rx_payload_writer_512 cases=2028` |
| `run_rtl_rx_payload_writer_512_integration.do` | Fixed-ingress/shared-pool source locking and integrated wide RX writes | `PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256` |
| `run_rtl_rx_payload_cdc_bridge.do` | Command/payload/completion CDC, tags, FIFO pressure, six clock profiles, and clock stops | `PASS tb_rtl_rx_payload_cdc_bridge frames=450 bytes=924873 source_stalls=321 fifo_empty=169 peak_payload_level=32 clock_profiles=6 clock_stops=2` |
| `run_rtl_rx_mem_async64_backend.do` | Async64 lengths, 4 KiB split, response errors, backpressure, 2,000-frame stress, and throughput | `PASS tb_rtl_rx_mem_async64_backend stress_frames=2000 clock_profiles=6 clock_stops=2` |
| `run_rtl_rx_mem_async64_integration.do` | Async64 fixed/shared source ordering and deferred soft-reset drain | `PASS tb_rtl_rx_mem_async64_integration directed_lengths=18 mixed_frames=256 soft_reset_drain=1` |
| `run_rtl_rx_mem_async512_backend.do` | Async512 lengths, 4 KiB split, response errors, backpressure, 2,000-frame stress, and throughput | `PASS tb_rtl_rx_mem_async512_backend stress_frames=2000 clock_profiles=6 clock_stops=2` |
| `run_rtl_rx_mem_async512_integration.do` | Async512 fixed/shared source ordering and deferred soft-reset drain | `PASS tb_rtl_rx_mem_async512_integration directed_lengths=18 mixed_frames=256 soft_reset_drain=1` |

The first ten rows are the frozen core regression and are always required. The
final four belong to the optional adapter P0 profile and are required only when
`CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER=y`; the default adapter-enabled defconfig
therefore schedules fourteen markers, while the core-only defconfig schedules
ten. The two wide-writer rows belong to the default-off same-clock development profile;
`configs/slvc_dma_512_rx_wide_defconfig` disables the adapter and schedules ten
core plus two wide markers, twelve total. Each asynchronous defconfig schedules
the ten core rows, the common CDC bridge row, and its two width-specific rows,
thirteen total. The matrix is directed verification, not coverage closure,
formal proof, or complete CDC/RDC signoff.
