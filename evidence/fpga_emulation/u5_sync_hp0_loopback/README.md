# U5 Synchronous HP0 Loopback FPGA Observation

Classification: `FPGA_DEBUGGER_CAPTURED_SINGLE_RUN`
Claim status: `partial`
Resume eligible: `false`

This package records one 1024 x 4096-byte FPGA board observation. The design
uses 13 RX and 13 TX contexts, TX0-to-RX0 synchronous local PL loopback, a
512-bit AXIS register slice, a 100 MHz PL clock, and the existing 64-bit PS HP0
port.

| Window | Payload | XTime ticks | 100 MHz equivalent cycles | MB/s/MHz | MB/s | Gb/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Hardware end-to-end | 4,194,304 B | 8,969,535 | 2,690,860 | 1.558722 | 155.872225 | 1.246978 |

The 38.968062% value is relative to a conservative 4 B/cycle payload-only
shared-HP0 model reference. It is not a measured DDR-controller limit.

## Capture And Correctness Boundary

The original SDK log binds the programmed bitstream and downloaded ELF, but
does not contain a reliable final UART report. The raw counters were read in
the SDK debugger after the end timestamp. Program control had already passed
TX/RX CQE validation, descriptor completion, RX release, byte-for-byte payload
comparison, and zero visible error/drop counter checks. The breakpoint cannot
inflate or shorten the saved measurement window because it occurs after both
timestamps are captured.

The original log is not public because it contains local filesystem paths and
a JTAG cable serial. [`sanitized_sdk_log.txt`](sanitized_sdk_log.txt) retains
only the bounded configuration/download timeline; its SHA-256 is retained in
[`artifacts.csv`](artifacts.csv).

## Numeric Authority

[`raw_counters.csv`](raw_counters.csv) is the transcribed raw observation.
[`derived_metrics.csv`](derived_metrics.csv) is regenerated and checked using
Python `Decimal`. The firmware's three-decimal integer output is informational
and is not the numeric authority. First-frame-excluded steady state and
run-to-run variation were not captured and are not claimed.

## Nonclaims

This observation is not Async64 CDC board testing, Aurora performance, DDR peak
bandwidth, FPGA Fmax, the Same-clock512/Async512 64 B/cycle Writer result, ASIC
evidence, or a repeated statistical measurement. It does not update the
separate 16 RX/16 TX Async64 RTL-simulation claim.
