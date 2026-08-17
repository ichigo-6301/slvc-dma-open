/*
 * DMA PL-loopback connectivity and throughput test in plain C.
 *
 * This variant reuses the SDK C template platform initialization path
 * so that UART/cache setup matches the known-good standalone examples.
 */

#include "platform.h"
#include "dma_mmio_diag.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xtime_l.h"
#include "dma_loopback_regs.h"

#define DMA_TEST_CONNECTIVITY 0U
#define DMA_TEST_THROUGHPUT   1U

/* User controls: run connectivity first, then select a throughput frame count. */
#ifndef DMA_TEST_MODE
#define DMA_TEST_MODE DMA_TEST_THROUGHPUT
#define DMA_THROUGHPUT_FRAME_COUNT 1024U
#endif
#ifndef DMA_THROUGHPUT_FRAME_COUNT
#define DMA_THROUGHPUT_FRAME_COUNT 1U
#endif

static const u32 DMA_CH0 = 0U;
static const u16 TEST_FLOW_ID = 0x1234U;
static const u16 TEST_STREAM_ID = 0x0028U;
static const u32 PL_CLOCK_MHZ = 100U;

/* Use high DDR addresses to avoid the ELF, heap, and stack near 0x0010_0000. */
static const u32 TX_SRC_ADDR  = 0x10000000U;
static const u32 RX_DST_ADDR  = 0x11000000U;
static const u32 CQ_BASE_ADDR = 0x12000000U;
static const u32 RX_RING_SIZE = 0x00010000U;
static const u32 CQ_SIZE      = 16U;
static const u32 MAX_PAYLOAD  = 4096U;
static const u32 TEST_LENGTHS[] = {64U, 128U, 256U, 1024U, 4096U};

/* Continuous descriptor-mode test regions. */
static const u32 THR_TX_SRC_ADDR  = 0x10000000U;
static const u32 THR_RX_DST_ADDR  = 0x11000000U;
static const u32 THR_CQ_BASE_ADDR = 0x12000000U;
static const u32 THR_DESC_BASE_ADDR = 0x13000000U;
static const u32 THR_FRAME_BYTES = 4096U;
static const u32 THR_RX_RING_SIZE = 0x00800000U;
static const u32 THR_CQ_SIZE = 4096U;
static const u32 THR_DESC_SIZE = 2048U * 64U;
static const u32 THR_MAX_FRAMES = 1024U;

struct CqeInfo {
    u32 index;
    u8 direction;
    u8 status;
    u8 channel;
    u16 flow_id;
    u32 addr;
    u32 length;
    u32 aligned_len;
    u32 frame_seq;
    u32 owner;
};

static inline u32 bit(unsigned b)
{
    return 1U << b;
}

static inline u32 dma_read(u32 off)
{
    return Xil_In32(DMA_BASE + off);
}

static inline void dma_write(u32 off, u32 value)
{
    Xil_Out32(DMA_BASE + off, value);
}

static inline void dma_write_sync(u32 off, u32 value)
{
    Xil_Out32(DMA_BASE + off, value);
    __asm__ volatile("dsb");
}

static inline u8 mem_read8(u32 addr)
{
    return *(volatile u8 *)addr;
}

static inline u16 mem_read16(u32 addr)
{
    u16 v = 0U;
    v |= (u16)mem_read8(addr + 0U);
    v |= (u16)mem_read8(addr + 1U) << 8;
    return v;
}

static inline u32 mem_read32(u32 addr)
{
    u32 v = 0U;
    v |= (u32)mem_read8(addr + 0U);
    v |= (u32)mem_read8(addr + 1U) << 8;
    v |= (u32)mem_read8(addr + 2U) << 16;
    v |= (u32)mem_read8(addr + 3U) << 24;
    return v;
}

static inline void mem_write32(u32 addr, u32 value)
{
    volatile u8 *p = (volatile u8 *)addr;
    p[0] = (u8)(value >> 0);
    p[1] = (u8)(value >> 8);
    p[2] = (u8)(value >> 16);
    p[3] = (u8)(value >> 24);
}

static inline u32 dma_ch_addr(u32 base, u32 ch, u32 off)
{
    return base + ch * DMA_CH_STRIDE + off;
}

static void delay_cycles(volatile u32 cycles)
{
    while (cycles--) {
        __asm__ volatile("nop");
    }
}

static u32 align64(u32 value)
{
    return (value + 63U) & ~63U;
}

static void fill_pattern(u32 addr, u32 length, u32 seed)
{
    volatile u8 *p = (volatile u8 *)addr;
    u32 i;
    for (i = 0U; i < length; ++i) {
        p[i] = (u8)((seed + i * 17U + (i >> 2)) & 0xffU);
    }
}

static void clear_region(u32 addr, u32 length)
{
    volatile u8 *p = (volatile u8 *)addr;
    u32 i;
    for (i = 0U; i < length; ++i) {
        p[i] = 0U;
    }
}

