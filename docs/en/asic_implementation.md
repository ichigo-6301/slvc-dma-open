# ASIC Implementation

This repository publishes reproducible flow adapters and bounded evidence for
two RX512 memory-subsystem research profiles. Technology libraries, generated
netlists, implementation databases, SPEF, and commercial-tool logs are not
distributed. Configure local tool paths from
[`flows/config/toolchain.mk.example`](../../flows/config/toolchain.mk.example).

## C2B4 Register-Expanded Profile

<!-- claim:slvc_dma_c2b4_n45_register_postroute_450 maturity:verified -->

`dma_rx512_reg_c2_b4_m2_sp64` preserves the 4 KiB maximum frame contract while
using two channels, metadata depth 2, and 64 shared blocks. Its flow-only memory
binding maps 65,536 fixed-payload bits plus 36,864 shared payload/keep bits to
13 register arrays. No SRAM macro is instantiated.

| Stage | Configuration | Result |
| --- | --- | --- |
| DC stress | 600 MHz, 0.200/0.050 ns setup/hold uncertainty | `TIMING_FAIL`, setup WNS `-0.0554587 ns`; no tool fatal |
| DC handoff | 550 MHz, ordinary `compile_ultra` | setup/hold WNS `+0.000284/+0.044102 ns`; 113,741 registers; 102,400 payload/keep bits preserved |
| OpenROAD/OpenRCX | 450 MHz, mapped-netlist handoff | detail-route DRC `0`, antenna `0`, electrical violations `0` |
| PrimeTime | same-run routed V/SDC/SPEF | setup/hold WNS `+0.041322/+0.000341 ns`; TNS `0`; synchronous endpoint coverage 100% |

The public flow keeps synthesis and physical clocks explicit. DC's 550 MHz
mapped netlist feeds a 450 MHz physical target. The physical SDC uses 0.200 ns
setup uncertainty and 0 ns hold uncertainty. The latter is a nominal
single-corner assumption with no OCV or jitter model, not a signoff margin.

OpenROAD consumes `SYNTH_NETLIST_FILES` with RTL/Yosys inputs disabled. The
published hold ECO is bound to the measured mapped-netlist SHA and exact
endpoint manifest; it is not applied to another netlist by default. Same-run
ODB, routed Verilog, SDC, and SPEF hashes are retained in the evidence summary,
but the artifacts themselves are not distributed.

This verified implementation point applies only to the two-channel RX512
memory subsystem. It is not C4B4, the complete DMA, Fmax, power, IO timing,
OCV/MMMC, foundry signoff, or silicon validation.

## SRAM A5 Research

<!-- claim:slvc_dma_sram_a5_clock_delivery_canary maturity:verified -->
<!-- claim:slvc_dma_sram_a5_256_area_reduction maturity:verified -->

The SRAM work is intentionally `partial/blocked`. The 512x128 1RW1R OpenRAM
model completed bounded transistor-level 4x4 characterization at TT, 1.1 V,
25 C. A routed one-macro boundary canary showed that `d200` CTS plus one
`CLKBUF_X3` leaf per macro clock pin reduced worst macro clock slew from
`86.384 ps` to `16.434 ps`, with setup/hold WNS `+0.372516/+0.171934 ns`, zero
detail-route DRC, zero antenna violations, and no Liberty table extrapolation.

The remaining blocker is not clock skew or clock slew. The current OpenRAM
proxy model reports 1.5625 ns high and low minimum pulse widths. At 300 MHz,
the constrained available pulse is about 1.4667 ns, so the canary retains four
minimum-pulse violations. No Liberty constraint was removed, edited, or
waived, and C4B4 SRAM DC/P&R/PT was not started.

The generated 256x128 macro area is 37.7383% below the generated 512x128 area,
but its minimum-pulse value did not improve and full 4x4 characterization was
not completed. This is an area-generation result, not a performance, power,
or integrated PPA claim. Independent true-pulse characterization and macro
DRC/LVS/PEX remain open.

## Reproduction Boundary

The public commands expose source manifests, constraints, mapped-netlist
handoff contracts, extraction/STA checks, model audits, and dry-runs. Users
must provide the pinned-compatible ORFS environment, Nangate45 Liberty/DB, and
commercial tools locally. Published summaries bind the measured source,
scripts, libraries, and non-distributed handoffs by SHA-256; sanitized public
drivers reproduce the method but are not claimed to be byte-identical to every
private execution wrapper.
