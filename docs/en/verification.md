# Verification

The release-bound regression uses Windows ModelSim SE-64 2020.4 and IC_EDA
Linux Questa Sim-64 10.7c. It covers TX channel tables, full-architecture
throughput, hybrid RX ingress, shared frame pools, parser behavior, AXI-Lite
reads, TX CQ space, descriptor queue/status, and the W prefetch FIFO.

The suite checks payload order, CQ count, descriptor status, backpressure, soft
reset, and maximum contiguous AXI W runs. It is a directed regression, not
coverage closure, formal proof, or CDC/RDC signoff.

Run `python3 flows/scripts/flowctl.py sim` with Python 3.6 or newer. The runner
requires ten exact PASS markers. Source provenance and evidence are under
`provenance/` and `evidence/`.
