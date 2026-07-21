# DMA ASIC Route A0 Frequency Matrix Proposal

The proposed runs are enumerated in [dma_frequency_matrix.csv](data/dma_frequency_matrix.csv). Every entry is planned; no new timing result was generated in Route A0.

## Principles

- **ANALYSIS**: record DC, P&R, and PrimeTime periods independently. A tighter DC target is useful only when synthesis actually closes it.
- **ANALYSIS**: select the first P&R clock from a setup-clean DC point and use a conservative physical target; do not copy MRTC's frequency.
- **ANALYSIS**: macro Liberty minimum-period and pulse-width checks can govern the target even when register setup paths are clean.
- **ANALYSIS**: 100 MHz is elaboration/sanity, 200 MHz is the architectural target inherited from the current development intent, 300 MHz is stretch, and 400 MHz is stress. These are proposals, not achieved values.

## Same-Clock Matrix

- **ASSUMPTION**: Profile A runs at 100 and 200 MHz to validate the flow wrapper and writer logic.
- **ASSUMPTION**: Profile B DC evaluates 100/200/300/400 MHz with identical macros and constraints.
- **ANALYSIS**: first Profile B P&R starts at the highest clean DC point no higher than 200 MHz, unless macro checks require a lower point.
- **TBD_MEASUREMENT**: actual DC closure and macro limits.

## Async Matrix

- **ASSUMPTION**: first Async512 implementation uses same-frequency but asynchronous 200/200 MHz clocks to separate CDC phase from rate-ratio complexity.
- **ASSUMPTION**: functional regressions also cover 100/200, 200/100, 125/200, 200/125, phase offset, and non-integer ratios, as the branch tests already model.
- **ANALYSIS**: physical sweeps should vary one domain at a time after 200/200 bring-up so source-domain and memory-domain limits remain attributable.

## Stop Rules

1. **ANALYSIS**: stop before compile if analyze/elaborate/link or macro binding fails.
2. **ANALYSIS**: stop frequency promotion on negative DC setup slack, macro min-period failure, unconstrained internal endpoints, or unresolved black boxes.
3. **ANALYSIS**: stop P&R promotion on macro overlap, unroutable pins, severe congestion, CTS failure, detail-route/antenna violations, or missing same-run SPEF.
4. **ANALYSIS**: stop result promotion on mapped-netlist/SDC/SPEF identity mismatch or incomplete PrimeTime setup/hold coverage.