static void dump_regs(void)
{
    const u32 rx = dma_ch_addr(DMA_RX_CH_BASE, DMA_CH0, 0U);
    const u32 tx = dma_ch_addr(DMA_TX_CH_BASE, DMA_CH0, 0U);

    xil_printf("REG GLOBAL : STATUS=%08x IRQ=%08x DEBUG=%08x DROP=%08x ERR=%08x\r\n",
               dma_read(DMA_REG_GLOBAL_STATUS),
               dma_read(DMA_REG_IRQ_STATUS),
               dma_read(DMA_REG_DEBUG_STATE),
               dma_read(DMA_REG_DROP_CNT),
               dma_read(DMA_REG_ERR_CNT));
    xil_printf("REG CQ     : WR=%08x RD=%08x\r\n",
               dma_read(DMA_REG_CQ_WR_PTR),
               dma_read(DMA_REG_CQ_RD_PTR));
    xil_printf("REG RX0    : STATUS=%08x USED=%08x WR=%08x RD=%08x FRM=%08x DROP=%08x ERR=%08x\r\n",
               dma_read(rx + DMA_CH_STATUS),
               dma_read(rx + DMA_CH_USED),
               dma_read(rx + DMA_RX_CH_WR_PTR),
               dma_read(rx + DMA_RX_CH_RD_PTR),
               dma_read(rx + DMA_CH_FRAME_CNT),
               dma_read(rx + DMA_CH_DROP_CNT),
               dma_read(rx + DMA_CH_ERR_CNT));
    xil_printf("REG TX0    : STATUS=%08x FRM=%08x ERR=%08x\r\n",
               dma_read(tx + DMA_CH_STATUS),
               dma_read(tx + DMA_CH_FRAME_CNT),
               dma_read(tx + DMA_CH_ERR_CNT));
}

static void dump_mismatch_window(u32 src, u32 dst, u32 offset, u32 length)
{
    const u32 start = (offset > 8U) ? (offset - 8U) : 0U;
    u32 end = offset + 8U;
    u32 i;

    if (end > length) {
        end = length;
    }

    xil_printf("PAYLOAD window src[%08x] dst[%08x] around off=%d\r\n",
               src + start, dst + start, (int)offset);
    for (i = start; i < end; ++i) {
        xil_printf("  +%04d exp=%02x got=%02x\r\n",
                   (int)i,
                   mem_read8(src + i),
                   mem_read8(dst + i));
    }
}

static void parse_cqe_at(u32 cq_base, u32 index, struct CqeInfo *out)
{
    const u32 addr = cq_base + index * DMA_CQE_BYTES;
    out->index = index;
    out->owner = mem_read32(addr + DMA_CQE_OWNER_OFF);
    out->direction = mem_read8(addr + DMA_CQE_DIRECTION_OFF);
    out->status = mem_read8(addr + DMA_CQE_STATUS_OFF);
    out->channel = mem_read8(addr + DMA_CQE_CHANNEL_ID_OFF);
    out->flow_id = mem_read16(addr + DMA_CQE_FLOW_ID_OFF);
    out->addr = mem_read32(addr + DMA_CQE_ADDR_OFF);
    out->length = mem_read32(addr + DMA_CQE_LENGTH_OFF);
    out->aligned_len = mem_read32(addr + DMA_CQE_ALEN_OFF);
    out->frame_seq = mem_read32(addr + DMA_CQE_FRAME_SEQ_OFF);
}

static void parse_cqe(u32 index, struct CqeInfo *out)
{
    parse_cqe_at(CQ_BASE_ADDR, index, out);
}

static int find_cqe(u8 direction, u8 status, u16 flow_id, u32 length, u32 payload_addr, struct CqeInfo *found)
{
    u32 poll;
    for (poll = 0U; poll < 200000U; ++poll) {
        u32 i;
        Xil_DCacheInvalidateRange(CQ_BASE_ADDR, CQ_SIZE * DMA_CQE_BYTES);
        for (i = 0U; i < CQ_SIZE; ++i) {
            const u32 base = CQ_BASE_ADDR + i * DMA_CQE_BYTES;
            struct CqeInfo cqe;
            if (mem_read32(base + DMA_CQE_MAGIC_OFF) != DMA_CQE_MAGIC) {
                continue;
            }
            parse_cqe(i, &cqe);
            if ((cqe.owner != 0U) &&
                (cqe.direction == direction) &&
                (cqe.status == status) &&
                (cqe.channel == DMA_CH0) &&
                (cqe.flow_id == flow_id) &&
                (cqe.length == length) &&
                (cqe.addr == payload_addr)) {
                *found = cqe;
                return 0;
            }
        }
        delay_cycles(100U);
    }

    xil_printf("CQE timeout dir=%02x status=%02x flow=%04x len=%d addr=%08x\r\n",
               direction, status, flow_id, (int)length, payload_addr);
    for (poll = 0U; poll < CQ_SIZE; ++poll) {
        const u32 base = CQ_BASE_ADDR + poll * DMA_CQE_BYTES;
        if (mem_read32(base + DMA_CQE_MAGIC_OFF) == DMA_CQE_MAGIC) {
            struct CqeInfo cqe;
            parse_cqe(poll, &cqe);
            xil_printf("CQE[%d] owner=%08x dir=%02x st=%02x ch=%d flow=%04x len=%d alen=%d addr=%08x\r\n",
                       (int)poll, cqe.owner, cqe.direction, cqe.status,
                       cqe.channel, cqe.flow_id, (int)cqe.length,
                       (int)cqe.aligned_len, cqe.addr);
        }
    }
    return -1;
}

static int compare_payload(u32 src, u32 dst, u32 length)
{
    u32 i;
    Xil_DCacheInvalidateRange(dst, align64(length));
    for (i = 0U; i < length; ++i) {
        const u8 exp = mem_read8(src + i);
        const u8 got = mem_read8(dst + i);
        if (exp != got) {
            xil_printf("PAYLOAD mismatch offset=%d exp=%02x got=%02x src=%08x dst=%08x\r\n",
                       (int)i, exp, got, src + i, dst + i);
            dump_mismatch_window(src, dst, i, length);
            return -1;
        }
    }
    return 0;
}

static void dma_program_cq(void)
{
    dma_write(DMA_REG_IRQ_MASK, 0xffffffffU);
    dma_write(DMA_REG_CQ_BASE_L, CQ_BASE_ADDR);
    dma_write(DMA_REG_CQ_BASE_H, 0U);
    dma_write(DMA_REG_CQ_SIZE, CQ_SIZE);
    dma_write(DMA_REG_CQ_RD_PTR, 0U);
}

