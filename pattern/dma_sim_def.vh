`ifndef DMA_SIM_DEF_VH
`define DMA_SIM_DEF_VH

`include "../rtl/dma_defs.vh"

`define DMA_SIM_MEM_BYTES     (4*1024*1024)
`define DMA_PKT_MEM_BYTES     (1024*1024)
`define DMA_SYS_MEM_PATH      tb.sys_mem
`define DMA_REF_MEM_PATH      tb.ref_mem
`define DMA_PKT_MEM_PATH      tb.pkt_mem

`endif
