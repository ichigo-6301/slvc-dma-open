#ifndef DMA_LOOPBACK_REGS_H
#define DMA_LOOPBACK_REGS_H

#include "xil_types.h"

#ifndef XPAR_DMA_CFG_AXI_BASEADDR
#define XPAR_DMA_CFG_AXI_BASEADDR 0x44000000U
#endif

static const u32 DMA_BASE = XPAR_DMA_CFG_AXI_BASEADDR;

static const u32 DMA_EXPECT_IP_ID = 0xFAD00700U;
static const u32 DMA_EXPECT_VERSION = 0x00000010U;
static const u32 DMA_EXPECT_RX_CH_NUM = 13U;
static const u32 DMA_EXPECT_TX_CH_NUM = 13U;

static const u32 DMA_REG_IP_ID         = 0x000U;
static const u32 DMA_REG_VERSION       = 0x004U;
static const u32 DMA_REG_GLOBAL_CTRL   = 0x008U;
static const u32 DMA_REG_GLOBAL_STATUS = 0x00cU;
static const u32 DMA_REG_IRQ_STATUS    = 0x010U;
static const u32 DMA_REG_IRQ_MASK      = 0x014U;
static const u32 DMA_REG_RX_CH_NUM     = 0x018U;
static const u32 DMA_REG_TX_CH_NUM     = 0x01cU;
static const u32 DMA_REG_CQ_BASE_L     = 0x020U;
static const u32 DMA_REG_CQ_BASE_H     = 0x024U;
static const u32 DMA_REG_CQ_SIZE       = 0x028U;
static const u32 DMA_REG_CQ_WR_PTR     = 0x02cU;
static const u32 DMA_REG_CQ_RD_PTR     = 0x030U;
static const u32 DMA_REG_SOFT_RESET    = 0x03cU;
static const u32 DMA_REG_DROP_CNT      = 0x040U;
static const u32 DMA_REG_ERR_CNT       = 0x044U;
static const u32 DMA_REG_DEBUG_STATE   = 0x048U;
static const u32 DMA_REG_FEATURE       = 0x04cU;

static const u32 DMA_TX_CH_BASE        = 0x100U;
static const u32 DMA_RX_CH_BASE        = 0x500U;
static const u32 DMA_TX_DESC_CH_BASE   = 0x900U;
static const u32 DMA_CH_STRIDE         = 0x040U;

static const u32 DMA_CH_CTRL           = 0x000U;
static const u32 DMA_CH_CFG            = 0x004U;
static const u32 DMA_CH_BASE_L         = 0x008U;
static const u32 DMA_CH_BASE_H         = 0x00cU;
static const u32 DMA_TX_CH_LEN         = 0x010U;
static const u32 DMA_CH_SIZE           = 0x010U;
static const u32 DMA_CH_MAX_LEN        = 0x014U;
static const u32 DMA_RX_CH_WR_PTR      = 0x018U;
static const u32 DMA_RX_CH_RD_PTR      = 0x01cU;
static const u32 DMA_CH_USED           = 0x020U;
static const u32 DMA_RX_CH_HIGH_WM     = 0x024U;
static const u32 DMA_RX_CH_LOW_WM      = 0x028U;
static const u32 DMA_CH_STATUS         = 0x02cU;
static const u32 DMA_CH_FRAME_CNT      = 0x030U;
static const u32 DMA_CH_DROP_CNT       = 0x034U;
static const u32 DMA_CH_ERR_CNT        = 0x038U;

static const u32 DMA_TX_DESC_CTRL      = 0x000U;
static const u32 DMA_TX_DESC_BASE_L    = 0x004U;
static const u32 DMA_TX_DESC_BASE_H    = 0x008U;
static const u32 DMA_TX_DESC_SIZE      = 0x00cU;
static const u32 DMA_TX_DESC_RD_PTR    = 0x010U;
static const u32 DMA_TX_DESC_WR_PTR    = 0x014U;
static const u32 DMA_TX_DESC_STATUS    = 0x018U;
static const u32 DMA_TX_DESC_ERR_CNT   = 0x01cU;

