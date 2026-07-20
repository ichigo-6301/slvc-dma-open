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
| +0.089 ns | 0 | +0.069 ns | 0 | 38,045 | 42,514 | 44 | 3 | 0 |

The same-clock synthesis audit found zero RX payload CDC cells. Explore,
NoTimingRelaxation, and MoreGlobalIterations all closed setup and hold with
WNS of `+0.089`, `+0.088`, and `+0.144 ns` respectively.

## Optional Dual-Clock RX Memory Profiles

These branch-local results bind to the dual-clock implementation commit and do
not modify the frozen RC1 evidence above. Each profile passed ten frozen-core
tests plus the common CDC bridge and two width-specific commands on Windows
ModelSim 2020.4 and Linux Questa 10.7c. Each integration command emits a second
quiesce marker, so each async profile requires 14 markers from 13 commands.

| Profile | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Async64 | +0.053 ns | +0.047 ns | 40,413 | 43,548 | 52 | 4 | 0 |
| Async512 | +0.053 ns | +0.015 ns | 39,995 | 43,327 | 52 | 4 | 0 |

Both Vivado 2018.3 routed runs use 5.000 ns `aclk` and `mem_clk`, have zero
TNS/THS, no unconstrained internal endpoint, no Critical CDC entry, and met
their Gray-pointer bus-skew checks. Three setup/hold-closed routed strategies
were retained per profile: async64 WNS `+0.053/+0.057/+0.082 ns` and async512
WNS `+0.053/+0.074/+0.028 ns`. The Vivado flow uses point-to-point exceptions
for actual non-Gray crossings; it does not use a blanket asynchronous clock
group that would override the four project Gray max-delay constraints. The
ideal-memory tests sustained 8 and 64 byte/cycle respectively at 100%
W-channel utilization.

Design Compiler 5.000 ns OOC reported `+2.953/+1.686 ns` source/memory setup
WNS for async64 and `+2.967/+1.393 ns` for async512. Generic FIFO arrays are
included in their 171,845.31 and 170,407.31 cell-area totals. These totals are
not macro-backed ASIC area and are not comparable to writer-only synthesis.
See the [dual-clock backend guide](rx_payload_cdc_backends.md).

## Same-Clock Writer-Only DC Sweep

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
