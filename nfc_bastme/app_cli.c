#include "app_cli.h"
#include "nfc.h"
#include "nfc_reg.h"
#include "nand_para.h"
#include "ftl_core.h"
#include "ftl_mon.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "xstatus.h"
#include <string.h>

/* CLI constants */
#define SEQ_VERIFY_LENGTH    200
#define FIRST_BYTES_TO_PRINT 16
#define PAGE_OFFSET_BYTES    0x000000010000ULL
#define BLOCK_OFFSET_BYTES   (1ULL << BLOCK_SHIFT)
#define WORKLOAD_PREFILL_PERCENT     70u

#define UARTLITE_DEVICE_ID   XPAR_AXI_UARTLITE_0_DEVICE_ID

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

static void print_u8_hex2(u8 val)
{
    static const char hex[] = "0123456789ABCDEF";
    outbyte((char8)hex[(val >> 4) & 0x0Fu]);
    outbyte((char8)hex[val & 0x0Fu]);
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

static inline void xil_print_u64_hex(u64 v)
{
    print_cstr("0x");
    print_u32_hex8((u32)(v >> 32));
    print_u32_hex8((u32)(v & 0xFFFFFFFFu));
}

/* ---------------- Helper: simple deterministic PRNG (xorshift32) ---------------- */
static u32 prng_next(u32 *state)
{
    /* xorshift32 */
    u32 x = *state;
    x ^= (x << 13);
    x ^= (x >> 17);
    x ^= (x << 5);
    *state = x;
    return x;
}

static void fill_page_pattern(u8 *buf, u32 lpn, u32 seq)
{
    /* Pattern: [0] = lpn low8, [1] = seq low8, others = lpn low8 */
    u8 v = (u8)(lpn & 0xFFu);
    for (u32 i = 0; i < NAND_PAGE_MAIN_SIZE_BYTES; i++) {
        buf[i] = v;
    }
    if (NAND_PAGE_MAIN_SIZE_BYTES >= 2) {
        buf[0] = (u8)(lpn & 0xFFu);
        buf[1] = (u8)(seq & 0xFFu);
    }
}

static void print_ops_summary(const char *name, u32 ops, u64 dt_ns)
{
    u32 dt_us = (u32)(dt_ns / 1000ull);
    print_cstr("\r\n[");
    print_cstr(name);
    print_cstr("] ops=");
    print_u32_dec(ops);
    print_cstr(", elapsed=");
    print_u32_dec(dt_us);
    print_cstr(" us lognum=");
    print_u32_dec(MAX_LOG_BLOCKS);
    print_cstr("\r\n");
}

static void reset_ftl_for_workload(void)
{
    FTL_Init();
    FTL_MonReset();
}

static void prefill_ftl_before_workload(AppContext *ctx, const char *name)
{
    u32 prefill_pages = (u32)(((u64)MAX_LBA_ADDRESS * WORKLOAD_PREFILL_PERCENT) / 100ull);

    print_cstr("\r\n[");
    print_cstr(name);
    print_cstr("] prefill ");
    print_u32_dec(WORKLOAD_PREFILL_PERCENT);
    print_cstr("% start (");
    print_u32_dec(prefill_pages);
    print_cstr(" pages)\r\n");

    reset_ftl_for_workload();

    for (u32 lpn = 0; lpn < prefill_pages; lpn++) {
        fill_page_pattern(ctx->FtlTxBuf, lpn, 0u);
        if (FTL_Write(lpn, ctx->FtlTxBuf) != FTL_OK) {
            print_cstr("[");
            print_cstr(name);
            print_cstr("] prefill failed at lpn=");
            print_u32_dec(lpn);
            print_cstr("\r\n");
            return;
        }
    }

    print_cstr("[");
    print_cstr(name);
    print_cstr("] prefill done\r\n");
    FTL_MonReset();
}

/* =========================================================================
 * 1) Fresh sequential write
 * ========================================================================= */
void Test_FreshSequentialWrite(AppContext *ctx, u32 start_lpn, u32 pages)
{
    if (pages == 0) {
        xil_printf("[FreshSeqWrite] invalid args\r\n");
        return;
    }

    reset_ftl_for_workload();

    u64 t0 = mon_now_ns();

    for (u32 i = 0; i < pages; i++) {
        u32 lpn = start_lpn + i;
        fill_page_pattern(ctx->FtlTxBuf, lpn, i);
        FTL_Write(lpn, ctx->FtlTxBuf);
    }

    u64 t1 = mon_now_ns();
    print_ops_summary("FreshSeqWrite", pages, (t1 - t0));
    FTL_MonPrint();
}

/* =========================================================================
 * 2) Sequential overwrite after 70% prefill
 * ========================================================================= */
void Test_SequentialOverwriteAfterPrefill(AppContext *ctx, u32 start_lpn, u32 pages)
{
    if (pages == 0) {
        xil_printf("[SeqOverwrite70] invalid args\r\n");
        return;
    }

    prefill_ftl_before_workload(ctx, "SeqOverwrite70");

    u64 t0 = mon_now_ns();

    for (u32 i = 0; i < pages; i++) {
        u32 lpn = start_lpn + i;
        fill_page_pattern(ctx->FtlTxBuf, lpn, i);
        FTL_Write(lpn, ctx->FtlTxBuf);
    }

    u64 t1 = mon_now_ns();
    print_ops_summary("SeqOverwrite70", pages, (t1 - t0));
    FTL_MonPrint();
}

/* =========================================================================
 * 3) Hot-page overwrite
 * ========================================================================= */
void Test_HotPageOverwrite(AppContext *ctx, u32 hot_base_lpn, u32 hot_pages, u32 total_ops, u32 seed)
{
    if (hot_pages == 0 || total_ops == 0) {
        xil_printf("[HotOverwrite] invalid args\r\n");
        return;
    }

    prefill_ftl_before_workload(ctx, "HotOverwrite");

    u32 rng = (seed != 0) ? seed : 0x12345678u;
    u64 t0 = mon_now_ns();

    for (u32 i = 0; i < total_ops; i++) {
        u32 r = prng_next(&rng);
        u32 idx = (hot_pages == 1) ? 0 : (r % hot_pages);
        u32 lpn = hot_base_lpn + idx;

        fill_page_pattern(ctx->FtlTxBuf, lpn, i);
        FTL_Write(lpn, ctx->FtlTxBuf);
    }

    u64 t1 = mon_now_ns();
    print_ops_summary("HotOverwrite", total_ops, (t1 - t0));
    FTL_MonPrint();
}

/* =========================================================================
 * 4) Narrow random write
 * ========================================================================= */
void Test_NarrowRandomWrite(AppContext *ctx, u32 window_base_lpn, u32 window_pages, u32 total_ops, u32 seed)
{
    if (window_pages == 0 || total_ops == 0) {
        xil_printf("[NarrowRandom] invalid args\r\n");
        return;
    }

    prefill_ftl_before_workload(ctx, "NarrowRandom");

    u32 rng = (seed != 0) ? seed : 0xCAFEBABEu;
    u64 t0 = mon_now_ns();

    for (u32 i = 0; i < total_ops; i++) {
        u32 r = prng_next(&rng);
        u32 off = (window_pages == 1) ? 0 : (r % window_pages);
        u32 lpn = window_base_lpn + off;

        fill_page_pattern(ctx->FtlTxBuf, lpn, i);
        FTL_Write(lpn, ctx->FtlTxBuf);
    }

    u64 t1 = mon_now_ns();
    print_ops_summary("NarrowRandom", total_ops, (t1 - t0));
    FTL_MonPrint();
}

/* =========================================================================
 * 5) Wide random write
 * ========================================================================= */
void Test_WideRandomWrite(AppContext *ctx, u32 range_base_lpn, u32 range_pages, u32 total_ops, u32 seed)
{
    if (range_pages == 0 || total_ops == 0) {
        xil_printf("[WideRandom] invalid args\r\n");
        return;
    }

    prefill_ftl_before_workload(ctx, "WideRandom");

    u32 rng = (seed != 0) ? seed : 0xA5A5A5A5u;
    u64 t0 = mon_now_ns();

    for (u32 i = 0; i < total_ops; i++) {
        u32 r = prng_next(&rng);
        u32 off = (range_pages == 1) ? 0 : (r % range_pages);
        u32 lpn = range_base_lpn + off;

        fill_page_pattern(ctx->FtlTxBuf, lpn, i);
        FTL_Write(lpn, ctx->FtlTxBuf);
    }

    u64 t1 = mon_now_ns();
    print_ops_summary("WideRandom", total_ops, (t1 - t0));
    FTL_MonPrint();
}

/* =========================================================================
 * 6) Mixed hot/cold write
 * ========================================================================= */
void Test_MixedHotColdWrite(AppContext *ctx,
                            u32 hot_base_lpn,
                            u32 hot_pages,
                            u32 cold_range_base_lpn,
                            u32 cold_range_pages,
                            u32 total_ops,
                            u32 seed)
{
    if (hot_pages == 0 || cold_range_pages == 0 || total_ops == 0) {
        xil_printf("[MixedHotCold] invalid args\r\n");
        return;
    }

    prefill_ftl_before_workload(ctx, "MixedHotCold");

    u32 rng = (seed != 0) ? seed : 0x13572468u;
    u64 t0 = mon_now_ns();

    for (u32 i = 0; i < total_ops; i++) {
        u32 r = prng_next(&rng);
        u32 lpn;

        if ((r % 10u) < 8u) {
            u32 off = (hot_pages == 1) ? 0 : (prng_next(&rng) % hot_pages);
            lpn = hot_base_lpn + off;
        } else {
            u32 off = (cold_range_pages == 1) ? 0 : (prng_next(&rng) % cold_range_pages);
            lpn = cold_range_base_lpn + off;
        }

        fill_page_pattern(ctx->FtlTxBuf, lpn, i);
        FTL_Write(lpn, ctx->FtlTxBuf);
    }

    u64 t1 = mon_now_ns();
    print_ops_summary("MixedHotCold", total_ops, (t1 - t0));
    FTL_MonPrint();
}

/* ====================================================================== */
/* Legacy simple buffer fill for single/seq menu functions                  */
/* ====================================================================== */
static void fill_ftl_buffer(u8 *buf, u32 lpn)
{
    for (u32 i = 0; i < NAND_PAGE_MAIN_SIZE_BYTES; i++) {
        buf[i] = (u8)(lpn & 0xFFu);
    }
}

int NAND_init(void)
{
    xil_printf("=== NAND init: reset + timing + configuration ===\r\n");

    /* Reset NAND controller */
    NFC_Reset();

    /* Apply timing parameters and controller configuration */
    NFC_SetTimingMode();
    NFC_SetConfiguration();

    xil_printf("=== NAND init done ===\r\n");
    return XST_SUCCESS;
}




static void handle_ftl_single_write(AppContext *ctx)
{
    fill_ftl_buffer(ctx->FtlTxBuf, ctx->current_lpn);
    print_cstr("FTL_Write: LPN = ");
    print_u32_dec(ctx->current_lpn);
    print_cstr("\r\n");
    FTL_Write(ctx->current_lpn, ctx->FtlTxBuf);
}

static void handle_ftl_single_read(AppContext *ctx)
{
    print_cstr("FTL_Read: LPN = ");
    print_u32_dec(ctx->current_lpn);
    print_cstr("\r\n");
    FTL_Read(ctx->current_lpn, ctx->FtlRxBuf);

    print_cstr("First ");
    print_u32_dec(FIRST_BYTES_TO_PRINT);
    print_cstr(" bytes:\r\n");
    for (int i = 0; i < FIRST_BYTES_TO_PRINT; i++) {
        print_u8_hex2(ctx->FtlRxBuf[i]);
        outbyte(' ');
    }
    xil_printf("\r\n");
}

static void handle_ftl_seq_write(AppContext *ctx, u32 start_lpn, u32 page_count)
{
    print_cstr("=== FTL sequential write ");
    print_u32_dec(page_count);
    print_cstr(" pages ===\r\n");
    FTL_MonReset();
    for (u32 lpn = start_lpn; lpn < start_lpn + page_count; lpn++) {
        fill_ftl_buffer(ctx->FtlTxBuf, lpn);
        FTL_Write(lpn, ctx->FtlTxBuf);
        print_cstr("Write LPN ");
        print_u32_dec(lpn);
        print_cstr(" done\r\n");
    }
    FTL_MonPrint();
    xil_printf("=== sequential write done ===\r\n");

}

static void handle_ftl_seq_verify(AppContext *ctx, u32 start_lpn, u32 page_count)
{
    xil_printf("=== FTL sequential read verify ===\r\n");

    for (u32 lpn = start_lpn; lpn < start_lpn + page_count; lpn++) {
        FTL_Read(lpn, ctx->FtlRxBuf);

        int ok = 1;
        for (int i = 0; i < FIRST_BYTES_TO_PRINT; i++) {
            if (ctx->FtlRxBuf[i] != (u8)(lpn & 0xFFu)) {
                ok = 0;
                break;
            }
        }

        if (!ok) {
            print_cstr("ERROR at LPN ");
            print_u32_dec(lpn);
            print_cstr(", data mismatch\r\n");
            break;
        } else {
            print_cstr("Read LPN ");
            print_u32_dec(lpn);
            print_cstr(" OK\r\n");
        }
    }

    xil_printf("=== sequential read verify done ===\r\n");
}

static void handle_nfc_read(AppContext *ctx)
{
    xil_printf("address: ");
    xil_print_u64_hex(ctx->starting_address);
    xil_printf("\r\n");

    Read(ctx->starting_address, ctx->ByteCount, ctx->RxBuffer);

    for (u32 i = 0; i < 16; i++) {
        print_cstr("RxBuffer[");
        print_u32_dec(i);
        print_cstr("] = 0x");
        print_u32_hex8(ctx->RxBuffer[i]);
        print_cstr("\r\n");
    }
}

static void handle_nfc_program(AppContext *ctx)
{
    u32 i;
    u32 block;
    u32 page;

    xil_printf("=== NFC Program Test ===\r\n");
    xil_printf("address: ");
    xil_print_u64_hex(ctx->starting_address);
    xil_printf("\r\n");

    block = (u32)((ctx->starting_address >> BLOCK_SHIFT) & 0xFFFFU);
    page  = (u32)((ctx->starting_address >> PAGE_SHIFT)  & 0xFFFFU);

    for (i = 0; i < (ctx->ByteCount / 4); i++) {
//        ctx->TxBuffer[i] = ((block & 0xFFFFU) << 16) | ((page + i) & 0xFFFFU);
    	ctx->TxBuffer[i] = 0xAAAAU;
    }

    Write(ctx->starting_address, ctx->ByteCount, ctx->TxBuffer);
}

static void handle_nfc_erase(AppContext *ctx)
{
    xil_printf("=== NFC Erase Test ===\r\n");
    xil_printf("address: ");
    xil_print_u64_hex(ctx->starting_address);
    xil_printf("\r\n");

    NFC_Erase(ctx->starting_address, 1);
}

static void handle_nfc_seqerase(AppContext *ctx, int n)
{
    xil_printf("=== NFC seqErase Test ===\r\n");
    xil_printf("address: ");
    xil_print_u64_hex(0);
    print_cstr(" erase:");
    print_u32_dec((u32)n);
    print_cstr(" blocks\r\n");

    for (int i = 0; i < n; i++) {
        NFC_Erase((u64)i * BLOCK_OFFSET_BYTES, 1);
    }
}

static void erase_all_blocks_and_reset_mon(void)
{
    xil_printf("=== NFC full erase start ===\r\n");
    for (u32 blk = 0; blk < BLOCK_NUM; blk++) {
        NFC_Erase(MAKE_NAND_ADDR((u16)blk, 0, 0, 0, 0), 1);
    }
    FTL_MonReset();
    xil_printf("=== NFC full erase done, monitor reset ===\r\n");
}

static void run_all_workloads(AppContext *ctx)
{
    xil_printf("\r\n========== Run All 6 Workloads ==========\r\n");

    xil_printf("\r\n[Batch] Experiment 1/6: Fresh sequential write\r\n");
    erase_all_blocks_and_reset_mon();
    Test_FreshSequentialWrite(ctx, 0, 1600);

    xil_printf("\r\n[Batch] Experiment 2/6: Sequential overwrite after 70%% prefill\r\n");
    erase_all_blocks_and_reset_mon();
    Test_SequentialOverwriteAfterPrefill(ctx, 0, 1600);

    xil_printf("\r\n[Batch] Experiment 3/6: Hot-page overwrite\r\n");
    erase_all_blocks_and_reset_mon();
    Test_HotPageOverwrite(ctx, 0, 8, 4000, 1);

    xil_printf("\r\n[Batch] Experiment 4/6: Narrow random write\r\n");
    erase_all_blocks_and_reset_mon();
    Test_NarrowRandomWrite(ctx, 0, 200, 4000, 2);

    xil_printf("\r\n[Batch] Experiment 5/6: Wide random write\r\n");
    erase_all_blocks_and_reset_mon();
    Test_WideRandomWrite(ctx, 0, 10000, 4000, 3);

    xil_printf("\r\n[Batch] Experiment 6/6: Mixed hot/cold write\r\n");
    erase_all_blocks_and_reset_mon();
    Test_MixedHotColdWrite(ctx, 0, 200, 0, 10000, 4000, 4);

    xil_printf("\r\n========== Run All 6 Workloads Done ==========\r\n");
}




static void handle_page_offset(AppContext *ctx, int delta)
{
    print_cstr("=== Page address ");
    print_cstr((delta > 0) ? "+1" : "-1");
    print_cstr(" ===\r\n");
    if (delta > 0) ctx->starting_address += PAGE_OFFSET_BYTES;
    else           ctx->starting_address -= PAGE_OFFSET_BYTES;
}

static void handle_block_offset(AppContext *ctx, int delta)
{
    print_cstr("=== Block address ");
    print_cstr((delta > 0) ? "+1" : "-1");
    print_cstr(" ===\r\n");
    if (delta > 0) ctx->starting_address += BLOCK_OFFSET_BYTES;
    else           ctx->starting_address -= BLOCK_OFFSET_BYTES;
}

static void handle_bbt(void)
{
    xil_printf("=== Read BBT_Bitmap ===\r\n");
    Read_BBT_Bitmap();
    Print_Bad_Block_Info();
    xil_printf("=== Read BBT_Bitmap done ===\r\n");
}

static void handle_scan_bad_blocks(void)
{
    xil_printf("=== Scan NAND bad blocks ===\r\n");
    NFC_ScanBadBlocks();
    Print_Bad_Block_Info();
    xil_printf("=== Scan NAND bad blocks done ===\r\n");
}

static void handle_write_bbt(void)
{
    xil_printf("=== Write BBT_Bitmap to reserved block ===\r\n");
    if (Write_BBT_Bitmap() != XST_SUCCESS) {
        xil_printf("=== Write BBT_Bitmap failed ===\r\n");
        return;
    }
    xil_printf("=== Write BBT_Bitmap done ===\r\n");
}

int App_InitPlatform(AppContext *ctx)
{
    if (init_dma() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    if (XUartLite_Initialize(&ctx->UartLite, UARTLITE_DEVICE_ID) != XST_SUCCESS) {
        xil_printf("UART init failed\r\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

void App_PrintMenu(const AppContext *ctx)
{
    xil_printf("\r\n================= NFC / FTL Test Menu =================\r\n");
    xil_printf("System ready.\r\n\r\n");

    xil_printf("[FTL]\r\n");
    xil_printf("  F  - FTL single page write (current LPN pattern)\r\n");
    print_cstr("  G  - FTL single page read  (print first ");
    print_u32_dec(FIRST_BYTES_TO_PRINT);
    print_cstr(" bytes)\r\n");
    print_cstr("  V  - FTL sequential write  (");
    print_u32_dec(SEQ_VERIFY_LENGTH);
    print_cstr(" pages from start LPN)\r\n");
    print_cstr("  C  - FTL sequential verify (");
    print_u32_dec(SEQ_VERIFY_LENGTH);
    print_cstr(" pages from start LPN)\r\n");
    xil_printf("  +  - current LPN + 1\r\n");
    xil_printf("  -  - current LPN - 1\r\n\r\n");

    xil_printf("[Workloads]\r\n");
    xil_printf("  1  - Fresh sequential write\r\n");
    xil_printf("  2  - Sequential overwrite after 70%% prefill\r\n");
    xil_printf("  3  - Hot-page overwrite\r\n");
    xil_printf("  4  - Narrow random write\r\n");
    xil_printf("  5  - Wide random write\r\n");
    xil_printf("  6  - Mixed hot/cold write\r\n");
    xil_printf("  7  - Run all 6 workloads automatically\r\n");
    xil_printf("\r\n");

    xil_printf("[NFC RAW]\r\n");
    print_cstr("  R  - NFC Read  (starting_address, ");
    print_u32_dec(ctx->ByteCount);
    print_cstr(" bytes)\r\n");
    print_cstr("  W  - NFC Program (starting_address, ");
    print_u32_dec(ctx->ByteCount);
    print_cstr(" bytes)\r\n");
    xil_printf("  E  - NFC Erase (starting_address, 1 block)\r\n");
    xil_printf("  O  - NFC seqErase (starting_address, n blocks)\r\n");

    xil_printf("[Address Step]\r\n");
    xil_printf("  A  - Page address +1 ( +"); xil_print_u64_hex(PAGE_OFFSET_BYTES);  xil_printf(" )\r\n");
    xil_printf("  Z  - Page address -1 ( -"); xil_print_u64_hex(PAGE_OFFSET_BYTES);  xil_printf(" )\r\n");
    xil_printf("  B  - Block address +1 ( +"); xil_print_u64_hex(BLOCK_OFFSET_BYTES); xil_printf(" )\r\n");
    xil_printf("  N  - Block address -1 ( -"); xil_print_u64_hex(BLOCK_OFFSET_BYTES); xil_printf(" )\r\n");
    xil_printf("\r\n");

    xil_printf("[BBT]\r\n");
    xil_printf("  M  - Read BBT_Bitmap and print bad block info\r\n");
    xil_printf("  K  - Scan blocks and rebuild bad block bitmap in RAM\r\n");
    xil_printf("  P  - Write current BBT_Bitmap to reserved block page 0\r\n");
    xil_printf("========================================================\r\n\r\n");
}

void App_DispatchCmd(AppContext *ctx, u8 recv_char)
{
    char cmd = (recv_char >= 'A' && recv_char <= 'Z') ?
               (char)(recv_char + ('a' - 'A')) : (char)recv_char;

    switch (cmd) {
    case 'f': handle_ftl_single_write(ctx); break;
    case 'g': handle_ftl_single_read(ctx); break;
    case 'v': handle_ftl_seq_write(ctx, ctx->start_lpn, SEQ_VERIFY_LENGTH); break;
    case 'c': handle_ftl_seq_verify(ctx, ctx->start_lpn, SEQ_VERIFY_LENGTH); break;

    case '+':
        ctx->current_lpn++;
        print_cstr("Current LPN = ");
        print_u32_dec(ctx->current_lpn);
        print_cstr("\r\n");
        break;
    case '-':
        if (ctx->current_lpn > 0) ctx->current_lpn--;
        print_cstr("Current LPN = ");
        print_u32_dec(ctx->current_lpn);
        print_cstr("\r\n");
        break;

    case 'o': handle_nfc_seqerase(ctx, BLOCK_NUM); break;

    case 'r': handle_nfc_read(ctx); break;
    case 'w': handle_nfc_program(ctx); break;
    case 'e': handle_nfc_erase(ctx); break;

    case 'a': handle_page_offset(ctx,  1); break;
    case 'z': handle_page_offset(ctx, -1); break;
    case 'b': handle_block_offset(ctx,  1); break;
    case 'n': handle_block_offset(ctx, -1); break;

    case '1': Test_FreshSequentialWrite(ctx,                  0,  1600);                break;
    case '2': Test_SequentialOverwriteAfterPrefill(ctx,       0,  1600);                break;
    case '3': Test_HotPageOverwrite(ctx,                      0,     8, 4000, 1);       break;
    case '4': Test_NarrowRandomWrite(ctx,                     0,   200, 4000, 2);       break;
    case '5': Test_WideRandomWrite(ctx,                       0, 10000, 4000, 3);       break;
    case '6': Test_MixedHotColdWrite(ctx,                     0,   200, 0, 10000, 4000, 4); break;
    case '7': run_all_workloads(ctx); break;

    case 'm': handle_bbt(); break;
    case 'k': handle_scan_bad_blocks(); break;
    case 'p': handle_write_bbt(); break;
    default: break;
    }
}
