# SLVC DMA 中文 RTL 阅读指南

本文面向希望从源码理解 SLVC DMA 数据路径、控制边界和验证方法的 FPGA/ASIC 开发者。
当前功能基线的 native Core 数据宽度固定为 512 bit，SHDR64 固定为 64 byte，最大
payload 为 4096 byte。外部宽度 frontend 可以把 64/128/256/512-bit AXI-Stream
聚合到 512-bit Core，但这不等同于 native Core 已经支持或验证所有宽度。

## 1. 推荐阅读顺序

建议按以下顺序阅读，而不是从最大文件逐行向下看：

1. `rtl/include/dma_defs.vh`：协议常量、寄存器偏移、状态码和功能开关。
2. `rtl/integration/slvc_dma_wrapper.v`：推荐系统接口和时钟域边界。
3. `rtl/integration/frame_dma_wrapper.v`：完整 FPGA OOC 顶层。
4. `rtl/integration/frame_dma_rx_top.v`：RX、TX、CQ、AXI-Lite 和 AXI master 的集成关系。
5. `rtl/rx/dma_rx_parser_pipe.v`：SHDR64 header 的分拍解析与发布。
6. `rtl/rx/dma_rx_channel_match.v`：header metadata 如何选择 RX channel。
7. `rtl/rx/dma_rx_frame_shared_adapter.v` 与 `rtl/rx/dma_frame_shared_pool.v`：共享帧存储。
8. `rtl/rx/dma_axi_write_engine.v`：RX payload 如何写入 AXI4 memory。
9. `rtl/tx/dma_tx_engine.v` 与 `rtl/tx/dma_axi_read_prefetch.v`：descriptor 驱动的 TX replay。
10. `rtl/cq/dma_cq_single_writer.v` 与 `rtl/cq/dma_cq_writer.v`：CQE 的 owner-last 发布。

读完这十个文件后，再根据关注方向进入 channel table、AXI-Lite、CDC 或 Adapter。

## 2. 纯文本模块层次

```text
slvc_dma_wrapper
└── frame_dma_wrapper
    └── frame_dma_rx_top
        ├── RX parser / channel match / admission
        ├── ingress queue 或 shared frame pool
        ├── dma_axi_write_engine
        ├── TX channel / descriptor table
        ├── dma_tx_engine
        │   ├── dma_tx_header_builder
        │   └── dma_axi_read_prefetch
        ├── dma_cq_single_writer / dma_cq_writer
        ├── dma_axil_regs
        ├── dma_ufc_mailbox
        └── RX/TX AXI master arbitration

可选外部边界：
dma_udp_ipv4_to_shdr64_adapter -> slvc_dma_wrapper
frame_dma_rx_axis_width_frontend -> 512-bit Core
slvc_carrier_cdc_adapter -> AXIS/control async FIFO -> Core
frame_dma_rx_aurora_ufc_wrap -> Aurora UFC adapter + Core
mcf_endpoint -> shared-link segment source
```

## 3. RX 数据路径

RX 的基本顺序如下：

```text
512-bit RX AXIS
  -> elastic FIFO
  -> SHDR64 parser
  -> channel match 和静态 context
  -> admission/resource reservation
  -> ingress queue 或 shared frame pool
  -> 64-bit AXI write engine
  -> payload 完成
  -> CQE body 写入
  -> CQE owner/valid 发布
```

### Header 与 segment 边界

当前 Core 中一个 512-bit beat 正好等于 64-byte SHDR64。segment 的 payload 长度来自
header 的 `payload_len`，主 Core 不依赖 AXI4-Stream `TLAST` 来判断 segment 结束。
`dma_rx_parser_pipe` 先锁存 header，再分阶段计算 CRC、验证固定字段并发布 metadata。

### Channel match 与 context

parser 输出的是当前包携带的动态 metadata，例如 flow/message ID、payload length、frame
sequence 和 timestamp。`dma_rx_channel_table` 保存的是软件配置和硬件维护的静态 channel
context，例如 base、size、read/write pointer、policy 和 counter。`dma_rx_channel_match`
把两者组合，但不拥有表状态。