static void dma_program_rx_channel(void)
{
    const u32 rx = dma_ch_addr(DMA_RX_CH_BASE, DMA_CH0, 0U);
    const u32 rx_cfg = ((u32)TEST_FLOW_ID << 16) |
                       (DMA_RX_POL_QUEUE_WITH_FC << 4) |
                       DMA_TC_FC;
    const u32 rx_ctrl = bit(DMA_RX_CTRL_ENABLE) |
                        bit(DMA_RX_CTRL_CPL_EN) |
                        bit(DMA_RX_CTRL_IRQ_EN) |
                        bit(DMA_RX_CTRL_FC_EN);

    dma_write(rx + DMA_CH_CFG, rx_cfg);
    dma_write(rx + DMA_CH_BASE_L, RX_DST_ADDR);
    dma_write(rx + DMA_CH_BASE_H, 0U);
    dma_write(rx + DMA_CH_SIZE, RX_RING_SIZE);
    dma_write(rx + DMA_CH_MAX_LEN, MAX_PAYLOAD);
    dma_write(rx + DMA_RX_CH_HIGH_WM, 0x00008000U);
    dma_write(rx + DMA_RX_CH_LOW_WM,  0x00002000U);
    dma_write(rx + DMA_CH_CTRL, rx_ctrl);
}

static void dma_program_tx_channel(u32 payload_len)
{
    const u32 tx = dma_ch_addr(DMA_TX_CH_BASE, DMA_CH0, 0U);
    const u32 tx_cfg = ((u32)TEST_FLOW_ID << 16) |
                       (DMA_TX_POL_SINGLE_SHOT << 4) |
                       DMA_TC_FC;

    dma_write(tx + DMA_CH_CFG, tx_cfg);
    dma_write(tx + DMA_CH_BASE_L, TX_SRC_ADDR);
    dma_write(tx + DMA_CH_BASE_H, 0U);
    dma_write(tx + DMA_TX_CH_LEN, payload_len);
}

static void dma_program_global_ctrl(void)
{
    dma_write(DMA_REG_GLOBAL_CTRL,
              bit(DMA_GCTRL_GLOBAL_EN) |
              bit(DMA_GCTRL_RX_EN) |
              bit(DMA_GCTRL_TX_EN) |
              bit(DMA_GCTRL_UFC_EN) |
              bit(DMA_GCTRL_IRQ_EN));
}

static int dma_reset_and_wait_idle(void)
{
    u32 poll;
    dma_write(DMA_REG_SOFT_RESET, 1U);
    for (poll = 0U; poll < 200000U; ++poll) {
        const u32 gstatus = dma_read(DMA_REG_GLOBAL_STATUS);
        if ((gstatus & bit(DMA_GSTATUS_RESET_REJECTED)) != 0U) {
            xil_printf("DMA reset rejected GLOBAL_STATUS=%08x DEBUG=%08x\r\n",
                       gstatus, dma_read(DMA_REG_DEBUG_STATE));
            return -1;
        }
        if (poll >= 1000U) {
            return 0;
        }
        delay_cycles(100U);
    }
    xil_printf("DMA reset wait timeout GLOBAL_STATUS=%08x DEBUG=%08x\r\n",
               dma_read(DMA_REG_GLOBAL_STATUS),
               dma_read(DMA_REG_DEBUG_STATE));
    return -1;
}

static void clear_case_regions(u32 payload_len, u32 case_id)
{
    const u32 aligned_len = align64(payload_len);
    clear_region(TX_SRC_ADDR, aligned_len);
    clear_region(RX_DST_ADDR, RX_RING_SIZE);
    clear_region(CQ_BASE_ADDR, CQ_SIZE * DMA_CQE_BYTES);
    fill_pattern(TX_SRC_ADDR, payload_len, 0x30U + case_id);
    Xil_DCacheFlushRange(TX_SRC_ADDR, aligned_len);
    Xil_DCacheFlushRange(RX_DST_ADDR, RX_RING_SIZE);
    Xil_DCacheFlushRange(CQ_BASE_ADDR, CQ_SIZE * DMA_CQE_BYTES);
}

static int wait_rx_used(u32 expected)
{
    const u32 rx = dma_ch_addr(DMA_RX_CH_BASE, DMA_CH0, 0U);
    u32 poll;
    for (poll = 0U; poll < 200000U; ++poll) {
        const u32 used = dma_read(rx + DMA_CH_USED);
        if (used == expected) {
            return 0;
        }
        delay_cycles(100U);
    }
    xil_printf("RX_USED timeout expected=%d got=%08x\r\n",
               (int)expected, dma_read(rx + DMA_CH_USED));
    return -1;
}

