# SLVC DMA RTL Reading Guide

This guide is for FPGA and ASIC engineers who want to understand the SLVC DMA
data path, control boundaries, and verification strategy from the source. The
native Core is fixed at 512 bits, SHDR64 is fixed at 64 bytes, and payloads are
bounded at 4096 bytes. An external width frontend can pack 64/128/256/512-bit
AXI-Stream beats into the 512-bit Core, but that does not establish native Core
support or verification for every external width.

The frozen default profile uses the legacy 64-bit memory writer. Same-clock
512, Async512, and C2B4 use `dma_axi_write_engine_512`. They share admission,
frame-buffering, and completion semantics, but implementation results from one
profile must not be extrapolated to another.

<a id="ten-minute-review-path"></a>
## 1. Recommended 10-Minute Path

| Order | File and reading focus |
| ---: | --- |
| 1 | [`slvc_dma_wrapper.v`](../../rtl/integration/slvc_dma_wrapper.v): system boundary, native 512-bit guard, AXI-Lite, memory master, control messages, and clocks/resets. |
| 2 | [`dma_rx_parser_pipe.v`](../../rtl/rx/dma_rx_parser_pipe.v): SHDR64 parsing and metadata publication; [`dma_rx_channel_match.v`](../../rtl/rx/dma_rx_channel_match.v): `flow_id` matching; [`dma_rx_channel_table.v`](../../rtl/rx/dma_rx_channel_table.v): up to 16 channel contexts and hardware-maintained state. |
| 3 | [`frame_dma_rx_top.v`](../../rtl/integration/frame_dma_rx_top.v): staged lookup, ring/free-space checks, buffer/CQ credit, reservation, and frame-admission commit. |
| 4 | [`dma_rx_ingress_queue.v`](../../rtl/rx/dma_rx_ingress_queue.v): per-channel Fixed ingress; [`dma_rx_frame_shared_adapter.v`](../../rtl/rx/dma_rx_frame_shared_adapter.v): frame context; [`dma_frame_shared_pool.v`](../../rtl/rx/dma_frame_shared_pool.v): block free list, linked blocks, and whole-frame commit/release. |
| 5 | [`dma_rx_ingress_source_selector.v`](../../rtl/rx/dma_rx_ingress_source_selector.v): Fixed/Shared source selection and locking through frame end. |
| 6 | [`dma_axi_write_engine_512.v`](../../rtl/rx/dma_axi_write_engine_512.v): 4 KiB splitting, burst planning, independent AW/W/B progress, outstanding tracking, and reservation credit. |
| 7 | [`dma_rx_payload_cdc_bridge.v`](../../rtl/rx/dma_rx_payload_cdc_bridge.v): command/payload/completion crossing; [`dma_async_fifo.v`](../../rtl/common/dma_async_fifo.v) and [`dma_async_fifo_tech.v`](../../rtl/common/dma_async_fifo_tech.v): Gray pointers, technology mapping, and reset boundaries. |
| 8 | [`tb_rtl_v33e20a107_udp_to_dma_smoke.v`](../../pattern/tb_rtl_v33e20a107_udp_to_dma_smoke.v): channel 1 progress and CQE publication while channel 0 is full; [`tb_rtl_rx_payload_writer_512.v`](../../pattern/tb_rtl_rx_payload_writer_512.v): the 2,028 directed Writer cases. |

Continue into TX descriptors, CQ owner-last publication, AXI-Lite, adapters,
or the complete CDC documentation according to the area under review.

## 2. Text Hierarchy

