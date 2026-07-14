# Verification

The release-bound regression uses ModelSim SE-64 2020.4. It covers TX channel
tables, full-architecture throughput, hybrid RX ingress, shared frame pools,
parser behavior, AXI-Lite reads, TX CQ space, descriptor queue/status, and the
W prefetch FIFO.

The suite checks payload order, CQ count, descriptor status, backpressure, soft
reset, and maximum contiguous AXI W runs. It is a directed regression, not
coverage closure, formal proof, or CDC/RDC signoff.

Run `python flows/scripts/flowctl.py sim`. Source provenance and evidence are
under `provenance/` and `evidence/`.
