
#include "ftl_mon.h"
#include "nand_para.h"
#include "nfc.h"
#include "ftl_core.h"


#define FTL_DEBUG 0
/* ============================================================
 * BAST-FTL (Block-Associative Log Blocks) - BRAM-only baseline
 *
 * Design goals:
 *   - No DDR/DRAM: all metadata lives in on-chip memory.
 *   - Each log block is associated with one LBN.
 *   - Read path checks only the associated log block for that LBN.
 *   - When a log block fills up, merge that LBN into a new data block,
 *     erase the log block, and reuse it.
 *
 * Correctness notes (important):
 *   - Updated pages are constrained to the associated log block of the LBN.
 *   - Merge only needs to consider that one associated log block.
 *
 * NAND constraints:
 *   - NAND programming requires sequential page programming within a block.
 *     Therefore, log blocks are append-only (write_ptr only increases).
 *   - Merge writes a full block sequentially (0..USER_PAGE-1). For never-written pages,
 *     it programs 0xFF. After merge, the data block is treated as "full".
 * ============================================================ */

/* ------------------------------------------------------------
 * Global metadata (BRAM)
 * ------------------------------------------------------------ */

static u32 log_gen_counter = 0;
static u16 next_free_block = 50;

u16        BMT[USER_BLOCK];            /* LBN -> Data PBN */
LogBlock_t Log_Table[MAX_LOG_BLOCKS];  /* Block-associative log blocks */


/* Optional: sequential direct-to-data write pointer (per LBN) */
static u16 Data_WP[USER_BLOCK];

/* Optional: LPN validity bitmap (tracks if an LPN has ever been written) */
#define LPN_VALID_BYTES  ((MAX_LBA_ADDRESS + 7u) / 8u)
static u8 LPN_Valid[LPN_VALID_BYTES];

/* Reusable merge buffer (32-bit aligned) */
static u32 MergeBufW[FTL_PAGE_BYTES / 4];


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
 * Log helpers
 * ------------------------------------------------------------ */

static int find_log_for_lbn(u16 lbn)
{
    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        if (Log_Table[i].assoc_lbn == lbn) {
            return (int)i;
        }
    }
    return -1;
}

static LogBlock_t *get_log_block_for_lbn(u16 lbn)
{
    int idx = find_log_for_lbn(lbn);
    if (idx < 0) {
        return NULL;
    }
    return &Log_Table[idx];
}

static LogBlock_t *get_free_log_block(void)
{
    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        if (Log_Table[i].assoc_lbn == INVALID_LBN) {
            return &Log_Table[i];
        }
    }
    return NULL;
}

static LogBlock_t *assign_free_log_block(u16 lbn)
{
    LogBlock_t *log = get_free_log_block();
    if (log == NULL) {
        return NULL;
    }

    log->write_ptr = 0;
    log->assoc_lbn = lbn;
    log->gen = log_gen_counter++;
    for (u32 j = 0; j < USER_PAGE; j++) {
        log->lpn[j] = INVALID_LPN;
    }
    return log;
}

static int find_log_page_for_lpn(u16 lbn, u32 lpn, u32 *log_idx_out, u16 *page_out)
{
    int idx = find_log_for_lbn(lbn);
    if (idx < 0) {
        return 0;
    }

    const LogBlock_t *log = &Log_Table[idx];
    for (u16 j = log->write_ptr; j > 0; j--) {
        if (log->lpn[j - 1] == lpn) {
            *log_idx_out = (u32)idx;
            *page_out = (u16)(j - 1);
            return 1;
        }
    }
    return 0;
}

/* ------------------------------------------------------------
 * Best-source table for one LBN from its associated log block.
 * ------------------------------------------------------------ */

typedef struct {
    u8  found;      /* 1 if log has a version for this page */
    u16 log_page;   /* which page inside that log block */
} BestSrc_t;

static BestSrc_t g_best_src[USER_PAGE];

static void build_best_src_for_lbn(u16 lbn)
{
    u32 base = (u32)lbn * (u32)USER_PAGE;
    int log_idx = find_log_for_lbn(lbn);

    /* Init */
    for (u16 p = 0; p < USER_PAGE; p++) {
        g_best_src[p].found    = 0;
        g_best_src[p].log_page = 0;
    }

    if (log_idx < 0) {
        return;
    }

    const LogBlock_t *log = &Log_Table[log_idx];
    for (u16 lp = 0; lp < log->write_ptr; lp++) {
        u32 tag = log->lpn[lp];

        if (tag == INVALID_LPN || tag < base) {
            continue;
        }

        u16 page = (u16)(tag - base);
        if (page >= USER_PAGE) {
            continue;
        }

        g_best_src[page].found    = 1;
        g_best_src[page].log_page = lp;
    }
}


