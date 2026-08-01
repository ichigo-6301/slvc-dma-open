# Verification

## Evidence Layers

SLVC DMA records protocol behavior, interface throughput, FPGA implementation, and ASIC implementation as separate layers. A PASS at one layer does not promote an adjacent layer automatically.

| Layer | Checks | Current evidence |
| --- | --- | --- |
| Release-core RTL | Parser, channel table, hybrid ingress, shared pool, descriptors, CQ, AXI-Lite, and W prefetch | Ten fixed markers on Windows ModelSim and IC_EDA Questa |
| Optional UDP adapter | Boundary/parser, random packets, error/reset/stall, and adapter-to-DMA channel mapping | Four regressions on both simulator hosts |
| RX memory backend | Same-clock 512, async64, async512, CDC/reset, AW planning, 4 KiB/tail, and response errors | Profile-specific markers on both simulator hosts |
| FPGA OOC | Synthesis, placement, physical optimization, routing, setup/hold, CDC/bus skew, and resources | Vivado 2018.3 profile matrix plus an independent Vivado 2022.2 async64 run |
| ASIC physical | Mapped handoff, detail route, same-run SPEF, and PT setup/hold/electrical checks | C2B4 register-expanded internal profile |

## Release-Bound Regression

The release-bound regression uses Windows ModelSim SE-64 2020.4 and IC_EDA Linux Questa Sim-64 10.7c. It covers TX channel tables, full-architecture throughput, hybrid RX ingress, shared frame pools, parser behavior, AXI-Lite reads, TX CQ space, descriptor queue/status, and the W prefetch FIFO.

The runner always requires ten frozen-core PASS markers. The default adapter-enabled defconfig adds four adapter markers for fourteen total. The optional RX-wide defconfig disables the adapter and adds two wide-backend markers for twelve total. Each dual-clock defconfig schedules ten core tests, one common CDC-bridge command, and two width-specific commands. Async64 requires fifteen markers and Async512 requires fourteen.

See the [Verification Matrix](verification_matrix.md) for every command, behavior, and marker.

## ASIC Paired-DC Evidence Contract

The public paired-DC bundle binds every point to a fixed source commit, source
file SHA-256, tool/library/constraint identity, simulation marker set, semantic
trace digest, lint boundary, and commercial-report digest. Raw commercial EDA
logs and reports are not published.

Windows ModelSim SE-64 2020.4 and Linux Questa Sim-64 10.7c use the same
sources, parameters, testbenches, and required markers. A normalized semantic
trace retains only ordered case/phase, throughput, final-count, and PASS
records; simulator prompts, timestamps, paths, and platform noise are removed.
Every point in an equivalence group must have the same trace SHA-256.

The Writer suites require the 2,028-case marker, the 64 B/cycle ideal-model
throughput marker, the directed integration marker, and both A3 profile
markers. P6 and P7 each require nine Shared Pool case markers plus the final
PASS marker on both platforms.

SpyGlass scope is intentionally not collapsed: bounded Writer lint has zero
fatal and zero error with reviewed warnings, while the full C2B4 common scope
remains `BLOCKED_COMMON_SCOPE` with 0 fatal, 15 errors, 202 warnings, and zero
waivers. No waiver converts that full scope into a lint-clean claim.

`make asic-evidence-check` validates the schema and identities, regenerates
all comparisons from `points.csv` using `Decimal`, checks markers and trace
equivalence, enforces the lint boundary, rejects sensitive data and raw EDA
payloads, and can restrict a PR to the approved evidence-only path set.

## Channel-Admission Isolation Scenario

The fixed adapter-to-DMA smoke marker is:

```text
PASS tb_rtl_v33e20a107_udp_to_dma_smoke packets=2 channels=2 cqes=2 ch0_full_then_ch1=1
```

The test first removes available ring space from channel 0, then sends a packet mapped to channel 1 and checks its admission, payload, and CQE. It demonstrates progress in this one per-channel ring-space scenario. It does not prove universal non-blocking behavior under shared-pool, CQ, or AXI exhaustion and is not an MCDMA performance comparison.

## RX Writer And CDC

The 512-bit writer test covers 2028 cases including length/tail handling, 4 KiB splits, maximum outstanding traffic, randomized AW/W/B backpressure, response errors, reset, and ideal-memory throughput. Async64/Async512 additionally cover:

- command, ordered 512-bit payload, and tagged-completion CDC FIFOs;
- six clock profiles, random phase, and two clock-stop scenarios;
- Gray-pointer bus-skew constraints and directional CDC reports;
- zero/short/exact/surplus source credit, 1/2/7/31-cycle AW stalls, and simultaneous events;
- bounded soft-reset quiesce/drain and software-visible protocol errors.

The ideal 1 MiB workload measures 64 B/cycle for same-clock 512 and async512, and 8 B/cycle for async64. All three report 100% W-channel utilization and four peak outstanding bursts. These are ready-memory-model RTL interface rates, not board DDR throughput.

## Entrypoints

```text
make slvc_dma_512_defconfig
make sim-dry-run
make sim
```

The public presentation and flow-contract check does not require a simulator:

```text
make showcase-check
```

Directed and deterministic-random PASS results are not functional coverage closure, formal proof, proof of every parameter combination, or complete CDC/RDC signoff. Fixed source commits, log checksums, and caveats are under `evidence/` and `provenance/`.
