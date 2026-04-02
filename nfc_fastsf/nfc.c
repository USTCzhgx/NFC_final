#include "nfc.h"
#include "nfc_reg.h"
#include "ftl_mon.h"
#include "xaxidma.h"
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_printf.h"

#include <string.h>   /* memcpy/memset */


#define NFC_STAT_TOP_STATUS_SHIFT    9           /* bits [10:9] */
#define NFC_STAT_TOP_STATUS_MASK     (3u << NFC_STAT_TOP_STATUS_SHIFT)

static inline u32 NFC_TopStatus(u32 st)
{
    return (st & NFC_STAT_TOP_STATUS_MASK) >> NFC_STAT_TOP_STATUS_SHIFT;
}

/* Wait until request FIFO is NOT almost full. */
static inline void NFC_WaitReqFifoSpace(void)
{
    while (NFC_GetStatus() & NFC_STAT_REQ_AFULL_MASK) {
        /* busy wait */
    }
}

/* Wait until controller is not BUSY(01) and not WAIT(10).
 * Completed states: IDLE(00) or READY(11).
 */
static inline void NFC_WaitDone(void)
{
    u32 ts;
    do {
        ts = NFC_TopStatus(NFC_GetStatus());
    } while ((ts == 1u) || (ts == 2u));
}

static int s_dma_inited = 0;
static XAxiDma s_axi_dma;

u8  BBT_Bitmap[BBT_SIZE_BYTES];
u32 BBT[BBT_SIZE_WORDS];
static u32 s_bbt_page_buf[NAND_PAGE_MAIN_SIZE_BYTES / 4];

/* ==========================================================
 *                     NFC BASIC COMMANDS
 * ========================================================== */

void NFC_Reset(void)
{
    NFC_WaitReqFifoSpace();
    NFC_SetOpcode(NFC_CMD_RESET);
    NFC_Start();
    NFC_WaitDone();
}

void NFC_SetTimingMode(void)
{
    NFC_WaitReqFifoSpace();
    NFC_SetOpcode(NFC_CMD_SET_Timing);
    NFC_Start();
    NFC_WaitDone();
}

void NFC_SetConfiguration(void)
{
    NFC_WaitReqFifoSpace();
    NFC_SetOpcode(NFC_CMD_SET_Configuration);
    NFC_Start();
    NFC_WaitDone();
}

void NFC_GetFeatures(void)
{
    NFC_WaitReqFifoSpace();
    NFC_SetOpcode(NFC_CMD_GET_FEATURE);
    NFC_Start();
    NFC_WaitDone();
}

void NFC_ReadParameter(void)
{
    NFC_WaitReqFifoSpace();
    NFC_SetOpcode(NFC_CMD_READ_PARAM1);
    NFC_Start();
    NFC_WaitDone();
}

void Read_BBT_Bitmap(void)
{
    Read(BBT_ADDRESS, BBT_SIZE_BYTES, BBT);
    memcpy(BBT_Bitmap, BBT, BBT_SIZE_BYTES);
}

int Write_BBT_Bitmap(void)
{
    memset(s_bbt_page_buf, 0xFF, sizeof(s_bbt_page_buf));
    memcpy(s_bbt_page_buf, BBT_Bitmap, BBT_SIZE_BYTES);

    NFC_Erase(BBT_ADDRESS, 1);

    if (Write(BBT_ADDRESS, NAND_PAGE_MAIN_SIZE_BYTES, s_bbt_page_buf) != XST_SUCCESS) {
        xil_printf("Write_BBT_Bitmap failed at address 0x%08X%08X\r\n",
                   (unsigned)(u32)(BBT_ADDRESS >> 32),
                   (unsigned)(u32)(BBT_ADDRESS & 0xFFFFFFFFu));
        return XST_FAILURE;
    }

    xil_printf("Write_BBT_Bitmap done at address 0x%08X%08X\r\n",
               (unsigned)(u32)(BBT_ADDRESS >> 32),
               (unsigned)(u32)(BBT_ADDRESS & 0xFFFFFFFFu));
    return XST_SUCCESS;
}

