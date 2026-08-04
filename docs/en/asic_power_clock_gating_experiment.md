# ASIC Clock-Gating Power Research: Negative Result

> [!WARNING]
> This is branch-only research evidence. It is not part of `main`, `v0.1.0-rc1`,
> or a production profile. The result is `NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED`;
> no production RTL change is recommended.

## 1. Purpose

This experiment evaluates automatic integrated clock gating on a fixed C2B4
register-expanded RX512 subsystem. Its goal is to establish deterministic
activity, activity-based mapped-DC power estimates, and bounded physical gates
without changing the design contract. It is an engineering research record, not
a released power result.

## 2. Scope And Identity

The scope is `dma_rx512_memory_subsystem_top` with two channels, 4 KiB fixed
payload per channel, 64 shared blocks, four outstanding bursts, and
register-expanded storage. Both variants use the same A1 RTL closure, parameter
contract, source-set digest, 2.000000 ns constraint, Nangate45 typical library,
and DC O-2018.06-SP1.

The data is bound to fixed source and evidence revisions plus source, constraint,
tool-script, activity, and artifact SHA-256 values in the
[manifest](../../evidence/asic_power_clock_gating_negative/manifest.json).
Those identifiers provide provenance only; this branch does not expose a source
checkout, raw EDA content, or a commercial library payload.

## 3. Why G0/G1 Is Paired

G0 runs ordinary `compile_ultra`; G1 runs `compile_ultra -gate_clock`. The
same RTL closure, top, parameters, library, constraint, compilation script,
workload contract, and normalized functional trace apply to both. The intended
tool difference is automatic ICG insertion. Per-point activity digests differ
because each mapped implementation receives its own annotated activity; they
are not presented as one identical activity file.

## 4. Activity Workloads

All workloads use seed `71`; reset, configuration, and warm-up are outside the
sampled window. The public package contains digests and summaries, never raw
VCD or SAIF files.

| Workload | Sample window | Functional contract |
| --- | ---: | --- |
| idle | 4,096 cycles | No transaction; energy per byte is not applicable |
| bursty | 4,096 cycles | 16 frames of 4 KiB, with 64 active and 192 idle cycles in each 256-cycle interval |
| saturated | 4,096 cycles | 1 MiB, 16-beat bursts, four outstanding, ready-memory model; power window is steady state |

Windows ModelSim and Linux Questa each record the required marker and the same
normalized functional trace for each workload/variant pair. Input and sequential
activity coverage are 100% for both G0 and G1; overall non-default activity is
97.14% for G0 and 97.12% for G1.

## 5. Clock-Gating Policy

G1 uses `CLKGATETST_X1`, a minimum width of 32 bits, maximum gate fanout 64,
and a bounded allowlist of Writer wide data-register banks. The allowlist yields
9 ICG cells and 576 gated bits. CDC synchronizers and pointers, reset handshakes,
AXI handshake control, completion, IRQ/error/status logic, and whole-domain
gating are excluded.

## 6. Mapped-DC Result

| Metric | G0 | G1 | Candidate minus baseline |
| --- | ---: | ---: | ---: |
| ICG cells / gated bits | 0 / 0 | 9 / 576 | +9 / +576 |
| Total area (um^2) | 946,749.061998 | 946,078.741998 | `-0.070802%` |
| Combinational area (um^2) | 429,844.296002 | 429,072.630002 | `-0.179522%` |
| Sequential area (um^2) | 516,904.766000 | 517,006.112000 | `+0.019606%` |
| Registers | 113,741 | 113,753 | +12 |
| Setup WNS at 500 MHz (ns) | +0.00336182 | +0.00580668 | +0.00244486 |

Mapped-DC clock power is not CTS clock-tree power. This table does not establish
post-route behavior.

## 7. Power Result

| Workload | G0 dynamic (mW) | G1 dynamic (mW) | Dynamic delta | Clock + sequential delta |
| --- | ---: | ---: | ---: | ---: |
| idle | 390.002509 | 388.002647 | `-0.512782%` | `-0.514643%` |
| bursty | 393.790000 | 390.800000 | `-0.759288%` | `-0.737455%` |
| saturated | 391.210000 | 393.130000 | `+0.490785%` | `+0.473508%` |

The bursty case does not reach either predefined gate: 3% total dynamic or 8%
clock plus sequential. Saturated dynamic regresses. The arithmetic bursty
incremental total-energy delta is `-25%`, but it subtracts total-power values
quantized to 405/409 mW and 403/406 mW. It is a small-residual calculation, not
a promotion-grade result.

## 8. Physical Implementation Attempts

| Frequency | G0 | G1 | Boundary retained |
| ---: | --- | --- | --- |
| 500 MHz | `BLOCKED_SETUP` | `NOT_STARTED_GATE_BLOCKED` | setup WNS `-0.0450512 ns`; 15 max-fanout violations |
| 475 MHz | `BLOCKED_ELECTRICAL` | `NOT_STARTED_GATE_BLOCKED` | setup/hold closed; 14 max-fanout violations |

The baseline-first gate stops G1 after each G0 physical boundary. The G0
physical failures cannot be attributed to G1, because G1 physical execution
never started. There is no common post-route G0/G1 frequency and no
PrimeTime post-route paired power result.

## 9. Why G2 Did Not Start

The bounded allowlist already captured the expected 576 eligible bits. The
low-recognition trigger for an RTL restructuring did not apply. Widening the
scope merely to chase a small result would risk changing the production RTL
contract, so G2 was not started.

## 10. Technical Interpretation

The 576 gated bits are about `0.506%` of G1's 113,753 registers. The allowlist
primarily covers Writer wide output data banks. Bursty traffic exposes idle
windows, so a small mapped-DC change is plausible. Under saturated traffic,
the gates are open most of the time; ICG overhead and mapping perturbation can
offset any benefit. The larger register-expanded storage dominates sequential
activity. These observations do not justify broader gating or a product RTL
change.

## 11. Engineering Decision

- Classification: `NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED`.
- Production RTL remains unchanged.
- G2 is not started.
- No post-route paired-power result is made.
- This branch is not recommended for merge into `main`.

## 12. Statements And Nonclaims

This evidence is a mapped-DC activity-based estimate for a two-channel
register-expanded C2B4 RX512 subsystem. It is not a complete-DMA result, an
SRAM result, a maximum-frequency statement, a CTS clock-tree result, a
post-route paired-power result, an LEC/Formality result, or a foundry/silicon
conclusion.

## 13. Public Evidence Review

The package publishes no raw commercial logs, reports, netlists, DDC, SDC,
ODB, SPEF, VCD, SAIF, library payload, host, account, license, or local-path
data. Review the machine-readable records with:

```text
make power-research-check
```

The command validates [points.csv](../../evidence/asic_power_clock_gating_negative/points.csv),
regenerates and checks [comparisons.csv](../../evidence/asic_power_clock_gating_negative/comparisons.csv),
checks [physical_attempts.csv](../../evidence/asic_power_clock_gating_negative/physical_attempts.csv),
and verifies the [branch-only validator](../../flows/scripts/validate_asic_power_clock_gating_experiment.py).
