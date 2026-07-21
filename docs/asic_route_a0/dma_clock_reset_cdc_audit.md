# DMA ASIC Route A0 Clock Reset And CDC Audit

The machine-readable domain table is [dma_clock_domain_matrix.csv](data/dma_clock_domain_matrix.csv).

## Core Clock Domains

### `aclk`

- **VERIFIED_REPOSITORY_FACT**: RX stream parsing, channel tables, admission, fixed/shared frame stores, AXI-Lite, TX engine, CQ, UFC mailbox, IRQ, and the shared 64-bit AXI master are clocked by `aclk`.
- **VERIFIED_REPOSITORY_FACT**: most blocks asynchronously assert reset through `aresetn` and synchronously apply local soft reset through control logic.
- **ANALYSIS**: Profile B should use this as its only functional clock for first macro/P&R bring-up.

### `mem_clk`

- **VERIFIED_REPOSITORY_FACT**: present only in Async64/Async512 profiles. Reset is asynchronously asserted and synchronously deasserted by `dma_reset_sync`.
- **VERIFIED_REPOSITORY_FACT**: the complete selected RX AXI writer resides in `mem_clk`; AW/W/B do not cross independently.
- **VERIFIED_REPOSITORY_FACT**: command and payload travel `aclk -> mem_clk`; completion travels `mem_clk -> aclk`.

### TX Stream Clock Ports

- **VERIFIED_REPOSITORY_FACT**: `tx_axis_aclk` and `tx_axis_aresetn` are top-level ports but are not referenced after the port declaration in `frame_dma_rx_top`.
- **VERIFIED_REPOSITORY_FACT**: `dma_tx_engine` is instantiated with `.clk(aclk)` and `.rstn(aresetn)`.
- **ANALYSIS**: the current top does not implement an internal TX stream CDC. Integrators must treat TX as `aclk` synchronous or place a verified carrier CDC adapter outside it.
- **ANALYSIS**: this contract must be resolved before Profile D SDC and IO timing are frozen.

## Reset Contract

- **VERIFIED_REPOSITORY_FACT**: Async profiles require `aresetn` and `mem_aresetn` to assert together; one-sided hard-reset recovery is unsupported.
- **VERIFIED_REPOSITORY_FACT**: hard reset assertion is asynchronous and each domain uses a two-stage synchronous deassertion helper for the RX payload CDC subsystem.
- **VERIFIED_REPOSITORY_FACT**: soft reset is a quiesce-and-drain transaction. It waits for source work, CDC channels, writer outstanding work, CQ, TX, and UFC to become idle before local state reset.
- **ANALYSIS**: SRAM data must not be assumed zero after reset. Visibility must remain qualified by reset pointers, counts, and valid state.
- **TBD_MEASUREMENT**: recovery/removal timing against generated SRAM and standard-cell models.

## CDC Mechanisms

| Crossing | Mechanism | Status | Classification |
| --- | --- | --- | --- |
| RX command | 4-entry Gray-pointer FIFO | branch regression and FPGA structural audit exist | VERIFIED_REPOSITORY_FACT |
| RX payload | 32-entry 577-bit FIFO; generic ASIC array or XPM FPGA binding | functional CDC tested; ASIC macro binding absent | VERIFIED_REPOSITORY_FACT |
| RX completion | 4-entry Gray-pointer FIFO | branch regression and FPGA structural audit exist | VERIFIED_REPOSITORY_FACT |
| soft-reset request/ack | synchronized toggles | bounded quiesce/drain tests exist | VERIFIED_REPOSITORY_FACT |
| busy/error status | two-stage single-bit synchronizers | observable and regression tested | VERIFIED_REPOSITORY_FACT |
| carrier data/control | separate async FIFOs in optional adapter | not part of first ASIC target | VERIFIED_REPOSITORY_FACT |

## Principal Risks

1. **ANALYSIS**: generic dual-clock array inference is not equivalent to a characterized dual-clock SRAM leaf.
2. **ANALYSIS**: Gray pointer synchronizers need both structural CDC recognition and physical max-delay/bus-skew control.
3. **ANALYSIS**: wide FIFO data is intentionally sampled only after pointer ownership changes; CDC tools may report it as unsynchronized data and require exact structural waivers.
4. **ANALYSIS**: stopped-clock reset behavior intentionally remains pending. SoC reset architecture must not assume bounded completion when either clock is stopped.
5. **ANALYSIS**: reset synchronization, memory validity, and macro collision rules must be tested together after memory replacement.