/* print BBT */
void Print_Bad_Block_Info(void)
{
    u32 bad_cnt = 0;
    u32 total_blocks = BLOCK_NUM;

    xil_printf("\r\n========================================\r\n");
    xil_printf("      Bad Block Table (Bitmap Dump)     \r\n");
    xil_printf("========================================\r\n");
    xil_printf("[List View]\r\n");
    for (u32 blk = 0; blk < total_blocks; blk++) {
        if (IS_BAD_BLOCK(blk)) {
            xil_printf(" -> Block [%4d] is MARKED BAD\r\n", blk);
            bad_cnt++;
        }
    }

    if (bad_cnt == 0) {
        xil_printf(" -> No Bad Blocks found (Perfect Chip!).\r\n");
    }

    xil_printf("\r\n----------------------------------------\r\n");
    xil_printf(" Summary: %d Bad Blocks found in %d Blocks\r\n", bad_cnt, total_blocks);
    xil_printf(" Bad Block Rate: %d.%d%%\r\n",
               (bad_cnt * 100) / total_blocks,
               ((bad_cnt * 1000) / total_blocks) % 10);
    xil_printf("----------------------------------------\r\n");
}

void NFC_ScanBadBlocks(void)
{
	static u32 page0_buf[4];
    u32 bad_cnt = 0;

    memset(BBT_Bitmap, 0, sizeof(BBT_Bitmap));
    memset(BBT, 0, sizeof(BBT));

    xil_printf("\r\n========================================\r\n");
    xil_printf("      Sequential Bad Block Scan         \r\n");
    xil_printf("========================================\r\n");

    for (u32 blk = 0; blk < BLOCK_NUM; blk++) {
        u64 page0_addr = MAKE_NAND_ADDR((u16)blk, 0, 0, 0, 0);

        NFC_Erase(page0_addr, 1);
        memset(page0_buf, 0xFF, sizeof(page0_buf));

        if (Read(page0_addr, sizeof(page0_buf), page0_buf) != XST_SUCCESS) {
            xil_printf("Block [%4d] read failed, mark as bad\r\n", blk);
            MARK_BAD_BLOCK(blk);
            bad_cnt++;
            continue;
        }

        if ((page0_buf[0] & 0xFFFFu) == 0x0000u) {
            MARK_BAD_BLOCK(blk);
            bad_cnt++;
            xil_printf("Block [%4d] BAD, page0[0]=0x%08X\r\n", blk, (unsigned)page0_buf[0]);
        } else {
            continue;
        } 
    }

    xil_printf("----------------------------------------\r\n");
    xil_printf(" Scan done: %d bad blocks in %d blocks\r\n", bad_cnt, BLOCK_NUM);
    xil_printf("----------------------------------------\r\n");
}

/* ==========================================================
 *                     NFC HIGH-LEVEL OPS
 * ========================================================== */

void NFC_Erase(u64 lba, u32 len)
{
    NFC_WaitReqFifoSpace();

    NFC_SetLBA(lba);
    NFC_SetLen(len);
    NFC_SetOpcode(NFC_CMD_BLOCK_ERASE);
    NFC_Start();

    NFC_WaitDone();

#if FTL_MON_ENABLE
    g_ftl_mon.phy_erase_blocks += 1;
#endif
}

void NFC_Program(u64 lba, u32 len)
{
    NFC_WaitReqFifoSpace();

    NFC_SetLBA(lba);
    NFC_SetLen(len);
    NFC_SetOpcode(NFC_CMD_PAGE_PROG);
    NFC_Start();

    /* Do NOT wait here if caller wants to overlap with DMA wait.
     * Caller (Write) will wait for completion after DMA done.
     */

#if FTL_MON_ENABLE
    g_ftl_mon.phy_prog_pages += 1;
#endif
}

