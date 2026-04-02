// ===== WITH COPYBACK & HARDWARE MERGE ENGINE =====

#include "ftl_mon.h"
#include "nand_para.h"
#include "nfc.h"
#include "nfc_reg.h"
#include "ftl_core.h"
#include "xil_printf.h"

#define FTL_DEBUG 0
#define FTL_MERGE_DEBUG 0
#define MERGE_PLAN_BASE_WORD_DEFAULT  0u
#define MERGE_TIMEOUT_POLL_LIMIT      2000000u

/* ============================================================
 * FAST-FTL (Fully-Associative Log Blocks) - BRAM-only baseline
 *
 * This version modification:
 *   - Keep original global-latest selection logic (scan ALL log blocks).
 *   - In merge, offload the execution loop to merge_engine hardware.
 *   - Keep destination new data block erase in software before merge.
 *   - Precise CPU profiling: separating logic compute vs HW stalls.
 *
 * Notes:
 *   - Never-written pages are still kept as erased 0xFF (baseline behavior).
 * ============================================================ */

/* ------------------------------------------------------------
 * Global metadata (BRAM)
 * ------------------------------------------------------------ */

static u32 log_gen_counter = 0;
static u16 next_free_block = 0;

u16        BMT[USER_BLOCK];            /* LBN -> Data PBN */
LogBlock_t Log_Table[MAX_LOG_BLOCKS];  /* Fully-associative log blocks */

/* Optional: sequential direct-to-data write pointer (per LBN) */
static u16 Data_WP[USER_BLOCK];

/* Optional: LPN validity bitmap (tracks if an LPN has ever been written) */
#define LPN_VALID_BYTES  ((MAX_LBA_ADDRESS + 7u) / 8u)
static u8 LPN_Valid[LPN_VALID_BYTES];

/* Reusable merge buffer (32-bit aligned) */
static u32 MergeBufW[FTL_PAGE_BYTES / 4];
static u32 g_merge_plan[USER_PAGE];

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

/* ------------------------------------------------------------
 * Small bitmap helpers
 * ------------------------------------------------------------ */

static inline int lpn_is_valid(u32 lpn)
{
    u32 byte = lpn >> 3;
    u32 bit  = lpn & 7u;
    if (byte >= LPN_VALID_BYTES) {
        return 0;
    }
    return (LPN_Valid[byte] & (u8)(1u << bit)) ? 1 : 0;
}

static inline void lpn_set_valid(u32 lpn)
{
    u32 byte = lpn >> 3;
    u32 bit  = lpn & 7u;
    if (byte >= LPN_VALID_BYTES) {
        return;
    }
    LPN_Valid[byte] |= (u8)(1u << bit);
}

/* ------------------------------------------------------------
 * Block allocation helpers
 * ------------------------------------------------------------ */

static int block_in_use(u16 pbn)
{
    for (u32 i = 0; i < USER_BLOCK; i++) {
        if (BMT[i] == pbn) {
            return 1;
        }
    }

    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        if (Log_Table[i].pbn == pbn) {
            return 1;
        }
    }

    return 0;
}

u16 Allocate_Free_Block(void)
{

    const u16 limit = BLOCK_NUM;
    u16 scanned = 0;

    while (scanned < limit) {
        u16 candidate = next_free_block;

        if (candidate < limit &&
            !IS_BAD_BLOCK(candidate) &&
            !block_in_use(candidate)) {

            next_free_block = (u16)((candidate + 1u) % limit);
            return candidate;
        }

        next_free_block = (u16)((next_free_block + 1u) % limit);
        scanned++;
    }

    xil_printf("FTL: no free block available\r\n");
    return INVALID_PBN;
}

/* ------------------------------------------------------------
 * Log scan helpers (newest selection by (gen, page))
 * ------------------------------------------------------------ */

/* Find the newest occurrence of lpn within a single log block (reverse scan). */
static int log_find_latest_page(const LogBlock_t *log, u32 lpn, u16 *page_out)
{
    if (log->write_ptr == 0) {
        return 0;
    }

    for (u16 j = log->write_ptr; j > 0; j--) {
        if (log->lpn[j - 1] == lpn) {
            *page_out = (u16)(j - 1);
            return 1;
        }
    }
    return 0;
}