static int run_one_case(u32 payload_len, u32 case_id)
{
    const u32 rx = dma_ch_addr(DMA_RX_CH_BASE, DMA_CH0, 0U);
    const u32 tx = dma_ch_addr(DMA_TX_CH_BASE, DMA_CH0, 0U);
    const u32 aligned_len = align64(payload_len);
    struct CqeInfo tx_cqe;
    struct CqeInfo rx_cqe;
    u32 cq_consume_ptr;

    xil_printf("CASE len=%d start\r\n", (int)payload_len);

    if (dma_reset_and_wait_idle() != 0) {
        dump_regs();
        return -1;
    }

    clear_case_regions(payload_len, case_id);
    dma_program_cq();
    dma_program_rx_channel();
    dma_program_tx_channel(payload_len);
    dma_program_global_ctrl();

    dma_write(tx + DMA_CH_CTRL,
              bit(DMA_TX_CTRL_ENABLE) |
              bit(DMA_TX_CTRL_START) |
              bit(DMA_TX_CTRL_CPL_EN) |
              bit(DMA_TX_CTRL_IRQ_EN));

    if (find_cqe(DMA_CQE_DIR_TX, DMA_ST_TX_DONE, TEST_FLOW_ID, payload_len, TX_SRC_ADDR, &tx_cqe) != 0) {
        dump_regs();
        return -1;
    }
    if (find_cqe(DMA_CQE_DIR_RX, DMA_ST_FRAME_DONE, TEST_FLOW_ID, payload_len, RX_DST_ADDR, &rx_cqe) != 0) {
        dump_regs();
        return -1;
    }
    if (compare_payload(TX_SRC_ADDR, RX_DST_ADDR, payload_len) != 0) {
        dump_regs();
        return -1;
    }
    if (wait_rx_used(aligned_len) != 0) {
        dump_regs();
        return -1;
    }

    dma_write(rx + DMA_RX_CH_RD_PTR, aligned_len);
    if (wait_rx_used(0U) != 0) {
        dump_regs();
        return -1;
    }

    cq_consume_ptr = (((tx_cqe.index > rx_cqe.index) ? tx_cqe.index : rx_cqe.index) + 1U) % CQ_SIZE;
    dma_write(DMA_REG_CQ_RD_PTR, cq_consume_ptr);
    dma_write(DMA_REG_IRQ_STATUS, 0xffffffffU);

    xil_printf("LEN=%d TX_CQE=OK(idx=%d) RX_CQE=OK(idx=%d) CMP=OK\r\n",
               (int)payload_len, (int)tx_cqe.index, (int)rx_cqe.index);
    xil_printf("    TX_STATUS=%08x RX_STATUS=%08x IRQ_STATUS=%08x CQ_NEXT=%08x\r\n",
               dma_read(tx + DMA_CH_STATUS),
               dma_read(rx + DMA_CH_STATUS),
               dma_read(DMA_REG_IRQ_STATUS),
               cq_consume_ptr);
    return 0;
}

static int board_probe_phase(void)
{
    u32 ip_id;
    u32 version;
    u32 feature;
    u32 rx_ch_num;
    u32 tx_ch_num;

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_BANNER, 0U);
    xil_printf("\r\nDMA LOOPBACK NEW TEST START mode=%d frames=%d\r\n",
               (int)DMA_TEST_MODE, (int)DMA_THROUGHPUT_FRAME_COUNT);
    xil_printf("DMA AXI-Lite base: %08x\r\n", DMA_BASE);
    xil_printf("STDOUT UART base : %08x\r\n", STDOUT_BASEADDRESS);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_PS_REG, STDOUT_BASEADDRESS);
    (void)dma_mmio_probe_read32("PS7_UART0", STDOUT_BASEADDRESS);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_AXI_BRAM, XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR);
    (void)dma_mmio_probe_read32("AXI_BRAM", XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_AXI_GPIO, XPAR_AXI_GPIO_0_BASEADDR);
    (void)dma_mmio_probe_read32("AXI_GPIO", XPAR_AXI_GPIO_0_BASEADDR);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_DEBUG_BRIDGE, XPAR_DEBUG_BRIDGE_0_BASEADDR);
    (void)dma_mmio_probe_read32("DEBUG_BRIDGE", XPAR_DEBUG_BRIDGE_0_BASEADDR);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_DMA_CFG, DMA_BASE + DMA_REG_IP_ID);
    ip_id = dma_mmio_probe_read32("DMA_IP_ID", DMA_BASE + DMA_REG_IP_ID);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_DMA_CFG, DMA_BASE + DMA_REG_VERSION);
    version = dma_mmio_probe_read32("DMA_VERSION", DMA_BASE + DMA_REG_VERSION);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_DMA_CFG, DMA_BASE + DMA_REG_FEATURE);
    feature = dma_mmio_probe_read32("DMA_FEATURE", DMA_BASE + DMA_REG_FEATURE);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_DMA_CFG, DMA_BASE + DMA_REG_RX_CH_NUM);
    rx_ch_num = dma_mmio_probe_read32("DMA_RX_CH_NUM", DMA_BASE + DMA_REG_RX_CH_NUM);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_DMA_CFG, DMA_BASE + DMA_REG_TX_CH_NUM);
    tx_ch_num = dma_mmio_probe_read32("DMA_TX_CH_NUM", DMA_BASE + DMA_REG_TX_CH_NUM);

    dma_mmio_diag_set_stage(DMA_PROBE_STAGE_NONE, 0U);

    xil_printf("IP_ID=%08x VERSION=%08x FEATURE=%08x RX_CH_NUM=%d TX_CH_NUM=%d\r\n",
               ip_id, version, feature, (int)rx_ch_num, (int)tx_ch_num);

    if ((ip_id != DMA_EXPECT_IP_ID) ||
        (version != DMA_EXPECT_VERSION) ||
        ((feature & bit(DMA_FEATURE_RX)) == 0U) ||
        ((feature & bit(DMA_FEATURE_TX)) == 0U) ||
        (rx_ch_num != DMA_EXPECT_RX_CH_NUM) ||
        (tx_ch_num != DMA_EXPECT_TX_CH_NUM) ||
        ((DMA_TEST_MODE == DMA_TEST_THROUGHPUT) &&
         (((feature & bit(DMA_FEATURE_DESC_Q)) == 0U) ||
          ((feature & bit(DMA_FEATURE_MULTI_OUT)) == 0U)))) {
        xil_printf("DMA identity probe failed exp_ip=%08x exp_ver=%08x exp_rx=%d exp_tx=%d\r\n",
                   DMA_EXPECT_IP_ID, DMA_EXPECT_VERSION,
                   (int)DMA_EXPECT_RX_CH_NUM, (int)DMA_EXPECT_TX_CH_NUM);
        dump_regs();
        return -1;
    }
    return 0;
}

