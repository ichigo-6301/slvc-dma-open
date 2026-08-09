# ASIC Storage-Bank Clock-Gating Research: Positive Mapped-DC Result

> [!WARNING]
> This is branch-only research evidence classified as `POSITIVE_MAPPED_DC /
> BRANCH_ONLY`. It is not part of `main`, `v0.1.0-rc1`, or a production profile,
> and it is not recommended for merge into `main`.

## 1. Purpose

This experiment asks whether automatic integrated clock gating becomes useful
when it targets the dominant register-expanded payload storage rather than only
the Writer output bank. It reuses existing bank write enables and keeps the RTL
contract fixed. The objective is a bounded, activity-based mapped-DC comparison,
not a released power claim.

## 2. Scope And Identity

The scope is `dma_rx512_memory_subsystem_top`: two channels, 4 KiB fixed payload
per channel, 64 shared 512-bit blocks, 16-beat bursts, four outstanding writes,
and register-expanded storage. S0 and S1 use the same production RTL closure,
top, profile, shared source set, 2.000000 ns constraint, Nangate45 typical
library, deterministic workload contract, and functional trace.

The fixed commits and SHA-256 identities are recorded in the
[manifest](../../evidence/asic_power_clock_gating_storage_positive/manifest.json).
S0/S1 prepared-manifest hashes differ because the flow-only test wrapper is
materialized per variant. That difference does not represent a production RTL
change.

## 3. Why S0/S1 Is Paired

S0 runs ordinary `compile_ultra`; S1 runs `compile_ultra -gate_clock`. The
intended tool difference is automatic ICG insertion. Each mapped implementation
has its own zero-delay GLS activity digest, but both use one seed, workload,
window, interface, and normalized-trace contract. Cross-frequency or
RTL-different power comparisons are not used.

## 4. Activity Workloads

All workloads use seed `71`, with reset, configuration, and 4,096 warm-up cycles
outside the measured window. Raw VCD/SAIF files remain private.

| Workload | Measured window | Contract |
| --- | ---: | --- |
| idle | 4,096 cycles | No transaction; energy per byte is not applicable |
| bursty | 4,096 cycles | Sixteen 4 KiB frames; 64 active and 192 idle cycles per 256-cycle interval |
| saturated | 4,096 cycles | 1 MiB, 16-beat bursts, four outstanding, ready-memory model |

RTL-reference, S0 mapped GLS, and S1 mapped GLS traces agree for ready/valid,
AW/W/B, CQ, byte count, visible latency, throughput, and peak outstanding.
Input, sequential, overall, and clock annotation coverage are 100% for S0/S1;
S1 ICG-enable annotation is also 100%. `power_test_en=0` during functional power
measurement, and the S1 test-enable smoke passes.

## 5. Clock-Gating Policy

The allowlist contains only wide banks with existing common write enables.
Metadata/control, read-side control, AXI control, CDC state, reset handshakes,
completion, IRQ/error/status, and whole-domain gating remain excluded. DC uses a
32-bit minimum bank width and a maximum gate fanout of 128.

| Category | Eligible bits | Gated bits | Coverage |
| --- | ---: | ---: | ---: |
| Fixed payload banks | 65,536 | 65,536 | 100% |
| Shared payload banks | 32,768 | 32,768 | 100% |
| Shared keep banks | 4,096 | 4,096 | 100% |
| Writer WDATA/WSTRB banks | 576 | 576 | 100% |
| **Total** | **102,976** | **102,976** | **100%** |

S1 contains 837 `CLKGATETST_X1` cells. The 102,976 gated bits are
`90.535515%` of S0's 113,741 mapped registers. ICG fanout, gating-check, mapped
electrical, and structural violation counts are zero.

## 6. Mapped-DC Result

| Metric | S0 | S1 | Candidate minus baseline |
| --- | ---: | ---: | ---: |
| Setup WNS at 500 MHz (ns) | +0.00336182 | +0.00553846 | +0.00217664 |
| Hold WNS (ns) | +0.0441018 | +0.0441018 | 0 |
| Total area (um^2) | 946,749.061998 | 749,598.107999 | `-20.823993%` |
| Combinational area (um^2) | 429,844.296002 | 229,293.596000 | `-46.656592%` |
| Sequential area (um^2) | 516,904.766000 | 520,304.512000 | `+0.657712%` |
| Cells | 472,128 | 253,412 | -218,716 |
| Registers | 113,741 | 113,752 | +11 |

