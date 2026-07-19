# Fresh-Clone Validation

Validate a fixed public commit, not a private development worktree.

1. Clone the public HTTPS URL into a new directory and record `git rev-parse HEAD`.
2. Confirm Python 3.6 or newer is available as `python3`.
3. Run `python3 flows/scripts/public_hygiene.py --root .` and require checksum and local-link success.
4. Run `python3 flows/scripts/flowctl.py defconfig --source configs/slvc_dma_512_defconfig`.
5. Run `python3 flows/scripts/flowctl.py show-config`, `sim-dry-run`, and `fpga-ooc-dry-run`.
6. With ModelSim/Questa available, run `python3 flows/scripts/flowctl.py sim`. Always require ten frozen-core PASS markers; when the selected config enables `CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER=y`, also require four adapter markers, fourteen total.
7. Optionally run `python3 flows/scripts/flowctl.py defconfig --source configs/slvc_dma_512_core_only_defconfig`, `show-config`, and `sim-dry-run` to verify the adapter-disabled ten-marker schedule.
8. On the RX-wide development branch, optionally select `configs/slvc_dma_512_rx_wide_defconfig`; require ten core plus two wide-backend markers, twelve total, and verify that `fpga-ooc-dry-run` selects `synth_rx_payload_512_ooc_2018_3.tcl`.
9. With Vivado 2018.3 available, run one bounded `Explore` OOC implementation using `fpga-ooc`.
10. Confirm `git status --short` is empty after ignored build and simulator outputs are produced.

The public claims are limited to the provenance-bound evidence. A fresh-clone
smoke proves source closure, not a new board or ASIC result.
