# Interfaces

`slvc_dma_wrapper` exposes RX/TX shared-link AXI-Stream, AXI4-Lite control,
an AXI4 memory master, a control-message interface, and IRQ. The release
profile is fixed as follows:

| Item | Value |
| --- | --- |
| Shared-link data width | 512 bit |
| Keep width | 64 bit |
| SHDR64 size | 64 byte |
| Maximum payload | 4096 byte |
| Timing top | `frame_dma_wrapper` |

AXI4-Lite manages channels, descriptors, ring pointers, CQ, and status. The
memory master performs RX payload writes and TX payload reads. RTL ports are
the authoritative interface definition; this version does not promise a
parameterized 128-bit profile.