/* Scan ALL logs and return the newest match by (gen, page). */
static int scan_all_logs_for_lpn(u32 lpn, u32 *log_idx_out, u16 *page_out)
{
    int found = 0;
    u32 best_log = 0;
    u16 best_page = 0;
    u32 best_gen = 0;

    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        const LogBlock_t *log = &Log_Table[i];
        u16 page;

        if (!log_find_latest_page(log, lpn, &page)) {
            continue;
        }

        if (!found ||
            (log->gen > best_gen) ||
            (log->gen == best_gen && page > best_page)) {
            found = 1;
            best_log = i;
            best_page = page;
            best_gen = log->gen;
        }
    }

    if (found) {
        *log_idx_out = best_log;
        *page_out = best_page;
    }
    return found;
}

/* Invalidate all log tags that belong to this LBN across ALL log blocks. */
static void invalidate_lbn_in_all_logs(u16 lbn)
{
    u32 base = (u32)lbn * (u32)USER_PAGE;
    u32 end  = base + (u32)USER_PAGE;

    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        LogBlock_t *log = &Log_Table[i];

        for (u16 p = 0; p < log->write_ptr; p++) {
            u32 t = log->lpn[p];
            if (t >= base && t < end) {
                log->lpn[p] = INVALID_LPN;
            }
        }
    }
}

/* ------------------------------------------------------------
 * Best-source table for one LBN (scan ALL logs once)
 *   - For each page in this LBN, record the newest log location by (gen, log_page)
 *   - Policy is unchanged: newest by (gen, log_page)
 * ------------------------------------------------------------ */

typedef struct {
    u8  found;      /* 1 if log has a version for this page */
    u8  log_idx;    /* which log block */
    u16 log_page;   /* which page inside that log block */
    u32 gen;        /* generation for compare */
} BestSrc_t;

static BestSrc_t g_best_src[USER_PAGE];

static void build_best_src_for_lbn(u16 lbn)
{
    u32 base = (u32)lbn * (u32)USER_PAGE;
    u32 end  = base + (u32)USER_PAGE;

    /* Init */
    for (u16 p = 0; p < USER_PAGE; p++) {
        g_best_src[p].found    = 0;
        g_best_src[p].log_idx  = 0;
        g_best_src[p].log_page = 0;
        g_best_src[p].gen      = 0;
    }

    /* Scan all logs once */
    for (u8 li = 0; li < (u8)MAX_LOG_BLOCKS; li++) {
        const LogBlock_t *log = &Log_Table[li];
        u32 gen = log->gen;

        for (u16 lp = 0; lp < log->write_ptr; lp++) {
            u32 tag = log->lpn[lp];

            if (tag == INVALID_LPN) {
                continue;
            }
            if (tag < base || tag >= end) {
                continue;
            }

            u16 page = (u16)(tag - base);

            /* Newest selection by (gen, lp) */
            if (!g_best_src[page].found ||
                gen > g_best_src[page].gen ||
                (gen == g_best_src[page].gen && lp > g_best_src[page].log_page)) {

                g_best_src[page].found    = 1;
                g_best_src[page].log_idx  = li;
                g_best_src[page].log_page = lp;
                g_best_src[page].gen      = gen;
            }
        }
    }
}

static int merge_wait_busy_clear_timeout(u32 max_iters)
{
    while (max_iters-- != 0u) {
        if ((MERGE_GetStatus() & NFC_MG_STAT_BUSY_MASK) == 0u) {
            return 0;
        }
    }
    return -1;
}

/* ------------------------------------------------------------
 * Log cleaning / merge
 * ------------------------------------------------------------ */

static void reset_log_block(LogBlock_t *log)
{
    log->write_ptr = 0;
    log->gen = log_gen_counter++;

    for (u32 j = 0; j < USER_PAGE; j++) {
        log->lpn[j] = INVALID_LPN;
    }
}

/* Pick a victim FULL log block (oldest generation). Returns index or -1. */
static int pick_victim_full_log(void)
{
    int victim = -1;
    u32 best_gen = 0;

    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        const LogBlock_t *log = &Log_Table[i];

        if (log->write_ptr < USER_PAGE) {
            continue;
        }

        if (victim < 0 || log->gen < best_gen) {
            victim = (int)i;
            best_gen = log->gen;
        }
    }

    return victim;
}

