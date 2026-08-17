#include "dma_mmio_diag.h"

#include "xil_exception.h"
#include "xil_io.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xparameters.h"

static volatile u32 g_probe_stage = DMA_PROBE_STAGE_NONE;
static volatile u32 g_last_addr = 0U;
static volatile u32 g_last_value = 0U;

static u32 read_dfsr(void)
{
    u32 value;
    __asm__ volatile("mrc p15, 0, %0, c5, c0, 0" : "=r"(value));
    return value;
}

static u32 read_dfar(void)
{
    u32 value;
    __asm__ volatile("mrc p15, 0, %0, c6, c0, 0" : "=r"(value));
    return value;
}

static u32 read_ifsr(void)
{
    u32 value;
    __asm__ volatile("mrc p15, 0, %0, c5, c0, 1" : "=r"(value));
    return value;
}

static u32 read_ifar(void)
{
    u32 value;
    __asm__ volatile("mrc p15, 0, %0, c6, c0, 2" : "=r"(value));
    return value;
}

static u32 read_spsr(void)
{
    u32 value;
    __asm__ volatile("mrs %0, spsr" : "=r"(value));
    return value;
}

static u32 read_lr(void)
{
    u32 value;
    __asm__ volatile("mov %0, lr" : "=r"(value));
    return value;
}

static void dma_abort_hang(const char *kind)
{
    xil_printf("\r\nEXCEPTION %s\r\n", kind);
    xil_printf("  stage=%08x last_addr=%08x\r\n", g_probe_stage, g_last_addr);
    xil_printf("  DFSR=%08x DFAR=%08x\r\n", read_dfsr(), read_dfar());
    xil_printf("  IFSR=%08x IFAR=%08x\r\n", read_ifsr(), read_ifar());
    xil_printf("  LR_abt=%08x SPSR=%08x\r\n", read_lr(), read_spsr());
    while (1) {
    }
}

static void dma_data_abort_handler(void *data)
{
    (void)data;
    dma_abort_hang("DATA_ABORT");
}

static void dma_prefetch_abort_handler(void *data)
{
    (void)data;
    dma_abort_hang("PREFETCH_ABORT");
}

static void dma_undef_handler(void *data)
{
    (void)data;
    dma_abort_hang("UNDEFINED");
}

void dma_mmio_diag_init(void)
{
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_DATA_ABORT_INT,
                                 (Xil_ExceptionHandler)dma_data_abort_handler,
                                 0);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_PREFETCH_ABORT_INT,
                                 (Xil_ExceptionHandler)dma_prefetch_abort_handler,
                                 0);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_UNDEFINED_INT,
                                 (Xil_ExceptionHandler)dma_undef_handler,
                                 0);
}

void dma_mmio_diag_configure_tlb(void)
{
    Xil_SetTlbAttributes(0x40000000U, DEVICE_MEMORY);
    Xil_SetTlbAttributes(0x41000000U, DEVICE_MEMORY);
    Xil_SetTlbAttributes(0x43000000U, DEVICE_MEMORY);
    Xil_SetTlbAttributes(0x44000000U, DEVICE_MEMORY);
    __asm__ volatile("dsb");
    __asm__ volatile("isb");
}

void dma_mmio_diag_set_stage(u32 stage, u32 addr)
{
    g_probe_stage = stage;
    g_last_addr = addr;
}

u32 dma_mmio_probe_read32(const char *name, u32 addr)
{
    u32 value;
    xil_printf("PROBE before ");
    xil_printf("%s", name);
    xil_printf(" @ %08x\r\n", addr);
    g_last_addr = addr;
    value = Xil_In32(addr);
    __asm__ volatile("dsb");
    __asm__ volatile("isb");
    g_last_value = value;
    xil_printf("PROBE after  ");
    xil_printf("%s", name);
    xil_printf(" @ %08x = %08x\r\n", addr, value);
    return value;
}
