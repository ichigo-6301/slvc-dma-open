#ifndef DMA_MMIO_DIAG_H
#define DMA_MMIO_DIAG_H

#include "xil_types.h"

enum DmaProbeStage {
    DMA_PROBE_STAGE_NONE = 0,
    DMA_PROBE_STAGE_BANNER = 1,
    DMA_PROBE_STAGE_PS_REG = 2,
    DMA_PROBE_STAGE_AXI_BRAM = 3,
    DMA_PROBE_STAGE_AXI_GPIO = 4,
    DMA_PROBE_STAGE_DEBUG_BRIDGE = 5,
    DMA_PROBE_STAGE_DMA_CFG = 6
};

void dma_mmio_diag_init(void);
void dma_mmio_diag_configure_tlb(void);
void dma_mmio_diag_set_stage(u32 stage, u32 addr);
u32 dma_mmio_probe_read32(const char *name, u32 addr);

#endif