### Admission 与 reservation

`frame_dma_rx_top` 的 RX 状态机依次读取 channel context、释放软件已消费空间、计算 ring
free space，并检查 ingress/CQ 等资源。只有这些条件全部满足后才进入 commit。reservation
使已经接收的包不会在写入前被后来请求抢占空间。

### Shared frame pool

`dma_rx_frame_shared_adapter` 为每个完整包建立 context，并把 payload 放入
`dma_frame_shared_pool`。pool 使用 block free list 共享容量，不为每个 channel 固定分配
一个深 FIFO。metadata commit 是可见性边界：未完整提交的 frame 不能被读出；读完后必须
显式 release，block 才重新进入 free list。

### AXI 写入

`dma_axi_write_engine` 的输入索引单位是 64-bit word。它把连续 word 规划成 AXI burst，
同时限制最大 burst、4KB 边界和 outstanding 数量。AW、W 和 B 进度独立跟踪；只有响应
完成后，上层才能把 payload 写入视为结束。

## 4. TX 数据路径

TX 支持 single-shot channel context 和 descriptor ring 两类入口，后半段发送路径共用：

```text
channel/descriptor 选择
  -> context capture
  -> CQ space check
  -> dma_tx_header_builder
  -> SHDR64 header beat
  -> dma_axi_read_prefetch
  -> payload beats
  -> TX completion/CQE
  -> descriptor RD_PTR 或 channel 状态更新
```

### Descriptor ownership

`dma_tx_desc_channel_table` 保存 ring base、size 和 RD/WR pointer。`dma_tx_engine` 读取并解析
descriptor 后锁存本次发送 context。descriptor 的推进必须发生在明确提交边界，不能仅因
AR/R channel 已经开始就提前改变软件可见 ownership。

### Read prefetch 与 backpressure

`dma_axi_read_prefetch` 把 64-bit AXI RDATA 聚合为 512-bit TX payload beat。FIFO 同时隔离
memory latency 和下游 `tx_axis_tready`。当 TX 被 backpressure 阻塞时，已发布的 valid/data
保持稳定；预取器通过 reservation 防止已发出的 outstanding read 超出本地 FIFO 容量。

### Header 与最后一拍

`dma_tx_header_builder` 生成固定 64-byte header 和 CRC。payload 的最后一拍由长度计数决定，
不足 64 byte 的尾部保持在内部长度语义中；主 shared-link segment 不依赖 TLAST。

## 5. CQ 与控制面

### Owner-last 发布

`dma_cq_writer` 先写 CQE body，再单独写 owner/valid 所在 word。软件只能在 owner 被发布后
消费 entry，因此不会读取到部分写入的 CQE。`dma_cq_single_writer` 在 RX/TX 两类 producer
之间串行化请求，并维护 shadow pointer 和 ring-space 检查。

### AXI-Lite

`dma_axil_regs` 将地址分为 global、TX channel、RX channel 和 TX descriptor region。读写
各自经过 decode/sample/execute/response 阶段，允许 CSR 操作增加固定周期，同时避免大范围
组合 decode 直接驱动多通道表。protected register 和硬件维护 pointer 只在合法阶段提交。

### Event 与 counter

数据面先形成一拍 event，再由 channel table 或寄存器模块更新 counter、status 和 IRQ。
这样同周期的 descriptor、CSR 和完成事件可以在各自 lane 中先锁存，再统一更新，避免
“后一个赋值覆盖前一个事件”的问题。

### Soft reset

hard reset 仍是各模块低有效异步 reset。soft reset 是同一 `aclk` 域的一拍同步事件，只清
FSM、valid、pointer、occupancy 和 pending 控制状态，不清空大容量 payload/data RAM。

## 6. Carrier、CDC 与 Adapter 边界

### Carrier CDC

