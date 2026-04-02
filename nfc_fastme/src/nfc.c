// ===== WITH COPYBACK =====


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



/* Wait until request FIFO is NOT almost full. */
static inline void NFC_WaitReqFifoSpace(void)
{
    while (NFC_GetStatus() & NFC_STAT_REQ_AFULL_MASK) {
        /* busy wait */
    }
}


static int s_dma_inited = 0;
static XAxiDma s_axi_dma;

u8  BBT_Bitmap[BBT_SIZE_BYTES];
u32 BBT[BBT_SIZE_WORDS];
static u32 s_bbt_page_buf[NAND_PAGE_MAIN_SIZE_BYTES / sizeof(u32)];

static void print_cstr(const char *s)
{
    if (s == NULL) {
        return;
    }

    while (*s != '\0') {
        outbyte((char8)(*s));
        s++;
    }
}

static void print_u32_dec(u32 val)
{
    char buf[12];
    int i = 10;

    buf[11] = '\0';
    if (val == 0u) {
        buf[i--] = '0';
    } else {
        while (val > 0u) {
            buf[i--] = (char)('0' + (val % 10u));
            val /= 10u;
        }
    }

    print_cstr(&buf[i + 1]);
}

static void print_u32_hex8(u32 val)
{
    static const char hex[] = "0123456789ABCDEF";
    char buf[9];

    for (int i = 7; i >= 0; i--) {
        buf[i] = hex[val & 0x0Fu];
        val >>= 4;
    }
    buf[8] = '\0';
    print_cstr(buf);
}

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
    memset(s_bbt_page_buf, 0xFF, sizeof(s_bbt_page_buf));
    memset(BBT, 0, sizeof(BBT));
    memset(BBT_Bitmap, 0, sizeof(BBT_Bitmap));

    if (Read(BBT_ADDRESS, NAND_PAGE_MAIN_SIZE_BYTES, s_bbt_page_buf) != XST_SUCCESS) {
        print_cstr("Read_BBT_Bitmap: read failed at block ");
        print_u32_dec(BBT_BLOCK_INDEX);
        print_cstr("\r\n");
        return;
    }

    memcpy(BBT_Bitmap, s_bbt_page_buf, BBT_SIZE_BYTES);
    memcpy(BBT, BBT_Bitmap, BBT_SIZE_BYTES);

    print_cstr("Read_BBT_Bitmap: loaded from block ");
    print_u32_dec(BBT_BLOCK_INDEX);
    print_cstr(" page 0\r\n");
}

int Write_BBT_Bitmap(void)
{
    memset(s_bbt_page_buf, 0xFF, sizeof(s_bbt_page_buf));
    memcpy(s_bbt_page_buf, BBT_Bitmap, BBT_SIZE_BYTES);

    NFC_Erase(BBT_ADDRESS, 1);

    if (Write(BBT_ADDRESS, NAND_PAGE_MAIN_SIZE_BYTES, s_bbt_page_buf) != XST_SUCCESS) {
        print_cstr("Write_BBT_Bitmap: write failed at block ");
        print_u32_dec(BBT_BLOCK_INDEX);
        print_cstr("\r\n");
        return XST_FAILURE;
    }

    memcpy(BBT, BBT_Bitmap, BBT_SIZE_BYTES);
    print_cstr("Write_BBT_Bitmap: saved to block ");
    print_u32_dec(BBT_BLOCK_INDEX);
    print_cstr(" page 0\r\n");
    return XST_SUCCESS;
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
            print_cstr("Block [");
            print_u32_dec(blk);
            print_cstr("] read failed, mark as bad\r\n");
            MARK_BAD_BLOCK(blk);
            bad_cnt++;
            continue;
        }

        if ((page0_buf[0] & 0xFFFFu) == 0x0000u) {
            MARK_BAD_BLOCK(blk);
            bad_cnt++;
            print_cstr("Block [");
            print_u32_dec(blk);
            print_cstr("] BAD, page0[0]=0x");
            print_u32_hex8(page0_buf[0]);
            print_cstr("\r\n");
        } else {
            continue;
        }
    }

    xil_printf("----------------------------------------\r\n");
    print_cstr(" Scan done: ");
    print_u32_dec(bad_cnt);
    print_cstr(" bad blocks in ");
    print_u32_dec(BLOCK_NUM);
    print_cstr(" blocks\r\n");
    xil_printf("----------------------------------------\r\n");
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
            print_cstr(" -> Block [");
            print_u32_dec(blk);
            print_cstr("] is MARKED BAD\r\n");
            bad_cnt++;
        }
    }

    if (bad_cnt == 0) {
        xil_printf(" -> No Bad Blocks found (Perfect Chip!).\r\n");
    }

    xil_printf("\r\n----------------------------------------\r\n");
    print_cstr(" Summary: ");
    print_u32_dec(bad_cnt);
    print_cstr(" Bad Blocks found in ");
    print_u32_dec(total_blocks);
    print_cstr(" Blocks\r\n");
    print_cstr(" Bad Block Rate: ");
    print_u32_dec((bad_cnt * 100) / total_blocks);
    outbyte('.');
    print_u32_dec(((bad_cnt * 1000) / total_blocks) % 10u);
    print_cstr("%\r\n");
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

int  Copyback(u64 src_lba, u64 dst_lba)
{
    NFC_WaitReqFifoSpace();
    NFC_SetLBA(src_lba);
    NFC_SetLen(0);
    NFC_SetOpcode(0x3500);
    NFC_Start();
    NFC_SetLBA(dst_lba);
    NFC_SetLen(0);
    NFC_SetOpcode(0x1085);
    NFC_Start();
    NFC_WaitDone();
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
