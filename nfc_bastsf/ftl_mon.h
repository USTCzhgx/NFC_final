#ifndef FTL_MON_H
#define FTL_MON_H

#include "xil_types.h"

/* Enable/disable monitor print at compile time if desired */
#ifndef FTL_MON_ENABLE
#define FTL_MON_ENABLE 1
#endif

/* Time source: platform-specific implementation in ftl_mon.c */
u64 mon_now_ns(void);

/* Call this periodically in main loop to prevent 32-bit timer wrap-around loss */
void FTL_MonTick(void);

/* Optional: classify slow-path reason */
typedef enum {
    WPATH_FAST = 0,
    WPATH_GC,
    WPATH_LOGFULL
} WritePath;

typedef struct {
    u64 host_write_pages;

    /* Latency */
    u64 t_write_ns_sum;
    u64 t_write_ns_max;

    /* Slow write counters */
    u64 slow_write_1ms;
    u64 slow_write_10ms;

    /* Slow-path breakdown for >1ms */
    u64 slow_gt_1ms_gc;
    u64 slow_gt_1ms_logfull;
    u64 slow_gt_1ms_fast;

    /* Events */
    u64 write_invalid_lpn;
    u64 gc_trigger_no_free_log;
    u64 gc_free_one_log_count;
    u64 merge_count;
    u64 merge_trigger_log_full;

    /* Merge Plan Details */
    u64 merge_plan_skip_pages;
    u64 merge_plan_from_log_pages;
    u64 merge_plan_from_old_pages;

    /* Precise CPU Profiling (Compute vs Stall vs I/O Copy) */
    u64 merge_cpu_compute_ns_sum;
    u64 merge_cpu_compute_ns_max;
    u64 merge_cpu_stall_ns_sum;
    u64 merge_cpu_stall_ns_max;
    u64 merge_hw_exec_ns_sum; /* Mapped to software I/O data copy time in pure SW FTL */
    u64 merge_hw_exec_ns_max;

    /* Last merge states */
    u32 merge_last_skip_count;
    u32 merge_last_from_log_count;
    u32 merge_last_from_old_count;

    /* Physical ops (counted in nfc.c Read/Write/Erase) */
    u64 phy_prog_pages;
    u64 phy_read_pages;
    u64 phy_erase_blocks;

    /* DMA traffic */
    u64 dma_mm2s_bytes;   /* host->device via DMA (MM2S) */
    u64 dma_s2mm_bytes;   /* device->host via DMA (S2MM) */
    u64 dma_total_bytes;  /* optional: mm2s + s2mm */
} FtlMonStats;

extern FtlMonStats g_ftl_mon;

/* Reset / print */
void FTL_MonReset(void);
void FTL_MonPrint(void);

/* End-of-write hook (no floating point; updates latency + slow counters) */
static inline void MON_WRITE_END_PATH(u64 t0_ns, WritePath path)
{
#if FTL_MON_ENABLE
    u64 t1 = mon_now_ns();
    u64 dt = t1 - t0_ns;

    g_ftl_mon.t_write_ns_sum += dt;
    if (dt > g_ftl_mon.t_write_ns_max) g_ftl_mon.t_write_ns_max = dt;

    if (dt > 1000000ull) { /* >1 ms */
        g_ftl_mon.slow_write_1ms++;
        if (path == WPATH_GC) g_ftl_mon.slow_gt_1ms_gc++;
        else if (path == WPATH_LOGFULL) g_ftl_mon.slow_gt_1ms_logfull++;
        else g_ftl_mon.slow_gt_1ms_fast++;

        if (dt > 10000000ull) { /* >10 ms */
            g_ftl_mon.slow_write_10ms++;
        }
    }
#else
    (void)t0_ns; (void)path;
#endif
}

#endif