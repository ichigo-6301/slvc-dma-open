# Architecture

## System Problem

SLVC DMA targets data movement when several traffic sources share one high-speed serial or packet link. Link sharing consolidates the physical interface, but the receiver must still:

- recover frame boundaries and channel identity from one stream;
- confirm DDR-ring, on-chip-buffer, and Completion Queue capacity before accepting payload;
- isolate software ownership and completion state by channel;
- share capacity across bursts without interleaving payload from committed sources;
- carry PAUSE/RESUME policy independently of payload backpressure.

The engineering contribution is this system architecture and its simulation, FPGA OOC, and ASIC reference-flow evidence, rather than a new compression or scheduling algorithm.

## Typical Alternatives And Tradeoffs

This is qualitative architecture analysis, not a competing-IP benchmark. MCDMA queueing, scheduling, outstanding traffic, and backpressure behavior varies by implementation and configuration.

| Approach | Advantage | Integration cost or risk |
| --- | --- | --- |
| Multiple single-channel DMAs | Channel state and backpressure are directly separated; each instance can select independent storage and AXI masters | Upstream parsing/demux is external; FIFO, CSR, IRQ, address space, and verification infrastructure is duplicated |
| Centralized MCDMA class | Reuses AXI masters, register interfaces, and scheduling | Requires adaptation to its channel/descriptor model; isolation depends on internal queues and scheduling, so shared resources can expose HOL or backpressure propagation |
| SLVC DMA | SHDR64 directly carries channel metadata; parser, admission, fixed/shared buffering, rings, and CQ ownership are integrated | Specialized for the current shared-link contract; the shared pool, CQ, and DDR remain finite shared resources, so universal non-blocking behavior is not claimed |

## End-to-End Data Path

![SLVC DMA shared-link overview](../assets/slvc_dma_overview.svg)

`slvc_dma_wrapper` is the public system-integration top for the fixed `slvc_dma_v1_512` profile. `frame_dma_wrapper` is the complete FPGA OOC timing top. The path includes a shared segment stream, RX parsing/channel matching, frame storage, AXI4 writing, CQ publication, and descriptor-driven TX replay.

RX parses the fixed 64-byte SHDR64 header, admits the segment using channel metadata, and writes payload into the target DDR ring. The CQ body is written before owner/valid becomes visible. TX reads descriptor-selected payload from DDR, rebuilds SHDR64, and replays it on shared-link TX.

## Virtual-Channel Lifecycle

1. **Parse**: the elastic input captures SHDR64 and extracts `flow_id`, payload length, sequence, timestamp, and CRC-related fields.
2. **Match**: `dma_rx_channel_match` combines dynamic header metadata with software-programmed context from `dma_rx_channel_table` without owning table state.
3. **Check**: the RX state machine checks destination-ring space, ingress/shared storage, CQ credit, reset state, and flow-control state.
4. **Reserve**: a frame receives capacity only when every required resource is available; later requests cannot steal that reservation.
5. **Commit and collect**: payload enters fixed ingress or the shared pool. An incompletely committed shared frame cannot be drained.
6. **Drain**: the source selector locks one committed frame through its end, then the legacy 64-bit writer or optional 512-bit backend generates AXI bursts.
7. **Complete**: after AXI responses complete, hardware writes the CQ body and then publishes owner/valid and IRQ. Software must advance ring/CQ ownership before reuse.

## Hybrid Buffering And Actual Isolation Boundaries

![SLVC DMA virtual-channel buffering](../assets/slvc_dma_virtual_channel_buffering.svg)

Fixed ingress reserves deterministic capacity for a channel. `dma_rx_frame_shared_adapter` and `dma_frame_shared_pool` use a block free list so frames arriving at different times can share capacity. Metadata commit is the shared-pool visibility boundary; a drained frame must be released before its blocks re-enter the free list.

The existing adapter-to-DMA directed smoke covers `ch0_full_then_ch1=1`: while channel 0 has no available ring space, the channel 1 packet is admitted and produces its CQE. This demonstrates that channel matching and per-channel ring-space checks do not propagate channel 0 blockage into channel 1 in that scenario.

It does not establish universal non-blocking behavior:

- shared-pool exhaustion blocks every channel selecting the shared policy;
- absent CQ credit, global reset/quiesce, or a permanently unresponsive shared AXI interface creates system-level backpressure;
- the selector locks an active frame for atomicity, so downstream backpressure on that frame delays the next source drain;
- PAUSE/RESUME is a policy message, not a network or AXI4-Stream beat-credit protocol.

## External Protocol Boundaries

Carrier adapters and the MCF endpoint sit outside the DMA ownership boundary:

- `frame_dma_rx_aurora_ufc_wrap` demonstrates an Aurora-compatible payload/UFC boundary; generated Aurora IP is not distributed.
- `mcf_endpoint` arbitrates local sources into shared-link segments, with PAUSE/RESUME on the control-message path.
- `dma_udp_ipv4_to_shdr64_adapter` accepts a fixed 512-bit Ethernet II / IPv4 IHL=5 / UDP profile, repacks payload beginning at byte 42, and maps the UDP destination port to `SHDR64.flow_id`.
- `frame_dma_rx_axis_width_frontend` can pack 64/128/256/512-bit external AXI-Stream beats into the 512-bit Core width; this is not a claim that every native Core width is implemented and verified.

The UDP adapter is outside `frame_dma_wrapper`, so frozen-core FPGA OOC results exclude it. It is not a complete Ethernet stack and excludes MAC/PHY, VLAN, IPv6, fragment reassembly, UDP checksum, and FCS handling.

## RX Memory Development Profiles

Default-off RX memory profiles leave parsing and admission unchanged. After a fixed-ingress or shared-pool frame reaches the existing commit point, `dma_rx_ingress_source_selector` locks one 512-bit drain source:

- same-clock 512 feeds `dma_axi_write_engine_512` directly;
- async64/async512 cross a command, ordered 512-bit payload, and tagged completion through three FIFO channels;
- Async64 serializes to 64 bits in `mem_clk`, while Async512 remains 512 bits;
- AW/W/B remain entirely in `mem_clk`, while the original 64-bit AXI master continues to carry CQ, TX read, and legacy RX traffic.

See the [same-clock backend](rx_payload_512_backend.md) and [dual-clock backends](rx_payload_cdc_backends.md).

## ASIC Memory Binding

ASIC experiments use flow-only bindings without changing production RTL behavior:

- The verified C2B4 register-expanded profile lowers two channels of fixed payload plus shared payload/keep storage into 13 standard-cell register arrays. It preserves 102,400 bits and contains zero SRAM macros.
- The A5 SRAM research profile binds fixed/shared payload arrays to OpenRAM macros and adds explicit macro-output and clock-leaf boundaries. Its one-macro clock delivery is verified, but the proxy minimum-pulse model blocks C4B4 integration.

The two profiles use different memory bindings, so their area and frequency cannot be presented as one methodology. See [ASIC Implementation](asic_implementation.md) and [Verified Results](results.md).