`slvc_carrier_cdc_adapter` 使用 `dma_axis_async_fifo` 和 `dma_ctrl_msg_async_fifo` 把 carrier
时钟域与 Core 时钟域隔离。`dma_async_fifo` 在两侧分别维护 binary/Gray pointer，并使用
两级同步器传递 Gray pointer。full/empty 只能由本域指针和同步后的对端指针判断。

### Aurora UFC

`dma_aurora_ufc_adapter` 把一条 Core 控制消息拆成 Aurora UFC beat，并在接收侧重新组合。
`frame_dma_rx_aurora_ufc_wrap` 是 carrier 集成示例，不是 DMA Core 的协议定义层。

### MCF

`mcf_endpoint` 在多个本地 source 之间仲裁并产生 shared-link segment。PAUSE/RESUME 属于
控制消息和策略层；它们不能被理解为等同于 AXI4-Stream `tready` 的逐拍流控。

### 外部 RX 宽度 frontend

`frame_dma_rx_axis_width_frontend` 和 `dma_axis_width_pack_512` 可把较窄外部 beat 聚合为
512-bit Core beat。该路径只改变 beat 切分，不改变 SHDR64。当前 native wrapper 仍对非
512-bit Core 配置执行硬保护，其他宽度需要独立 source closure、回归和实现证据。

### UDP/IPv4 Adapter

`dma_udp_ipv4_to_shdr64_adapter` 接受固定 Ethernet II / IPv4 IHL=5 / UDP profile，剥离
42-byte protocol header，并利用 22-byte carry 形成 SHDR64 后的 payload stream。固定 merge
避免通用 barrel shifter。它不支持 VLAN、IPv6、IP options、fragment reassembly、UDP
checksum 或 FCS，也不提供 UDP 端到端流控。late error 只能阻止后续输出并报告 drop，不能
回滚已经被下游握手接收的数据。

Error Matrix 曾出现额外 drop 的原因是 testbench 在真实 valid/ready 握手前撤销 `tvalid`，
不是 Adapter RTL bug。阅读本模块时应把“输入 beat 已握手”作为 packet 状态推进的唯一依据。

## 7. 关键单位

| 名称 | 单位 | 当前 profile |
| --- | --- | --- |
| SHDR64 | byte | 64 byte |
| Core RX/TX beat | bit/byte | 512 bit / 64 byte |
| AXI memory word | bit/byte | 64 bit / 8 byte |
| payload length | byte | 最大 4096 byte |
| aligned length | byte | 向 64 byte 对齐 |
| ring pointer | entry 或 byte | 取决于所属 ring，需结合信号名和寄存器定义 |
| pool block | Core beat | 512-bit payload block |

特别注意 `payload_len`、`aligned_len`、`*_words`、`*_beats` 和 `*_ptr` 不能互换。RX AXI 写
路径通常先把 byte length 换算为 64-bit word 数；shared pool 的 block 则以 512-bit beat
为粒度。

## 8. 核心状态机

| 文件 | 状态/信号 | 阅读重点 |
| --- | --- | --- |
| `frame_dma_rx_top.v` | `RX_*` | parse、lookup、space check、commit、collect、drop |
| `frame_dma_rx_top.v` | `WR_*` | payload command、写响应、CQE、frame pop |
| `dma_rx_parser_pipe.v` | `ST_IDLE/CRC/VALIDATE/OUT` | header 锁存和输出弹性 |
| `dma_frame_shared_pool.v` | `RD_*`、`REL_*` | metadata read、payload drain、block release |
| `dma_tx_engine.v` | `ST_DESC_*`、`ST_HEADER`、`ST_SEND_PAY` | descriptor 和 replay 共用路径 |
| `dma_cq_writer.v` | `ST_BODY_*`、`ST_OWNER_*` | owner-last 软件可见性 |
| `dma_axil_regs.v` | `RD_*`、`WR_*` | CSR pipeline 和保护检查 |
| `dma_udp_ipv4_to_shdr64_adapter.v` | `ST_*` | header 校验、carry merge、drop drain |

## 9. 关键定向测试

以下测试适合与 RTL 对照阅读：