```text
slvc_dma_wrapper
`-- frame_dma_wrapper
    `-- frame_dma_rx_top
        |-- RX parser / channel match / admission
        |-- ingress queue or shared frame pool
        |-- selected legacy64 / same-clock 512 / async memory writer
        |-- TX channel / descriptor table
        |-- dma_tx_engine
        |   |-- dma_tx_header_builder
        |   `-- dma_axi_read_prefetch
        |-- dma_cq_single_writer / dma_cq_writer
        |-- dma_axil_regs
        |-- dma_ufc_mailbox
        `-- RX/TX AXI master arbitration

Optional external boundaries:
dma_udp_ipv4_to_shdr64_adapter -> slvc_dma_wrapper
frame_dma_rx_axis_width_frontend -> 512-bit Core
slvc_carrier_cdc_adapter -> AXIS/control async FIFO -> Core
frame_dma_rx_aurora_ufc_wrap -> Aurora UFC adapter + Core
mcf_endpoint -> shared-link segment source
```

## 3. RX Data Path

```text
512-bit RX AXIS
  -> elastic FIFO
  -> SHDR64 parser
  -> channel match and static context
  -> admission/resource reservation
  -> ingress queue or shared frame pool
  -> selected legacy64 / same-clock 512 / async memory backend
  -> payload completion
  -> CQE body write
  -> CQE owner/valid publication
```

### Header And Segment Boundary

One 512-bit Core beat equals the 64-byte SHDR64 header. `payload_len` in that
header determines segment length; the Core does not use AXI4-Stream `TLAST` to
find the segment boundary. `dma_rx_parser_pipe` captures the header, stages CRC
and fixed-field checks, and then publishes metadata through an elastic output.

### Channel Match And Context

Parser output contains dynamic packet metadata such as flow/message ID, payload
length, sequence, and timestamp. `dma_rx_channel_table` owns software
configuration and hardware-maintained channel state such as base, size,
pointers, policy, and counters. `dma_rx_channel_match` combines these views but
does not own table state.

### Admission And Reservation

The RX state machine in `frame_dma_rx_top` reads channel context, accounts for
software-consumed ring space, computes free space, and checks ingress and CQ
resources. A frame reaches commit only after these checks pass. Reservation
prevents a later frame from taking resources already promised to an accepted
frame.

### Shared Frame Pool

`dma_rx_frame_shared_adapter` creates one context per frame and stores payload
in `dma_frame_shared_pool`. A block free list shares capacity instead of
assigning one deep FIFO to every channel. Metadata commit is the visibility
boundary: an incomplete frame cannot drain, and drained blocks return to the
free list only after explicit release.

### AXI Write Paths

The frozen default `dma_axi_write_engine` accepts 64-bit words. Same-clock 512
and Async512 use `dma_axi_write_engine_512`; Async64 serializes in the memory
clock domain before `dma_axi_write_engine_64_stream`. All three paths bound
burst length, split at 4 KiB, limit outstanding traffic, and track AW, W, and B
progress independently. Upper layers complete a payload only after responses
finish.

`dma_axi_write_engine_512` sizes source reservation from
`MAX_BURST_BEATS * MAX_OUTSTANDING` and uses source level plus reservation
credit before publishing an AW plan. Distinguish the 32-bit payload
bytes-left state from the bounded reservation counter. Writer-only DC evidence
does not establish C2B4 or complete-DMA area.

## 4. TX Data Path

TX supports single-shot channel context and descriptor-ring entrypoints, then
shares the remaining path:

```text
channel/descriptor selection
  -> context capture
  -> CQ space check
  -> dma_tx_header_builder
  -> SHDR64 header beat
  -> dma_axi_read_prefetch
  -> payload beats
  -> TX completion/CQE
  -> descriptor RD_PTR or channel-state update
```

`dma_tx_desc_channel_table` owns descriptor-ring base, size, and pointers.
`dma_tx_engine` captures the selected descriptor context before transmission.
Pointer advancement occurs only at a defined commit boundary, not merely when
AR or R activity begins.

`dma_axi_read_prefetch` aggregates 64-bit AXI RDATA into 512-bit TX payload.
Its FIFO isolates memory latency from `tx_axis_tready`; reservation keeps issued
reads within local FIFO capacity. `dma_tx_header_builder` emits the fixed
64-byte header and CRC. Length state, rather than TLAST, determines the final
payload beat.

