# Private Async64 Throughput Evidence

Status: `BLOCKED_PROTOCOL_CONTRACT`.

This package records a fail-closed benchmark bring-up. `points.csv` is the raw
counter source for smoke paths that completed payload and CQ processing.
`metrics.csv` is regenerated with Python `Decimal`; every row is explicitly
non-claimable. `stall_breakdown.csv` is regenerated from those raw counters.
`matrix.csv` records every formal point as `NOT_RUN_PREREQUISITE` rather than
leaving an ambiguous blank. `latency.csv` contains individual owner-visible samples.
`verification.csv` records blocked, inconclusive, and not-run endpoints.
`artifacts.csv` binds ignored raw transcripts by logical name, size, and
SHA-256 without publishing simulator logs.

No value in this directory is a public SLVC-DMA claim. In particular, the
public `64 B/cycle` result remains scoped to the ready ideal-memory
Same-clock512/Async512 Writer interface. Async64 is bounded to `8 B/cycle` at
the 64-bit, 100 MHz memory interface before protocol, arbitration, and
completion overhead.
