# DMA ASIC Route A0 DC Compatibility And Timing Risk

The predicted path register is [dma_predicted_critical_paths.csv](data/dma_predicted_critical_paths.csv).

## Language And Elaboration Compatibility

- **VERIFIED_REPOSITORY_FACT**: synthesizable sources are Verilog with indexed part selects, generate blocks, parameters, `$clog2`, functions/tasks, attributes, and compile-time profile defines.
- **VERIFIED_REPOSITORY_FACT**: the existing Design Compiler O-2018.06-SP1 OOC flow successfully analyzed and elaborated `dma_rx_payload_async_ooc_top`, including the generic async arrays and selected writer. That evidence does not cover full `frame_dma_rx_top`.
- **VERIFIED_REPOSITORY_FACT**: Xilinx XPM is selected only under `DMA_ASYNC_FIFO_XPM`; the ASIC OOC path uses generic RTL arrays.
- **VERIFIED_REPOSITORY_FACT**: simulation-only fatal checks are variably guarded by `SYNTHESIS` or `DMA_SYNTHESIS`; some top/writer parameter checks remain as `initial` blocks.
- **ANALYSIS**: a full-design DC preflight must audit how O-2018.06 handles every remaining `initial/$fatal` construct and must fail on unresolved references, black boxes other than approved memory leaves, latches, or multiple drivers.
- **VERIFIED_REPOSITORY_FACT**: no DPI, BFM, testbench, or generated Xilinx IP is required by `filelists/dma_rtl.f`.

## Array And Reset Compatibility

- **VERIFIED_REPOSITORY_FACT**: large payload arrays are isolated behind RAM leaf modules and do not reset their data.
- **VERIFIED_REPOSITORY_FACT**: channel tables, shared-pool free/next arrays, TX prefetch data, and several small arrays are reset with loops.
- **ANALYSIS**: the first group is compatible with technology wrappers; the reset arrays should remain registers unless a later functional task replaces bulk reset with valid/scrub semantics.
- **ANALYSIS**: attributes such as `ram_style`, `ASYNC_REG`, `keep`, and `max_fanout` are FPGA-oriented hints. The ASIC flow must either ignore them safely or translate intent in wrappers/constraints without changing function.

## Static Control-Cone Review

### RX Admission

- **VERIFIED_REPOSITORY_FACT**: channel match scans up to 16 flattened channel entries; subsequent stages select control, base, size, pointers, watermarks, queue occupancy, CQ availability, and release state.
- **VERIFIED_REPOSITORY_FACT**: the current top already stages match, context, release, ring-free, and final admission decisions across several registered states.
- **ANALYSIS**: likely limiters are dynamic channel selection, fanout, and placement between channel tables and ingress/CQ state, not the 512-bit payload datapath itself.

### Shared Frame Pool

- **VERIFIED_REPOSITORY_FACT**: scheduling uses round-robin request vectors, free-list state, linked-list pointers, metadata, allocation/release exclusion, and optional drain/request pipelines.
- **ANALYSIS**: free-list read to allocation control and linked-list read to release/drain are likely control paths. Macroizing pointer arrays would add latency and should not be attempted without a redesigned protocol.

### AXI Write Planning

- **VERIFIED_REPOSITORY_FACT**: both 512-bit and 64-bit writers limit bursts, split at 4 KiB, track accepted plans, and allow up to four ordered responses.
- **VERIFIED_REPOSITORY_FACT**: commit `2a3faf3` added a registered Async64 AW candidate. Branch evidence reports that the former `issue_beats_left -> AWADDR/CE` path left the optimized top-100 list.
- **VERIFIED_REPOSITORY_FACT**: the branch-local FPGA global worst path became ingress payload-RAM address routing, while the remaining planner-internal path was noncritical in that measured profile.
- **ANALYSIS**: retain the planner pipeline. Do not infer that ASIC timing is closed or apply the Async64 edit to unrelated 512-bit logic without a measured path.

### TX And CQ

- **VERIFIED_REPOSITORY_FACT**: TX scheduling scans channel requests, fetches descriptors over 64-bit AXI, captures a 512-bit descriptor, plans 4 KiB-bounded reads, and aggregates 64-bit words into 512-bit stream beats.
- **ANALYSIS**: request arbitration, descriptor/status fanout, AR planning, and prefetch reservation are more likely control limiters than the registered SHDR data itself.
- **VERIFIED_REPOSITORY_FACT**: CQ publication is explicitly body-first and owner/valid-last. Shared writer arbitration and CQ reservation are correctness boundaries.
- **ANALYSIS**: never pipeline or merge CQ stages solely for WNS without preserving the software visibility order and reservation proof.

### AXI-Lite And Global Control

- **VERIFIED_REPOSITORY_FACT**: AXI-Lite reads select among global, RX, TX, and descriptor regions; status mirrors and event lanes already reduce some direct table fanout.
- **ANALYSIS**: full-top readback muxing, soft-reset distribution, status mirrors, and IRQ/event reduction remain high-fanout candidates.

## Width-Dependent Risks

- **ANALYSIS**: 512-bit data mostly affects routing, register clock load, macro pin access, and mux placement rather than combinational arithmetic depth.
- **ANALYSIS**: 512-bit keep generation and byte-lane steering are bounded fixed-width structures, but a distant bank mux can make them route dominated.
- **ANALYSIS**: control paths such as admission, free-list, AW credit, and CQ reservation can limit frequency even when the 512-bit datapath is physically local.

## Do Not Pre-Optimize

1. **ANALYSIS**: do not add pipeline stages to admission, shared-pool release, CQ publication, or descriptor ownership before endpoint-level DC evidence.
2. **ANALYSIS**: do not replace reset arrays with SRAM in this route-analysis task.
3. **ANALYSIS**: do not reduce channel count, FIFO depth, outstanding count, or error observability to improve a synthetic result.
4. **ANALYSIS**: do not report the historical writer-only DC sweep as full-DMA frequency.
5. **TBD_MEASUREMENT**: first collect `check_design`, per-clock QOR, top paths, fanout, inferred/mapped memories, unmapped points, and unconstrained endpoints for each profile.

