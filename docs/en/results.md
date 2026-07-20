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

These branch-local results do not modify the frozen RC1 evidence above. Both
profiles passed ten frozen-core tests plus the common CDC bridge and two
width-specific commands on Windows ModelSim 2020.4 and Linux Questa 10.7c.
Each integration command emits a second quiesce marker. Async64 now also
requires a dedicated AW-candidate marker from its backend command, so it
requires 15 markers from 13 commands; async512 remains 14 from 13.

| Profile | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Async64 | +0.109 ns | +0.065 ns | 39,554 | 43,562 | 52 | 4 | 0 |
| Async512 | +0.060 ns | +0.058 ns | 40,020 | 43,316 | 52 | 4 | 0 |

Both Vivado 2018.3 routed runs use 5.000 ns `aclk` and `mem_clk`, have zero
TNS/THS, no unconstrained internal endpoint, no Critical CDC entry, and met
their Gray-pointer bus-skew checks. Async512 retained three setup/hold-closed
strategies with WNS `+0.060/+0.084/+0.081 ns`. After inserting one registered
AW-plan candidate stage, Async64 closed all four measured strategies with WNS
`+0.138/+0.122/+0.109/+0.223 ns` and minimum WHS `+0.065 ns`. The earlier
pre-pipeline results (`+0.004/+0.003/-0.019/-0.004 ns`) remain in evidence as
the timing baseline rather than being overwritten. The Vivado flow uses point-to-point exceptions
for actual non-Gray crossings; it does not use a blanket asynchronous clock
group that would override the four project Gray max-delay constraints. The
ideal-memory tests sustained 8 and 64 byte/cycle respectively at 100%
W-channel utilization. Async64 issued 8,192 sixteen-beat bursts for the 1 MiB
test and observed 8,192 planner-bubble cycles; four outstanding bursts hid
those AW intervals from the W channel. The same-clock 512 test independently
sustained 64 byte/cycle at 100% W-channel utilization and four peak outstanding
bursts.

The selected worst setup paths belong to the same-clock reset distribution,
the async64 ingress payload-RAM address route, and the async512 RX/flow-control
resume calculation. The original `issue_beats_left_q -> m_axi_awaddr/CE` path
is absent from every optimized top-100 report. A planner-internal path from
`issue_beats_left_q` to `aw_candidate_valid_q` remains visible below the global
worst path at `+0.268 ns` in MoreGlobalIterations. Neither quiesce nor CDC
protocol-error detection appears in these paths. Relative to the `79a5366`
resource baseline, current async64 LUT use is up 0.21% while async512 remains up
2.21%; BRAM and DSP are unchanged. Relative to the immediate pre-pipeline
async64 result, the routed design uses 848 fewer LUTs and 11 more FFs.

Design Compiler 5.000 ns OOC recompiled async64 and reported
`+2.948/+1.682 ns` source/memory setup WNS, `+0.039 ns` hold WNS, zero setup
violations, 172,104.93 cell area, 20,602 registers, and zero latches. This is a
0.231% area and 0.204% register increase versus the immediate pre-pipeline
async64 result. Async512 source is unchanged and retains its existing
`+3.011/+1.393 ns`, 170,410.51-area result rather than being presented as a
new run. Generic FIFO arrays are included in both totals. These totals are
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