## 5. Completion And Control Plane

`dma_cq_writer` writes the CQE body before the owner/valid word, so software
cannot consume a partial CQE. `dma_cq_single_writer` arbitrates RX and TX
producers and maintains shadow pointers and ring-space accounting.

`dma_axil_regs` divides global, TX-channel, RX-channel, and TX-descriptor
regions. Read and write pipelines stage decode, sampling, execution, and
response so broad combinational decode does not directly drive every channel
table. Hardware events are captured before table/counter updates, preventing
one same-cycle assignment from overwriting another.

Hard reset remains asynchronous and active low. Soft reset is a synchronous
event in `aclk`; it clears FSM, valid, pointer, occupancy, and pending control
state without clearing large payload RAM bodies.

## 6. Carrier, CDC, And Adapter Boundaries

`slvc_carrier_cdc_adapter` uses `dma_axis_async_fifo` and
`dma_ctrl_msg_async_fifo` between carrier and Core clocks. `dma_async_fifo`
maintains binary/Gray pointers in each domain and transfers Gray pointers
through two-stage synchronizers; full and empty are local-domain decisions.

`dma_rx_payload_cdc_bridge` crosses a committed frame as one command, ordered
512-bit payload entries, and one tagged completion rather than crossing a full
AXI channel. Source and memory active state explain the one-frame-in-flight
contract. `dma_async_fifo_tech` selects XPM for the 32-entry payload FIFO and
the Gray-pointer implementation for shallower command/completion FIFOs.

Async64 uses `dma_rx_payload_serializer_512_to_64` and
`dma_axi_write_engine_64_stream`; Async512 reuses
`dma_axi_write_engine_512`. `frame_dma_rx_top` waits for completion and frame
release before propagating an idle soft reset across both domains. See
[Optional Dual-Clock RX Payload Backends](rx_payload_cdc_backends.md).

Aurora UFC and MCF carry control-policy messages, not AXI beat-level
backpressure. The width frontend changes beat packing without changing SHDR64
semantics. The fixed UDP/IPv4 adapter supports Ethernet II, IPv4 IHL=5, and UDP
only; it does not claim VLAN, IPv6, reassembly, checksum/FCS, or end-to-end flow
control.

## 7. Units That Must Not Be Mixed

| Name | Unit | Current profile meaning |
| --- | --- | --- |
| SHDR64 | byte | 64 bytes |
| Core RX/TX beat | bit / byte | 512 bits / 64 bytes |
| Legacy AXI memory word | bit / byte | 64 bits / 8 bytes |
| Payload length | byte | up to 4096 bytes |
| Aligned length | byte | rounded to 64 bytes |
| Ring pointer | entry or byte | depends on the named ring |
| Pool block | Core beat | one 512-bit payload block |

Do not interchange `payload_len`, `aligned_len`, `*_words`, `*_beats`, and
`*_ptr`. The legacy write path converts byte length into 64-bit words, while
the shared pool allocates 512-bit blocks.

## 8. Primary State Machines

| File | State or signal | Reading focus |
| --- | --- | --- |
| `frame_dma_rx_top.v` | `RX_*` | parse, lookup, space check, commit, collect, drop |
| `frame_dma_rx_top.v` | `WR_*` | payload command, write response, CQE, frame pop |
| `dma_rx_parser_pipe.v` | `ST_IDLE/CRC/VALIDATE/OUT` | header capture and elastic output |
| `dma_frame_shared_pool.v` | `RD_*`, `REL_*` | metadata read, payload drain, block release |
| `dma_tx_engine.v` | `ST_DESC_*`, `ST_HEADER`, `ST_SEND_PAY` | descriptor and replay path |
| `dma_cq_writer.v` | `ST_BODY_*`, `ST_OWNER_*` | owner-last visibility |
| `dma_axil_regs.v` | `RD_*`, `WR_*` | CSR pipeline and protection checks |
| `dma_udp_ipv4_to_shdr64_adapter.v` | `ST_*` | validation, carry merge, and drop drain |

