# SLVC DMA

[![Public Integrity](https://github.com/ichigo-6301/slvc-dma-open/actions/workflows/public-integrity.yml/badge.svg?branch=main)](https://github.com/ichigo-6301/slvc-dma-open/actions/workflows/public-integrity.yml)

[中文](README.md)

SLVC DMA is a 512-bit virtual-channel DMA IP for a shared high-speed link.
Multiple upstream sources can be multiplexed into an SHDR64-framed segment
stream; the DMA moves payloads between the shared link and DDR rings according
to channel metadata, then publishes completion events to software through a
completion queue.

## Current Public Release

`v0.1.0-rc1` releases `slvc_dma_wrapper`, `frame_dma_wrapper`, the optional
carrier adapter, and the MCF companion. It freezes the 512-bit
Aurora-compatible profile together with its ModelSim/Questa regression and
Vivado 2018.3 OOC implementation entrypoint.

`v0.1.0-rc1` is a frozen tag. `main` may contain documentation, delivery, and
public-integrity updates that do not change the frozen tag target. See
[Release Notes](docs/en/release_notes.md).

## Stage Status

| Stage | Status | Public boundary |
| --- | --- | --- |
| Directed RTL regression | [verified](docs/en/verification_matrix.md) | Windows ModelSim and IC_EDA Questa completed the ten release-bound tests. |
| FPGA OOC implementation | [verified](docs/en/results.md) | Three Vivado 2018.3 strategies met 200 MHz OOC setup and hold. |
| Carrier CDC | [partial](docs/en/delivery_status.md) | Directed behavior is verified; complete CDC/RDC signoff is absent. |
| ASIC frontend | [planned](docs/en/delivery_status.md) | Requires a separate library-bound profile and evidence. |
| Physical implementation | [blocked](docs/en/delivery_status.md) | Awaiting validated standard-cell and SRAM macro physical views. |
| Board validation | [not claimed](docs/en/delivery_status.md) | The exact public release commit has no board-level claim. |
| Lossless 10G operation | [not claimed](docs/en/delivery_status.md) | This release is not a board-level 10G production validation. |

## Features

- 512-bit shared-link AXI-Stream RX/TX data paths with 64-byte SHDR64 framing;
- RX header parsing, channel match/admission, shared frame pool, and DDR ring writes;
- Descriptor-driven TX payload reads, prefetch, SHDR64 rebuild, and shared-link replay;
- AXI4-Lite control for channels, descriptors, ring pointers, CQ, status, and IRQ;
- CQ body-first and owner/valid-last publication to prevent partial software reads;
- AXI/AXI-Stream backpressure, payload-writer prefetch, and local soft-reset control;
- Optional carrier CDC adapter and MCF companion endpoint for multi-source aggregation.

## Architecture

```mermaid
flowchart LR
    RX["Shared-link RX AXIS"] --> PARSE["SHDR64 parser<br/>channel match"]
    PARSE --> POOL["Shared frame pool"]
    POOL --> WR["AXI4 write engine"]
    WR --> RXDDR["DDR RX rings"]
    WR --> CQ["Completion queue<br/>owner-last publish"]
    CQ --> SW["Software / IRQ"]

    DESC["TX descriptors"] --> RD["AXI4 read + prefetch"]
    TXDDR["DDR TX buffers"] --> RD
    RD --> REPLAY["SHDR64 builder<br/>TX replay"]
    REPLAY --> TX["Shared-link TX AXIS"]

    CSR["AXI4-Lite control"] --> PARSE
    CSR --> DESC
    CSR --> CQ
```

`slvc_dma_wrapper` is the public system-integration top. `frame_dma_wrapper`
is the complete FPGA OOC timing top. The carrier adapter and MCF endpoint sit
at the DMA boundary and do not change DDR/CQ ownership semantics.

## Release Profile

| Item | `slvc_dma_v1_512` |
| --- | --- |
| Shared-link data width | 512 bit |
| Keep width | 64 bit |
| SHDR64 size | 64 byte |
| Maximum payload | 4096 byte |
| FPGA timing target | 200 MHz / 5.000 ns |
| FPGA device | `xc7z100ffg900-2` |
| OOC top | `frame_dma_wrapper` |

See [Interfaces](docs/en/interfaces.md) for control registers, descriptors,
CQEs, and ownership rules. The public RTL port lists are the authoritative
interface definitions.

## Verified Results

| Vivado 2018.3 strategy | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Explore | +0.226 ns | +0.045 ns | 38,074 | 40,787 | 44 | 3 | 0 |
| Performance_Explore | +0.173 ns | +0.046 ns | 38,087 | 40,787 | 44 | 3 | 0 |
| ExtraNetDelay_high | +0.162 ns | +0.054 ns | 38,088 | 40,785 | 44 | 3 | 0 |

All three routed OOC runs have zero TNS and THS. The selected ten-test
directed regression passed with Windows ModelSim SE-64 2020.4 and IC_EDA Linux
Questa Sim-64 10.7c. The writer-prefetch smoke observed 48 contiguous 512-bit
AXI W beats in its specified long multi-burst case; this is not an end-to-end
lossless 10G throughput claim.

See [Results](docs/en/results.md), [Verification](docs/en/verification.md), and
[`provenance/`](provenance/) for conditions, source commits, checksums, and
caveats.

## Quick Start

### 1. Configuration And Public Integrity

```text
python3 flows/scripts/flowctl.py defconfig --source configs/slvc_dma_512_defconfig
python3 flows/scripts/flowctl.py show-config
python3 flows/scripts/public_hygiene.py --root .
```

### 2. Simulator Regression

```text
python3 flows/scripts/flowctl.py sim-dry-run
python3 flows/scripts/flowctl.py sim
```

### 3. Vivado OOC Entrypoint

```text
python3 flows/scripts/flowctl.py fpga-ooc-dry-run
```

The public runner requires Python 3.6 or newer. `sim` requires ModelSim or
Questa; `fpga-ooc` requires Vivado 2018.3. GNU Make targets are convenience
wrappers. On Windows, replace `python3` with `python` when that command resolves
to Python 3.6 or newer. Keep tool paths and environment overrides under ignored
`flows/local/`. See the [Flow README](flows/README.md) for the complete command
set.

## Top Levels And Repository Layout

| Path | Contents |
| --- | --- |
| `rtl/` | DMA, carrier-adapter, and MCF-companion RTL |
| `rtl/slvc_dma_wrapper.v` | System-integration top |
| `rtl/frame_dma_wrapper.v` | 200 MHz OOC timing top |
| `pattern/`, `modelsim/` | Public directed testbenches and run scripts |
| `fpga/xilinx/` | Vivado 2018.3 OOC Tcl entrypoint |
| `flows/`, `configs/` | Portable runner, manifest, and defconfig |
| `evidence/`, `provenance/` | Fixed-commit verification, PPA, and SHA-256 evidence |

## Documentation

- [Architecture](docs/en/architecture.md)
- [Interfaces](docs/en/interfaces.md)
- [Integration Guide](docs/en/integration.md)
- [Module Catalog](docs/en/module_catalog.md)
- [Verification](docs/en/verification.md)
- [Verification Matrix](docs/en/verification_matrix.md)
- [Verified Results](docs/en/results.md)
- [FPGA Implementation](docs/en/fpga_implementation.md)
- [Delivery Status](docs/en/delivery_status.md)
- [Release Notes](docs/en/release_notes.md)
- [Limitations](docs/en/limitations.md)
- [Roadmap](docs/en/roadmap.md)
- [Public Scope](PUBLIC_SCOPE.md)
- [Fresh-Clone Validation](FRESH_CLONE_VALIDATION.md)
- [Contributing](CONTRIBUTING.md), [Support Boundary](SUPPORT.md), and [Security](SECURITY.md)

## Current Limitations

- Only the 512-bit profile is frozen; the generic 128-bit profile is not implemented;
- The 200 MHz numbers are OOC results, not board implementation or lossless 10G claims;
- Directed regression does not constitute coverage, formal, or CDC/RDC signoff;
- The public release excludes the P0/U5 board design, generated Xilinx IP, SDK
  application, ASIC SRAM/library, DFT, P&R, and signoff STA.

See [Limitations](docs/en/limitations.md) and [Public Scope](PUBLIC_SCOPE.md) for
the complete release boundary.
