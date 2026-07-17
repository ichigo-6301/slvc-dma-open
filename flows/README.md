# Public Flow

The public flow dispatches the native ModelSim, Vivado, and optional
adapter-only Design Compiler source-level entrypoints. It never carries tools,
PDKs, libraries, generated IP, board
projects, implementation databases, or credentials.

`python3 flows/scripts/flowctl.py <command>` is the portable entrypoint and
requires Python 3.6 or newer. GNU Make targets are convenience wrappers. `sim`
requires `vsim` on `PATH`;
`fpga-ooc` requires `vivado` on `PATH` or an explicit `VIVADO` environment
variable and writes only ignored `build/` and
`reports/` outputs. `adapter-dc-ooc` requires `dc_shell` and an untracked
`DMA_DC_TARGET_LIBRARY` pointing to a local standard-cell `.db`. The
`*-dry-run` commands print the exact invocation
without calling a commercial tool.

Linux examples use `python3`. On Windows, use `python` directly or invoke Make
with `PYTHON=python` when that command resolves to Python 3.6 or newer.

The selected simulation runner always validates the ten frozen core tests. When
`CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER=y`, it appends four optional adapter tests;
the default adapter-enabled profile therefore requires fourteen markers. With
the adapter disabled it requires ten. The runner uses tool exit status, native
error summary, and one exact completion marker per test. It has no dependency on
`rg`, `grep`, or another external source-search utility.

`python3 flows/scripts/public_hygiene.py --root .` verifies the tracked public
release checksum manifest and local Markdown links without invoking an EDA
tool. `make public-hygiene` is its Make wrapper and is the same check used by
the public GitHub Actions workflow.
