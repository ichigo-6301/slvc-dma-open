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
- 可选 RX memory 开发 profile 仅包含同频 512、async64 和 async512；不实现任意
  128/256-bit memory width、非对齐首拍移位、TX/CQ 宽化或多端口 striping。
- 异步 profile 要求两个 hard reset 同时 assert，不支持任意单边 reset/recovery。
  soft reset 会阻止新的 RX、TX/descriptor 和 UFC launch，排空已经接受的 work，并在
  memory-domain acknowledgement 返回后才提交。其有界完成要求两个时钟持续运行且
  所有下游最终响应；它不是通用 external AXI reset protocol。
- CDC evidence 覆盖已实现 FIFO 结构、仿真 assertion、双向 Vivado CDC report 和
  bus skew；不等价于完整 ASIC CDC/RDC signoff 与 waiver package。
- Async64 routed OOC 保留 3 个 `PDRC-190` synchronizer-placement warning；两个
  异步 OOC profile 都保留 integration top 的 BRAM/reset DRC warning。这些 warning
  被明确披露，不能作为 signoff waiver。
- 流水化后的 Async64 在 4 条实测 routing strategy 中全部达到 200 MHz，最小 WNS
  为 `+0.109 ns`；流水化前 2 条通过、2 条失败的矩阵仍作为 baseline evidence
  保留，没有被覆盖。允许每个 burst 有一个 registered AW planning 间隔；理想 1 MiB
  workload 实测仍为 100% W 利用率，但不保证任意 memory latency 或短传输模式。
- RX backend Vivado 结果是 OOC，Design Compiler 结果是包含 generic FIFO array 的
  frontend OOC synthesis；它们不是完整系统 FPGA、板级 DDR、routed ASIC、SRAM
  macro、physical design 或 signoff evidence。
