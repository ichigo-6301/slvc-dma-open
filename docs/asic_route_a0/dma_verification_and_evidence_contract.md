# DMA ASIC Route A0 Verification And Evidence Contract

The maturity matrix is [dma_result_maturity_matrix.csv](data/dma_result_maturity_matrix.csv).

## Functional Gate

Every implementation profile must bind an exact source commit, profile defines, filelist, test list, and PASS-marker set.

- **VERIFIED_REPOSITORY_FACT**: the selected baseline already has frozen-core, RX512 writer, Async512 CDC/backend, reset-drain, AXI backpressure, 4 KiB split, tail strobe, response-error, and randomized tests.
- **ANALYSIS**: future macro profiles must rerun all tests touched by wrapper latency, memory semantics, CDC, reset, or source selection; historical evidence is not sufficient for changed memory bindings.

Required cases:

1. **ANALYSIS**: original frozen RTL regression and profile-specific RX512 tests.
2. **ANALYSIS**: 512-bit write path with random AW/W/B backpressure and four outstanding responses.
3. **ANALYSIS**: 4 KiB boundaries, unaligned profile rejection, final `WSTRB`, ring wrap, CQ no-space, and BRESP errors.
4. **ANALYSIS**: reset during idle, accepted frame, payload drain, outstanding AXI, and downstream stall.
5. **ANALYSIS**: Async512 frequency ratios, random phase, clock stop, FIFO wrap/full/empty, tag mismatch, duplicate or out-of-window traffic, and joint hard-reset contract.
6. **ANALYSIS**: shared-pool free-list/linked-list allocation and release, no double allocation/free, no stale frame visibility, and no same-address memory collision outside the approved contract.

## Memory-Replacement Gate

- **ANALYSIS**: compare each behavioral RAM and technology wrapper cycle by cycle under identical commands.
- **ANALYSIS**: assert one-cycle read latency, write-mask behavior, read-before-write or forbidden same-address behavior, and output stability.
- **ANALYSIS**: prove reset correctness without assuming data bits clear. Pointer/count/valid state alone must hide stale memory.
- **ANALYSIS**: for width/depth banking, prove address decode, registered read-bank selection, unused-bit tie-off, and byte ordering.
- **ANALYSIS**: for a dual-clock FIFO leaf, prove independent clocks, Gray ownership, no legal collision, full/empty wrap, reset, and Liberty/Verilog semantic agreement.
- **TBD_MEASUREMENT**: exact behavioral-versus-macro regression results.

## OpenRAM Preparation Gate

1. **ANALYSIS**: pin generator commit and complete configuration.
2. **ANALYSIS**: generate all required Verilog, Liberty, LEF, GDS, SPICE, and compiled DB views in ignored build output.
3. **ANALYSIS**: audit cell name, all scalar/bus pins, port direction, clocks, active polarity, timing tables, dimensions, manufacturing grid, and perimeter pin access.
4. **ANALYSIS**: record SHA-256 for every view and the actual generated PVT corner.
5. **ANALYSIS**: disclose analytical characterization and missing macro DRC/LVS/PEX.
6. **ANALYSIS**: fail if a required port or routeable pin is absent.

## Design Compiler Gate

- **ANALYSIS**: require `analyze`, `elaborate`, `link`, `uniquify`, and `check_design` success.
- **ANALYSIS**: unresolved references and black boxes must be zero except exact approved macro leaves.
- **ANALYSIS**: assert exact macro count and reference names per profile.
- **ANALYSIS**: report latches, multiple drivers, inferred memories, per-clock setup/hold, top path classes, high fanout, design-rule violations, and unconstrained endpoints.
- **ANALYSIS**: write mapped netlist and SDC, hash both, and record tool/library/macro-view hashes.
- **ANALYSIS**: a negative-WNS sweep is a stress result, not implementation margin.

## P&R And Extraction Gate

- **ANALYSIS**: OpenROAD must import the exact DC mapped netlist rather than remap RTL with Yosys/ABC.
- **ANALYSIS**: require macro-count identity, no overlap/core escape, PDN connection, legal placement, CTS, global route, detailed route, antenna report, final routed netlist/SDC, and same-run OpenRCX SPEF.
- **ANALYSIS**: record die/core dimensions, macro dimensions, standard-cell area, utilization, buffer growth, congestion, DRC, antenna, and runtime conditions without promoting them before review.
- **ANALYSIS**: route-tool DRC does not substitute for macro DRC/LVS/PEX.

## PrimeTime Gate

- **ANALYSIS**: require exact netlist, SDC, SPEF, standard-cell DB, and SRAM DB hashes from the same implementation run.
- **ANALYSIS**: fail closed on read, link, SDC, parasitic, clock, or coverage errors.
- **ANALYSIS**: report setup and hold separately by clock group, recovery/removal, macro min-period/pulse-width, transition/capacitance, unconstrained endpoints, and analysis coverage.
- **ANALYSIS**: waivers must be an exact reviewed object set with rationale and limits.
- **ANALYSIS**: internal timing closure does not imply IO, OCV/MMMC, foundry, or silicon signoff.

## Result Maturity Vocabulary

- **ANALYSIS**: use only `planned`, `analyzed`, `elaboration_verified`, `dc_verified`, `chip_level_pnr_verified`, `post_route_sta_verified`, `overall_profile_partial`, and `not_completed` in Route A0 result matrices.
- **ANALYSIS**: stage maturity and overall profile maturity remain separate. A profile may have verified P&R and STA while the macro model or macro physical signoff remains partial.
- **VERIFIED_REPOSITORY_FACT**: all Route A0 implementation rows remain `planned` or `analyzed`; this task ran no OpenRAM generation, DC, P&R, RCX, or STA.

## Publication Contract

- **ANALYSIS**: publish source/profile/tool/view hashes, exact conditions, results, caveats, and nonclaims together.
- **ANALYSIS**: never mix Profile Z measurements into Profile B/C/D claims.
- **ANALYSIS**: call a proven point a closure point, not Fmax, unless a controlled search proves a maximum under fixed conditions.
- **ANALYSIS**: keep PDKs, generated views, commercial logs, licenses, absolute paths, mapped netlists, and SPEF outside the public repository.