static const unsigned DMA_GCTRL_GLOBAL_EN = 0U;
static const unsigned DMA_GCTRL_RX_EN     = 1U;
static const unsigned DMA_GCTRL_TX_EN     = 2U;
static const unsigned DMA_GCTRL_UFC_EN    = 3U;
static const unsigned DMA_GCTRL_IRQ_EN    = 4U;
static const unsigned DMA_GSTATUS_RESET_REJECTED = 11U;

static const unsigned DMA_FEATURE_RX = 0U;
static const unsigned DMA_FEATURE_TX = 1U;
static const unsigned DMA_FEATURE_DESC_Q = 6U;
static const unsigned DMA_FEATURE_MULTI_OUT = 7U;

static const unsigned DMA_RX_CTRL_ENABLE = 0U;
static const unsigned DMA_RX_CTRL_CPL_EN = 2U;
static const unsigned DMA_RX_CTRL_IRQ_EN = 3U;
static const unsigned DMA_RX_CTRL_FC_EN  = 4U;

static const unsigned DMA_TX_CTRL_ENABLE = 0U;
static const unsigned DMA_TX_CTRL_START  = 1U;
static const unsigned DMA_TX_CTRL_CPL_EN = 3U;
static const unsigned DMA_TX_CTRL_IRQ_EN = 4U;

static const unsigned DMA_TX_DESC_CTRL_ENABLE = 0U;
static const unsigned DMA_TX_DESC_CTRL_START  = 1U;
static const unsigned DMA_TX_DESC_CTRL_IRQ_EN = 4U;
static const unsigned DMA_TX_DESC_STATUS_BUSY = 1U;
static const unsigned DMA_TX_DESC_STATUS_EMPTY = 2U;

static const u32 DMA_TC_FC                 = 0x1U;
static const u32 DMA_RX_POL_QUEUE_WITH_FC  = 0x5U;
static const u32 DMA_TX_POL_SINGLE_SHOT    = 0x1U;

static const u8 DMA_ST_FRAME_DONE = 0x01U;
static const u8 DMA_ST_TX_DONE    = 0x44U;

static const u32 DMA_CQE_BYTES          = 64U;
static const u32 DMA_CQE_MAGIC          = 0x45514346U;
static const u32 DMA_CQE_MAGIC_OFF      = 0U;
static const u32 DMA_CQE_STATUS_OFF     = 6U;
static const u32 DMA_CQE_CHANNEL_ID_OFF = 12U;
static const u32 DMA_CQE_DIRECTION_OFF  = 13U;
static const u32 DMA_CQE_ADDR_OFF       = 16U;
static const u32 DMA_CQE_LENGTH_OFF     = 24U;
static const u32 DMA_CQE_ALEN_OFF       = 28U;
static const u32 DMA_CQE_FLOW_ID_OFF    = 44U;
static const u32 DMA_CQE_FRAME_SEQ_OFF  = 40U;
static const u32 DMA_CQE_OWNER_OFF      = 60U;

static const u8 DMA_CQE_DIR_RX = 0x00U;
static const u8 DMA_CQE_DIR_TX = 0x01U;

static const u32 DMA_TX_DESC_BYTES         = 64U;
static const u32 DMA_TX_DESC_CTRL_OFF      = 0U;
static const u32 DMA_TX_DESC_CH_STREAM_OFF = 8U;
static const u32 DMA_TX_DESC_LEN_OFF       = 12U;
static const u32 DMA_TX_DESC_ADDR_LO_OFF   = 16U;
static const u32 DMA_TX_DESC_ADDR_HI_OFF   = 20U;
static const u32 DMA_TX_DESC_SEQ_OFF       = 24U;
static const u32 DMA_TX_DESC_SAMPLE_OFF    = 36U;
static const unsigned DMA_TX_DESC_OWNER_VALID = 0U;

#endif
