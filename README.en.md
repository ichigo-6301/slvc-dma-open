# SLVC DMA

[中文](README.md)

SLVC DMA is a 512-bit virtual-channel DMA IP for a shared high-speed link.
Upstream sources are multiplexed into an SHDR64-framed segment stream; the DMA
routes payloads to DDR rings by channel metadata and publishes completions
through a completion queue.

## Current Public Release

`v0.1.0-rc1` releases `slvc_dma_wrapper`, `frame_dma_wrapper`, the optional
carrier adapter, and the MCF companion. It freezes the 512-bit
Aurora-compatible profile. It does not claim a generic 128-bit implementation,
board-level lossless 10G operation, or ASIC signoff.

## Verified Scope

- Ten selected ModelSim directed regressions;
- Vivado 2018.3 OOC implementation on `xc7z100ffg900-2` at 5.000 ns with
  no setup or hold violation across three strategies, minimum WNS `+0.162 ns`;
- RX dispatch, TX replay, AXI-Lite control, DDR rings, CQ owner-last
  publication, and the 512-bit payload writer.

See [results](docs/en/results.md), [verification](docs/en/verification.md),
and [limitations](docs/en/limitations.md) for measurements and caveats.
