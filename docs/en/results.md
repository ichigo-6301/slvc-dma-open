# Verified Results

| Strategy | WNS | WHS | LUT | FF | RAMB36 | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Explore | +0.226 ns | +0.045 ns | 38,074 | 40,787 | 44 | 3 | 0 |
| Performance_Explore | +0.173 ns | +0.046 ns | 38,087 | 40,787 | 44 | 3 | 0 |
| ExtraNetDelay_high | +0.162 ns | +0.054 ns | 38,088 | 40,785 | 44 | 3 | 0 |

TNS and THS are zero in all runs. The minimum WNS is `+0.162 ns`; the earlier
preferred `+0.300 ns` margin was not reached. The long multi-burst W prefetch
test observed 48 contiguous 512-bit AXI W beats.

Each claim has a fixed source commit, tool, report checksum, and caveat in
`provenance/` and `evidence/`.
