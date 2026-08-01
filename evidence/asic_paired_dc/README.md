# ASIC Paired-DC Evidence

This directory contains sanitized, machine-readable summaries for three
fixed-commit Design Compiler comparisons. `points.csv` is the sole numeric
source. `comparisons.csv` is regenerated from it with decimal arithmetic by
the public validator; numeric values in prose or YAML are never authoritative.

Only report names, SHA-256 digests, fixed source commits, and source-file
digests are published. Raw commercial logs, reports, netlists, DDC, SDC,
libraries, host details, local paths, and license configuration are excluded.

The three claim scopes are deliberately separate:

- writer component OOC evidence cannot be extrapolated to C2B4 or the DMA;
- the C2B4 comparison is a negative promotion result because W0 already
  closes and W1 increases writer hierarchy area;
- the Shared Pool result is a register-expanded component comparison with a
  small timing-margin change and disclosed register/area cost.

The C2B4 full-common lint result remains `BLOCKED_COMMON_SCOPE` with 15 errors
and zero waivers. Only the bounded Writer lint scope has zero fatal and zero
error. None of these records is an Fmax, P&R, extracted timing, power, SRAM,
MMMC/OCV, foundry, silicon, or signoff claim.
