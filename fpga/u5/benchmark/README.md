# U5 Synchronous HP0 Loopback Benchmark

This directory contains an operator-supplied source-only reproduction reference
for the bounded U5 FPGA observation. It is not a published SDK application or
Vivado project and does not include a
bitstream, ELF, HDF, BSP, or generated SDK workspace.

## As-Run Configuration

- Xilinx Vivado/SDK 2018.3
- `xc7z100ffg900-2`
- `DMA_MAX_CH=16`, `DMA_RX_CH_NUM=13`, `DMA_TX_CH_NUM=13`
- TX channel 0 to RX channel 0 through a 512-bit AXIS register slice
- one 100 MHz PL clock and the existing 64-bit PS HP0 port
- `DMA_TEST_MODE=DMA_TEST_THROUGHPUT`
- `DMA_THROUGHPUT_FRAME_COUNT=1024U`
- 4096 bytes per frame

The [`helloworld.c`](helloworld.c) identity matches the source supplied after
the board run. Relative to the supplied connectivity source, only the test mode
and frame-count controls changed. No retained build manifest cryptographically
links this reference source to the private ELF or bitstream.

## Measurement Window In The Reference Source

The timer starts after the descriptor-start AXI4-Lite
write returns and stops when software observes the final RX CQE owner. Memory
preparation and final payload comparison are outside the timer. Before calling
the reporting function, the program checks all TX/RX CQEs, descriptor
consumption, RX release, byte-for-byte payload equality, and visible drop/error
counters.

The board's UART intermittently omitted the final report. The published raw
counters were therefore read in the SDK debugger at the reporting function,
after the timer and correctness gates had completed. This capture method is
classified as `FPGA_DEBUGGER_TRANSCRIBED_SINGLE_RUN`; it is not an automated UART
transcript or a repeatability study.

See the [evidence package](../../../evidence/fpga_emulation/u5_sync_hp0_loopback/README.md)
for immutable identities, raw counters, derived values, and claim boundaries.
