# Verified Results

| Strategy | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Explore | +0.226 ns | +0.045 ns | 38,074 | 40,787 | 44 | 3 | 0 |
| Performance_Explore | +0.173 ns | +0.046 ns | 38,087 | 40,787 | 44 | 3 | 0 |
| ExtraNetDelay_high | +0.162 ns | +0.054 ns | 38,088 | 40,785 | 44 | 3 | 0 |

TNS and THS are zero in all runs. The minimum WNS is `+0.162 ns`; the earlier
preferred `+0.300 ns` margin was not reached. The long multi-burst W prefetch
test observed 48 contiguous 512-bit AXI W beats.

Each claim has a fixed source commit, tool, report checksum, and caveat in
`provenance/` and `evidence/`.

## Optional RX-Wide Development Profile

These branch-local measurements are separate from the frozen RC1 claims above.
They apply to the optional same-clock 512-bit RX payload backend documented in
[its profile guide](rx_payload_512_backend.md).

The two new Windows ModelSim 2020.4 and Linux Questa 10.7c regressions passed:

```text
PASS tb_rtl_rx_payload_writer_512 cases=2028
PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256
```

The ideal-memory 1 MiB test observed 64 byte/cycle and 100% W-channel active
utilization, with 16-beat average bursts and four peak outstanding bursts. The
corresponding 12.8 GB/s at 200 MHz is an RTL/model interface rate, not board
DDR throughput.

Vivado 2018.3 routed `frame_dma_rx_top` on `xc7z100ffg900-2` at 5.000 ns:

| WNS | TNS | WHS | THS | LUT | FF | RAMB36 | RAMB18 | DSP |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| +0.059 ns | 0 | +0.059 ns | 0 | 37,874 | 42,365 | 44 | 3 | 0 |

The writer-only Design Compiler OOC sweep used O-2018.06-SP1, Nangate45
typical, 0.200 ns setup uncertainty, 0.050 ns hold uncertainty, and identical
I/O assumptions at every point:

| Target period | Setup WNS | Hold WNS | Cell area | Leaf cells |
| ---: | ---: | ---: | ---: | ---: |
| 5.000 ns | +2.059 ns | +0.047 ns | 6,860.41 | 3,352 |
| 4.000 ns | +1.059 ns | +0.047 ns | 6,860.41 | 3,352 |
| 3.333 ns | +0.393 ns | +0.047 ns | 6,860.67 | 3,352 |
| 2.500 ns | +0.028 ns | +0.047 ns | 6,579.24 | 2,764 |
| 2.400 ns | +0.086 ns | +0.047 ns | 6,581.37 | 2,785 |
| 2.250 ns | +0.038 ns | +0.047 ns | 6,966.01 | 3,393 |
| 2.000 ns | +0.013 ns | +0.046 ns | 6,669.95 | 2,795 |
| 1.800 ns | +0.015 ns | +0.046 ns | 6,692.29 | 2,863 |
| 1.500 ns | +0.013 ns | +0.046 ns | 6,795.24 | 2,975 |
| 1.250 ns | -0.033 ns | +0.046 ns | 7,195.57 | 3,622 |

At 5.000 ns, the comparable legacy 64-bit writer configuration reports
12,548.55 total cell area, 5,706 leaf cells, 1,678 registers, and 30 logic
levels. The wide writer reports 6,860.41 area, 3,352 leaf cells, 832 registers,
and 37 logic levels. This writer-only result does not show that wider systems
are generally smaller: the legacy comparison enables its 16x64-bit prefetch
FIFO, and neither synthesis includes the full DMA or physical memories.

The sweep recompiles for each target, so non-monotonic area and slack are
expected. The 1.500 ns point is the last tested setup-closed target and
1.250 ns is the first tested failure; this is not routed ASIC Fmax, physical
implementation, or signoff evidence.