## 9. Directed Tests To Read With The RTL

- `modelsim/run_rtl_v13_parser_pipeline.do`: parser, CRC, and output handshake.
- `modelsim/run_rtl_v33e19_shared_frame_pool.do`: shared allocation, read, and release.
- `modelsim/run_rtl_v33e20a_hybrid_rx_ingress_minimal.do`: Fixed/Shared integration.
- `modelsim/run_rtl_v33e20a23_full_arch_throughput.do`: steady-state full architecture.
- `modelsim/run_rtl_v33e20a23_w_prefetch_fifo.do`: legacy prefetch and burst boundaries.
- `modelsim/run_rtl_rx_payload_writer_512.do`: 2,028 Writer length, 4 KiB, tail, outstanding, and backpressure cases.
- `modelsim/run_rtl_rx_payload_cdc_bridge.do`: command/payload/completion CDC and clock/reset stress.
- `modelsim/run_rtl_v33e20a107_udp_to_dma_smoke.do`: channel 1 progress and CQE after channel 0 fills.
- `modelsim/run_rtl_v28_tx_descriptor_queue.do`: descriptor ownership and TX queue.
- `modelsim/run_rtl_v33e20a106_udp_to_shdr_error_matrix.do`: adapter drops and recovery.

## 10. Legacy And Compatibility Modules

- `dma_rx_payload_buffer` is the older payload buffer and is not the preferred shared-pool path.
- `dma_axi_write_engine` is the frozen default profile's legacy 64-bit path; `dma_axi_write_engine_512` belongs to same-clock 512, Async512, and C2B4.
- `dma_cq_writer` remains for one producer; the complete profile can serialize RX/TX through `dma_cq_single_writer`.
- `UFC` in names denotes the existing control-message compatibility boundary and does not bind the Core to Aurora.
- The width packer is an external adaptation boundary, not proof of native width parameterization.
- Historical smoke and experimental modules outside the public allowlist are not release tops.

## 11. Questions For The Primary Files

| File | Signals or question |
| --- | --- |
| `dma_defs.vh` | header/CQE bytes, channel count, feature macros, register offsets |
| `slvc_dma_wrapper.v` | RX/TX clocks, native-width guard, control-message interface |
| `frame_dma_rx_top.v` | `rx_state`, `wr_state`, events, CQ reservation, AXI arbitration |
| `dma_rx_parser_pipe.v` | `in_ready`, `out_valid`, CRC chunks, soft reset |
| `dma_rx_channel_table.v` | protected CSR, RD pointer, counter event lanes |
| `dma_rx_frame_shared_adapter.v` | context reservation, RDQ, pool boundary |
| `dma_frame_shared_pool.v` | free FIFO, metadata commit, read/release FSM |
| `dma_axi_write_engine_512.v` | 4 KiB split, AW plan queue, source reservation, AW/W/B outstanding |
| `dma_axi_write_engine.v` | frozen default legacy 64-bit word path |
| `dma_tx_engine.v` | descriptor context, CQ check, header/payload handshake |
| `dma_axi_read_prefetch.v` | reserved beats, packing lane, RRESP/flush |
| `dma_cq_single_writer.v` | RX/TX selection, shadow pointer, commit event |
| `dma_async_fifo.v` | binary/Gray conversion, two-flop synchronization, full/empty |
| `dma_udp_ipv4_to_shdr64_adapter.v` | 42-byte strip, 22-byte carry, drop drain, late error |

## 12. Comment-Only Equivalence

The documented comment branch uses `scripts/check_rtl_comment_only.py` to
compare functional RTL with annotated RTL after lexical removal of ordinary
comments and whitespace. Any functional token change fails the check.

```bash
python3 scripts/check_rtl_comment_only.py --base <base-commit> --paths rtl
```

Chinese text is limited to ordinary comments and Markdown. Existing synthesis
attributes and tool-semantic comments remain unchanged.
