# DMA ASIC Route A0 Memory Architecture Audit

## Scope And Counting Rule

- **VERIFIED_REPOSITORY_FACT**: this audit follows the `frame_dma_rx_top` Async512 hierarchy at `eed14d7` and separately lists optional carrier and uninstantiated legacy memories.
- **VERIFIED_REPOSITORY_FACT**: the named major storage families sum to at least `1,178,900 bit`, excluding scalar state, small pipeline registers, optional carrier FIFOs, and uninstantiated legacy modules.
- **ANALYSIS**: this number is a logical RTL storage lower bound, not a standard-cell area, SRAM area, or post-synthesis bit count.

Detailed rows are in [dma_memory_inventory.csv](data/dma_memory_inventory.csv), with candidate binding in [dma_openram_candidate_mapping.csv](data/dma_openram_candidate_mapping.csv).

## Dominant Memories

### Fixed-Channel Ingress Payload

- **VERIFIED_REPOSITORY_FACT**: `dma_rx_fc_ingress_bank/u_payload_ram` is logically `2048 x 512` across 16 channels: `16 * (1024 64-bit words / 8) = 2048` beats, or `1,048,576 bit`.
- **VERIFIED_REPOSITORY_FACT**: it has one synchronous read and one synchronous write in `aclk`; payload contents are not reset, while validity and pointers are reset.
- **ANALYSIS**: this storage is `MUST_MACRO` for representative ASIC PPA.
- **ASSUMPTION**: the leading organization is four 128-bit width banks by four 512-deep banks, for 16 candidate `512 x 128` 1R1W macros. A 2-bit depth select and registered read-bank select are required.
- **TBD_MEASUREMENT**: generated dimensions, pin access, banking mux delay, and whether `512 x 128` is the best compiler point.

### Shared Frame Pool

- **VERIFIED_REPOSITORY_FACT**: payload data is `64 x 512` (`32,768 bit`) and keep data is `64 x 64` (`4,096 bit`). Both have synchronous 1R1W behavior and no payload-array reset.
- **ANALYSIS**: payload data is `MUST_MACRO` for the final representative profile; four `64 x 128` width banks are the initial candidate. Keep bits remain `KEEP_REGISTERS` until a combined byte-mask or narrow companion macro is proven beneficial.
- **VERIFIED_REPOSITORY_FACT**: `free_fifo`, `next_ptr`, ownership, open-frame state, and pool metadata are initialized or cleared in reset loops.
- **ANALYSIS**: those reset-dependent structures should remain registers in Route A1. Macroizing them would require an initialization/scrub architecture change and new regression.

### Metadata And Context

- **VERIFIED_REPOSITORY_FACT**: fixed ingress metadata is `64 x 352` (`22,528 bit`); shared-adapter context is `64 x 299` (`19,136 bit`). Their data arrays are not cleared; pointer/valid state controls visibility.
- **ANALYSIS**: both are `MAY_MACRO`. Three 128-bit banks per memory are feasible, but unused bits, read-latency compatibility, and added bank muxes may cost more than registers at this depth.
- **TBD_MEASUREMENT**: compare register and macro implementations after exact macro dimensions and timing models exist.

### Async512 Payload FIFO

- **VERIFIED_REPOSITORY_FACT**: the RX CDC bridge contains command `4 x 108`, payload `32 x 577`, and completion `4 x 13` storage, totaling `18,948 bit`.
- **VERIFIED_REPOSITORY_FACT**: generic RTL writes the array in `s_clk` and reads it in `mem_clk`; Gray pointers and two-stage synchronizers protect ownership.
- **ANALYSIS**: command and completion stay registers. The payload FIFO is `MAY_MACRO`, not automatically safe for an ordinary single-clock SRAM.
- **ASSUMPTION**: a macro candidate is five 128-bit width banks at depth 32 behind `dma_async_fifo_tech`.
- **TBD_MEASUREMENT**: the chosen OpenRAM release must prove independent clocks, 1W1R timing arcs, cross-port collision behavior, Liberty checks, and physical pin access. Otherwise use registers or a separately characterized dual-clock memory leaf.

