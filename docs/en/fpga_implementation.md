# FPGA Implementation

The verified implementation is a Vivado 2018.3 source-level OOC run of
`frame_dma_wrapper` on `xc7z100ffg900-2` with a 5.000 ns clock. Explore,
Performance_Explore, and ExtraNetDelay_high all meet setup and hold timing.

`python flows/scripts/flowctl.py fpga-ooc` calls the public native Tcl and
writes only ignored `build/` and `reports/` outputs. It does not generate
Xilinx IP, mutate a BD, or include device libraries or board projects.
