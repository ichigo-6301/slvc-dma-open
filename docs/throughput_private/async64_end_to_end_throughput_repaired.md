# Async64 自回环修复与每 MHz 吞吐评估

状态：`VERIFIED_PRIVATE_SIMULATION`，不构成公开 Claim 或简历板测结论。

Status: `VERIFIED_PRIVATE_SIMULATION`. This package is not a public or resume claim.

The fixed main point is 1024 x 4 KiB full TX-to-RX loopback, HP0_SHARED, 16-cycle response latency, 100% service, 3 ns CDC phase, seed 71.

The 1/2/5/32/1024-frame correctness ladder passed on both simulators before the 28-point matrix was accepted.

| Window | MB/s/MHz | MB/s at 100 MHz | Gb/s at 100 MHz | Model efficiency |
| --- | ---: | ---: | ---: | ---: |
| Hardware end-to-end | 3.831177 | 383.117735 | 3.064942 | 95.779434% |
| Datapath steady-state | 3.831723 | 383.172335 | 3.065379 | 95.793084% |

The HP0_SHARED payload-only loopback ceiling is 4 MB/s/MHz; IDEAL_SPLIT is 8 MB/s/MHz. These are RTL model limits, not board DDR throughput.

The existing 64 B/cycle result remains a Same-clock512/Async512 ready-memory Writer-interface result and is not reused here. C2B4 physical sources are byte-identical to the fixed 550/450 MHz evidence chain; no DC, P&R, OpenRCX, or PrimeTime rerun was performed.

## 修复边界

修复仅涉及 CDC 合法窗口检查与 TX 读预取 FIFO occupancy；接口、容量、流水和 4 KiB 合同不变。C2B4 source set不包含这两个模块，既有物理证据未重跑也未改写。
