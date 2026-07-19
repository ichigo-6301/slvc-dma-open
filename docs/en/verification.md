# Verification

The release-bound regression uses Windows ModelSim SE-64 2020.4 and IC_EDA
Linux Questa Sim-64 10.7c. It covers TX channel tables, full-architecture
throughput, hybrid RX ingress, shared frame pools, parser behavior, AXI-Lite
reads, TX CQ space, descriptor queue/status, and the W prefetch FIFO.

The suite checks payload order, CQ count, descriptor status, backpressure, soft
reset, and maximum contiguous AXI W runs. It is a directed regression, not
coverage closure, formal proof, or CDC/RDC signoff.

Run `python3 flows/scripts/flowctl.py sim` with Python 3.6 or newer. The runner
always requires ten exact frozen-core PASS markers. The default adapter-enabled
defconfig adds four adapter markers for fourteen total. The optional RX-wide
defconfig disables the adapter and adds two wide-backend markers for twelve
total. Each dual-clock defconfig disables the adapter and adds one common CDC
bridge marker plus two width-specific markers for thirteen total. Frozen
release provenance remains under `provenance/` and `evidence/`; RX memory
backend measurements are documented separately as development-profile results.
