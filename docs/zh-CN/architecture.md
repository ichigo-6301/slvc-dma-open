# 架构

## 系统问题

SLVC DMA 面向多个业务源共享一条高速串行或 packet link 的数据搬运场景。共享链路解决了物理接口复用，但接收端仍需完成以下工作：

- 从统一 stream 中恢复 frame 边界和 channel identity；
- 在接收 payload 前确认 DDR ring、片上 buffer 和 Completion Queue 都有空间；
- 隔离不同 channel 的软件 ownership 和 completion；
- 允许突发流量共享容量，同时避免一个已提交 frame 的 payload 与其它 source 交织；
- 在 payload backpressure 之外传递 PAUSE/RESUME 等策略消息。

本项目的技术重点是这些系统实现边界，以及同一 RTL 在仿真、FPGA OOC 和 ASIC reference flow 中的闭合证据，不是新的数据压缩或调度算法。

## 典型替代方案与取舍

以下是架构层面的定性比较，不是竞争 IP benchmark。尤其是 MCDMA 的 queue、scheduler、outstanding 和 backpressure 行为因实现与配置而异。

| 方案 | 优点 | 集成代价或风险 |
| --- | --- | --- |
| 多个单通道 DMA | 通道状态和反压天然分离；每个实例可独立选择 buffer 和 AXI master | 上游需要解帧/分流；FIFO、CSR、IRQ、地址空间和验证环境按实例重复 |
| 集中式 MCDMA 类 IP | 复用 AXI master、寄存器接口和调度器 | 需要适配其 channel/descriptor 模型；隔离程度依赖内部 queue 和 scheduler，共享资源可能产生 HOL/backpressure 扩散 |
| SLVC DMA | SHDR64 直接携带 channel metadata；统一 parser、admission、fixed/shared buffering、ring 和 CQ ownership | 针对当前 shared-link contract 定制；shared pool、CQ 和 DDR 仍是有限共享资源，不能声明任意条件下完全无阻塞 |

## End-to-End 数据路径

![SLVC DMA shared-link overview](../assets/slvc_dma_overview.svg)

`slvc_dma_wrapper` 是固定 `slvc_dma_v1_512` profile 的公开系统集成顶层，`frame_dma_wrapper` 是完整 FPGA OOC timing top。数据路径包含 shared segment stream、RX parser/channel match、frame storage、AXI4 writer、CQ publication 和 descriptor-driven TX replay。

RX 解析固定 64-byte SHDR64 header，根据 channel metadata 执行 admission，并把 payload 写入目标 DDR ring。CQ body 先写入，owner/valid 最后可见。TX 根据 descriptor 从 DDR 读取 payload，重新生成 SHDR64 header 后回放到 shared-link TX。

## 虚拟通道生命周期

![SLVC DMA frame lifecycle and ownership boundaries](../assets/slvc_dma_frame_lifecycle.svg)

1. **Parse**：elastic input 先锁存 SHDR64，提取 `flow_id`、payload length、sequence、timestamp 和 CRC 相关字段。
2. **Match**：`dma_rx_channel_match` 将动态 header metadata 与 `dma_rx_channel_table` 中的软件配置组合，但不拥有表状态。
3. **Check**：RX 状态机检查目标 ring free space、ingress/shared storage、CQ credit 和当前 reset/flow-control 状态。
4. **Reserve**：只有全部资源同时可用时才为本 frame 预留容量；预留资源不会被后来请求抢占。
5. **Commit and collect**：payload 进入 fixed ingress 或 shared pool。未完整提交的 shared frame 不可被 writer 读出。
6. **Drain**：source selector 锁定一个 committed frame 直到结束，再由 64-bit legacy writer 或可选 512-bit backend 产生 AXI burst。
7. **Complete**：AXI response 完成后写 CQ body，再发布 owner/valid 和 IRQ；软件推进 ring/CQ ownership 后资源才能复用。

## 混合缓冲与真实隔离边界

![SLVC DMA virtual-channel buffering](../assets/slvc_dma_virtual_channel_buffering.svg)

