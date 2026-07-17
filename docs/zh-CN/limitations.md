# 限制

- 本版本仅冻结 512-bit SLVC profile；128-bit standard profile 尚未实现。
- 200 MHz 结果是 OOC，不是 board implementation 或 10G lossless claim。
- 精选仿真是 directed regression，不是 functional coverage 或 formal closure。
- ASIC library binding、SRAM macro、DFT、P&R、post-layout STA 和 signoff 未完成。
- 当前 release commit 未重新执行 U5 board validation；历史板级结果不作为当前
  commit 的 verified claim。
- carrier CDC 有 directed verification，但无完整 signoff/waiver package。
- 可选 UDP/IPv4 adapter 是固定 RX profile，不是完整 Ethernet/IP stack；不支持
  VLAN、IPv6、options、fragment、UDP checksum 或 FCS handling。
- adapter-only DC OOC 不等于完整 DMA ASIC synthesis、physical implementation、
  signoff、board-level 10G 或 lossless UDP evidence。