Both points have zero setup/hold TNS and zero timing, electrical, latch,
unresolved-reference, GTECH, or unclocked-register violations. This is one
500 MHz mapped point, not an Fmax result. The large combinational-area change is
consistent with DC replacing per-bit recirculation muxing with shared ICGs; it
is a result of this mapped register-expanded implementation, not an RTL-area or
SRAM claim.

## 7. Activity-Based Power Result

| Workload | S0 dynamic (mW) | S1 dynamic (mW) | Dynamic delta | Clock + sequential delta |
| --- | ---: | ---: | ---: | ---: |
| idle | 212.00 | 26.90 | `-87.311321%` | `-87.337797%` |
| bursty | 389.33 | 47.07 | `-87.909999%` | `-89.531364%` |
| saturated | 387.81 | 49.27 | `-87.295325%` | `-89.293144%` |

The predefined mapped-DC gates require at least 20% gated-state coverage,
bursty dynamic at or below -10%, saturated dynamic no worse than +1%, and total
area no worse than +2%. S1 passes all four gates.

| Workload | Dynamic E/B S0 -> S1 (pJ/B) | Delta | Incremental total E/B S0 -> S1 (pJ/B) | Delta |
| --- | ---: | ---: | ---: | ---: |
| bursty | 70.787273 -> 8.558182 | `-87.909999%` | 32.181818 -> 3.672727 | `-88.587571%` |
| saturated | 57.057103 -> 7.248920 | `-87.295325%` | 25.747126 -> 3.310345 | `-87.142857%` |

Dynamic power is the primary metric. DC hierarchy total-power fields have three
significant digits, so the validator allows only the explicit 1.1 mW bounded
independent half-LSB sum. Incremental total energy remains secondary.

## 8. Physical Boundary

No P&R, CTS, OpenRCX, or PrimeTime run was started for S0 or S1. There is no
post-route paired power, routed timing, congestion, clock-tree, DRC, antenna, or
electrical result in this experiment. Mapped-DC clock power is not CTS
clock-tree power.

## 9. Why No G2 Was Needed

The flow recognized every allowlisted bit without changing RTL. The experiment
therefore did not trigger a gating-friendly RTL rewrite. Expanding into control,
CDC, reset, or whole-domain state merely to increase a metric would violate the
bounded policy.

## 10. Why This Differs From The Earlier Negative Result

The earlier immutable [negative experiment](https://github.com/ichigo-6301/slvc-dma-open/commit/78d4d3336270d4d01c4731050e9eea7fe8e47497)
gated only the 576-bit Writer output bank, about 0.506% of mapped register state.
Its bursty dynamic improvement was below 1%, and its physical baseline stopped
before G1. This experiment adds 102,400 payload/keep bits that already have
native bank-select write enables, raising gated-state coverage to 90.535515%.

The saturated reduction is plausible because only the selected payload bank
needs a clock edge on a write; saturated interface traffic does not imply that
all register-expanded banks update every cycle. This interpretation is bounded
to the mapped hierarchy and does not establish post-CTS behavior.

## 11. Engineering Decision

- Classification: `POSITIVE_MAPPED_DC / BRANCH_ONLY`.
- The predefined mapped-DC promotion gates pass.
- The production RTL remains unchanged.
- No G2 RTL work is needed.
- No P&R or post-route power claim is made.
- The result is not recommended for merge into `main`.

## 12. Claims And Nonclaims

This branch supports only a bounded activity-based mapped-DC result for the
two-channel register-expanded C2B4 RX512 subsystem. It does not support a
complete-DMA, SRAM, Fmax, P&R, CTS clock-tree, post-route power, MMMC/OCV,
power-integrity, thermal, foundry, signoff, or silicon conclusion. No
LEC/Formality PASS exists; zero-delay mapped GLS is bounded functional evidence,
not formal equivalence.

## 13. Public Evidence Review

The package publishes only summaries and logical artifact IDs, byte sizes, and
SHA-256 values. It contains no raw commercial logs/reports, DDC, netlist, SDC,
VCD, SAIF, library payload, host, account, license, or local path. Run:

```text
make power-research-check
```

Review [points.csv](../../evidence/asic_power_clock_gating_storage_positive/points.csv),
the Decimal-generated [comparisons.csv](../../evidence/asic_power_clock_gating_storage_positive/comparisons.csv),
the [category census](../../evidence/asic_power_clock_gating_storage_positive/category_census.csv),
[verification records](../../evidence/asic_power_clock_gating_storage_positive/verification.csv),
and the [branch-only validator](../../flows/scripts/validate_asic_power_storage_clock_gating_experiment.py).
