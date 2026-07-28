# 验证

## 验证层级

SLVC DMA 将协议行为、接口吞吐、FPGA 实现和 ASIC 实现分开记录。一个层级 PASS 不会自动提升相邻层级的成熟度。

| 层级 | 检查内容 | 当前证据 |
| --- | --- | --- |
| Release core RTL | parser、channel table、hybrid ingress、shared pool、descriptor、CQ、AXI-Lite、W prefetch | Windows ModelSim 与 IC_EDA Questa 十项固定 marker |
| Optional UDP adapter | boundary/parser、random packet、error/reset/stall、adapter-to-DMA channel mapping | 两个 simulator host 四项 regression |
| RX memory backend | same-clock 512、async64、async512、CDC/reset、AW planner、4 KiB/tail、response error | 两个 simulator host 的 profile-specific marker |
| FPGA OOC | synth、place、phys-opt、route、setup/hold、CDC/bus-skew 与资源 | Vivado 2018.3 profile matrix；独立 Vivado 2022.2 async64 |
| ASIC physical | mapped handoff、detail route、same-run SPEF、PT setup/hold/electrical | C2B4 register-expanded internal profile |

## Release-Bound Regression

release-bound regression 使用 Windows ModelSim SE-64 2020.4 和 IC_EDA Linux Questa Sim-64 10.7c，覆盖 TX channel table、完整架构 throughput、hybrid RX ingress、shared frame pool、parser、AXI-Lite read、TX CQ space、descriptor queue/status 和 W prefetch FIFO。

runner 始终核对 10 个 frozen-core PASS marker。默认 adapter-enabled defconfig 再增加 4 个 adapter marker，共 14 项。可选 RX-wide defconfig 关闭 adapter，并增加 2 个 wide-backend marker，共 12 项。每个双时钟 defconfig 调度 10 项 core、1 条公共 CDC bridge command 和 2 条 width-specific command；Async64 需要 15 个 marker，Async512 需要 14 个。

完整命令、行为和 marker 见[验证矩阵](verification_matrix.md)。

## Channel Admission 隔离场景

adapter-to-DMA smoke 的固定 marker 为：

```text
PASS tb_rtl_v33e20a107_udp_to_dma_smoke packets=2 channels=2 cqes=2 ch0_full_then_ch1=1
```

测试先让 channel 0 缺少可用 ring space，再发送映射到 channel 1 的 packet，并检查 channel 1 admission、payload 和 CQE。该结果证明这一个 per-channel ring-space 场景中的继续前进，不证明 shared pool/CQ/AXI 耗尽时的 universal non-blocking，也不构成 MCDMA 性能比较。

## RX Writer 与 CDC

512 writer test 覆盖 2028 cases，包括长度与 tail、4 KiB split、最大 outstanding、AW/W/B random backpressure、response error、reset 和理想 memory throughput。Async64/Async512 额外覆盖：

- command、ordered 512-bit payload 和 tagged completion 三条 CDC FIFO；
- 六种 clock profile、random phase、两种 clock-stop 场景；
- Gray-pointer bus-skew constraint 和 directional CDC report；
- source-credit zero/short/exact/surplus、1/2/7/31-cycle AW stall 和 simultaneous events；
- bounded soft-reset quiesce/drain 与 protocol-error software visibility。

理想 1 MiB workload 测得 same-clock 512 与 async512 为 64 B/cycle，async64 为 8 B/cycle；三者 W-channel utilization 都为 100%，peak outstanding 都为 4。这是 ready memory model 下的 RTL interface rate，不是 board DDR throughput。

## 运行入口

```text
make slvc_dma_512_defconfig
make sim-dry-run
make sim
```

公开展示与 flow-contract 检查不需要 simulator：

```text
make showcase-check
```

Directed 与 deterministic-random PASS 不等价于 functional coverage closure、formal proof、任意参数组合证明或完整 CDC/RDC signoff。固定 source commit、log checksum 和 caveat 位于 `evidence/` 与 `provenance/`。
