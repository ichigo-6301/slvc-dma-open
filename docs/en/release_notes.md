# Release Notes

## Unreleased Documentation And Delivery Updates

Current `main` publishes the measured reservation-timing updates to the two RX
writers, C2B4 register-expanded ASIC flow contracts and evidence, the separate
Vivado 2022.2 async64 routed-OOC result, and SRAM A5 model/clock-delivery audit
methods. Writer ports, parameters, AXI cycle behavior, and throughput contracts
remain unchanged.

The C2 point is a two-channel RX512 memory subsystem at a nominal academic
corner, not C4B4 or complete DMA. SRAM A5 remains blocked by proxy minimum
pulse checks before C4B4. The public repository distributes summaries and
sanitized reproducer scripts, not PDK/library payloads or measured handoffs.

The `v0.1.0-rc1` annotated tag and its target remain immutable. No new tag is
created for these evolving-main updates.

The adapter P0 preview is a separate optional source profile. It adds a fixed
Ethernet II / IPv4 / UDP receive adapter and its own simulation/DC evidence;
it is not a retag of RC1 and does not change the frozen DMA core evidence.

## v0.1.0-rc1

The frozen public release contains the 512-bit SLVC DMA profile, selected
ModelSim/Questa directed regression, and Vivado 2018.3 FPGA OOC evidence.
Public claims and nonclaims are bound to `provenance/` and
`provenance/checksums.sha256`.