- `modelsim/run_rtl_v13_parser_pipeline.do`：pipelined parser、CRC 和 output handshake。
- `modelsim/run_rtl_v33e19_shared_frame_pool.do`：shared pool allocation/read/release。
- `modelsim/run_rtl_v33e20a_hybrid_rx_ingress_minimal.do`：普通 ingress 与 frame ingress 集成。
- `modelsim/run_rtl_v33e20a23_full_arch_throughput.do`：完整架构稳态吞吐。
- `modelsim/run_rtl_v33e20a23_w_prefetch_fifo.do`：RX writer prefetch/burst 边界。
- `modelsim/run_rtl_v28_tx_descriptor_queue.do`：descriptor ownership 和 TX queue。
- `modelsim/run_rtl_v31_tx_desc_status_pipeline.do`：descriptor 状态事件 pipeline。
- `modelsim/run_rtl_v33e20a10_tx_cq_space_check_pipeline.do`：TX CQ 空间检查。
- `modelsim/run_rtl_v15_axil_read_pipeline.do`：AXI-Lite read pipeline。
- `modelsim/run_rtl_v33e20a106_udp_to_shdr_error_matrix.do`：Adapter drop reason 和恢复。

## 10. Legacy 与兼容模块

- `dma_rx_payload_buffer` 是旧式 payload buffer，shared pool profile 下不是首选主路径。
- `dma_cq_writer` 保留单来源 writer；完整 profile 可由 `dma_cq_single_writer` 串行化 RX/TX。
- 文件名和信号中的 `UFC` 是现有控制消息兼容命名，不意味着 Core 被 Aurora 绑定。
- 外部 width packer 是边界适配，不是 native Core 宽度参数化完成的证明。
- 仓库中未进入公开 allowlist 的历史 smoke/实验模块用于设计演进记录，不应默认当作发行 top。

## 11. 阅读每个首要文件时关注什么

| 文件 | 建议信号或问题 |
| --- | --- |
| `dma_defs.vh` | header/CQE bytes、channel count、feature macro、register offset |
| `slvc_dma_wrapper.v` | RX/TX clock、native 512-bit guard、控制消息接口 |
| `frame_dma_wrapper.v` | OOC 边界、Core 端口映射、TX 独立时钟 |
| `frame_dma_rx_top.v` | `rx_state`、`wr_state`、`event_*`、CQ reservation、AXI arbiter |
| `dma_rx_parser_pipe.v` | `in_ready`、`out_valid`、CRC chunk、soft reset |
| `dma_rx_channel_table.v` | protected CSR、RD pointer、counter event lane |
| `dma_rx_frame_shared_adapter.v` | context reservation、RDQ、pool input boundary |
| `dma_frame_shared_pool.v` | free FIFO、metadata commit、read/release FSM |
| `dma_axi_write_engine.v` | 4KB split、burst queue、AW/W/B outstanding |
| `dma_tx_engine.v` | descriptor context、CQ check、header/payload handshake |
| `dma_axi_read_prefetch.v` | reserved beats、pack lane、RRESP/flush |
| `dma_cq_single_writer.v` | RX/TX request selection、shadow pointer、commit event |
| `dma_axil_regs.v` | read/write region pipeline、soft reset pulse、IRQ |
| `dma_async_fifo.v` | binary/Gray conversion、two-flop sync、full/empty |
| `dma_udp_ipv4_to_shdr64_adapter.v` | 42-byte strip、22-byte carry、drop drain、late error |

## 12. 注释等价性

本注释分支使用 `scripts/check_rtl_comment_only.py` 对功能基线与带注释 RTL 进行词法比较。
脚本识别行注释、块注释、字符串、转义标识符、compiler directive 和 Verilog 数字 literal，
删除普通注释与空白后比较 token 序列。任何功能 token 变化都会使检查失败。

示例：

```bash
python3 scripts/check_rtl_comment_only.py --base <base-commit> --paths rtl
```

中文只出现在普通注释和 Markdown 中；现有综合属性和工具语义注释保持不变。
