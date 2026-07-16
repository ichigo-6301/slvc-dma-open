# Fresh-Clone Validation

Validate a fixed public commit, not a private development worktree.

1. Clone the public HTTPS URL into a new directory and record `git rev-parse HEAD`.
2. Confirm Python 3.6 or newer is available as `python3`.
3. Run `python3 flows/scripts/public_hygiene.py --root .` and require checksum and local-link success.
4. Run `python3 flows/scripts/flowctl.py defconfig --source configs/slvc_dma_512_defconfig`.
5. Run `python3 flows/scripts/flowctl.py show-config`, `sim-dry-run`, and `fpga-ooc-dry-run`.
6. With ModelSim/Questa available, run `python3 flows/scripts/flowctl.py sim` and require all ten PASS markers.
7. With Vivado 2018.3 available, run one bounded `Explore` OOC implementation using `fpga-ooc`.
8. Confirm `git status --short` is empty after ignored build and simulator outputs are produced.

The public claims are limited to the provenance-bound evidence. A fresh-clone
smoke proves source closure, not a new board or ASIC result.
