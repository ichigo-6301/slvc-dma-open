# Optional UDP/IPv4 RX Adapter

`dma_udp_ipv4_to_shdr64_adapter` is an optional compatibility layer in front
of the frozen 512-bit SLVC DMA RX input. It converts one Ethernet II, IPv4, UDP
packet into one SHDR64 segment. It does not alter the DMA core, channel table,
register map, descriptor format, or CQE ABI.

```text
512-bit packet AXI4-Stream
  -> dma_udp_ipv4_to_shdr64_adapter
  -> 512-bit SHDR64 stream
  -> slvc_dma_wrapper
```

The upstream MAC must remove preamble, SFD, and FCS and present a complete
packet in one clock/reset domain. The P0 profile accepts EtherType IPv4,
version 4, IHL 5, UDP protocol 17, no fragmentation, and payloads up to 4096
bytes. VLAN, IPv6, IPv4 options, fragment reassembly, UDP checksum validation,
and Ethernet FCS handling are outside the module.

The mapping is direct: `SHDR64.flow_id = UDP destination port`. The existing
DMA channel table remains responsible for flow-to-channel and DDR-context
selection.

## Datapath

UDP payload starts at byte 42. The adapter uses a fixed 22-byte carry and
42-byte merge rather than a generic barrel shifter. It computes the SHDR64
header CRC in six 8-byte chunks, then transfers one 64-byte SHDR64 header beat.
After startup, large payloads sustain one 512-bit output beat per cycle when
both interfaces remain ready. The output register remains stable under
backpressure.

At 200 MHz with no stalls, a zero-byte UDP payload has an 8-cycle packet
interval (25 Mpacket/s upper bound), while a 64-byte payload has a 10-cycle
interval (20 Mpacket/s upper bound). These are local adapter limits before MAC
overhead and downstream stalls, not network packet-rate guarantees.

Errors visible in the first beat suppress all output and produce one drop
pulse. Errors detected after SHDR or payload publication are reported but P0
does not roll back accepted output. Local soft reset abandons a partial packet;
the upstream boundary must restart at a packet boundary.

## Evidence Boundary

Four adapter tests passed on ModelSim SE-64 2020.4 and Questa Sim-64 10.7c:
18 directed/parser cases through 4096 bytes, 400 deterministic-random packets,
a 23-case error/reset/stall matrix with 17 explicit invalid-packet drops and 23
successful accepts, and a
two-channel adapter-to-DMA smoke.

Adapter-only Design Compiler OOC at 5.000 ns reported +0.39 ns WNS, 0 TNS,
3746 leaf cells, 909 registers, zero latches, and 11744.32 library area units.
The worst path is the 8-byte CRC chunk select/XOR cone. This is frontend
synthesis of the adapter alone, not full-DMA area, physical design, extracted
STA, power signoff, board-level 10G, or lossless UDP evidence.

The tracked OOC scripts require an untracked `DMA_DC_TARGET_LIBRARY` value.
No standard-cell library, mapped design, generated report, or private path is
distributed.
