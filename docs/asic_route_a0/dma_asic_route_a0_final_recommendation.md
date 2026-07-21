# DMA ASIC Route A0 Final Recommendation

## Decision Summary

```text
Decision:
GO_WITH_BLOCKERS

Canonical Flow:
RTL regression
-> OpenRAM memory preparation
-> Synopsys Design Compiler
-> mapped-netlist / SDC identity audit
-> OpenROAD placement / CTS / route
-> OpenRCX SPEF
-> Synopsys PrimeTime setup/hold STA

Reference Platform:
Nangate45 academic/reference platform

Analysis Baseline:
fix/async64-aw-planner-pipeline
eed14d7a0dd86ca64177951c0bfc7c3f1829dfa7

First DC Target:
Target B / dma_rx512_sameclk_sram

First P&R Target:
Target B / dma_rx512_sameclk_sram

Canonical RX ASIC Profile:
dma_rx512_async_sram

Final System Profile:
dma_full_rx512_async_sram
```

- **ANALYSIS**: `GO_WITH_BLOCKERS` means the architecture is suitable for a staged SRAM-aware implementation, but no implementation result exists and four contracts must be frozen first.
- **VERIFIED_REPOSITORY_FACT**: Route A0 changed documentation/data only and ran no OpenRAM generation, DC, P&R, RCX, or STA.

## Why This Baseline

- **VERIFIED_REPOSITORY_FACT**: `eed14d7` contains same-clock RX512, real Async512 CDC, Async64 compatibility, reset quiesce/drain, protocol-error visibility, and the registered Async64 AW planner.
- **ANALYSIS**: it is more complete than public `main` and every intermediate remote branch.
- **ANALYSIS**: 64-bit Async64 remains Profile Z. It is not the native ASIC architecture.
- **VERIFIED_REPOSITORY_FACT**: the complete DMA still has mixed memory widths: dedicated RX payload can be 512 bit, while TX/CQ/descriptor shared AXI remains 64 bit.

## Memory Recommendation

- **ANALYSIS**: first macroize fixed ingress payload and shared-pool payload only.
- **ASSUMPTION**: initial banking is 16 fixed-ingress plus 4 shared-pool payload macros, using 128-bit leaves and width/depth banking.
- **ANALYSIS**: keep metadata/context as optional comparison points and keep free list, linked list, channel tables, CQ, AXI plan queues, and shallow FIFOs in registers.
- **ANALYSIS**: keep Async512 payload FIFO in registers until an independent-clock 1W1R macro contract is proven; a later macro-backed variant may use five width banks.
- **TBD_MEASUREMENT**: all macro organizations, counts, dimensions, timing, area, power, and physical behavior.

## Clock Recommendation

- **ASSUMPTION**: Profile B uses one `aclk` and begins with 100 MHz sanity plus 200 MHz architectural-target analysis.
- **ASSUMPTION**: Profile C begins at asynchronous 200/200 MHz, then varies one clock at a time.
- **ANALYSIS**: frequency promotion is limited by clean DC, macro checks, routability, and matching post-route STA; it is not copied from MRTC or FPGA OOC results.

## Mandatory Blockers

1. **ANALYSIS**: freeze canonical source ownership. The selected architecture is in `slvc-dma-open`, not the current private delivery-source line.
2. **ANALYSIS**: generate and audit actual DMA OpenRAM views before macro count, floorplan, or clock targets are finalized.
3. **ANALYSIS**: freeze the dual-clock FIFO implementation and collision/timing contract for Profile C.
4. **ANALYSIS**: resolve the unused `tx_axis_aclk/tx_axis_aresetn` contract before Profile D constraints. If independent TX clocking is required, it is a separate RTL task.

**ANALYSIS**: no production RTL change is proven mandatory for the first same-clock Target B. Alternate ASIC memory leaf modules and a synthesis-only thin wrapper can be implemented in the flow layer. Any required latency/protocol change discovered by macro equivalence must become a separate RTL task.

## Flow-Only Work

- **ANALYSIS**: profile manifests, thin synthesis tops, ASIC replacement leaves under existing RAM boundaries, generated OpenRAM configurations, view audit, LC conversion, DC source/define selection, SDC, mapped-handoff hashing, ORFS adapter, macro placement, PDN hook, RCX handoff, PrimeTime runner, and result parser.
- **ANALYSIS**: none of this work should alter production behavior or historical evidence.

## Deferred Work

- **ANALYSIS**: macroizing reset-dependent free-list/channel arrays.
- **ANALYSIS**: widening TX/CQ/descriptor memory interfaces to 512 bit.
- **ANALYSIS**: adding an internal TX stream CDC if the SoC requires one.
- **ANALYSIS**: clock gating, scan DFT, LEC, MMMC/OCV, IO signoff, macro DRC/LVS/PEX, power integrity, and silicon validation.
- **ANALYSIS**: performance-driven RTL changes before measured DC/P&R evidence.

## Risk Order

1. **ANALYSIS**: source-control/canonical baseline divergence.
2. **ANALYSIS**: macro model and physical pin feasibility.
3. **ANALYSIS**: 512-bit bank routing and depth-mux placement.
4. **ANALYSIS**: dual-clock FIFO technology binding and CDC exceptions.
5. **ANALYSIS**: complete-top TX clock contract and mixed-width memory floorplan.
6. **ANALYSIS**: reset/high-fanout/hold repair in the full hierarchy.

## Next-Round Matrix

1. **ANALYSIS**: static flow preflight and macro generation for candidate `64 x 128`, `128 x 128`, and `512 x 128` 1R1W organizations.
2. **ANALYSIS**: Target A 100/200 MHz elaboration and DC sanity.
3. **ANALYSIS**: Target B same-clock SRAM DC at 100/200/300/400 MHz, stopping promotion at first failed gate.
4. **ANALYSIS**: first conservative Target B P&R from a clean DC point, followed by same-run OpenRCX and PrimeTime.
5. **ANALYSIS**: Async512 Target B only after the same-clock macro baseline and dual-clock leaf decision.
6. **ANALYSIS**: Target C only after Target B closes and the TX clock contract is frozen.

## Potential Resume Metrics

- **ANALYSIS**: a completed future profile may report exact source/config/tool/view hashes, logical and physical macro organization, standard-cell and macro area separately, routed die/core/utilization, DRC/antenna counts, setup/hold WNS/TNS and coverage, clock periods by stage, congestion, and explicitly bounded caveats.
- **ANALYSIS**: power is reportable only with a defined activity/corner/method. Fmax is reportable only after a controlled fixed-profile search; otherwise report verified closure points.
- **VERIFIED_REPOSITORY_FACT**: Route A0 reports none of those implementation metrics as new results.

## Next Branch And Strict Scope

```text
Recommended branch:
feat/dma-rx512-sram-route-a1

Strict scope:
- resolve canonical source ownership;
- add flow-only Target A/B wrappers and profile manifests;
- generate and audit candidate Nangate45/OpenRAM views;
- implement alternate ASIC RAM leaves without changing production behavior;
- run memory semantic equivalence and existing RX512 regression;
- run DC only through an approved Target A/B matrix;
- stop before OpenROAD if macro binding, constraints, or regression are not clean.
```

- **ANALYSIS**: P&R/RCX/PrimeTime should be a subsequent bounded task after A1 freezes the exact mapped netlist, SDC, and macro views.
