# SLVC DMA

[![Public Integrity](https://github.com/ichigo-6301/slvc-dma-open/actions/workflows/public-integrity.yml/badge.svg?branch=main)](https://github.com/ichigo-6301/slvc-dma-open/actions/workflows/public-integrity.yml) ![RTL](https://img.shields.io/badge/RTL-Verilog-2f6f9f) [![License](https://img.shields.io/github/license/ichigo-6301/slvc-dma-open)](LICENSE)

[中文](README.md) · [Architecture](docs/en/architecture.md) · [Integration](docs/en/integration.md) · [Verification](docs/en/verification.md) · [Results](docs/en/results.md) · [Limitations](docs/en/limitations.md) · [Power research](docs/en/asic_power_clock_gating_experiment.md)

> [!WARNING]
> This is a branch-only ASIC power research record. It is not part of `main`,
> `v0.1.0-rc1`, or any production profile. The experiment established deterministic
> activity, mapped-DC automatic clock gating, and bounded physical gates, but did
> not meet the predefined promotion gate. No production RTL change is recommended.

**A 512-bit virtual-channel DMA for multi-source shared high-speed links, providing channel-aware admission, hybrid buffering, a separate control-message path, and auditable completion ownership between protocol adapters and DDR.**

Sensors, baseband pipelines, or local endpoints can first be multiplexed into one SHDR64 segment stream. SLVC DMA selects a virtual channel and DDR ring from header metadata, manages either fixed channel storage or a shared frame pool, and publishes software-visible completion events through a Completion Queue.

![SLVC DMA shared-link overview](docs/assets/slvc_dma_overview.svg)

## 60-Second Overview

| Dimension | Current implementation |
| --- | --- |
| Application problem | Move multiple independently managed sources over one high-speed serial or packet link into separate DDR rings |
| Canonical IP | [`slvc_dma_wrapper`](rtl/integration/slvc_dma_wrapper.v), with [`slvc_dma_512.f`](flows/manifests/slvc_dma_512.f) as the filelist |
| Data contract | 512-bit RX/TX AXI-Stream, 64-byte SHDR64 header, and payloads up to 4096 bytes |
| Virtual channels | `flow_id` selects channel context; packet-level admission, reservation, ring pointers, and completion accounting |
| Buffering | Per-channel fixed ingress storage or a free-list-managed shared frame pool |
| Flow-control boundary | Payload `valid/ready` is separate from PAUSE/RESUME control messages; the latter is not network end-to-end flow control |
| Implementation evidence | Windows ModelSim + Linux Questa, Vivado routed OOC, and Nangate45 DC/OpenROAD/OpenRCX/PrimeTime |

## ASIC Power Research Branch

> [!WARNING]
> This section records a branch-only negative research result. It will not enter
> `main`, `v0.1.0-rc1`, or any production profile, and it is not recommended for
> merge.

This bounded ASIC power experiment uses the two-channel C2B4 register-expanded
RX512 subsystem and deterministic activity to compare ordinary Design Compiler
mapping with automatic clock gating. G1 inserted `9 x CLKGATETST_X1` gating
`576` bits. It is not a conclusion about a complete DMA or an SRAM profile.

| Item | Result |
| --- | --- |
| Scope | Two-channel C2B4 register-expanded RX512 subsystem |
| Tool point | DC O-2018.06-SP1, Nangate45 typical, 500 MHz mapped-DC |
| Clock gates | `9 x CLKGATETST_X1` |
| Gated bits | `576` |
| Bursty dynamic | `-0.759288%` |
| Saturated dynamic | `+0.490785%` |
| Area | `-0.070802%` |
| Physical comparison | Blocked before G1; no paired physical comparison |
| Decision | `NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED`; no production RTL change |

The result misses both the `3% dynamic` and `8% clock + sequential` promotion
gates. The G0 physical attempt at 500 MHz was blocked by setup and max-fanout
issues. At 475 MHz, G0 closed setup/hold but retained 14 max-fanout violations.
G1 physical implementation therefore did not start; there is no common
post-route point and no post-route paired power. A bursty `-25%` incremental
energy figure formed by coarse total-power residuals is not used as a benefit,
because it is dominated by report quantization.

Method and boundaries: [English research note](docs/en/asic_power_clock_gating_experiment.md) ·
[Chinese research note](docs/zh-CN/asic_power_clock_gating_experiment.md) ·
[Evidence README](evidence/asic_power_clock_gating_negative/README.md) ·
[points.csv](evidence/asic_power_clock_gating_negative/points.csv) ·
[comparisons.csv](evidence/asic_power_clock_gating_negative/comparisons.csv) ·
[physical_attempts.csv](evidence/asic_power_clock_gating_negative/physical_attempts.csv) ·
[branch-only validator](flows/scripts/validate_asic_power_clock_gating_experiment.py)

Mapped-DC clock power is not CTS clock-tree power. This scope is not a complete
DMA, and register-expanded C2B4 is not an SRAM profile. There is no
LEC/Formality PASS. This branch is an auditable record of automatic clock-gating
evaluation, physical blocking, and a negative result only.

<a id="key-results-and-evidence"></a>
## Key Results And Evidence

<!-- claim:slvc_dma_writer_reservation_component_paired_dc maturity:verified -->
<!-- claim:slvc_dma_c2b4_writer_subsystem_paired_dc maturity:verified -->
<!-- claim:slvc_dma_rx_payload_cdc_ideal_throughput maturity:verified -->
<!-- claim:slvc_dma_c2b4_n45_register_postroute_450 maturity:verified -->

![SLVC DMA verified results at a glance](docs/assets/slvc_dma_results_at_a_glance.svg)

| Focus | Architecture / verified evidence | Direct evidence path |
| --- | --- | --- |
| 16-channel architecture / bounded admission check | **Architecture:** up to 16 AXI-Lite-configured channel contexts with joint ingress, DDR Ring, and CQ reservation plus Fixed/Shared buffering. **Verified:** one two-packet, two-channel directed case where channel 1 progresses and publishes a CQE while channel 0 is full | [Architecture](docs/en/architecture.md#virtual-channel-lifecycle) · [Verification](docs/en/verification.md#channel-admission-isolation-scenario) · [Results](docs/en/results.md#rtl-function-and-interface-throughput) · [Evidence](evidence/slvc_dma_udp_adapter_regression_summary.yaml) |
| 512-bit AXI4 Writer structure / OOC result | **Structural change:** bound reservation accounting by `4 x 16` beats, narrow its counter from 32 bits to 7 bits, and refactor its combinational relationship with payload `bytes-left`/`ready`. **Verified:** same-library, same-constraint 1.5 ns Writer-only paired DC reduces total/combinational area by `7.97%/15.84%`; public Evidence does not establish endpoint-level path removal | [Architecture](docs/en/rx_payload_512_backend.md) · [Verification](docs/en/verification.md#asic-paired-dc-evidence-contract) · [Results](docs/en/results.md#asic-paired-dc-comparisons) · [CSV](evidence/asic_paired_dc/comparisons.csv) / [Manifest](evidence/asic_paired_dc/manifest.yaml) |
| RTL memory-interface throughput | With a ready ideal-memory 1 MiB workload, same-clock 512 and Async512 sustain `64 B/cycle`, `100%` W utilization, and `4` peak outstanding | [Architecture](docs/en/architecture.md#rx-memory-development-profiles) · [Verification](docs/en/verification.md#rx-writer-and-cdc) · [Results](docs/en/results.md#rtl-function-and-interface-throughput) · [Evidence](evidence/slvc_dma_rx_payload_cdc_regression_summary.yaml) |
| C2B4 ASIC implementation | The two-channel register-expanded RX512 subsystem completes a 550 MHz DC handoff and a 450 MHz route/PT point; setup/hold WNS is `+0.041322/+0.000341 ns`, standard-cell area is `1.04207 mm²`, and route DRC/antenna/electrical counts are `0` | [Architecture](docs/en/architecture.md#asic-memory-binding) · [Verification](docs/en/verification.md#asic-paired-dc-evidence-contract) · [Results](docs/en/results.md#asic-c2b4-register-expanded) · [Evidence](evidence/slvc_dma_c2b4_n45_register_postroute_summary.yaml) |

<a id="result-scope-levels"></a>
## Result Scope Levels

| Level | What the result covers | What must not be inferred |
| --- | --- | --- |
| Writer-only OOC | `dma_axi_write_engine_512` synthesized alone for the 1.5 ns paired-DC area result | Not a C2B4 or complete-DMA area reduction |
| C2B4 RX512 memory subsystem | Two channels, 4 KiB per channel, 64 Shared Pool blocks, register-expanded, at fixed DC/P&R/PT points | Not the complete DMA, C4B4, an SRAM implementation, or Fmax |
| Complete SLVC DMA | 16-channel architecture, public RTL, and bounded directed regressions | No complete-DMA ASIC PPA, place-and-route, or signoff claim |
| FPGA Async64 OOC | A 200 MHz routed OOC profile on XC7Z100 | Not a bitstream, board DDR/10G result, or ASIC result |

The C2B4 Writer paired A/B **does not meet the subsystem-promotion condition**: W0 already closes the fixed 550 MHz point. The complete counterexample and reasoning remain in the [detailed results](docs/en/results.md#asic-paired-dc-comparisons); the negative result is neither hidden nor recast as an optimization gain.

<a id="quick-public-checks"></a>
## Quick Public Checks

The following commands do not invoke ModelSim/Questa, Vivado, DC, OpenROAD, or PrimeTime:

```bash
make showcase-check
make slvc_dma_512_defconfig
make sim-dry-run
make asic-evidence-check
```

`asic-evidence-check` validates only the sanitized CSV/YAML, fixed source/tool/library/constraint identities, markers, traces, report hashes, and claim boundaries. It does not rerun commercial EDA or physical-implementation tools.

With ModelSim or Questa installed, the public profiles run the corresponding RTL regressions:

| Focus | Entrypoint |
| --- | --- |
| Core, parser, admission, and Fixed/Shared buffering | `make slvc_dma_512_defconfig sim` |
| Same-clock 512 Writer | `make slvc_dma_512_rx_wide_defconfig sim` |
| CDC bridge and Async64 backend | `make slvc_dma_512_rx_async64_defconfig sim` |
| CDC bridge and Async512 Writer | `make slvc_dma_512_rx_async512_defconfig sim` |

The SpyGlass boundary remains unchanged: **the bounded Writer scope has 0 fatal / 0 error; the complete C2B4 common scope is not claimed clean**. See the [verification details](docs/en/verification.md#asic-paired-dc-evidence-contract).

<a id="ten-minute-rtl-reading-path"></a>
## 10-Minute RTL Reading Path

| Order | File and reading focus |
| ---: | --- |
| 1 | [`slvc_dma_wrapper.v`](rtl/integration/slvc_dma_wrapper.v): start with the system boundary for the 512-bit stream, AXI-Lite, memory master, control messages, and clocks/resets. |
| 2 | [`dma_rx_parser_pipe.v`](rtl/rx/dma_rx_parser_pipe.v): follow SHDR64 parsing and metadata publication; [`dma_rx_channel_match.v`](rtl/rx/dma_rx_channel_match.v): follow `flow_id` matching; [`dma_rx_channel_table.v`](rtl/rx/dma_rx_channel_table.v): inspect up to 16 static contexts and hardware-maintained state. |
| 3 | [`frame_dma_rx_top.v`](rtl/integration/frame_dma_rx_top.v): trace staged lookup, ring/free-space checks, buffer/CQ credits, reservation, and frame admission commit. |
| 4 | [`dma_rx_ingress_queue.v`](rtl/rx/dma_rx_ingress_queue.v): inspect per-channel Fixed ingress; [`dma_rx_frame_shared_adapter.v`](rtl/rx/dma_rx_frame_shared_adapter.v): inspect frame context; [`dma_frame_shared_pool.v`](rtl/rx/dma_frame_shared_pool.v): inspect the block free list, linked blocks, and whole-frame commit/release. |
| 5 | [`dma_rx_ingress_source_selector.v`](rtl/rx/dma_rx_ingress_source_selector.v): see how a Fixed or Shared source is selected and locked through frame end. |
| 6 | [`dma_axi_write_engine_512.v`](rtl/rx/dma_axi_write_engine_512.v): inspect 4 KiB splitting, burst planning, independent AW/W/B progress, outstanding tracking, and reservation credit. |
| 7 | [`dma_rx_payload_cdc_bridge.v`](rtl/rx/dma_rx_payload_cdc_bridge.v): follow command/payload/completion crossing; [`dma_async_fifo.v`](rtl/common/dma_async_fifo.v) and [`dma_async_fifo_tech.v`](rtl/common/dma_async_fifo_tech.v): inspect Gray pointers, technology mapping, and reset boundaries. |
| 8 | [`tb_rtl_v33e20a107_udp_to_dma_smoke.v`](pattern/tb_rtl_v33e20a107_udp_to_dma_smoke.v): follow channel 1 progress and CQE publication while channel 0 is full; [`tb_rtl_rx_payload_writer_512.v`](pattern/tb_rtl_rx_payload_writer_512.v): follow the 2,028 directed Writer cases. |

[Open the complete RTL Reading Guide](docs/en/rtl_reading_guide.md#ten-minute-review-path)

## 1. Problem: Multi-Source Movement On A Shared Link

Acquisition systems often aggregate several traffic sources onto an Aurora-like serial link, an on-chip shared stream, or a packet stream emitted by a MAC. Link sharing reduces external interfaces and protocol instances, but it does not by itself solve channel identification, buffering isolation, DDR ownership, completion publication, or backpressure propagation.

The comparison below is **qualitative architecture analysis**, not a performance benchmark against a vendor DMA. Actual MCDMA behavior depends on its scheduler, per-channel queues, shared AXI master, and software configuration.

| Approach | External-system responsibility | Isolation and shared resources | Primary tradeoff |
| --- | --- | --- | --- |
| `N x` single-channel DMA | External frame parsing and demux, per-channel FIFOs, multiple CSR/IRQ sets, and AXI-master management | Independent instances can provide direct isolation | Control and buffers are duplicated; resource and integration cost scales with channel count |
| Centralized MCDMA class | Usually requires adaptation to its stream and channel-descriptor model | Isolation depends on queues and scheduling; poorly configured shared resources can expose HOL or backpressure propagation | Fewer instances, but the exact blocking and completion semantics must be verified |
| SLVC DMA | Upstream emits SHDR64 or uses a published boundary adapter | Channel-aware admission, fixed/shared storage, and independent rings/CQ; DDR, CQ, and the shared pool remain finite shared resources | Specialized for shared-link segments, with public RTL, regression, and implementation evidence |

## 2. Architecture: Four Implementation Choices

### Keep protocol adaptation at the boundary

The native path is `Aurora/native SHDR64 -> SLVC DMA`. `mcf_endpoint` can arbitrate local sources into shared-link segments. A fixed-profile `dma_udp_ipv4_to_shdr64_adapter` converts Ethernet II / IPv4 IHL=5 / UDP receive packets into SHDR64. MAC/PHY logic, a complete Ethernet stack, and network end-to-end reliability remain outside the DMA Core.

### Let the header select a virtual channel

The parser extracts SHDR64 `flow_id` and length before matching software-programmed channel context. A frame crosses the commit boundary only when ring space, ingress storage, and CQ reservation are all available. Once accepted, its reserved resources cannot be taken by a later request.

### Combine dedicated storage with a shared pool

Fixed ingress storage reserves deterministic channel capacity, while the shared frame pool uses a block free list to absorb uneven bursts. After commit, the source selector remains locked through the frame boundary so 512-bit payload data cannot interleave across sources.

### Separate data backpressure from control messages

AXI4-Stream `valid/ready` provides local beat-level backpressure. PAUSE/RESUME policy travels over the separate control-message/UFC boundary. The Completion Queue writes its body first and publishes owner/valid last so software cannot observe a partial CQE.

![SLVC DMA virtual-channel buffering](docs/assets/slvc_dma_virtual_channel_buffering.svg)

<!-- claim:slvc_dma_channel_admission_isolation_directed maturity:verified -->

The existing adapter-to-DMA directed smoke records `packets=2 channels=2 cqes=2 ch0_full_then_ch1=1`: while channel 0 has no available space, a packet mapped to channel 1 is still accepted and produces its expected CQE. This proves only that directed admission scenario. It is neither a formal claim for arbitrary resource exhaustion nor an MCDMA comparison.

[See the complete data path, resource boundaries, and blocking conditions](docs/en/architecture.md)

## 3. Verification: Protocol Behavior To Physical Results

```text
directed and deterministic-random RTL regression
        -> same-clock / dual-clock RX memory profiles
        -> Vivado synth / place / phys-opt / route OOC
        -> Design Compiler mapped handoff
        -> OpenROAD detail route / same-run OpenRCX SPEF
        -> PrimeTime internal setup / hold STA
```

The public regression covers parsing, channel admission, fixed/shared storage, descriptors, CQ ownership, 4 KiB AXI boundaries, tail WSTRB, randomized backpressure, reset/drain, CDC FIFOs, and writer outstanding traffic. This is bounded directed verification, not formal proof, coverage closure, or complete CDC/RDC signoff.

[See the verification matrix and exact PASS markers](docs/en/verification_matrix.md)

## 4. Currently Verified Results

<!-- claim:slvc_dma_rx_payload_cdc_regression maturity:verified -->
<!-- claim:slvc_dma_async64_vivado_2022_2_ooc_200m maturity:verified -->

| Layer | Profile and workload | Verified result | Maturity boundary |
| --- | --- | --- | --- |
| RTL / memory interface | 512-bit writer, `2028` cases; 1 MiB ideal-memory workload | Same-clock 512 and async512 both sustain `64 B/cycle`, `100%` W utilization, and `4` peak outstanding | RTL/model interface rate, not board DDR or lossless-network throughput |
| FPGA | Async64, Vivado 2022.2, `xc7z100ffg900-2`, 200 MHz routed OOC | WNS/WHS `+0.152/+0.059 ns`; 39,299 LUTs, 43,671 FFs, and 54 BRAM tiles | Retains 52 classified OOC DRC warnings; not a bitstream or board implementation |
| ASIC | C2B4 register-expanded RX512; 550 MHz DC handoff -> 450 MHz route/PT | PT setup/hold WNS `+0.041322/+0.000341 ns`; DRC/antenna/electrical `0` | Two-channel internal memory subsystem; not C4B4, complete DMA, or Fmax |

The same-run C2B4 route uses a `1684.865 x 1684.865 um` die (`2.83877 mm^2`) and a `1644.640 x 1643.600 um` core (`2.70313 mm^2`). Standard-cell area is `1.04207 mm^2` at `38.5506%` core utilization. Here, die means the implementation-block boundary of the two-channel RX512 memory subsystem, not packaged-chip area.

Evidence: [RTL/CDC regression](evidence/slvc_dma_rx_payload_cdc_regression_summary.yaml) · [Vivado 2022.2 OOC](evidence/slvc_dma_async64_vivado_2022_2_ooc_summary.yaml) · [C2B4 post-route](evidence/slvc_dma_c2b4_n45_register_postroute_summary.yaml)

## 5. SRAM Research Progress And Current Blocker

<!-- claim:slvc_dma_sram_a5_clock_delivery_canary maturity:verified -->
<!-- claim:slvc_dma_sram_a5_256_area_reduction maturity:verified -->

SRAM A5 is a separate `partial/blocked` research route, not a peer of the closed results above. The audited 512x128 OpenRAM model and routed boundary canary use `d200 + macro_x3` to reduce macro clock slew from `86.384 ps` to `16.434 ps`. The generated 256x128 macro is `37.74%` smaller than the generated 512x128 macro.

The proxy minimum pulse remains `1.5625 ns`, and independent true-pulse characterization is incomplete, so C4B4 SRAM DC/P&R/PT was not started. The area reduction likewise does not establish performance, power, or integrated PPA improvement.

[See the SRAM model, clock-delivery result, and nonclaims](docs/en/asic_implementation.md)

## Choose An Integration Entrypoint

| Goal | Canonical top / boundary | Configuration and check |
| --- | --- | --- |
| Complete 512-bit Shared-Link DMA | [`slvc_dma_wrapper`](rtl/integration/slvc_dma_wrapper.v) | [`slvc_dma_512.f`](flows/manifests/slvc_dma_512.f) · `make sim-dry-run` |
| FPGA OOC timing top | [`frame_dma_wrapper`](rtl/integration/frame_dma_wrapper.v) | `make fpga-ooc-dry-run` |
| Fixed Ethernet/IPv4/UDP RX adaptation | [`dma_udp_ipv4_to_shdr64_adapter`](rtl/adapters/dma_udp_ipv4_to_shdr64_adapter.v) -> `slvc_dma_wrapper` | Default defconfig · [protocol boundary](docs/en/udp_ipv4_adapter.md) |
| Same-clock or dual-clock RX memory backend | [`frame_dma_rx_top`](rtl/integration/frame_dma_rx_top.v) | `slvc_dma_512_rx_{wide,async64,async512}_defconfig` |

[See ports, clocks/reset, bring-up, and ownership contracts](docs/en/integration.md)

## Documentation And Release Boundary

[Interfaces](docs/en/interfaces.md) · [RTL Reading Guide](docs/en/rtl_reading_guide.md) · [Dual-Clock Backends](docs/en/rx_payload_cdc_backends.md) · [FPGA Implementation](docs/en/fpga_implementation.md) · [ASIC Implementation](docs/en/asic_implementation.md) · [Delivery Status](docs/en/delivery_status.md) · [Evidence](provenance/evidence.yaml) · [Claims](provenance/claims.yaml)

Current `main` is the presentation and development line after `v0.1.0-rc1`. The immutable annotated tag `v0.1.0-rc1` still fixes the original release source, evidence, and checksum identity; this documentation update neither moves nor rebuilds it. See [Limitations](docs/en/limitations.md) and [Public Scope](PUBLIC_SCOPE.md) for complete nonclaims.