static int dma_loopback_phase(void)
{
    u32 i;
    for (i = 0U; i < (sizeof(TEST_LENGTHS) / sizeof(TEST_LENGTHS[0])); ++i) {
        if (run_one_case(TEST_LENGTHS[i], i) != 0) {
            xil_printf("DMA LOOPBACK C TEST FAIL at len=%d\r\n", (int)TEST_LENGTHS[i]);
            return -1;
        }
    }
    return 0;
}

struct ErrorSnapshot {
    u32 global_drop;
    u32 global_err;
    u32 rx_drop;
    u32 rx_err;
    u32 tx_err;
    u32 desc_err;
};

struct ThroughputResult {
    u32 frame_count;
    u32 payload_bytes;
    XTime e2e_ticks;
    XTime steady_ticks;
};

static void take_error_snapshot(struct ErrorSnapshot *out)
{
    const u32 rx = dma_ch_addr(DMA_RX_CH_BASE, DMA_CH0, 0U);
    const u32 tx = dma_ch_addr(DMA_TX_CH_BASE, DMA_CH0, 0U);
    const u32 desc = dma_ch_addr(DMA_TX_DESC_CH_BASE, DMA_CH0, 0U);

    out->global_drop = dma_read(DMA_REG_DROP_CNT);
    out->global_err = dma_read(DMA_REG_ERR_CNT);
    out->rx_drop = dma_read(rx + DMA_CH_DROP_CNT);
    out->rx_err = dma_read(rx + DMA_CH_ERR_CNT);
    out->tx_err = dma_read(tx + DMA_CH_ERR_CNT);
    out->desc_err = dma_read(desc + DMA_TX_DESC_ERR_CNT);
}

static int error_snapshot_is_zero(const struct ErrorSnapshot *value)
{
    return (value->global_drop == 0U) && (value->global_err == 0U) &&
           (value->rx_drop == 0U) && (value->rx_err == 0U) &&
           (value->tx_err == 0U) && (value->desc_err == 0U);
}

static int throughput_frame_count_valid(u32 frame_count)
{
    return (frame_count == 1U) || (frame_count == 2U) ||
           (frame_count == 5U) || (frame_count == 32U) ||
           (frame_count == 1024U);
}

static void fill_throughput_frame(u32 addr, u32 frame_index)
{
    volatile u8 *p = (volatile u8 *)addr;
    const u32 seed = 0x13579bdfU ^ (frame_index * 0x9e3779b9U);
    u32 i;

    for (i = 0U; i < THR_FRAME_BYTES; ++i) {
        const u32 mixed = seed ^ (i * 17U) ^ (i >> 3) ^ (frame_index << 5);
        p[i] = (u8)(mixed ^ (mixed >> 8) ^ (mixed >> 16) ^ (mixed >> 24));
    }
}

static void write_throughput_descriptor(u32 index)
{
    const u32 desc = THR_DESC_BASE_ADDR + index * DMA_TX_DESC_BYTES;
    const u32 src = THR_TX_SRC_ADDR + index * THR_FRAME_BYTES;

    mem_write32(desc + DMA_TX_DESC_CH_STREAM_OFF,
                ((u32)TEST_STREAM_ID << 16) | TEST_FLOW_ID);
    mem_write32(desc + DMA_TX_DESC_LEN_OFF, THR_FRAME_BYTES);
    mem_write32(desc + DMA_TX_DESC_ADDR_LO_OFF, src);
    mem_write32(desc + DMA_TX_DESC_ADDR_HI_OFF, 0U);
    mem_write32(desc + DMA_TX_DESC_SEQ_OFF, index + 1U);
    mem_write32(desc + DMA_TX_DESC_SAMPLE_OFF, 0x20000000U | index);
    __asm__ volatile("dmb");
    mem_write32(desc + DMA_TX_DESC_CTRL_OFF, bit(DMA_TX_DESC_OWNER_VALID));
}

static void prepare_throughput_memory(u32 frame_count)
{
    const u32 payload_bytes = frame_count * THR_FRAME_BYTES;
    u32 i;

    clear_region(THR_TX_SRC_ADDR, payload_bytes);
    clear_region(THR_RX_DST_ADDR, THR_RX_RING_SIZE);
    clear_region(THR_CQ_BASE_ADDR, THR_CQ_SIZE * DMA_CQE_BYTES);
    clear_region(THR_DESC_BASE_ADDR, THR_DESC_SIZE);

    for (i = 0U; i < frame_count; ++i) {
        fill_throughput_frame(THR_TX_SRC_ADDR + i * THR_FRAME_BYTES, i);
        write_throughput_descriptor(i);
    }

    Xil_DCacheFlushRange(THR_TX_SRC_ADDR, payload_bytes);
    Xil_DCacheFlushRange(THR_RX_DST_ADDR, THR_RX_RING_SIZE);
    Xil_DCacheFlushRange(THR_CQ_BASE_ADDR, THR_CQ_SIZE * DMA_CQE_BYTES);
    Xil_DCacheFlushRange(THR_DESC_BASE_ADDR, THR_DESC_SIZE);
    __asm__ volatile("dsb");
}

