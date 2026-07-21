# DMA ASIC Route A0 Branch And Baseline Audit

## Classification

- `VERIFIED_REPOSITORY_FACT`: directly observed in Git, RTL, configuration, or fixed-commit evidence.
- `ANALYSIS`: engineering conclusion derived from repository facts.
- `ASSUMPTION`: a proposal that requires confirmation before implementation.
- `TBD_MEASUREMENT`: requires a future tool run or generated memory view.

## Repository State At Audit Start

- **VERIFIED_REPOSITORY_FACT**: private repository `ichigo-6301/dma` was clean on `fix/udp-adapter-evidence-readme-closure` at `be71e1660dc27c49af771132de086a7e3ad48b7f`.
- **VERIFIED_REPOSITORY_FACT**: that private remote contains the RC1, UDP adapter, README preview, and Chinese-comment delivery lines, but it does not contain the later RX 512-bit memory-backend or RX payload CDC branches.
- **VERIFIED_REPOSITORY_FACT**: public repository `ichigo-6301/slvc-dma-open` was clean on `fix/async64-aw-planner-pipeline` at `eed14d7a0dd86ca64177951c0bfc7c3f1829dfa7`.
- **VERIFIED_REPOSITORY_FACT**: `origin/main` remained `6857197c46c11d8709defeb68748bebfbd708a4b`; frozen `v0.1.0-rc1` peeled to `d16f7bbb2e00289383e8325a67d76557504002c0`.
- **VERIFIED_REPOSITORY_FACT**: the analysis branch was created in a separate worktree, so neither existing checkout was switched or cleaned.

The machine-readable candidate list is in [dma_branch_candidates.csv](data/dma_branch_candidates.csv).

## Development Line

| Ref | Relevant content | Evidence boundary |
| --- | --- | --- |
| `origin/main` | Frozen/public 512-bit SHDR core with 64-bit shared AXI memory interface | Release baseline, not native 512-bit ASIC memory backend |
| `7b347f5` | Chinese comments and RTL subsystem directory organization | No functional profile change |
| `4b9f4f5` | Optional same-clock 512-bit RX payload writer and dedicated AXI master | Same-clock RX-only development profile |
| `79a5366` | Optional Async64 and Async512 RX payload CDC profiles | Real command/payload/completion CDC |
| `89fc2e0` | Reset quiesce/drain, CDC constraints, protocol visibility, reroute support | CDC-hardened development baseline |
| `eed14d7` | Registered Async64 AW planning plus regression and evidence binding | Latest complete candidate at audit time |

All rows above are **VERIFIED_REPOSITORY_FACT**. The commit chain from `main` to `eed14d7` is linear; the named remote branches mark intermediate points on that chain.

## Baseline Decision

**ANALYSIS**: use `eed14d7a0dd86ca64177951c0bfc7c3f1829dfa7` as the Route A0 analysis baseline. It is the only audited head that contains all of the following at once:

1. the same-clock dedicated 512-bit RX payload writer;
2. the Async512 command/payload/completion bridge with the complete AXI writer in `mem_clk`;
3. the Async64 Zynq-compatible serializer/writer path;
4. bounded soft-reset quiesce/drain and observable CDC protocol errors;
5. the registered Async64 AW candidate stage and its branch-local regression evidence.

**VERIFIED_REPOSITORY_FACT**: the native shared-link stream remains 512 bit. The new 512-bit interface is a dedicated RX payload AXI write master. The existing full-core shared AXI interface used by TX, CQ, and the legacy RX path remains 64 bit.

**ANALYSIS**: therefore the repository does not yet contain a uniformly 512-bit full-DMA memory fabric. Route A0 may call the preferred architecture `RX512`, but must not call the complete design `full512` without this qualifier.

**VERIFIED_REPOSITORY_FACT**: `frame_dma_rx_top` with an asynchronous RX-memory profile implements real `aclk <-> mem_clk` CDC through one command FIFO, one 577-bit payload FIFO, one completion FIFO, and reset/status synchronizers. The same-clock wide profile has no generated RX payload CDC.

**VERIFIED_REPOSITORY_FACT**: Async64 is selected only by `DMA_RX_MEM_ASYNC64_PROFILE`; it serializes committed 512-bit payload entries to 64-bit AXI data in `mem_clk`. It is a compatibility profile, not the preferred ASIC PPA point.

**VERIFIED_REPOSITORY_FACT**: no newer unmerged remote branch was found beyond `fix/async64-aw-planner-pipeline` during the fetch-and-ref audit.

## Canonical Repository Blocker

**ANALYSIS**: the latest functional architecture currently exists in the public repository while the private source/delivery repository stops earlier. Before an implementation release is started, maintainers must freeze which repository owns the canonical source and reproduce the selected commit in that control plane.

**ASSUMPTION**: if the public development line is accepted as canonical for the next engineering cycle, create the implementation branch directly from `eed14d7`. If private-source ownership remains mandatory, first create a dedicated private synchronization branch, import the exact functional tree, and prove source/hash/regression closure before any ASIC flow work.

## Recommended Next Branch Point

- **ANALYSIS**: analysis branch: `docs/dma-asic-route-a0-analysis` from `eed14d7`.
- **ASSUMPTION**: next implementation branch after blocker review: `feat/dma-rx512-sram-route-a1` from the approved canonical equivalent of `eed14d7`.
- **ANALYSIS**: do not branch ASIC work from `origin/main`, Async64 alone, or the private UDP adapter line; each omits required 512-bit/CDC development work.

