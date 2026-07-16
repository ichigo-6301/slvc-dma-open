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