static void program_throughput_dma(u32 frame_count)
{
    const u32 rx = dma_ch_addr(DMA_RX_CH_BASE, DMA_CH0, 0U);
    const u32 tx = dma_ch_addr(DMA_TX_CH_BASE, DMA_CH0, 0U);
    const u32 desc = dma_ch_addr(DMA_TX_DESC_CH_BASE, DMA_CH0, 0U);
    const u32 rx_cfg = ((u32)TEST_FLOW_ID << 16) |
                       (DMA_RX_POL_QUEUE_WITH_FC << 4) | DMA_TC_FC;
    const u32 rx_ctrl = bit(DMA_RX_CTRL_ENABLE) |
                        bit(DMA_RX_CTRL_CPL_EN) |
                        bit(DMA_RX_CTRL_IRQ_EN) |
                        bit(DMA_RX_CTRL_FC_EN);
    const u32 tx_cfg = ((u32)TEST_FLOW_ID << 16) |
                       (DMA_TX_POL_SINGLE_SHOT << 4) | DMA_TC_FC;

    dma_write(DMA_REG_IRQ_MASK, 0xffffffffU);
    dma_write(DMA_REG_CQ_BASE_L, THR_CQ_BASE_ADDR);
    dma_write(DMA_REG_CQ_BASE_H, 0U);
    dma_write(DMA_REG_CQ_SIZE, THR_CQ_SIZE);
    dma_write(DMA_REG_CQ_RD_PTR, 0U);

    dma_write(rx + DMA_CH_CFG, rx_cfg);
    dma_write(rx + DMA_CH_BASE_L, THR_RX_DST_ADDR);
    dma_write(rx + DMA_CH_BASE_H, 0U);
    dma_write(rx + DMA_CH_SIZE, THR_RX_RING_SIZE);
    dma_write(rx + DMA_CH_MAX_LEN, THR_FRAME_BYTES);
    dma_write(rx + DMA_RX_CH_HIGH_WM, 0x00700000U);
    dma_write(rx + DMA_RX_CH_LOW_WM, 0x00200000U);
    dma_write(rx + DMA_CH_CTRL, rx_ctrl);

    dma_write(tx + DMA_CH_CFG, tx_cfg);
    dma_write(tx + DMA_CH_BASE_L, THR_TX_SRC_ADDR);
    dma_write(tx + DMA_CH_BASE_H, 0U);
    dma_write(tx + DMA_TX_CH_LEN, THR_FRAME_BYTES);
    dma_write(tx + DMA_CH_CTRL,
              bit(DMA_TX_CTRL_ENABLE) |
              bit(DMA_TX_CTRL_CPL_EN) |
              bit(DMA_TX_CTRL_IRQ_EN));

    dma_write(desc + DMA_TX_DESC_BASE_L, THR_DESC_BASE_ADDR);
    dma_write(desc + DMA_TX_DESC_BASE_H, 0U);
    dma_write(desc + DMA_TX_DESC_SIZE, THR_DESC_SIZE);
    dma_write(desc + DMA_TX_DESC_RD_PTR, 0U);
    dma_write(desc + DMA_TX_DESC_WR_PTR, frame_count * DMA_TX_DESC_BYTES);
    dma_program_global_ctrl();
    __asm__ volatile("dsb");
}

static int validate_throughput_cqe(const struct CqeInfo *cqe,
                                   u32 frame_count,
                                   u8 *tx_seen,
                                   u8 *rx_seen,
                                   u32 *tx_count,
                                   u32 *rx_count)
{
    u32 index;
    u32 expected_addr;

    if ((cqe->owner == 0U) || (cqe->channel != DMA_CH0) ||
        (cqe->flow_id != TEST_FLOW_ID) ||
        (cqe->length != THR_FRAME_BYTES) ||
        (cqe->aligned_len != THR_FRAME_BYTES) ||
        (cqe->frame_seq == 0U) || (cqe->frame_seq > frame_count)) {
        xil_printf("CQE common mismatch idx=%d owner=%08x dir=%02x st=%02x ch=%d flow=%04x len=%d alen=%d seq=%d\r\n",
                   (int)cqe->index, cqe->owner, cqe->direction, cqe->status,
                   (int)cqe->channel, cqe->flow_id, (int)cqe->length,
                   (int)cqe->aligned_len, (int)cqe->frame_seq);
        return -1;
    }

    index = cqe->frame_seq - 1U;
    if (cqe->direction == DMA_CQE_DIR_TX) {
        expected_addr = THR_TX_SRC_ADDR + index * THR_FRAME_BYTES;
        if ((cqe->status != DMA_ST_TX_DONE) ||
            (cqe->addr != expected_addr) || tx_seen[index]) {
            xil_printf("TX CQE mismatch seq=%d st=%02x addr=%08x exp=%08x duplicate=%d\r\n",
                       (int)cqe->frame_seq, cqe->status, cqe->addr,
                       expected_addr, (int)tx_seen[index]);
            return -1;
        }
        tx_seen[index] = 1U;
        *tx_count += 1U;
    } else if (cqe->direction == DMA_CQE_DIR_RX) {
        expected_addr = THR_RX_DST_ADDR + index * THR_FRAME_BYTES;
        if ((cqe->status != DMA_ST_FRAME_DONE) ||
            (cqe->addr != expected_addr) || rx_seen[index]) {
            xil_printf("RX CQE mismatch seq=%d st=%02x addr=%08x exp=%08x duplicate=%d\r\n",
                       (int)cqe->frame_seq, cqe->status, cqe->addr,
                       expected_addr, (int)rx_seen[index]);
            return -1;
        }
        rx_seen[index] = 1U;
        *rx_count += 1U;
    } else {
        xil_printf("CQE direction mismatch idx=%d dir=%02x\r\n",
                   (int)cqe->index, cqe->direction);
        return -1;
    }
    return 0;
}