void NFC_Read(u64 lba, u32 len)
{
    NFC_WaitReqFifoSpace();

    NFC_SetLBA(lba);
    NFC_SetLen(len);
    NFC_SetOpcode(NFC_CMD_PAGE_READ);
    NFC_Start();

    /* Do NOT wait here if caller wants to overlap with DMA wait.
     * Caller (Read) will wait for completion after DMA done.
     */

#if FTL_MON_ENABLE
    g_ftl_mon.phy_read_pages += 1;
#endif
}

/* ==========================================================
 *                        DMA + NFC WRITE
 * ========================================================== */

int Write(u64 lba, u32 len, u32 *TxBuffer)
{
    if (!s_dma_inited) return XST_FAILURE;

    int Status;

    /* Ensure request FIFO has space before launching a new op. */
    NFC_WaitReqFifoSpace();

    /* 1) Flush cache for outgoing buffer */
    Xil_DCacheFlushRange((UINTPTR)TxBuffer, len);

    /* 2) Setup DMA MM2S */
    Status = XAxiDma_SimpleTransfer(&s_axi_dma,
                                    (UINTPTR)TxBuffer,
                                    len,
                                    XAXIDMA_DMA_TO_DEVICE);
    if (Status != XST_SUCCESS) {
        xil_printf("DMA MM2S setup failed\r\n");
        return Status;
    }

#if FTL_MON_ENABLE
    g_ftl_mon.dma_mm2s_bytes  += (u64)len;
    g_ftl_mon.dma_total_bytes += (u64)len;
#endif

    /* 3) Start NFC program */
    NFC_Program(lba, len);

    /* 4) Wait for DMA done */
    while (XAxiDma_Busy(&s_axi_dma, XAXIDMA_DMA_TO_DEVICE)) {
        /* busy wait */
    }

    /* 5) Wait for NFC done */
    NFC_WaitDone();

    return XST_SUCCESS;
}

/* ==========================================================
 *                        DMA + NFC READ
 * ========================================================== */

int Read(u64 lba, u32 len, u32 *RxBuffer)
{
    if (!s_dma_inited) return XST_FAILURE;

    int Status;

    /* Ensure request FIFO has space before launching a new op. */
    NFC_WaitReqFifoSpace();

    /* 1) Invalidate cache before DMA writes */
    Xil_DCacheInvalidateRange((UINTPTR)RxBuffer, len);

    /* 2) Setup DMA S2MM */
    Status = XAxiDma_SimpleTransfer(&s_axi_dma,
                                    (UINTPTR)RxBuffer,
                                    len,
                                    XAXIDMA_DEVICE_TO_DMA);
    if (Status != XST_SUCCESS) {
        xil_printf("DMA S2MM setup failed\r\n");
        return Status;
    }

#if FTL_MON_ENABLE
    g_ftl_mon.dma_s2mm_bytes  += (u64)len;
    g_ftl_mon.dma_total_bytes += (u64)len;
#endif

    /* 3) Start NFC read */
    NFC_Read(lba, len);

    /* 4) Wait for DMA done */
    while (XAxiDma_Busy(&s_axi_dma, XAXIDMA_DEVICE_TO_DMA)) {
        /* busy wait */
    }

    /* 5) Wait for NFC done */
    NFC_WaitDone();

    /* 6) Invalidate again to ensure cache coherence */
    Xil_DCacheInvalidateRange((UINTPTR)RxBuffer, len);

    return XST_SUCCESS;
}

/* ==========================================================
 *                         DMA INIT
 * ========================================================== */

int init_dma(void)
{
    XAxiDma_Config *CfgPtr;

    CfgPtr = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    if (!CfgPtr) {
        xil_printf("No AXI DMA config found.\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_CfgInitialize(&s_axi_dma, CfgPtr) != XST_SUCCESS) {
        xil_printf("AXI DMA init failed.\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&s_axi_dma)) {
        xil_printf("AXI DMA must be in simple mode.\r\n");
        return XST_FAILURE;
    }

    s_dma_inited = 1;
    return XST_SUCCESS;
}
