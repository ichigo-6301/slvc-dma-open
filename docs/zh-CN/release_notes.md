# Release Notes

## Unreleased Documentation And Delivery Updates

`main` 可以在 frozen release tag 之后包含 documentation、delivery structure 和
public-integrity update。这些更新不会改变 RTL、interface、PPA claim，也不会改变
`v0.1.0-rc1` tag target。

adapter P0 preview 是独立的可选 source profile。它增加固定 Ethernet II / IPv4 /
UDP receive adapter 及其独立 simulation/DC evidence；它不是 RC1 retag，也不修改
frozen DMA core evidence。

## v0.1.0-rc1

frozen public release 包含 512-bit SLVC DMA profile、选定的 ModelSim/Questa directed
regression，以及 Vivado 2018.3 FPGA OOC evidence。public claim 和 nonclaim 绑定在
`provenance/` 与 `provenance/checksums.sha256`。
