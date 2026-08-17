# FPGA Implementation

The verified implementation is a Vivado 2018.3 source-level OOC run of
`frame_dma_wrapper` on `xc7z100ffg900-2` with a 5.000 ns clock. Explore,
Performance_Explore, and ExtraNetDelay_high all meet setup and hold timing.

After selecting a defconfig, `make fpga-ooc` calls the public native Tcl and
writes only ignored `build/` and `reports/` outputs. It does not generate
Xilinx IP, mutate a BD, or include device libraries or board projects.
<!-- fpga-bram-publication:slvc_dma_u5_13ch_bram_architecture_comparison:start -->
## U5 13-Channel BRAM Resource Boundary

The additional comparison is bound to the existing synchronous U5 profile: `DMA_MAX_CH=16`, 13 active RX and 13 active TX contexts, a 512-bit stream, 64-bit HP0, and 100 MHz. The current wrapper contains `135168` physical payload bytes across sixteen 8 KiB Fixed banks and one 4 KiB Shared Pool. The thirteen-channel FIFO baselines cover only the active channels and contain 106496 payload bytes, so the results are not capacity-normalized.

Hierarchy utilization was read from the protected existing synthesis and routed checkpoints without changing the XPR, BD, RTL, SDK, or bitstream. The independent FIFOs, packed bank, and MCDMA points were generated in isolated OOC projects. The [Evidence package](../../evidence/fpga_resources/u5_13ch_bram_architecture/README.md) records the input artifact SHA-256 identities.

This comparison supports only a bounded BRAM-mapping result, not functional equivalence, complete-area superiority, or zero loss under unlimited bursts.
<!-- fpga-bram-publication:slvc_dma_u5_13ch_bram_architecture_comparison:end -->
