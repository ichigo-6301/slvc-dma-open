# SLVC DMA

[![Public Integrity](https://github.com/ichigo-6301/slvc-dma-open/actions/workflows/public-integrity.yml/badge.svg?branch=main)](https://github.com/ichigo-6301/slvc-dma-open/actions/workflows/public-integrity.yml) ![RTL](https://img.shields.io/badge/RTL-Verilog-2f6f9f) [![License](https://img.shields.io/github/license/ichigo-6301/slvc-dma-open)](LICENSE)

[English](README.en.md) · [架构](docs/zh-CN/architecture.md) · [集成](docs/zh-CN/integration.md) · [验证](docs/zh-CN/verification.md) · [结果](docs/zh-CN/results.md) · [限制](docs/zh-CN/limitations.md)

**面向多源共享高速链路的 512-bit 虚拟通道 DMA：在协议适配层与 DDR 之间提供 channel-aware admission、混合缓冲、独立控制消息和可审计的 completion ownership。**

多个传感器、基带处理单元或本地 endpoint 可以先复用为一条 SHDR64 segment stream。SLVC DMA 依据 header metadata 选择虚拟通道和 DDR ring，在固定通道缓冲与共享 frame pool 之间进行资源管理，并通过 Completion Queue 向软件发布完成事件。

![SLVC DMA shared-link overview](docs/assets/slvc_dma_overview.svg)

## 60 秒总览

| 维度 | 当前实现 |
| --- | --- |
| 应用问题 | 多个带独立软件上下文的数据源共享一条高速串行或分组链路，并搬运到各自 DDR ring |
| Canonical IP | [`slvc_dma_wrapper`](rtl/integration/slvc_dma_wrapper.v)，filelist 为 [`slvc_dma_512.f`](flows/manifests/slvc_dma_512.f) |
| 数据合同 | 512-bit RX/TX AXI-Stream；64-byte SHDR64 header；最大 payload 4096 byte |
| 虚拟通道 | `flow_id` 匹配 channel context；包级 admission、reservation、ring pointer 和 completion accounting |
| 缓冲策略 | 每通道 fixed ingress buffer，或由 free list 管理的 shared frame pool |
| 流控边界 | Payload `valid/ready` 与 PAUSE/RESUME control-message 通道分离；后者不是网络端到端流控 |
| 实现证据 | Windows ModelSim + Linux Questa；Vivado routed OOC；Nangate45 DC/OpenROAD/OpenRCX/PrimeTime |

## 1. 背景：共享链路上的多源搬运

典型采集系统会把多个业务源汇聚到 Aurora 类串行链路、片内共享 stream，或由 MAC 输出的 packet stream。链路复用减少外部引脚和协议实例，但不会自动解决通道识别、缓冲隔离、DDR ownership、完成通知和反压传播问题。

以下比较是**定性架构分析**，不是对某个厂商 DMA 的性能 benchmark。实际 MCDMA 行为取决于调度器、每通道 queue、共享 AXI master 和软件配置。

| 方案 | 外部系统需要承担 | 隔离与共享资源 | 主要取舍 |
| --- | --- | --- | --- |
| `N x` 单通道 DMA | 外部解帧、分流、每通道 FIFO、多个 CSR/IRQ 和 AXI master 管理 | 独立实例可获得直接隔离 | 控制面和 buffer 重复，资源与集成工作随通道数增长 |
| 集中式 MCDMA 类方案 | 通常仍需匹配其 stream/channel descriptor 模型 | 隔离取决于内部 queue 和 scheduler；共享资源配置不当时可能产生 HOL/backpressure 扩散 | 实例数少，但需要验证具体 IP 的阻塞和 completion 语义 |
| SLVC DMA | 上游只需生成 SHDR64，或选用公开边界 adapter | channel-aware admission、fixed/shared buffer、独立 ring/CQ；DDR、CQ 和 shared pool 仍是有限共享资源 | 针对 shared-link segment 语义定制，并公开 RTL、回归和实现证据 |

## 2. 方案：四个实现选择

### 协议适配留在边界

原生入口是 `Aurora/native SHDR64 -> SLVC DMA`。多个本地源可由 `mcf_endpoint` 仲裁成 shared-link segment；固定 profile 的 `dma_udp_ipv4_to_shdr64_adapter` 可把 Ethernet II / IPv4 IHL=5 / UDP RX packet 转成 SHDR64。MAC/PHY、完整 Ethernet stack 和网络端到端可靠性不属于 DMA Core。

### Header 驱动虚拟通道

SHDR64 的 `flow_id` 和长度先经过 parser，再与软件配置的 channel context 匹配。只有 ring space、ingress storage 和 CQ reservation 同时满足时，frame 才越过 commit 边界。已经接收的 frame 不会被后来请求抢占其预留资源。

### 专有缓冲与共享池并存

固定 ingress 为通道保留确定容量；shared frame pool 用 block free list 让突发流量共享容量。两种 source 在 commit 后由 selector 锁定到 frame 结束，避免 512-bit payload 在 source 之间交织。

### 数据流控与控制消息分离

AXI4-Stream `valid/ready` 处理本地逐拍反压；PAUSE/RESUME 经独立 control-message/UFC 边界传递策略状态。Completion Queue 先写 body、最后发布 owner/valid，避免软件看到部分 CQE。

![SLVC DMA virtual-channel buffering](docs/assets/slvc_dma_virtual_channel_buffering.svg)

<!-- claim:slvc_dma_channel_admission_isolation_directed maturity:verified -->

现有 adapter-to-DMA directed smoke 精确记录了 `packets=2 channels=2 cqes=2 ch0_full_then_ch1=1`：channel 0 无可用空间时，映射到 channel 1 的 packet 仍被接收并产生预期 CQE。该结果只证明这一项 admission 场景，不是任意资源耗尽下的形式证明，也不是 MCDMA 对比实验。

[查看完整数据路径、资源边界和阻塞条件](docs/zh-CN/architecture.md)

## 3. 验证：从协议行为到物理结果

```text
directed and deterministic-random RTL regression
        -> same-clock / dual-clock RX memory profiles
        -> Vivado synth / place / phys-opt / route OOC
        -> Design Compiler mapped handoff
        -> OpenROAD detail route / same-run OpenRCX SPEF
        -> PrimeTime internal setup / hold STA
```

公开回归覆盖 parser、channel admission、fixed/shared buffer、descriptor、CQ ownership、4 KiB AXI boundary、tail WSTRB、random backpressure、reset/drain、CDC FIFO 和 writer outstanding。它是有界 directed verification，不等价于 formal proof、coverage closure 或完整 CDC/RDC signoff。

[查看验证矩阵与精确 PASS marker](docs/zh-CN/verification_matrix.md)

## 4. 当前已核验结果

<!-- claim:slvc_dma_rx_payload_cdc_regression maturity:verified -->
<!-- claim:slvc_dma_rx_payload_cdc_ideal_throughput maturity:verified -->
<!-- claim:slvc_dma_async64_vivado_2022_2_ooc_200m maturity:verified -->
<!-- claim:slvc_dma_c2b4_n45_register_postroute_450 maturity:verified -->

| 层级 | Profile 与 workload | 已核验结果 | 成熟度边界 |
| --- | --- | --- | --- |
| RTL / memory interface | 512 writer `2028` cases；1 MiB ideal-memory workload | 同频 512 与 async512 均为 `64 B/cycle`、W 利用率 `100%`、peak outstanding `4` | RTL/model interface rate，不是板级 DDR 或无损网络吞吐 |
| FPGA | Async64，Vivado 2022.2，`xc7z100ffg900-2`，200 MHz routed OOC | WNS/WHS `+0.152/+0.059 ns`；39,299 LUT、43,671 FF、54 BRAM tiles | 保留 52 条分类 OOC DRC warning；不是 bitstream 或板级实现 |
| ASIC | C2B4 register-expanded RX512；550 MHz DC handoff -> 450 MHz route/PT | PT setup/hold WNS `+0.041322/+0.000341 ns`；DRC/antenna/electrical `0` | 两通道 internal memory subsystem；不是 C4B4、完整 DMA 或 Fmax |

C2B4 同次 route 的 die 为 `1684.865 x 1684.865 um`（`2.83877 mm^2`），core 为 `1644.640 x 1643.600 um`（`2.70313 mm^2`）；standard-cell area 为 `1.04207 mm^2`，core utilization 为 `38.5506%`。这里的 die 是两通道 RX512 memory-subsystem 的 implementation block 边界，不是封装芯片面积。

证据：[RTL/CDC regression](evidence/slvc_dma_rx_payload_cdc_regression_summary.yaml) · [Vivado 2022.2 OOC](evidence/slvc_dma_async64_vivado_2022_2_ooc_summary.yaml) · [C2B4 post-route](evidence/slvc_dma_c2b4_n45_register_postroute_summary.yaml)

## 5. SRAM 研究进展与当前阻塞

<!-- claim:slvc_dma_sram_a5_clock_delivery_canary maturity:verified -->
<!-- claim:slvc_dma_sram_a5_256_area_reduction maturity:verified -->

SRAM A5 是独立的 `partial/blocked` 研究路线，不与上方完成闭合的结果混列。经过审计的 512x128 OpenRAM model 和 routed boundary canary 使用 `d200 + macro_x3`，把 macro clock slew 从 `86.384 ps` 降到 `16.434 ps`；生成的 256x128 macro 面积比 512x128 小 `37.74%`。

当前 proxy minimum-pulse 仍为 `1.5625 ns`，independent true-pulse characterization 尚未完成，因此 C4B4 SRAM DC/P&R/PT 没有启动。面积降低也不能直接扩展为 performance、power 或完整 PPA 改善。

[查看 SRAM model、clock delivery 与 nonclaim](docs/zh-CN/asic_implementation.md)

## 选择集成入口

| 目标 | Canonical top / boundary | 配置与检查 |
| --- | --- | --- |
| 完整 512-bit Shared-Link DMA | [`slvc_dma_wrapper`](rtl/integration/slvc_dma_wrapper.v) | [`slvc_dma_512.f`](flows/manifests/slvc_dma_512.f) · `make sim-dry-run` |
| FPGA OOC timing top | [`frame_dma_wrapper`](rtl/integration/frame_dma_wrapper.v) | `make fpga-ooc-dry-run` |
| 固定 Ethernet/IPv4/UDP RX adaptation | [`dma_udp_ipv4_to_shdr64_adapter`](rtl/adapters/dma_udp_ipv4_to_shdr64_adapter.v) -> `slvc_dma_wrapper` | 默认 defconfig · [协议边界](docs/zh-CN/udp_ipv4_adapter.md) |
| 同频或双时钟 RX memory backend | [`frame_dma_rx_top`](rtl/integration/frame_dma_rx_top.v) | `slvc_dma_512_rx_{wide,async64,async512}_defconfig` |

[查看端口、时钟/reset、bring-up 和 ownership 合同](docs/zh-CN/integration.md)

## 快速检查

不需要商业 EDA 工具的展示完整性检查：

```bash
make showcase-check
```

生成默认配置并查看可执行命令：

```bash
python3 flows/scripts/flowctl.py defconfig --source configs/slvc_dma_512_defconfig
python3 flows/scripts/flowctl.py show-config
python3 flows/scripts/flowctl.py sim-dry-run
```

安装 ModelSim/Questa 后运行 `make sim`。Vivado、DC/PT、ORFS、PDK 和 library 路径只允许出现在 ignored `flows/local/`；公开仓库不分发商业工具产物或工艺数据。

## 文档与发行边界

[接口](docs/zh-CN/interfaces.md) · [RTL 阅读指南](docs/zh-CN/rtl_reading_guide.md) · [双时钟后端](docs/zh-CN/rx_payload_cdc_backends.md) · [FPGA 实现](docs/zh-CN/fpga_implementation.md) · [ASIC 实现](docs/zh-CN/asic_implementation.md) · [Delivery 状态](docs/zh-CN/delivery_status.md) · [Evidence](provenance/evidence.yaml) · [Claims](provenance/claims.yaml)

当前 `main` 是 `v0.1.0-rc1` 之后的展示与开发线。不可变 annotated tag `v0.1.0-rc1` 仍固定原始 release source、evidence 和 checksum，不因本轮文档更新而移动或重建。完整 nonclaim 见[限制](docs/zh-CN/limitations.md)与[公开范围](PUBLIC_SCOPE.md)。
