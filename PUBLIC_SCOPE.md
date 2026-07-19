# Public Scope

This repository releases the 512-bit Shared-Link Virtual-Channel DMA RTL,
selected ModelSim directed tests, and a Vivado 2018.3 OOC flow for
`xc7z100ffg900-2`.

The adapter P0 delivery adds an optional, fixed-profile 512-bit Ethernet II /
IPv4 / UDP receive adapter, four public directed tests, and a portable
adapter-only Design Compiler OOC entrypoint. It does not alter the frozen DMA
core or the `v0.1.0-rc1` tag.

The RX memory development branch adds optional same-clock 512, async64, and
async512 backends, their public tests, and profile-specific Vivado/DC OOC
entrypoints. These profiles do not change the frozen wrappers or tag and do not
claim arbitrary memory widths, one-sided reset recovery, board DDR throughput,
or ASIC physical signoff.

It excludes Unified Lite/P0 pilot RTL, board designs, generated Xilinx IP,
SDK applications, historical experiment reports, technology libraries, PDK
payloads, credentials, and private development history. The optional MCF
endpoint is supplied as an upstream shared-link companion; it is not part of
the `frame_dma_wrapper` 200 MHz OOC timing claim. The UDP adapter is likewise
outside that FPGA claim, and no standard-cell library or generated ASIC output
is distributed.
