# DMA ASIC Route A0 Profile Definition

## Classification Rule

Every statement is prefixed with `VERIFIED_REPOSITORY_FACT`, `ANALYSIS`, `ASSUMPTION`, or `TBD_MEASUREMENT`. The complete field set is in [dma_asic_profiles.csv](data/dma_asic_profiles.csv).

## Profile A: `dma_rx512_sameclk_register_sanity`

- **VERIFIED_REPOSITORY_FACT**: `dma_axi_write_engine_512` is an existing same-clock synthesis top and `frame_dma_rx_top` has a same-clock 512-bit RX payload generate branch.
- **ANALYSIS**: Profile A should elaborate the dedicated writer and a minimal behavioral/register storage source. It is useful for source closure, control-area attribution, and tool compatibility only.
- **ANALYSIS**: this profile is not representative physical PPA because it excludes the RX ingress bank, shared frame pool, CQ, and physical SRAM macros.
- **TBD_MEASUREMENT**: macro count is zero by definition; no frequency, area, or timing result is claimed in Route A0.

## Profile B: `dma_rx512_sameclk_sram`

- **VERIFIED_REPOSITORY_FACT**: the same-clock wide branch drains committed 512-bit entries directly from fixed ingress and shared-pool storage into `dma_axi_write_engine_512`.
- **ANALYSIS**: this is the recommended first synthesis and first P&R profile because it retains the native 512-bit RX path while avoiding clock-crossing uncertainty during macro and floorplan bring-up.
- **ASSUMPTION**: a synthesis-only thin top and technology-neutral SRAM wrappers will be required; neither exists in the current source.
- **TBD_MEASUREMENT**: exact macro organization and count remain open until OpenRAM feasibility and generated dimensions are reviewed.

## Profile C: `dma_rx512_async_sram`

- **VERIFIED_REPOSITORY_FACT**: Async512 already crosses command, ordered 577-bit payload entries, completion, reset request/acknowledgement, busy, and protocol-error status between `aclk` and `mem_clk`.
- **ANALYSIS**: this is the recommended canonical ASIC RX profile. It keeps the stream-side admission and frame stores in `aclk`, and places the complete 512-bit AXI writer in `mem_clk`.
- **ANALYSIS**: ordinary single-clock SRAMs can serve source-domain frame stores, but the 577-bit payload FIFO requires either register implementation or a characterized dual-clock 1W1R technology leaf.
- **TBD_MEASUREMENT**: CDC signoff, dual-clock memory binding, macro timing, and routed timing are not complete.

## Profile D: `dma_full_rx512_async_sram`

- **VERIFIED_REPOSITORY_FACT**: `frame_dma_rx_top` contains RX, TX, AXI-Lite, CQ, UFC, descriptor handling, shared write arbitration, and optional RX memory CDC.
- **VERIFIED_REPOSITORY_FACT**: TX reads, CQ writes, descriptor reads, and the legacy shared memory master remain 64 bit. Only RX payload traffic gains the dedicated 512-bit interface.
- **ANALYSIS**: use `full_rx512`, not `full512`, in the profile name. This is the final system-level target after Target A and Target B close.
- **ANALYSIS**: the top-level `tx_axis_aclk` and `tx_axis_aresetn` ports are not consumed internally; TX engine state and TX stream outputs are clocked by `aclk`. The intended TX clock contract must be frozen before full-chip constraints.
- **TBD_MEASUREMENT**: full hierarchy macro mapping, IO timing, CDC/RDC, physical congestion, and post-route STA remain unmeasured.

## Profile Z: `dma_zynq_async64_compat`

- **VERIFIED_REPOSITORY_FACT**: Async64 serializes each committed 512-bit payload entry to eight 64-bit beats after CDC and drives `AWSIZE=3` in `mem_clk`.
- **ANALYSIS**: retain it as a Zynq/FPGA emulation compatibility profile and regression reference. Do not use its PPA or throughput as the native ASIC representative point.
- **VERIFIED_REPOSITORY_FACT**: its registered AW candidate fixes a branch-local FPGA timing cone, but it does not make 64-bit AXI the ASIC architectural default.

## Frozen Selection

| Decision | Selected profile | Classification | Reason |
| --- | --- | --- | --- |
| First actual DC target | `dma_rx512_sameclk_sram` | ANALYSIS | exposes macro binding and 512-bit writer without CDC complexity |
| First actual P&R target | `dma_rx512_sameclk_sram` | ANALYSIS | representative RX storage and bus routing with one clock |
| Canonical RX target | `dma_rx512_async_sram` | ANALYSIS | real stream/memory CDC with native 512-bit RX backend |
| Final resume/system target | `dma_full_rx512_async_sram` | ANALYSIS | full control and data hierarchy while stating the mixed-width memory fabric accurately |
| FPGA emulation | `dma_zynq_async64_compat` | ANALYSIS | isolated 64-bit compatibility point |

**ANALYSIS**: the user's initial preference is accepted with one correction: the final system target is named `full_rx512`, because the repository does not implement 512-bit TX/CQ/descriptor memory ports.
