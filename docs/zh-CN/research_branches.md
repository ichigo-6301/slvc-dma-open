# 实验性研究分支

公开 `main` 只索引已经完成脱敏、具备机器校验、且与生产线隔离的研究入口。研究分支不会自动成为生产 Profile、正式 Claim 或 release 内容。

## ASIC Storage-Bank Clock Gating

- Canonical branch：[`research/dma-a3-clock-gating-storage-positive-2026-08`](https://github.com/ichigo-6301/slvc-dma-open/tree/research/dma-a3-clock-gating-storage-positive-2026-08)
- 审计时固定提交：[`d99234ffb3d7d9a5b068ca4434fcfce8b7fd5c79`](https://github.com/ichigo-6301/slvc-dma-open/tree/d99234ffb3d7d9a5b068ca4434fcfce8b7fd5c79)
- Scope：两通道 C2B4 register-expanded RX512 memory subsystem 的 branch-only Mapped-DC activity-based power 研究。
- Production RTL：未修改。

该研究不是完整 DMA、SRAM Profile、Fmax、P&R、CTS clock-tree power、post-route power、LEC/Formality PASS、foundry signoff 或 silicon 结果。量化数据只在研究分支内展示，不注册到 `main` 的正式 claims/evidence/nonclaims。

[返回首页](../../README.md) · [查看公开结果边界](results.md) · [查看限制](limitations.md)