## Port And Collision Conclusions

1. **VERIFIED_REPOSITORY_FACT**: payload leaves require one read and one write port, synchronous one-cycle read, and no reset of stored data.
2. **VERIFIED_REPOSITORY_FACT**: nonblocking RTL reads return the pre-write value for a same-edge same-address operation in simulation; synthesis/macro binding must preserve or explicitly forbid that collision.
3. **ANALYSIS**: the normal queue ownership protocols should avoid read/write collision for committed payload, but this must be asserted at each wrapper rather than assumed from intent.
4. **VERIFIED_REPOSITORY_FACT**: shared-pool free-list and linked-list arrays are reset and updated as control state; they are not clean SRAM inference candidates.
5. **ANALYSIS**: shallow AXI plan queues, CQE staging, TX prefetch, and status tables stay registers because they need low latency, reset, multiple update sources, or have poor macro utilization.

## Three-Level Classification

| Class | Storage families | Candidate count | Classification |
| --- | --- | ---: | --- |
| `MUST_MACRO` | fixed ingress payload plus shared-pool payload data | 20 | ASSUMPTION |
| `MAY_MACRO` | fixed metadata, shared context, Async512 payload FIFO | up to 11 additional | ASSUMPTION |
| `KEEP_REGISTERS` | keep bits, command/completion FIFOs, channel tables, free list, linked-list state, CQ/TX/AXI queues | 0 macros | ANALYSIS |

**ASSUMPTION**: the same-clock Profile B starts with 20 payload macros and may grow to 26 if metadata/context macroization wins. Async Profile C may reach 31 if the dual-clock payload FIFO is macro-backed. These are banking proposals, not generated macro counts.

## OpenRAM Feasibility Answers

1. **ANALYSIS**: map a logical `128-deep x 512-bit` channel slice by width banking into four `128 x 128` leaves, or aggregate the full store with width plus depth banking. For the current single read/single write aggregate, `4 width x 4 depth` using `512 x 128` leaves is the lower-count candidate.
2. **ANALYSIS**: two-dimensional banking is preferred over 64 per-channel macros because only one global read and one global write occur per cycle.
3. **VERIFIED_REPOSITORY_FACT**: major payload and metadata arrays are 1R1W; no current candidate requires two writes to the same memory leaf.
4. **ANALYSIS**: same-address read/write semantics and asynchronous-port collisions require explicit wrapper contracts.
5. **VERIFIED_REPOSITORY_FACT**: free list, linked list, channel tables, and several metadata/status arrays are reset; these do not map directly without changing initialization behavior.
6. **ANALYSIS**: all FIFOs below roughly one wide beat of useful depth, plus plan/response queues, remain registers for first implementation.
7. **ANALYSIS**: small per-channel metadata tables should remain registers until macro area and mux costs are measured.
8. **ANALYSIS**: shared payload data, keep bits, linked-list pointers, and frame metadata need separate bindings; their width, reset, and access contracts differ.
9. **ANALYSIS**: an ordinary single-clock OpenRAM leaf is not safe for the CDC payload FIFO. A verified dual-clock 1W1R leaf or register implementation is required.
10. **VERIFIED_REPOSITORY_FACT**: the MRTC-pinned OpenRAM flow generated a 1R1W macro with separate read and write clocks, but DMA depth/width, unrelated-clock timing, and collision behavior have not been generated or tested.
11. **ANALYSIS**: every macro must be instantiated through a technology wrapper. Direct OpenRAM module names in production hierarchy would couple functional RTL to one academic platform.

## Physical Risks

- **ANALYSIS**: four width banks create at least 512 data wires plus read/write control at each logical memory boundary; bank quartets must be placed near the 512-bit consumer.
- **ANALYSIS**: depth banking adds decode and a 512-bit read mux. Register the bank select with the synchronous read address and avoid a cross-core combinational mux.
- **ANALYSIS**: macro pin orientation and perimeter access may dominate routability more than cell logic.
- **TBD_MEASUREMENT**: macro aspect ratio, halo, channel spacing, mux area, clock pin load, and floorplan dimensions.

