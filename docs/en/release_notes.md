# Release Notes

## Unreleased Documentation And Delivery Updates

`main` may contain documentation, delivery-structure, and public-integrity
updates after the frozen release tag. These updates do not change RTL,
interfaces, PPA claims, or the `v0.1.0-rc1` tag target.

The adapter P0 preview is a separate optional source profile. It adds a fixed
Ethernet II / IPv4 / UDP receive adapter and its own simulation/DC evidence;
it is not a retag of RC1 and does not change the frozen DMA core evidence.

## v0.1.0-rc1

The frozen public release contains the 512-bit SLVC DMA profile, selected
ModelSim/Questa directed regression, and Vivado 2018.3 FPGA OOC evidence.
Public claims and nonclaims are bound to `provenance/` and
`provenance/checksums.sha256`.
