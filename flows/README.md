# Public Flow

The public flow dispatches the native ModelSim and Vivado source-level
entrypoints. It never carries tools, PDKs, libraries, generated IP, board
projects, implementation databases, or credentials.

`python flows/scripts/flowctl.py <command>` is the portable entrypoint.
GNU Make targets are convenience wrappers. `sim` requires `vsim` on `PATH`;
`fpga-ooc` requires `vivado` on `PATH` or an explicit `VIVADO` environment
variable and writes only ignored `build/` and
`reports/` outputs. The `*-dry-run` commands print the exact invocation
without calling a commercial tool.
