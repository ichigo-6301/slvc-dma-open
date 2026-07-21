# DMA ASIC Route A0 Implementation Target Hierarchy

## Current Hierarchy Facts

- **VERIFIED_REPOSITORY_FACT**: `frame_dma_rx_top` is the integration core. It instantiates channel tables, parser/match/admission, fixed ingress storage, shared frame pool, source selector, flow control, TX engine, optional RX payload writer/CDC, CQ writers, AXI write arbitration, AXI-Lite registers, and UFC mailbox.
- **VERIFIED_REPOSITORY_FACT**: `dma_rx_payload_async_ooc_top` contains only reset synchronizers, the RX payload CDC bridge, optional 512-to-64 serializer, and one selected RX writer. It intentionally excludes source frame stores and most DMA control.
- **VERIFIED_REPOSITORY_FACT**: `frame_dma_wrapper` and `slvc_dma_wrapper` hard-fail when `SL_DATA_WIDTH != 512`.

The comparison matrix is in [dma_target_matrix.csv](data/dma_target_matrix.csv).

## Target A: 512-bit AXI Write Backend

Proposed hierarchy:

```text
dma_rx512_writer_route_top (new thin flow wrapper)
`-- dma_axi_write_engine_512
    |-- AW burst and 4 KiB planning
    |-- accepted-burst plan queue
    |-- W channel and tail WSTRB generation
    `-- ordered B-response/error completion
```

- **VERIFIED_REPOSITORY_FACT**: the production writer module already exists and has standalone regression and DC OOC evidence.
- **ANALYSIS**: a thin route wrapper is still useful to define realistic source-credit, AXI boundary, clock/reset, and output-load contracts without including unrelated DMA logic.
- **ANALYSIS**: Target A captures control timing in burst planning and response accounting but does not capture the dominant ingress SRAM-to-W routing or RX admission cones.
- **ANALYSIS**: use Target A for elaboration and floorplan plumbing sanity, not as the resume PPA result.

## Target B: RX Memory Subsystem

Proposed hierarchy:

```text
dma_rx512_memory_subsystem_top (new thin flow wrapper)
|-- dma_rx_fc_ingress_bank
|   `-- dma_payload_beat_ram
|-- dma_rx_frame_shared_adapter
|   `-- dma_frame_shared_pool
|       `-- dma_frame_payload_ram
|-- dma_rx_ingress_source_selector
|-- optional dma_rx_payload_cdc_bridge
`-- dma_axi_write_engine_512
```

- **VERIFIED_REPOSITORY_FACT**: no existing top contains exactly this boundary. `frame_dma_rx_top` contains it, while the existing async OOC top omits the source stores.
- **ANALYSIS**: Target B is the first representative P&R target because it includes the 1,048,576-bit fixed-ingress data store, shared payload store, metadata/context paths, frame-locked selection, 512-bit payload movement, and AXI write control.
- **ASSUMPTION**: the thin wrapper may drive pre-admitted committed-frame commands instead of reproducing the entire parser/channel-admission state machine. This must be cycle-accurately tied to an integration regression before it is accepted.
- **ANALYSIS**: build same-clock Target B first, then enable the Async512 bridge under the same wrapper.

## Target C: Complete DMA

Existing hierarchy:

```text
frame_dma_rx_top
|-- RX parser / channel match / admission / flow control
|-- fixed ingress bank and shared frame pool
|-- optional RX payload CDC and 512-bit writer
|-- TX descriptor scheduler / 64-bit AXI read prefetch / SHDR builder
|-- CQ writers and shared 64-bit AXI write arbiter
|-- AXI-Lite register and channel tables
`-- UFC mailbox / IRQ / soft-reset coordination
```

- **VERIFIED_REPOSITORY_FACT**: Target C already exists as synthesizable RTL, but no macro-aware full-design DC/P&R/STA flow exists.
- **ANALYSIS**: it is the final system target, not the first P&R bring-up object. It combines wide SRAM buses, deep control muxes, multiple reset policies, mixed 64/512-bit memory interfaces, and optional CDC.
- **ANALYSIS**: carrier CDC and MCF should remain outside the first Target C physical block unless the SoC boundary explicitly requires them. They have additional clocks and shallow wide FIFOs that need separate technology decisions.

## Recommended Order

1. **ANALYSIS**: Target A, to prove 512-bit writer elaboration, constraints, mapped-netlist handoff, and basic route plumbing.
2. **ANALYSIS**: Target B same-clock SRAM, to freeze macro wrappers, banking, floorplan, and representative RX timing.
3. **ANALYSIS**: Target B Async512, to add dual-clock FIFO and CDC constraints without full control-plane noise.
4. **ANALYSIS**: Target C, after memory and CDC leaves are independently closed.

**ANALYSIS**: Target A is too local for final claims, while Target C is too broad for first macro/P&R bring-up. The A-to-B-to-C sequence is retained.