int ME_MergeOneLbn(u16 lbn)
{
    u16 old_data_pbn;
    u16 new_data_pbn;
    u16 old_pbn_hdr;
    u32 skip_count = 0;
    u32 from_log_count = 0;
    u32 from_old_count = 0;

    /* Timing variables for precise CPU profiling */
    u64 t_start, t_end;
    u64 t_stall_start;
    u64 total_dt = 0;
    u64 stall_dt = 0;
    u64 compute_dt = 0;
    u64 hw_merge_dt = 0;

    g_ftl_mon.merge_count++;

    /* 1. Record absolute entry time */
    t_start = mon_now_ns();

    old_data_pbn = BMT[lbn];
    new_data_pbn = Allocate_Free_Block();

    if (new_data_pbn == INVALID_PBN) {
        xil_printf("Merge: no free block for new data\r\n");
        return (int)FTL_NO_SPACE;
    }

    /* Hardware Stall 1: Erase destination block */
    t_stall_start = mon_now_ns();
    NFC_Erase(MAKE_NAND_ADDR(new_data_pbn, 0, 0, 0, 0), 1);
    stall_dt += (mon_now_ns() - t_stall_start);

    /* Pure Logic: Build plan */
    build_best_src_for_lbn(lbn);

    for (u16 page = 0; page < USER_PAGE; page++) {
        u32 target_lpn = (u32)lbn * (u32)USER_PAGE + (u32)page;

        if (g_best_src[page].found) {
            u8 li = g_best_src[page].log_idx;
            g_merge_plan[page] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_FROM_LOG,
                                                 Log_Table[li].pbn,
                                                 g_best_src[page].log_page);
            from_log_count++;
            continue;
        }

        if ((old_data_pbn != INVALID_PBN) && lpn_is_valid(target_lpn)) {
            g_merge_plan[page] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_FROM_OLD, 0u, 0u);
            from_old_count++;
            continue;
        }

        g_merge_plan[page] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_SKIP, 0u, 0u);
        skip_count++;
    }

    g_ftl_mon.merge_plan_skip_pages += skip_count;
    g_ftl_mon.merge_plan_from_log_pages += from_log_count;
    g_ftl_mon.merge_plan_from_old_pages += from_old_count;
    g_ftl_mon.merge_last_skip_count = skip_count;
    g_ftl_mon.merge_last_from_log_count = from_log_count;
    g_ftl_mon.merge_last_from_old_count = from_old_count;

#if FTL_MERGE_DEBUG
    print_cstr("ME_MergeOneLbn: lbn=");
        print_u32_dec((u32)lbn);
        print_cstr(" skip=");
        print_u32_dec(skip_count);
        print_cstr(" from_log=");
        print_u32_dec(from_log_count);
        print_cstr(" from_old=");
        print_u32_dec(from_old_count);
        print_cstr("\r\n");