/* ------------------------------------------------------------
 * Log cleaning / merge
 * ------------------------------------------------------------ */

static void reset_log_block(LogBlock_t *log)
{
    log->write_ptr = 0;
    log->assoc_lbn = INVALID_LBN;
    log->gen = log_gen_counter++;

    for (u32 j = 0; j < USER_PAGE; j++) {
        log->lpn[j] = INVALID_LPN;
    }
}

static int pick_victim_log(int prefer_full_only)
{
    int victim = -1;
    u32 best_gen = 0;

    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        const LogBlock_t *log = &Log_Table[i];

        if (log->assoc_lbn == INVALID_LBN) {
            continue;
        }
        if (prefer_full_only && log->write_ptr < USER_PAGE) {
            continue;
        }

        if (victim < 0 || log->gen < best_gen) {
            victim = (int)i;
            best_gen = log->gen;
        }
    }

    return victim;
}

static u32 merge_one_lbn_bast(u16 lbn)
{
    u16 old_data_pbn;
    u16 new_data_pbn;
    int log_idx;
    u32 skip_count = 0;
    u32 from_log_count = 0;
    u32 from_old_count = 0;
    
    /* Timing variables for CPU profiling */
    u64 t_start, t_end;
    u64 t_stall_start;
    u64 total_dt = 0;
    u64 stall_dt = 0;
    u64 compute_dt = 0;
    u64 io_copy_dt = 0; /* Software I/O copy time (equivalent to hw_merge time) */

    g_ftl_mon.merge_count++;
    
    /* 1. Record absolute entry time */
    t_start = mon_now_ns();

    old_data_pbn = BMT[lbn];
    log_idx = find_log_for_lbn(lbn);
    new_data_pbn = Allocate_Free_Block();

    if (new_data_pbn == INVALID_PBN) {
        xil_printf("Merge: no free block for new data\r\n");
        return FTL_NO_SPACE;
    }

    /* Stall 1: Erase destination block */
    t_stall_start = mon_now_ns();
    NFC_Erase(MAKE_NAND_ADDR(new_data_pbn, 0, 0, 0, 0), 1);
    stall_dt += (mon_now_ns() - t_stall_start);

    /* Pure Logic: Build best source table from the associated log block */
    build_best_src_for_lbn(lbn);

    for (u16 page = 0; page < USER_PAGE; page++) {
        u32 target_lpn = (u32)lbn * (u32)USER_PAGE + (u32)page;

        /* Case 1: newest version in some log */
        if (g_best_src[page].found) {
            u16 lp = g_best_src[page].log_page;

            u64 src = MAKE_NAND_ADDR((u16)Log_Table[log_idx].pbn, lp, 0, 0, 0);
            u64 dst = MAKE_NAND_ADDR(new_data_pbn, page, 0, 0, 0);

            /* Stall 2a: CPU blocked waiting for Flash Read & Write */
            t_stall_start = mon_now_ns();
            Read(src, FTL_PAGE_BYTES, MergeBufW);
            Write(dst, FTL_PAGE_BYTES, MergeBufW);
            io_copy_dt += (mon_now_ns() - t_stall_start);
            
            from_log_count++;
            continue;
        }

        /* Case 2: fall back to old data if ever written */
        if (old_data_pbn != INVALID_PBN && lpn_is_valid(target_lpn)) {
            u64 src = MAKE_NAND_ADDR(old_data_pbn, page, 0, 0, 0);
            u64 dst = MAKE_NAND_ADDR(new_data_pbn, page, 0, 0, 0);

            /* Stall 2b: CPU blocked waiting for Flash Read & Write */
            t_stall_start = mon_now_ns();
            Read(src, FTL_PAGE_BYTES, MergeBufW);
            Write(dst, FTL_PAGE_BYTES, MergeBufW);
            io_copy_dt += (mon_now_ns() - t_stall_start);
            
            from_old_count++;
            continue;
        }

        /* Case 3: never written -> keep erased 0xFF, skip program */
        skip_count++;
        continue;
    }
    
    /* Accumulate I/O copy time into total stall time */
    stall_dt += io_copy_dt;

    /* Stall 3: Erase old data block */
    if (old_data_pbn != INVALID_PBN) {
        t_stall_start = mon_now_ns();
        NFC_Erase(MAKE_NAND_ADDR(old_data_pbn, 0, 0, 0, 0), 1);
        stall_dt += (mon_now_ns() - t_stall_start);
    }

    if (log_idx >= 0) {
        t_stall_start = mon_now_ns();
        NFC_Erase(MAKE_NAND_ADDR((u16)Log_Table[log_idx].pbn, 0, 0, 0, 0), 1);
        stall_dt += (mon_now_ns() - t_stall_start);
    }

    /* Pure Logic: Update metadata */
    BMT[lbn] = new_data_pbn;
    Data_WP[lbn] = USER_PAGE;
    if (log_idx >= 0) {
        reset_log_block(&Log_Table[log_idx]);
    }

    /* Update plan statistics */
    g_ftl_mon.merge_plan_skip_pages += skip_count;
    g_ftl_mon.merge_plan_from_log_pages += from_log_count;
    g_ftl_mon.merge_plan_from_old_pages += from_old_count;
    g_ftl_mon.merge_last_skip_count = skip_count;
    g_ftl_mon.merge_last_from_log_count = from_log_count;
    g_ftl_mon.merge_last_from_old_count = from_old_count;

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

    /* Map the software data-copy time to the hw_exec stat for consistency */
    g_ftl_mon.merge_hw_exec_ns_sum += io_copy_dt;
    if (io_copy_dt > g_ftl_mon.merge_hw_exec_ns_max) {
        g_ftl_mon.merge_hw_exec_ns_max = io_copy_dt;
    }

    return FTL_OK;
}

