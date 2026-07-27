# Fresh-Clone Validation

Validate a fixed public commit, not a private development worktree.

1. Clone the public HTTPS URL into a new directory and record `git rev-parse HEAD`.
2. Confirm Python 3.6 or newer is available as `python3`.
3. Run `python3 flows/scripts/public_hygiene.py --root .` and require checksum and local-link success.
4. Run `python3 -m unittest flows.scripts.test_n45_showcase`; require 51 tests, including exactly 48 C2 flow-contract tests.
5. Run `python3 flows/scripts/flowctl.py defconfig --source configs/slvc_dma_512_defconfig`.
6. Run `python3 flows/scripts/flowctl.py show-config`, `sim-dry-run`, and `fpga-ooc-dry-run`.
7. Run every new showcase dry-run: `n45-c2-reg-sim-dry-run`, `n45-c2-reg-dc-dry-run`, `n45-c2-reg-pnr-dry-run`, `n45-c2-reg-sta-dry-run`, `vivado-async64-2022.2-ooc-dry-run`, `n45-a5-model-audit-dry-run`, and `n45-a5-clock-delivery-audit-dry-run`; also require `n45-c2-reg-audit` to report `payload_keep_bits=102400 arrays=13 macros=0`.
8. With ModelSim/Questa available, run `python3 flows/scripts/flowctl.py sim`. Always require ten frozen-core PASS markers; when the selected config enables `CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER=y`, also require four adapter markers, fourteen total.
9. Run `configs/slvc_dma_512_core_only_defconfig`, `configs/slvc_dma_512_rx_wide_defconfig`, `configs/slvc_dma_512_rx_async64_defconfig`, and `configs/slvc_dma_512_rx_async512_defconfig` in turn. Require the documented 10/12/15/14 marker schedules and matching dry-run scripts.
10. Run `n45-c2-reg-sim` and require the writer, async64/async512, and four C2 focused suites to pass with native zero-error summaries. Confirm channels=2, payload/keep=102400 bits, and no duplicate default/override RAM source.
11. With Vivado 2018.3 available, run the bounded profile-specific OOC implementation using `fpga-ooc`. Vivado 2022.2 is a separate optional measured profile and must not be numerically merged with 2018.3.
12. Repeat the source, dry-run, and simulator gates on Windows ModelSim 2020.4 and Linux IC_EDA_FULL Questa 10.7c from independent clones of the exact candidate commit.
13. Confirm `git status --short` is empty after ignored build and simulator outputs are produced.

Validate the immutable `v0.1.0-rc1` tag from a separate checkout using the
manifest stored in that tag. Require annotated tag object
`ae813bc1dee2c3fe1487010cafdb8d4211968d4d` and peeled commit
`d16f7bbb2e00289383e8325a67d76557504002c0`; never rebuild its checksum manifest
from current `main`.

The public claims are limited to the provenance-bound evidence. A fresh-clone
smoke proves source closure, not a new board or ASIC result.