#endif

    BRAM_WriteWords(MERGE_PLAN_BASE_WORD_DEFAULT, g_merge_plan, USER_PAGE);

    old_pbn_hdr = (old_data_pbn == INVALID_PBN) ? INVALID_PBN : old_data_pbn;
    MERGE_SetHeader((u32)lbn,
                    new_data_pbn,
                    old_pbn_hdr,
                    USER_PAGE,
                    MERGE_PLAN_BASE_WORD_DEFAULT);

    /* Hardware Stall 2: Start engine and poll */
    t_stall_start = mon_now_ns();
    MERGE_Start();

    if (merge_wait_busy_clear_timeout(MERGE_TIMEOUT_POLL_LIMIT) != 0) {
        stall_dt += (mon_now_ns() - t_stall_start);
        g_ftl_mon.merge_hw_timeout_count++;  // <--- ÍêÈ«Æ¥Åä ftl_mon.h
        print_cstr("ME_MergeOneLbn: busy timeout, lbn=");
        print_u32_dec((u32)lbn);
        print_cstr(" status=0x");
        print_u32_hex8(MERGE_GetStatus());
        print_cstr("\r\n");
        return (int)FTL_ERR;
    }

    hw_merge_dt = mon_now_ns() - t_stall_start;
    stall_dt += hw_merge_dt;

    /* Hardware Stall 3: Erase old block */
    if (old_data_pbn != INVALID_PBN) {
        t_stall_start = mon_now_ns();
        NFC_Erase(MAKE_NAND_ADDR(old_data_pbn, 0, 0, 0, 0), 1);
        stall_dt += (mon_now_ns() - t_stall_start);
    }

    /* Pure Logic: Update metadata */
    BMT[lbn] = new_data_pbn;
    Data_WP[lbn] = USER_PAGE;

    invalidate_lbn_in_all_logs(lbn);

    /* 2. Record absolute exit time and calculate compute metrics */
    t_end = mon_now_ns();
    total_dt = t_end - t_start;

    if (total_dt > stall_dt) {
        compute_dt = total_dt - stall_dt;
    } else {
        compute_dt = 0; /* Fallback for precision limits */
    }

    /* 3. Update global CPU profiling monitors */
    g_ftl_mon.merge_cpu_compute_ns_sum += compute_dt;
    if (compute_dt > g_ftl_mon.merge_cpu_compute_ns_max) {
        g_ftl_mon.merge_cpu_compute_ns_max = compute_dt;
    }

    g_ftl_mon.merge_cpu_stall_ns_sum += stall_dt;
    if (stall_dt > g_ftl_mon.merge_cpu_stall_ns_max) {
        g_ftl_mon.merge_cpu_stall_ns_max = stall_dt;
    }

    /* Record Hardware Merge Engine time */
    g_ftl_mon.merge_hw_time_ns_last = hw_merge_dt;
    g_ftl_mon.merge_hw_time_ns_sum += hw_merge_dt;
    if (hw_merge_dt > g_ftl_mon.merge_hw_time_ns_max) {
        g_ftl_mon.merge_hw_time_ns_max = hw_merge_dt;
    }

    return (int)FTL_OK;
}

static u32 merge_one_lbn_global_latest(u16 lbn)
{
    return (u32)ME_MergeOneLbn(lbn);
}

/*
 * Clean a FULL log block:
 *   - Identify all LBNs referenced inside it,
 *   - Merge each such LBN into its own data block (global-latest selection),
 *   - Erase the victim log block and reset its metadata.
 */
static u32 clean_full_log_block(int victim_idx)
{
    LogBlock_t *vlog = &Log_Table[victim_idx];

    static u8 lbn_bitmap[(USER_BLOCK + 7u) / 8u];
    memset(lbn_bitmap, 0, sizeof(lbn_bitmap));

    for (u16 j = 0; j < vlog->write_ptr; j++) {
        u32 lpn = vlog->lpn[j];
        if (lpn == INVALID_LPN || lpn >= MAX_LBA_ADDRESS) {
            continue;
        }
        u16 lbn = LPN_TO_LBN(lpn);
        lbn_bitmap[(u32)lbn >> 3] |= (u8)(1u << ((u32)lbn & 7u));
    }

    for (u16 lbn = 0; lbn < USER_BLOCK; lbn++) {
        if (!(lbn_bitmap[(u32)lbn >> 3] & (u8)(1u << ((u32)lbn & 7u)))) {
            continue;
        }

        u32 st = merge_one_lbn_global_latest(lbn);
        if (st != FTL_OK) {
            return st;
        }
    }

    /* Wait/Stall handled inside NFC_Erase, currently not tracked in GC total,
       but if you need GC-specific stall tracking, it can be added here. */
    NFC_Erase(MAKE_NAND_ADDR((u16)vlog->pbn, 0, 0, 0, 0), 1);
    reset_log_block(vlog);

    return FTL_OK;
}

/* ------------------------------------------------------------
 * Log allocation (append-only)
 * ------------------------------------------------------------ */

static LogBlock_t *get_writable_log_block(void)
{
    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        if (Log_Table[i].write_ptr < USER_PAGE) {
            return &Log_Table[i];
        }
    }
    return NULL;
}

