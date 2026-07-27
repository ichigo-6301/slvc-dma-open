# Release Notes

## Unreleased Documentation And Delivery Updates

当前 `main` 同步了两个 RX writer 的 reservation-timing 实测优化、C2B4
register-expanded ASIC flow contract 与 evidence、独立 Vivado 2022.2 async64 routed
OOC 结果，以及 SRAM A5 model/clock-delivery 审计方法。writer port、parameter、AXI
周期行为和 throughput contract 保持不变。

C2 点是 nominal academic corner 下的两通道 RX512 memory subsystem，不是 C4B4 或
完整 DMA；SRAM A5 在 C4B4 之前仍受 proxy minimum-pulse 检查阻塞。公开仓库只分发
摘要和 sanitized reproducer script，不分发 PDK/library payload 或实测 handoff。

`v0.1.0-rc1` annotated tag 与其 target 保持不变；本轮 evolving-main update 不创建
新 tag。

adapter P0 preview 是独立的可选 source profile。它增加固定 Ethernet II / IPv4 /
UDP receive adapter 及其独立 simulation/DC evidence；它不是 RC1 retag，也不修改
frozen DMA core evidence。

## v0.1.0-rc1

frozen public release 包含 512-bit SLVC DMA profile、选定的 ModelSim/Questa directed
regression，以及 Vivado 2018.3 FPGA OOC evidence。public claim 和 nonclaim 绑定在
`provenance/` 与 `provenance/checksums.sha256`。