固定 ingress 为 channel 保留确定容量，适合需要容量隔离的流。`dma_rx_frame_shared_adapter` 与 `dma_frame_shared_pool` 使用 block free list，让不同时到达的 frame 共享容量。metadata commit 是 shared pool 的可见性边界，读完后必须 release，block 才能回到 free list。

现有 adapter-to-DMA directed smoke 覆盖 `ch0_full_then_ch1=1`：channel 0 无可用 ring space 时，channel 1 packet 仍被 admission 并产生 CQE。这证明 channel match 和 per-channel ring-space check 在该场景中没有把 channel 0 的阻塞扩散到 channel 1。

该结果不能推广为任意 non-blocking 保证：

- shared pool 耗尽会阻塞所有选择 shared policy 的 channel；
- CQ 无 credit、全局 reset/quiesce 或共享 AXI 长期不响应会形成系统级反压；
- active frame 由 selector 锁定以保持 frame atomicity，当前 frame 的下游 backpressure 会推迟下一个 source 的 drain；
- PAUSE/RESUME 是策略消息，不等同于网络或 AXI4-Stream 的逐拍 credit protocol。

## 外部协议边界

carrier adapter 与 MCF endpoint 位于 DMA 边界之外，不改变 DDR/CQ ownership：

- `frame_dma_rx_aurora_ufc_wrap` 展示 Aurora-compatible payload/UFC 边界；仓库不分发 generated Aurora IP。
- `mcf_endpoint` 在多个本地 source 之间仲裁并生成 shared-link segment；PAUSE/RESUME 走 control-message path。
- `dma_udp_ipv4_to_shdr64_adapter` 接收固定 512-bit Ethernet II / IPv4 IHL=5 / UDP profile，从 byte 42 开始重新打包 payload，并将 UDP destination port 映射为 `SHDR64.flow_id`。
- `frame_dma_rx_axis_width_frontend` 可把 64/128/256/512-bit 外部 AXI-Stream beat 聚合为 512-bit Core beat；这不代表 native Core 已验证所有宽度。

UDP adapter 不属于 `frame_dma_wrapper`，因此冻结 core 的 FPGA OOC 结果不包含 adapter logic。它也不是完整 Ethernet stack，不包含 MAC/PHY、VLAN、IPv6、fragment reassembly、UDP checksum 或 FCS handling。

## RX Memory 开发 Profile

默认关闭的 RX memory profile 不改变 parser/admission 前端。fixed ingress 或 shared pool frame 到达现有 commit 点后，`dma_rx_ingress_source_selector` 锁定一个 512-bit drain source：

![SLVC DMA RX memory profiles and CDC transaction directions](../assets/slvc_dma_memory_profiles.svg)

- same-clock 512 直接进入 `dma_axi_write_engine_512`；
- async64/async512 通过 command、ordered 512-bit payload 和 tagged completion 三条 FIFO channel 跨域；
- Async64 在 `mem_clk` 中序列化为 64-bit，Async512 保持 512-bit；
- AW/W/B 全部保留在 `mem_clk`，原 64-bit AXI master 继续承担 CQ、TX read 和 legacy RX traffic。

详见[同频后端](rx_payload_512_backend.md)与[双时钟后端](rx_payload_cdc_backends.md)。

## ASIC Memory Binding

ASIC 探索使用 flow-only binding，不改变生产 RTL 行为：

- 已验证的 C2B4 register-expanded profile 把两个 channel 的 fixed payload 和 shared payload/keep store lower 为 13 个标准单元 register array，共保留 102,400 bit，SRAM macro 数为 0。
- A5 SRAM research profile 将 fixed/shared payload array 绑定到 OpenRAM macro，并显式增加 macro output boundary 和 clock leaf。单宏 clock delivery 已通过，但 proxy minimum-pulse model 在 C4B4 integration 前阻塞该路线。

两类结果使用不同 memory binding，面积与频率不可直接混称。详见 [ASIC 实现](asic_implementation.md)和[已核验结果](results.md)。