/*
 * Clean one block-associative log block by merging its associated LBN.
 */
static u32 clean_log_block(int victim_idx)
{
    LogBlock_t *vlog = &Log_Table[victim_idx];

    if (vlog->assoc_lbn == INVALID_LBN) {
        reset_log_block(vlog);
        return FTL_OK;
    }

    return merge_one_lbn_bast(vlog->assoc_lbn);
}

/* ------------------------------------------------------------
 * Log allocation (append-only)
 * ------------------------------------------------------------ */

/* Ensure there is a writable log block for one LBN; if not, trigger cleaning. */
static u32 ensure_log_space_for_lbn(u16 lbn, int *did_clean)
{
    LogBlock_t *log = get_log_block_for_lbn(lbn);

    if (did_clean) {
        *did_clean = 0;
    }

    if (log != NULL && log->write_ptr < USER_PAGE) {
        return FTL_OK;
    }

    if (log != NULL) {
        if (did_clean) {
            *did_clean = 1;
        }

        g_ftl_mon.merge_trigger_log_full++;
        if (clean_log_block((int)(log - Log_Table)) == FTL_OK) {
            g_ftl_mon.gc_free_one_log_count++;
            return FTL_OK;
        }
        return FTL_ERR;
    }

    if (get_free_log_block() != NULL) {
        return FTL_OK;
    }

    int victim = pick_victim_log(1);
    if (victim < 0) {
        victim = pick_victim_log(0);
    }
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
    xil_printf("FTL: cleaning log block idx=%d pbn=%u gen=%u lbn=%u\r\n",
           victim, (u32)Log_Table[victim].pbn, (u32)Log_Table[victim].gen,
           (u32)Log_Table[victim].assoc_lbn);
#endif
    u32 st = clean_log_block(victim);
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
    xil_printf("=== BAST FTL Init (Block-Associative Log) Start ===\r\n");

    log_gen_counter = 0;
    next_free_block = 50;

    /* Clear BMT and data write pointers */
    for (u32 i = 0; i < USER_BLOCK; i++) {
        BMT[i] = INVALID_PBN;
        Data_WP[i] = 0;
    }

    /* Clear Log_Table to avoid false "in-use" detection */
    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        Log_Table[i].pbn = INVALID_PBN;
        Log_Table[i].write_ptr = 0;
        Log_Table[i].assoc_lbn = INVALID_LBN;
        Log_Table[i].gen = 0;
        for (u32 j = 0; j < USER_PAGE; j++) {
            Log_Table[i].lpn[j] = INVALID_LPN;
        }
    }

    /* Clear LPN validity bitmap */
    memset(LPN_Valid, 0, sizeof(LPN_Valid));

    /* Optional: load/clear BBT bitmap */
    // Read_BBT_Bitmap();

    /* Initialize log blocks (allocate physical blocks up-front) */
    for (u32 i = 0; i < MAX_LOG_BLOCKS; i++) {
        Log_Table[i].pbn = Allocate_Free_Block();
        if (Log_Table[i].pbn == INVALID_PBN) {
            xil_printf("FTL_Init: failed to allocate log block %u\r\n", i);
            return;
        }
        reset_log_block(&Log_Table[i]);

        xil_printf("LogBlock[%u] -> PBN %u (gen=%u)\r\n",
               i, (u32)Log_Table[i].pbn, (u32)Log_Table[i].gen);
    }

    xil_printf("=== BAST FTL Init Done ===\r\n");
}

