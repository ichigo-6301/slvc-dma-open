# Integration Guide

`slvc_dma_wrapper` is the public integration top for the fixed
`slvc_dma_v1_512` profile. `frame_dma_wrapper` exposes the same functional
interfaces and is the FPGA OOC timing top. The public wrapper rejects widths
other than 512 bits.

## Interface Groups

| Group | Public wrapper signals | Contract |
| --- | --- | --- |
| Shared-link RX | `sl_rx_*` | 512-bit SHDR64-framed segment stream into the DMA. Packet length and framing are carried by the segment protocol rather than AXIS `TLAST`. |
| Shared-link TX | `sl_tx_*` | 512-bit replay stream emitted from configured TX descriptors. |
| Control | `s_axil_*` | 32-bit AXI4-Lite channel, descriptor, ring, CQ, status, and IRQ configuration. |
| Memory | `m_axi_*` | 32-bit-address, 64-bit AXI4 master for RX payload writes and TX payload reads. |
| Control messages | `ctrl_msg_{tx,rx}_*` | Optional valid/ready flow-control message boundary. |
| Interrupt | `irq` | Completion/status notification; software still reads and acknowledges state through AXI4-Lite. |

`sl_rx_aclk` and `sl_rx_aresetn` clock the RX, AXI4-Lite, and AXI memory-side
logic. `sl_tx_aclk` and `sl_tx_aresetn` clock the TX shared-link boundary.
Carrier-clock crossing belongs in `slvc_carrier_cdc_adapter`, not in an
unconstrained wrapper connection.

## Optional Same-Clock Wide RX Memory Boundary

`configs/slvc_dma_512_rx_wide_defconfig` selects a development profile whose
OOC top is `frame_dma_rx_top`. Under `DMA_RX_WIDE_PAYLOAD_PROFILE`, that top
adds `m_axi_rx_payload_*`: a write-only AXI4 master with 32-bit addresses,
512-bit WDATA, and 64-bit WSTRB. RX destination addresses must be 64-byte
aligned. The frozen `slvc_dma_wrapper` interface and default 64-bit AXI master
remain unchanged.

This profile is same-clock: the RX ingress stores, source selector, writer, and
external memory slave all use `aclk`. Do not connect it to an asynchronous
memory clock without command, 512-bit payload, and completion CDC FIFOs. See
the [wide-backend profile guide](rx_payload_512_backend.md).

## Optional Dual-Clock RX Memory Boundary

`configs/slvc_dma_512_rx_async64_defconfig` and
`configs/slvc_dma_512_rx_async512_defconfig` add `mem_clk`, `mem_aresetn`, and a
dedicated RX write master to the development top. The 64-bit profile exposes
64-bit WDATA/8-bit WSTRB; the 512-bit profile exposes 512-bit WDATA/64-bit
WSTRB. AXI AW/W/B are generated and consumed only in `mem_clk`.

The integrator must assert `aresetn` and `mem_aresetn` together. Each domain
synchronizes deassertion locally. A soft reset received during an active RX
memory operation is deferred until the frame completion returns and the source
is released. Do not reset one side independently or use this boundary for TX,
CQ, descriptor, or AXI4-Lite clock crossing. See the
[dual-clock backend guide](rx_payload_cdc_backends.md).

## Optional Ethernet Packet Boundary

Place `dma_udp_ipv4_to_shdr64_adapter` before `sl_rx_*` only when the upstream
interface supplies 512-bit Ethernet II packet AXI4-Stream with `TKEEP` and
`TLAST`. The MAC must remove preamble, SFD, and FCS. The adapter and DMA RX must
share a clock/reset domain unless an explicit CDC boundary is inserted. Its
output has no `TKEEP` or `TLAST`; SHDR64 `payload_len` carries the segment
boundary expected by `slvc_dma_wrapper`.

The UDP destination port becomes `SHDR64.flow_id`. Configure the existing DMA
channel table for that flow ID before admitting packets. Treat `stat_drop` as
diagnostic status; P0 does not provide packet rollback after late errors.

## Minimum Bring-Up Sequence

1. Hold both wrapper resets active, then release the RX/control domain before
   programming the device.
2. Use AXI4-Lite to configure the selected channel, RX/TX ring state,
   descriptors, and completion queue ownership/consumer state.
3. Enable the configured path and present valid SHDR64-framed RX traffic or TX
   descriptors.
4. Consume completion entries only after owner/valid becomes visible; the CQ
   body is written before this ownership publication.
5. Acknowledge status and advance software-owned ring/CQ state through
   AXI4-Lite before reusing the associated buffer or completion entry.

This guide is not a board-design recipe. MAC/PHY integration, generated FPGA
IP, software drivers, and 10G lossless behavior are outside the public release.
The RTL port lists remain authoritative.
