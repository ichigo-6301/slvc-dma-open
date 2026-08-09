# Branch-Only C2B4 Storage Clock-Gating Evidence

This directory is a sanitized, machine-readable record of a bounded automatic
clock-gating experiment. Its classification is `POSITIVE_MAPPED_DC /
BRANCH_ONLY`: it passed the experiment's predefined mapped-DC promotion gates,
but it is not a verified `main` claim, release result, or production-profile
change. A merge into `main` is not recommended.

The scope is the two-channel C2B4 RX512 register-expanded subsystem. S0 uses
ordinary `compile_ultra`; S1 uses `compile_ultra -gate_clock`. Both use the same
production RTL closure, top, profile, shared source set, library, 500 MHz
constraint, and deterministic workload contract. Variant-specific prepared
manifests and mapped activity are separately hashed because the flow-only test
wrapper and mapped implementations differ.

`points.csv` is the sole numeric authority. `comparisons.csv` is generated from
it with `Decimal` arithmetic and must match byte for byte. The remaining CSVs
bind the four-category clock-gating census, hierarchy power, mapped-GLS trace
and annotation evidence, and logical commercial-artifact identities. No raw
commercial artifact is distributed.

The result includes 837 `CLKGATETST_X1` cells and 102,976 gated bits. At the
common 500 MHz mapped point, bursty dynamic changes by `-87.909999%`, saturated
dynamic by `-87.295325%`, and total mapped area by `-20.823993%`. These values
apply only to this exact register-expanded mapped-DC scope.

This package contains no raw logs or reports, netlists, DDC, SDC, VCD, SAIF,
library payload, host, account, license, or local-path data. It provides no
complete-DMA, SRAM, Fmax, P&R, CTS clock-tree, post-route power,
LEC/Formality, foundry, signoff, or silicon conclusion.

Run from the repository root:

```text
make power-research-check
```