/* Ensure there is at least one writable log block; if not, trigger cleaning. */
static u32 ensure_log_space(int *did_clean)
{
    if (did_clean) {
        *did_clean = 0;
    }

    if (get_writable_log_block() != NULL) {
        return FTL_OK;
    }

    int victim = pick_victim_full_log();
    if (victim < 0) {
        g_ftl_mon.gc_trigger_no_free_log++;
        xil_printf("FTL: no victim log found (unexpected)\r\n");
        return FTL_NO_SPACE;
    }

    if (did_clean) {
        *did_clean = 1;
    }

    g_ftl_mon.merge_trigger_log_full++;
#if FTL_DEBUG
    print_cstr("FTL: cleaning full log block idx=");
    print_u32_dec((u32)victim);
    print_cstr(" pbn=");
    print_u32_dec((u32)Log_Table[victim].pbn);
    print_cstr(" gen=");
    print_u32_dec((u32)Log_Table[victim].gen);
    print_cstr("\r\n");
#endif
    u32 st = clean_full_log_block(victim);
    if (st == FTL_OK) {
        g_ftl_mon.gc_free_one_log_count++;
    }
    return st;
}

/* ------------------------------------------------------------
 * Public APIs
 * ------------------------------------------------------------ */

void FTL_Init(void)
{
    xil_printf("=== FAST FTL Init (Fully-Associative Log) Start ===\r\n");

    log_gen_counter = 0;
    next_free_block = 0;


    /* Clear BMT and data write pointers */
    for (u32 i = 0; i < USER_BLOCK; i++) {
        BMT[i] = INVALID_PBN;
        Data_WP[i] = 0;
    }

    /* Clear Log_Table to avoid false "in-use" detection */
    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        Log_Table[i].pbn = INVALID_PBN;
        Log_Table[i].write_ptr = 0;
        Log_Table[i].gen = 0;
        for (u32 j = 0; j < USER_PAGE; j++) {
            Log_Table[i].lpn[j] = INVALID_LPN;
        }
    }

    /* Clear LPN validity bitmap */
    memset(LPN_Valid, 0, sizeof(LPN_Valid));

    /* Initialize log blocks (allocate physical blocks up-front) */
    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        Log_Table[i].pbn = Allocate_Free_Block();
        if (Log_Table[i].pbn == INVALID_PBN) {
            print_cstr("FTL_Init: failed to allocate log block ");
            print_u32_dec(i);
            print_cstr("\r\n");
            return;
        }
        reset_log_block(&Log_Table[i]);

        print_cstr("LogBlock[");
        print_u32_dec(i);
        print_cstr("] -> PBN ");
        print_u32_dec((u32)Log_Table[i].pbn);
        print_cstr(" (gen=");
        print_u32_dec((u32)Log_Table[i].gen);
        print_cstr(")\r\n");
    }

    xil_printf("=== FAST FTL Init Done ===\r\n");
}