static int poll_throughput_cq(u32 frame_count,
                              XTime start_time,
                              XTime *first_rx_time,
                              XTime *last_rx_time)
{
    static u8 tx_seen[1024];
    static u8 rx_seen[1024];
    const u32 expected_total = frame_count * 2U;
    const XTime timeout_ticks = (XTime)COUNTS_PER_SECOND * 60U;
    u32 consumer = 0U;
    u32 tx_count = 0U;
    u32 rx_count = 0U;
    u32 total = 0U;
    u32 i;

    for (i = 0U; i < THR_MAX_FRAMES; ++i) {
        tx_seen[i] = 0U;
        rx_seen[i] = 0U;
    }
    *first_rx_time = 0U;
    *last_rx_time = 0U;

    while (total < expected_total) {
        const u32 producer = dma_read(DMA_REG_CQ_WR_PTR);
        while ((consumer != producer) && (total < expected_total)) {
            const u32 entry_addr = THR_CQ_BASE_ADDR + consumer * DMA_CQE_BYTES;
            struct CqeInfo cqe;
            XTime now;

            Xil_DCacheInvalidateRange(entry_addr, DMA_CQE_BYTES);
            __asm__ volatile("dsb");
            if (mem_read32(entry_addr + DMA_CQE_MAGIC_OFF) != DMA_CQE_MAGIC) {
                xil_printf("CQE magic mismatch idx=%d magic=%08x producer=%d\r\n",
                           (int)consumer,
                           mem_read32(entry_addr + DMA_CQE_MAGIC_OFF),
                           (int)producer);
                return -1;
            }
            parse_cqe_at(THR_CQ_BASE_ADDR, consumer, &cqe);
            if (validate_throughput_cqe(&cqe, frame_count,
                                        tx_seen, rx_seen,
                                        &tx_count, &rx_count) != 0) {
                return -1;
            }
            XTime_GetTime(&now);
            if (cqe.direction == DMA_CQE_DIR_RX) {
                if (rx_count == 1U) {
                    *first_rx_time = now;
                }
                if (rx_count == frame_count) {
                    *last_rx_time = now;
                }
            }
            consumer = (consumer + 1U) % THR_CQ_SIZE;
            total += 1U;
        }

        {
            XTime now;
            XTime_GetTime(&now);
            if ((now - start_time) > timeout_ticks) {
                xil_printf("CQ timeout total=%d/%d tx=%d rx=%d producer=%d consumer=%d\r\n",
                           (int)total, (int)expected_total,
                           (int)tx_count, (int)rx_count,
                           (int)dma_read(DMA_REG_CQ_WR_PTR), (int)consumer);
                return -1;
            }
        }
    }

    if ((tx_count != frame_count) || (rx_count != frame_count) ||
        (*first_rx_time == 0U) || (*last_rx_time == 0U)) {
        xil_printf("CQ count mismatch tx=%d rx=%d expected=%d\r\n",
                   (int)tx_count, (int)rx_count, (int)frame_count);
        return -1;
    }
    dma_write(DMA_REG_CQ_RD_PTR, consumer);
    return 0;
}

static int wait_descriptor_complete(u32 frame_count)
{
    const u32 desc = dma_ch_addr(DMA_TX_DESC_CH_BASE, DMA_CH0, 0U);
    const u32 expected_rd = frame_count * DMA_TX_DESC_BYTES;
    u32 poll;

    for (poll = 0U; poll < 200000U; ++poll) {
        const u32 rd = dma_read(desc + DMA_TX_DESC_RD_PTR);
        const u32 status = dma_read(desc + DMA_TX_DESC_STATUS);
        if ((rd == expected_rd) &&
            ((status & bit(DMA_TX_DESC_STATUS_BUSY)) == 0U) &&
            ((status & bit(DMA_TX_DESC_STATUS_EMPTY)) != 0U)) {
            return 0;
        }
        delay_cycles(100U);
    }
    xil_printf("DESC completion timeout rd=%08x exp=%08x status=%08x err=%08x\r\n",
               dma_read(desc + DMA_TX_DESC_RD_PTR), expected_rd,
               dma_read(desc + DMA_TX_DESC_STATUS),
               dma_read(desc + DMA_TX_DESC_ERR_CNT));
    return -1;
}

static void print_u64_hex(const char *label, u64 value)
{
    xil_printf("%s0x%08x%08x", label, (u32)(value >> 32), (u32)value);
}

static void print_fixed3(const char *label, u64 milli)
{
    xil_printf("%s%d.%03d", label,
               (int)(milli / 1000U), (int)(milli % 1000U));
}

static void report_throughput_window(const char *name,
                                     u32 payload_bytes,
                                     XTime ticks,
                                     int report_model_efficiency)
{
    u64 pl_cycles;
    u64 score_milli;
    u64 mbps_milli;
    u64 gbps_milli;

    if (ticks == 0U) {
        xil_printf("%s window invalid: zero ticks\r\n", name);
        return;
    }
    pl_cycles = ((u64)ticks * (PL_CLOCK_MHZ * 1000000U) +
                 ((u64)COUNTS_PER_SECOND / 2U)) /
                (u64)COUNTS_PER_SECOND;
    if (pl_cycles == 0U) {
        pl_cycles = 1U;
    }
    score_milli = ((u64)payload_bytes * 1000U) / pl_cycles;
    mbps_milli = ((u64)payload_bytes * (u64)COUNTS_PER_SECOND * 1000U) /
                 ((u64)ticks * 1000000U);
    gbps_milli = (mbps_milli * 8U) / 1000U;

    xil_printf("%s payload_bytes=%d ", name, (int)payload_bytes);
    print_u64_hex("ticks=", ticks);
    xil_printf(" ");
    print_u64_hex("pl_cycles=", pl_cycles);
    xil_printf("\r\n  ");
    print_fixed3("MB/s/MHz=", score_milli);
    xil_printf(" ");
    print_fixed3("MB/s@100MHz=", mbps_milli);
    xil_printf(" ");
    print_fixed3("Gb/s@100MHz=", gbps_milli);
    if (report_model_efficiency) {
        xil_printf(" ");
        print_fixed3("vs_HP0_SHARED_4B/cycle=", score_milli * 25U);
        xil_printf("%%");
    }
    xil_printf("\r\n");
}

