# 架构

数据路径由共享 segment stream、RX parser/channel match、frame pool、AXI4 write
engine、CQ writer 和 TX replay 组成。`slvc_dma_wrapper` 是通用集成顶层；
`frame_dma_wrapper` 是本次 FPGA OOC timing top。

RX 首先解析固定 64-byte SHDR64 header，再依据 channel metadata 进行 admission，
payload 写入目标 DDR ring。CQ body 先写入，owner/valid 最后可见，避免软件看到
部分完成记录。TX 根据 descriptor 从 DDR 读取 payload，并重新生成 SHDR64 segment。

carrier adapter 与 MCF endpoint 是边界模块：前者适配可选物理 carrier，后者可将
多个本地源汇聚为共享链路输入。二者不改变 DMA 的 DDR/CQ ownership 语义。
