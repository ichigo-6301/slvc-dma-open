# 限制

- README 中多个单通道 DMA、MCDMA 类方案和 SLVC DMA 的比较是定性架构分析，
  不是对某个厂商 IP 的实测 benchmark。MCDMA 的 HOL/backpressure 行为取决于具体
  queue、scheduler、共享 AXI 和软件配置。
- `ch0_full_then_ch1=1` 只验证 channel 0 ring space 不足时 channel 1 的一项
  directed admission 场景。它不证明 shared pool、CQ、AXI 或 reset/quiesce 条件下
  的 universal channel isolation。
- 本版本仅冻结 512-bit SLVC profile；128-bit standard profile 尚未实现。
- 200 MHz 结果是 OOC，不是 board implementation 或 10G lossless claim。
- 精选仿真是 directed regression，不是 functional coverage 或 formal closure。
- C2B4 register-expanded RX512 memory subsystem 有一个 verified internal
  post-route point，但它是 102,400 memory bit 全部用 register 实现的两通道 profile，
  不是 C4B4、完整 DMA、代表性 SRAM PPA 或 signoff。
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
- C2 物理结果在 nominal single corner 下使用 0 ns hold uncertainty，不包含 IO timing、
  OCV/MMMC、功耗、foundry extraction 或 silicon evidence。
- SRAM A5 clock delivery 只在单宏 boundary canary 上 verified。proxy high/low
  minimum-pulse 仍为 1.5625 ns，未启动 C4B4 SRAM DC/P&R/PT，macro DRC/LVS/PEX
  也未闭合。
- 256x128 macro 37.74% 的生成面积降低不代表 performance、power 或集成 PPA 改善；
  full characterization 尚未完成。
- Vivado 2022.2 async64 数据与 Vivado 2018.3 分开；它保留 52 条分类 OOC DRC
  warning，不是 board 或 zero-DRC 结果。
