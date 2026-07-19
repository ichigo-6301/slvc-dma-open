# Optional Dual-Clock RX Payload Backends

These development profiles move only committed RX payload traffic to a
separate memory clock domain. SHDR64 parsing, channel match, admission, frame
storage, completion queue publication, TX, descriptors, and the frozen public
wrappers retain their existing clocking and software-visible behavior.

## Profile Matrix

| Profile | RX memory clock | RX AXI WDATA | CDC path | Defconfig |
| --- | --- | ---: | --- | --- |
| Frozen/default | `aclk` | 64 bit | none | `slvc_dma_512_defconfig` |
| Same-clock wide | `aclk` | 512 bit | generate bypass | `slvc_dma_512_rx_wide_defconfig` |
| Async64 | `mem_clk` | 64 bit | command + 512-bit payload + completion | `slvc_dma_512_rx_async64_defconfig` |
| Async512 | `mem_clk` | 512 bit | command + 512-bit payload + completion | `slvc_dma_512_rx_async512_defconfig` |

Only the two discrete memory widths above are implemented. This is not an
arbitrary 64/128/256/512-bit parameterization.

## Datapath And Ownership

```mermaid
flowchart LR
    SRC["Committed fixed-ingress or shared-pool frame"] --> LOCK["Frame-locked source selector"]
    LOCK --> CMD["Command FIFO<br/>address, length, channel, tag"]
    LOCK --> PAY["32-entry payload FIFO<br/>512 data + keep + last"]
    CMD --> MEM["Memory clock domain"]
    PAY --> MEM
    MEM --> S64["512-to-64 serializer"]
    MEM --> W512["512-bit writer"]
    S64 --> W64["64-bit writer"]
    W64 --> AXI["Dedicated RX AXI4 write master"]
    W512 --> AXI
    AXI --> CPL["Completion FIFO<br/>tag + status"]
    CPL --> REL["WR_PTR, CQ, and frame release in aclk"]
```

AXI AW, W, and B never cross the clock boundary independently. The complete
writer is in `mem_clk`; only a frame command, ordered 512-bit payload beats,
and one completion cross. The source remains locked until the matching tagged
completion returns, so a frame is not released before all B responses have
completed.

The bridge uses an 8-bit transaction tag and accepts one frame at a time. A
completion-tag mismatch becomes error code 7 and latches a protocol error.
Command and completion use four-entry Gray-pointer FIFOs. Payload uses a
32-entry, 577-bit FIFO containing `TDATA`, `TKEEP`, and `TLAST`.

## Memory-Domain Writers

Async64 performs `512 -> 64` serialization after CDC. It emits `AWSIZE=3`, up
to 16 beats per burst, splits at 4 KiB boundaries, supports four ordered
outstanding responses, and sustains one 64-bit W beat per `mem_clk` when the
memory model is ready.

Async512 reuses `dma_axi_write_engine_512` in `mem_clk`. It emits `AWSIZE=6`,
uses 64-byte-aligned destinations, and preserves the same burst, response, and
completion rules. It may issue AW before a complete payload burst has reached
the read side; W remains valid/ready backpressured. This removes a long
occupancy/4-KiB planning cone without weakening AXI or completion ordering.

## Reset Contract

Hard reset is asynchronously asserted and synchronously deasserted in each
domain. The current profiles require `aresetn` and `mem_aresetn` to be asserted
together; arbitrary one-sided hard-reset recovery is unsupported and checked
in simulation.

Soft reset is quiesce-and-drain at the integrated top. A request received while
an asynchronous payload transaction is active is remembered, new core work is
not reset destructively, and reset is applied only after payload transfer,
all AXI B responses, the tagged completion, and source-side release finish.
The resulting idle reset event is then synchronized into `mem_clk`. The bridge
asserts if a soft reset reaches either side while its transaction state is busy.

## Technology Binding

`dma_async_fifo_tech` is the common boundary. Vivado OOC selects XPM for the
32-entry payload FIFO, allowing block-RAM mapping; the four-entry command and
completion FIFOs use the verified generic Gray-pointer implementation because
Vivado 2018.3 XPM requires a deeper FIFO. Simulation and the ASIC OOC profile
use generic RTL arrays.

The aggregate modeled storage is 18,948 bits. Design Compiler includes those
generic arrays as standard-cell storage, so its area is not comparable to a
macro-backed ASIC implementation or to the writer-only same-clock result.

## Verification And Measured Results

Each asynchronous profile schedules ten frozen-core tests plus three backend
tests. The common bridge test covers 450 frames, six clock profiles, clock
stops, FIFO full/empty pressure, tag accounting, and 924,873 bytes. Each
backend test covers 2,000 random frames plus directed lengths, 4 KiB splits,
AW/W/B backpressure, response errors, reset/restart, and byte-accurate memory
comparison. The integration test covers 18 directed lengths, 256 mixed source
frames, and active soft-reset drain.

The ideal 1 MiB runs measured:

| Profile | AXI bytes/cycle | W utilization | Peak outstanding | Interface rate at 200 MHz |
| --- | ---: | ---: | ---: | ---: |
| Async64 | 8 | 100% | 4 | 1.6 GB/s |
| Async512 | 64 | 100% | 4 | 12.8 GB/s |

These are RTL/model interface rates, not board DDR measurements.

Vivado 2018.3 routed `frame_dma_rx_top` on `xc7z100ffg900-2` with 5.000 ns
`aclk` and `mem_clk`:

| Profile | WNS | TNS | WHS | THS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Same-clock 512 | +0.029 ns | 0 | +0.052 ns | 0 | 38,595 | 42,492 | 44 | 3 | 0 |
| Async64 | +0.028 ns | 0 | +0.069 ns | 0 | 39,471 | 43,586 | 52 | 4 | 0 |
| Async512 | +0.076 ns | 0 | +0.051 ns | 0 | 39,155 | 43,306 | 52 | 4 | 0 |

The same-clock netlist audit found zero RX payload CDC cells. Both asynchronous
profiles have no unconstrained internal endpoint or Critical CDC entry, and all
reported Gray-pointer bus-skew constraints are met. Vivado still reports
structural CDC warnings for recognized Gray buses and clock-enabled FIFO data;
these are documented structures, not a blanket CDC signoff waiver.

Design Compiler OOC at 5.000 ns closed both asynchronous profiles:

| Profile | Source WNS | Memory WNS | Hold WNS | Cell area | Registers | FIFO model |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Async64 | +2.933 ns | +1.686 ns | +0.039 ns | 171,658.05 | 20,554 | generic arrays included |
| Async512 | +2.963 ns | +1.393 ns | +0.039 ns | 170,311.29 | 20,457 | generic arrays included |

This is frontend OOC synthesis, not physical implementation, extracted STA,
SRAM-macro characterization, or ASIC signoff.

## Explicit Limits

- TX, CQ, descriptor, and AXI4-Lite traffic remain in the original domains.
- Frames complete in order; multiple-frame out-of-order completion is absent.
- Async512 addresses must be 64-byte aligned; Async64 addresses must be
  8-byte aligned.
- One-sided hard-reset recovery, arbitrary memory widths, unaligned first-beat
  shifting, multi-port striping, and board DDR throughput are not claimed.
