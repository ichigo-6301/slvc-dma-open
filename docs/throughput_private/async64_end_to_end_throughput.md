# Async64 End-to-End Throughput Experiment

## Status

`BLOCKED_PROTOCOL_CONTRACT`. This branch establishes the benchmark harness and
records fail-closed smoke evidence. It does not establish an end-to-end
throughput result, does not supersede the public Same-clock512/Async512
`64 B/cycle` interface claim, and is not ready to bridge to an FPGA result.

## Fixed Identity

- Baseline: `resume-2026-08-r3@c20681fad0eaa6ad55dbb919149765b175b29117`.
- Top: `frame_dma_rx_top`.
- Compile-only benchmark identity: 16 RX contexts, 16 TX contexts, 512-bit
  SHDR64 front end, Async64 64-bit RX memory back end.
- Clocks: `aclk=100 MHz`, `mem_clk=100 MHz`, fixed nonzero phase.
- AXI bounds: 16-beat bursts and four outstanding transactions.
- Seed: 71.
- Descriptor workload: 1024 entries in a 2048-entry TB ring. The extra ring
  capacity preserves the empty-slot distinction while all 1024 descriptors are
  preloaded. CQ capacity is 4096 entries.
- Production RTL, default profile, constraints, and file list are unchanged.

## Harness

The TB-only `axi_hp0_dual_master_64_model` connects the main TX/CQ AXI port and
the independent Async64 RX write port to one byte-addressable memory image.
`HP0_SHARED` permits one 64-bit read or write service beat per cycle with
round-robin arbitration. `IDEAL_SPLIT` permits the independent service classes
to advance together. These are deterministic architectural models, not a
calibrated Zynq HP0 or board DDR model.

The intended loop is:

```text
TX descriptor -> DDR read -> SHDR64 TX -> one-entry elastic loopback
              -> RX admission/buffer -> Async64 -> DDR write -> CQE
```

The formal matrix defines RX-only peak/size sweep, loopback peak/size sweep,
16-flow mixed traffic, HP0 latency/service sensitivity, and three CDC phases.
Every formal point uses 1024 frames. The matrix was not started after the first
mandatory protocol gate failed.

## Primary Blocker

The RX-only and one-frame loopback smoke tests transfer the expected payload,
publish owner-last CQEs, observe four RX outstanding bursts, and report no
frame drop or memory-model protocol error. They nevertheless fail the required
`protocol_error=0` gate.

On command acceptance, the shared-pool source already presents Payload valid:

```text
s_cmd_fire=1
s_payload_tvalid=1
s_payload_tready=0
source_active_q=0
```

`dma_rx_payload_cdc_bridge` defines `source_payload_outside_frame` from valid,
not from a payload handshake. Because `source_active_q` changes after the same
clock edge, the condition sets sticky `source_protocol_error_q`. The top wires
the shared-pool Payload valid directly to this source interface. The benchmark
does not waive or mask this status.

Relevant implementation:

- `rtl/rx/dma_rx_payload_cdc_bridge.v`: `s_cmd_fire`,
  `source_payload_outside_frame`, source protocol-error latch.
- `rtl/integration/frame_dma_rx_top.v`: `pay_cmd_*` and
  `queue_wide_payload_*` connection to the Async bridge.
- `pattern/tb_rtl_dma_async64_end_to_end_throughput.v`:
  `DMA_TP_BRIDGE_CAUSE`, strict error gate, and raw diagnostic counters.

## Secondary Multi-Frame Result

Two-frame loopback smoke did not reach all expected TX/RX CQEs. Shared and
split service modes reached different incomplete terminal states, so the
observation is classified `INCONCLUSIVE_TEST_INFRASTRUCTURE_OR_RTL`; it is not
attributed to either the production TX engine or the new memory model without a
separate root-cause experiment. No 16-flow, sensitivity, or phase-sweep point
is promoted from this state.

## Observed Smoke Boundaries

- Windows ModelSim: RX-only four-frame and loopback one-frame payload/CQE paths
  completed, then failed the strict CDC protocol gate.
- Linux Questa: not run because the configured endpoint was unreachable. This
  is recorded as `NOT_RUN_ENVIRONMENT_UNREACHABLE`, not PASS.
- Formality/LEC: not run and not claimed.
- No synthesis, P&R, CTS, extraction, PrimeTime, or FPGA board test was run.

The Async64 interface ceiling at 100 MHz is `8 B/cycle = 0.8 GB/s`. Derived
rates in `metrics.csv` are diagnostic calculations from blocked smoke counters
and have `claim_eligible=false`. They are not a new throughput claim.

## Reproduction

```text
make dma-async64-throughput-check
```

Raw simulator transcripts stay in ignored build storage. The tracked package
contains only counters, semantic trace hashes, artifact hashes, formulas, and
the explicit blocked decision.

## Next Decision

Do not begin the 1024-frame matrix or SDK/FPGA bridge until the command/Payload
source contract is resolved in a separate RTL change with regression coverage.
The multi-frame loopback smoke must then be rerun and independently closed.
