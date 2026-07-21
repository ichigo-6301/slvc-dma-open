# MRTC To DMA Flow Reuse Analysis

The component matrix is [mrtc_dma_flow_reuse_matrix.csv](data/mrtc_dma_flow_reuse_matrix.csv).

## Reuse Boundary

- **VERIFIED_REPOSITORY_FACT**: the public MRTC flow separates OpenRAM generation/view audit, Library Compiler DB creation, Design Compiler, digest-pinned ORFS OpenROAD/OpenRCX, handoff sanitization, and PrimeTime.
- **VERIFIED_REPOSITORY_FACT**: MRTC's SRAM is a fixed `64 x 128` 1R1W prefix macro with two instances and a same-cycle same-address collision prohibition.
- **ANALYSIS**: DMA can reuse the stage contracts and fail-closed checks, but not MRTC's top name, two-macro count, memory organization, pin list assumptions, floorplan dimensions, placement coordinates, clock, or measured results.

## Directly Reusable Methodology

1. **ANALYSIS**: Kconfig/defconfig stage selection and ignored local tool paths.
2. **ANALYSIS**: source manifest parsing and profile-specific build roots.
3. **ANALYSIS**: pinned OpenRAM commit, generated-view presence checks, Liberty/LEF/Verilog pin audit, SHA-256 manifest, and LC `.db` conversion.
4. **ANALYSIS**: exact mapped SRAM count checks and fail-closed unresolved/blackbox policy.
5. **ANALYSIS**: digest-pinned ORFS container and explicit mapped-netlist input.
6. **ANALYSIS**: immutable source views plus build-local LEF normalization with recorded hash.
7. **ANALYSIS**: pre-PDN supply-pin mapping, same-run netlist/SDC/SPEF handoff, SDC sanitization, and PrimeTime read/link/parasitics failure gates.
8. **ANALYSIS**: result maturity and public/private artifact separation.

## DMA-Specific Rewrites

- **ANALYSIS**: OpenRAM configuration must support several organizations and possibly a dual-clock leaf rather than one `64 x 128` macro.
- **ANALYSIS**: memory wrappers need 512-bit width banking, depth select, optional metadata banks, and explicit collision assertions.
- **ANALYSIS**: DC must support Profile A/B/C/D source sets, profile defines, multiple clocks, exact macro counts, and per-clock timing reports.
- **ANALYSIS**: OpenROAD configuration must be generated from real DMA macro dimensions and regional placement. MRTC's fixed die/core and symmetric two-macro placement are unusable.
- **ANALYSIS**: SDC/PrimeTime audits must cover Async512 Gray pointers, FIFO data structures, recovery/removal, mixed 64/512-bit interfaces, and the unresolved TX clock boundary.

## MRTC Caveats That Still Apply

- **VERIFIED_REPOSITORY_FACT**: MRTC records analytical OpenRAM characterization, generated-corner mismatch, no macro DRC/LVS, LEF grid normalization without GDS rewrite, and academic RC/signoff limits.
- **ANALYSIS**: DMA must retain equivalent caveats unless it obtains stronger macro characterization and physical verification.
- **ANALYSIS**: a route-tool DRC result does not prove macro DRC/LVS, and a PrimeTime internal result does not prove IO/MMMC/OCV or silicon signoff.

## DMA Risks Absent Or Smaller In MRTC

1. **ANALYSIS**: at least 20 proposed payload macros instead of two.
2. **ANALYSIS**: 512-bit buses and depth-bank muxes create much higher pin-access and congestion pressure.
3. **ANALYSIS**: real `aclk <-> mem_clk` CDC and a potential dual-clock memory leaf.
4. **ANALYSIS**: reset-initialized free-list/linked-list arrays that cannot be blindly macroized.
5. **ANALYSIS**: full-system mixed 64/512-bit AXI boundaries and unused TX clock ports.
6. **ANALYSIS**: shared frame-pool ownership, multi-outstanding AXI, CQ owner-last publication, and larger control fanout.

## Common Flow Opportunity

- **ANALYSIS**: abstract common Python/Tcl helpers for manifest reading, tool-path isolation, view hashing, LC conversion, mapped-netlist/SDC identity, ORFS handoff, SPEF validation, PrimeTime coverage, and maturity rendering.
- **ANALYSIS**: keep design-owned files separate: top/profile definitions, memory inventory, wrapper maps, macro manifests, pins, SDC exceptions, floorplan, macro placement, and report parsers.
- **ASSUMPTION**: a common flow library should accept declarative design/profile manifests rather than branching on `MRTC` or `DMA` names inside shared scripts.