u32 FTL_Write(u32 lpn, u8 *buffer)
{
    uint64_t t0 = mon_now_ns();
    WritePath path = WPATH_FAST;

    g_ftl_mon.host_write_pages++;

    if (lpn >= MAX_LBA_ADDRESS) {
        g_ftl_mon.write_invalid_lpn++;
        print_cstr("FTL_Write: invalid LPN ");
        print_u32_dec((u32)lpn);
        print_cstr("\r\n");
        MON_WRITE_END_PATH(t0, path);
        return FTL_ERR;
    }

    u16 lbn    = LPN_TO_LBN(lpn);
    u16 offset = LPN_OFFSET(lpn);

    /* Ensure data block exists */
    if (BMT[lbn] == INVALID_PBN) {
        u16 pbn = Allocate_Free_Block();
        if (pbn == INVALID_PBN) {
            MON_WRITE_END_PATH(t0, path);
            return FTL_NO_SPACE;
        }
        BMT[lbn] = pbn;
        Data_WP[lbn] = 0;
#if FTL_DEBUG
        print_cstr("FTL_Write: allocate DataPBN ");
        print_u32_dec((u32)pbn);
        print_cstr(" for LBN ");
        print_u32_dec((u32)lbn);
        print_cstr("\r\n");
#endif
    }

    /* Fast path: first-time sequential write to data block */
    if (!lpn_is_valid(lpn) && Data_WP[lbn] < USER_PAGE && offset == Data_WP[lbn]) {
        u64 phy = MAKE_NAND_ADDR(BMT[lbn], offset, 0, 0, 0);
        Write(phy, FTL_PAGE_BYTES, (u32 *)buffer);

        lpn_set_valid(lpn);
        Data_WP[lbn]++;
#if FTL_DEBUG
        print_cstr("FTL_Write: LPN ");
        print_u32_dec((u32)lpn);
        print_cstr(" -> DataPBN ");
        print_u32_dec((u32)BMT[lbn]);
        print_cstr(" Page ");
        print_u32_dec((u32)offset);
        print_cstr(" (seq)\r\n");
#endif
        MON_WRITE_END_PATH(t0, path);
        return FTL_OK;
    }

    /* Otherwise write to log */
    int did_clean = 0;
    u32 st = ensure_log_space(&did_clean);
    if (st != FTL_OK) {
        MON_WRITE_END_PATH(t0, path);
        return st;
    }
    if (did_clean) {
        path = WPATH_LOGFULL;
    }

    LogBlock_t *log = get_writable_log_block();
    if (log == NULL) {
        g_ftl_mon.gc_trigger_no_free_log++;
        MON_WRITE_END_PATH(t0, path);
        return FTL_NO_SPACE;
    }

    u16 log_page = log->write_ptr;
    u64 phy = MAKE_NAND_ADDR((u16)log->pbn, log_page, 0, 0, 0);

    Write(phy, FTL_PAGE_BYTES, (u32 *)buffer);

    log->lpn[log_page] = lpn;
    log->write_ptr++;

    lpn_set_valid(lpn);
#if FTL_DEBUG
    print_cstr("FTL_Write: LPN ");
    print_u32_dec((u32)lpn);
    print_cstr(" -> LogPBN ");
    print_u32_dec((u32)log->pbn);
    print_cstr(" Page ");
    print_u32_dec((u32)log_page);
    print_cstr(" (gen=");
    print_u32_dec((u32)log->gen);
    print_cstr(")\r\n");
#endif
    MON_WRITE_END_PATH(t0, path);
    return FTL_OK;
}

u32 FTL_Read(u32 lpn, u8 *buffer)
{
    if (lpn >= MAX_LBA_ADDRESS) {
        print_cstr("FTL_Read: invalid LPN ");
        print_u32_dec((u32)lpn);
        print_cstr("\r\n");
        return FTL_ERR;
    }

    /* Scan ALL log blocks */
    u32 log_idx = 0;
    u16 page = 0;

    if (scan_all_logs_for_lpn(lpn, &log_idx, &page)) {
        const LogBlock_t *log = &Log_Table[log_idx];
        u64 phy = MAKE_NAND_ADDR((u16)log->pbn, page, 0, 0, 0);
        Read(phy, FTL_PAGE_BYTES, (u32 *)buffer);
#if FTL_DEBUG
        print_cstr("FTL_Read: LPN ");
        print_u32_dec((u32)lpn);
        print_cstr(" <- LogPBN ");
        print_u32_dec((u32)log->pbn);
        print_cstr(" Page ");
        print_u32_dec((u32)page);
        print_cstr(" (gen=");
        print_u32_dec((u32)log->gen);
        print_cstr(")\r\n");
#endif
        return FTL_OK;
    }

    /* Fall back to data block */
    u16 lbn    = LPN_TO_LBN(lpn);
    u16 offset = LPN_OFFSET(lpn);

    if (BMT[lbn] == INVALID_PBN) {
        memset(buffer, 0xFF, FTL_PAGE_BYTES);
        return FTL_OK;
    }

    if (!lpn_is_valid(lpn)) {
        memset(buffer, 0xFF, FTL_PAGE_BYTES);
        return FTL_OK;
    }

    u64 phy = MAKE_NAND_ADDR(BMT[lbn], offset, 0, 0, 0);
    Read(phy, FTL_PAGE_BYTES, (u32 *)buffer);
#if FTL_DEBUG
    print_cstr("FTL_Read: LPN ");
    print_u32_dec((u32)lpn);
    print_cstr(" <- DataPBN ");
    print_u32_dec((u32)BMT[lbn]);
    print_cstr(" Page ");
    print_u32_dec((u32)offset);
    print_cstr("\r\n");
#endif
    return FTL_OK;
}