u32 FTL_Write(u32 lpn, u8 *buffer)
{
    uint64_t t0 = mon_now_ns();
    WritePath path = WPATH_FAST;

    g_ftl_mon.host_write_pages++;

    if (lpn >= MAX_LBA_ADDRESS) {
        g_ftl_mon.write_invalid_lpn++;
        xil_printf("FTL_Write: invalid LPN %u\r\n", (u32)lpn);
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
        xil_printf("FTL_Write: allocate DataPBN %u for LBN %u\r\n", (u32)pbn, (u32)lbn);
#endif
    }

    /* Fast path: first-time sequential write to data block */
    if (!lpn_is_valid(lpn) && Data_WP[lbn] < USER_PAGE && offset == Data_WP[lbn]) {
        u64 phy = MAKE_NAND_ADDR(BMT[lbn], offset, 0, 0, 0);
        Write(phy, FTL_PAGE_BYTES, (u32 *)buffer);

        lpn_set_valid(lpn);
        Data_WP[lbn]++;
#if FTL_DEBUG
        xil_printf("FTL_Write: LPN %u -> DataPBN %u Page %u (seq)\r\n",
               (u32)lpn, (u32)BMT[lbn], (u32)offset);
#endif
        MON_WRITE_END_PATH(t0, path);
        return FTL_OK;
    }

    /* Otherwise write to log */
    int did_clean = 0;
    u32 st = ensure_log_space_for_lbn(lbn, &did_clean);
    if (st != FTL_OK) {
        MON_WRITE_END_PATH(t0, path);
        return st;
    }
    if (did_clean) {
        path = WPATH_LOGFULL;
    }

    LogBlock_t *log = get_log_block_for_lbn(lbn);
    if (log == NULL) {
        log = assign_free_log_block(lbn);
    }
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
    xil_printf("FTL_Write: LPN %u -> LogPBN %u Page %u LBN %u (gen=%u)\r\n",
           (u32)lpn, (u32)log->pbn, (u32)log_page, (u32)log->assoc_lbn, (u32)log->gen);
#endif
    MON_WRITE_END_PATH(t0, path);
    return FTL_OK;
}

u32 FTL_Read(u32 lpn, u8 *buffer)
{
    if (lpn >= MAX_LBA_ADDRESS) {
        xil_printf("FTL_Read: invalid LPN %u\r\n", (u32)lpn);
        return FTL_ERR;
    }

    u16 lbn = LPN_TO_LBN(lpn);

    /* Check only the associated log block */
    u32 log_idx = 0;
    u16 page = 0;

    if (find_log_page_for_lpn(lbn, lpn, &log_idx, &page)) {
        const LogBlock_t *log = &Log_Table[log_idx];
        u64 phy = MAKE_NAND_ADDR((u16)log->pbn, page, 0, 0, 0);
        Read(phy, FTL_PAGE_BYTES, (u32 *)buffer);
#if FTL_DEBUG
        xil_printf("FTL_Read: LPN %u <- LogPBN %u Page %u (gen=%u)\r\n",
               (u32)lpn, (u32)log->pbn, (u32)page, (u32)log->gen);
#endif
        return FTL_OK;
    }

    /* Fall back to data block */
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
    xil_printf("FTL_Read: LPN %u <- DataPBN %u Page %u\r\n",
           (u32)lpn, (u32)BMT[lbn], (u32)offset);
#endif
    return FTL_OK;
}
