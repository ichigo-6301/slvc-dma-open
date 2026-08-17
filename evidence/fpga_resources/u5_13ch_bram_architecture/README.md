# U5 13-Channel BRAM Architecture Comparison

This package records one bounded Vivado 2018.3 resource comparison on
`xc7z100ffg900-2`. [`resources.csv`](resources.csv) is Numeric Authority;
[`comparisons.csv`](comparisons.csv) is regenerated from those BRAM counts with
decimal arithmetic. Private checkpoints, reports, and generation scripts are
identified by size and SHA-256 in [`artifacts.csv`](artifacts.csv); they are not
published because raw Vivado output contains host and absolute-path metadata.

## Fixed Configurations

- Current U5 SLVC build: `DMA_MAX_CH=16`, 13 active RX and 13 active TX
  contexts, 512-bit stream, existing 64-bit HP0, synchronous 100 MHz profile.
- Payload FIFO baseline: thirteen independent `512 x 128` FIFOs, or 8 KiB per
  active channel.
- AXIS FIFO baseline: thirteen independent `577 x 128` FIFOs carrying
  `data + keep + last`.
- Packed-bank lower bound: one centralized 13 x 8 KiB payload store without
  independent FIFO control.
- MCDMA lower bound: AXI MCDMA v1.1 with 13 MM2S and 13 S2MM channels,
  512-bit memory and 512-bit streams, store-and-forward enabled.

Vivado 2018.3 rejects direct 64-bit memory / 512-bit stream AXI MCDMA because
its memory-map width property accepts only 512 or 1024 bits for this profile.
The successful 512/512 point therefore favors the MCDMA baseline and excludes
the width conversion and arbitration needed for the board's 64-bit HP0 port.

## Result Boundary

The current SLVC wrapper maps to 45.5 BRAM tiles. Thirteen independent payload
FIFOs map to 97.5 tiles and the complete AXIS FIFOs map to 110.5 tiles. This
supports a fragmentation result for independent shallow-wide FIFOs.

The ideal packed bank maps to 28.5 tiles, below the SLVC wrapper. The current
SLVC build retains sixteen 8 KiB Fixed payload banks and adds a 4 KiB Shared
Pool, for 135,168 logical payload bytes versus 106,496 bytes in the active
13-channel FIFO baselines. No capacity normalization is applied.

MCDMA plus FIFO totals are resource-budget comparisons only. The designs do
not implement identical framing, admission, Fixed/Shared ownership, CQ, or TX
contracts. LUT/FF totals are disclosed in `resources.csv` but are not promoted
as a total-area result.

This package does not claim exact MCDMA internal FIFO depth, complete functional
equivalence, a Shared-Pool-only reduction, arbitrary unbounded lossless
operation, throughput, Fmax, ASIC PPA, or a resume-ready result.
