# FPGA Implementation

The verified implementation is a Vivado 2018.3 source-level OOC run of
`frame_dma_wrapper` on `xc7z100ffg900-2` with a 5.000 ns clock. Explore,
Performance_Explore, and ExtraNetDelay_high all meet setup and hold timing.

After selecting a defconfig, `make fpga-ooc` calls the public native Tcl and
writes only ignored `build/` and `reports/` outputs. It does not generate
Xilinx IP, mutate a BD, or include device libraries or board projects.

## U5 Board Evidence Maturity

<!-- claim:slvc_dma_u5_sync_hp0_loopback_board_throughput maturity:partial -->

| Dimension | Status | Fixed boundary |
| --- | --- | --- |
| Source / RTL simulation / synthesis / implementation / bitstream | verified | Vivado 2018.3, XC7Z100, 13 RX/13 TX, synchronous PL-local loopback |
| Timing | partial | Fixed 100 MHz operating point; no Fmax claim |
| Board smoke / workload validation | partial | `FPGA_DEBUGGER_CAPTURED_SINGLE_RUN`; 1024 x 4 KiB; no repeatability statistics |

The public repository retains byte-identical SDK source, a sanitized startup excerpt, raw debugger counters, derivation formulas, and external bitstream/ELF hashes. It does not publish the bitstream, ELF, complete SDK log, or JTAG identity. [Read the evidence package](../../evidence/fpga_emulation/u5_sync_hp0_loopback/README.md).
