# Architecture

The data path comprises the shared segment stream, RX parser/channel match,
frame pool, AXI4 write engine, CQ writer, and TX replay. `slvc_dma_wrapper`
is the generic integration top; `frame_dma_wrapper` is the FPGA OOC timing top.

RX parses the fixed 64-byte SHDR64 header, admits the segment by channel
metadata, and writes payload into the target DDR ring. CQ body data is written
before owner/valid becomes visible. TX reads a descriptor payload from DDR and
generates a new SHDR64 segment.

The carrier adapter and MCF endpoint are boundary modules. The former adapts
an optional physical carrier; the latter can aggregate local sources. Neither
changes DMA DDR or CQ ownership semantics.

The optional `dma_udp_ipv4_to_shdr64_adapter` is another upstream boundary. It
accepts a fixed 512-bit Ethernet II / IPv4 / UDP packet profile, constructs the
SHDR64 header, and repacks payload beginning at byte 42. It is not part of
`frame_dma_wrapper`, so the frozen core FPGA OOC result excludes adapter logic.

The default-off RX-wide development profile leaves that front end unchanged.
After a fixed-ingress or shared-pool frame reaches its existing commit point,
`dma_rx_ingress_source_selector` locks one 512-bit drain source and feeds
`dma_axi_write_engine_512`. The new writer uses a dedicated 512-bit AXI4 write
master; the existing 64-bit AXI master continues to carry CQ, TX read, and
legacy RX traffic. This boundary is currently synchronous. See the
[optional 512-bit RX payload backend](rx_payload_512_backend.md) for the future
command/payload/completion CDC insertion points.

```mermaid
flowchart LR
    MAC["MAC packet AXIS<br/>preamble/FCS removed"] --> UDP["Optional UDP/IPv4 adapter<br/>fixed 42-byte parse"]
    UDP --> SHDR["512-bit SHDR64 RX"]
    SHDR --> PARSER["DMA parser + channel match"]
    PARSER --> POOL["Shared frame pool"]
    POOL --> DDR["AXI4 write + CQ owner-last"]
```
