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

The matrix is directed verification, not coverage closure, formal proof, or
CDC/RDC signoff.