static int dma_throughput_phase(struct ThroughputResult *result)
{
    const u32 frame_count = DMA_THROUGHPUT_FRAME_COUNT;
    const u32 payload_bytes = frame_count * THR_FRAME_BYTES;
    const u32 rx = dma_ch_addr(DMA_RX_CH_BASE, DMA_CH0, 0U);
    const u32 desc = dma_ch_addr(DMA_TX_DESC_CH_BASE, DMA_CH0, 0U);
    struct ErrorSnapshot before;
    struct ErrorSnapshot after;
    XTime start_time;
    XTime first_rx_time;
    XTime last_rx_time;

    if (!throughput_frame_count_valid(frame_count)) {
        xil_printf("Unsupported DMA_THROUGHPUT_FRAME_COUNT=%d; use 1,2,5,32,1024\r\n",
                   (int)frame_count);
        return -1;
    }
    if (frame_count > THR_MAX_FRAMES) {
        return -1;
    }

    xil_printf("THROUGHPUT setup frames=%d frame_bytes=%d path=TX0->512b slice->RX0 HP0=64b clock=100MHz\r\n",
               (int)frame_count, (int)THR_FRAME_BYTES);
    if (dma_reset_and_wait_idle() != 0) {
        return -1;
    }
    prepare_throughput_memory(frame_count);
    program_throughput_dma(frame_count);
    take_error_snapshot(&before);
    if (!error_snapshot_is_zero(&before)) {
        xil_printf("Nonzero counters before run drop=%d err=%d rx_drop=%d rx_err=%d tx_err=%d desc_err=%d\r\n",
                   (int)before.global_drop, (int)before.global_err,
                   (int)before.rx_drop, (int)before.rx_err,
                   (int)before.tx_err, (int)before.desc_err);
        return -1;
    }

    dma_write_sync(desc + DMA_TX_DESC_CTRL,
                   bit(DMA_TX_DESC_CTRL_ENABLE) |
                   bit(DMA_TX_DESC_CTRL_START) |
                   bit(DMA_TX_DESC_CTRL_IRQ_EN));
    XTime_GetTime(&start_time);

    if (poll_throughput_cq(frame_count, start_time,
                           &first_rx_time, &last_rx_time) != 0) {
        dump_regs();
        return -1;
    }
    if (wait_descriptor_complete(frame_count) != 0) {
        dump_regs();
        return -1;
    }
    if (wait_rx_used(payload_bytes) != 0) {
        dump_regs();
        return -1;
    }
    if (compare_payload(THR_TX_SRC_ADDR, THR_RX_DST_ADDR, payload_bytes) != 0) {
        dump_regs();
        return -1;
    }

    dma_write(rx + DMA_RX_CH_RD_PTR, payload_bytes);
    if (wait_rx_used(0U) != 0) {
        dump_regs();
        return -1;
    }
    dma_write(DMA_REG_IRQ_STATUS, 0xffffffffU);
    take_error_snapshot(&after);
    if (!error_snapshot_is_zero(&after)) {
        xil_printf("Nonzero counters after run drop=%d err=%d rx_drop=%d rx_err=%d tx_err=%d desc_err=%d\r\n",
                   (int)after.global_drop, (int)after.global_err,
                   (int)after.rx_drop, (int)after.rx_err,
                   (int)after.tx_err, (int)after.desc_err);
        dump_regs();
        return -1;
    }

    result->frame_count = frame_count;
    result->payload_bytes = payload_bytes;
    result->e2e_ticks = last_rx_time - start_time;
    result->steady_ticks = (frame_count > 1U) ?
                           (last_rx_time - first_rx_time) : 0U;

    xil_printf("THROUGHPUT correctness PASS tx_cqe=%d rx_cqe=%d desc_rd=%08x rx_used=0 payload_compare=PASS\r\n",
               (int)frame_count, (int)frame_count,
               dma_read(desc + DMA_TX_DESC_RD_PTR));
    report_throughput_window("hardware_end_to_end", payload_bytes,
                             result->e2e_ticks, 1);
    if (frame_count > 1U) {
        report_throughput_window("first_frame_excluded",
                                 (frame_count - 1U) * THR_FRAME_BYTES,
                                 result->steady_ticks, 0);
    } else {
        xil_printf("first_frame_excluded N/A for one frame\r\n");
    }
    xil_printf("BOUNDARY: 64-bit HP0, 100 MHz synchronous PL loopback; not Async64 CDC, DDR peak, Fmax, or 64 B/cycle Writer evidence.\r\n");
    return 0;
}

int main(void)
{
    int rc;
    struct ThroughputResult throughput_result;

    init_platform();
    dma_mmio_diag_init();
    dma_mmio_diag_configure_tlb();

    if (board_probe_phase() != 0) {
        xil_printf("DMA LOOPBACK NEW TEST FAIL\r\n");
        cleanup_platform();
        return -1;
    }

    if (DMA_TEST_MODE == DMA_TEST_CONNECTIVITY) {
        rc = dma_loopback_phase();
    } else if (DMA_TEST_MODE == DMA_TEST_THROUGHPUT) {
        rc = dma_throughput_phase(&throughput_result);
    } else {
        xil_printf("Invalid DMA_TEST_MODE=%d\r\n", (int)DMA_TEST_MODE);
        rc = -1;
    }

    if (rc != 0) {
        xil_printf("DMA LOOPBACK NEW TEST FAIL\r\n");
        cleanup_platform();
        return -1;
    }

    xil_printf("DMA LOOPBACK NEW TEST PASS\r\n");
    cleanup_platform();
    return 0;
}
