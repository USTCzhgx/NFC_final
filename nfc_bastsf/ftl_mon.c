#include "ftl_mon.h"
#include "xil_printf.h"
#include <string.h>
#include "xparameters.h"
#include "xtmrctr.h"

/* ---------- Configuration ---------- */
/* Make sure your design has an AXI Timer instance.
 * The device id macro name depends on your xparameters.h.
 */
#ifndef XPAR_TMRCTR_0_DEVICE_ID
#error "AXI Timer driver not found: please add AXI Timer in Vivado and rebuild BSP."
#endif

#define MON_TMR_DEV_ID   XPAR_TMRCTR_0_DEVICE_ID
#define MON_TMR_CNTR     0

/* If your xparameters.h provides timer clock frequency, use it.
 * Otherwise fall back to CPU clock.
 */
#if defined(XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ)
#define MON_TMR_CLK_HZ   XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ
#elif defined(XPAR_CPU_M_AXI_DP_FREQ_HZ)
#define MON_TMR_CLK_HZ   XPAR_CPU_M_AXI_DP_FREQ_HZ
#else
#error "Cannot determine timer clock frequency (MON_TMR_CLK_HZ)."
#endif

/* Warning threshold for "large sample gap" only.
 * IMPORTANT: we never drop time even if warning triggers.
 * Set to 0 to disable warnings.
 */
#ifndef MON_WARN_GAP_TICKS
#define MON_WARN_GAP_TICKS ((uint32_t)((uint64_t)MON_TMR_CLK_HZ * 10ull))
#endif

static XTmrCtr g_mon_tmr;
static int g_mon_inited = 0;
FtlMonStats g_ftl_mon = {0};
static uint8_t  g_mon_time_inited = 0;
static uint32_t g_mon_last_ticks  = 0;
static uint64_t g_mon_acc_ticks   = 0;

static void mon_timer_init(void)
{
    if (g_mon_inited) return;

    /* Initialize timer */
    if (XTmrCtr_Initialize(&g_mon_tmr, MON_TMR_DEV_ID) != XST_SUCCESS) {
        /* In baremetal, handle this as a fatal error */
        g_mon_inited = 0;
        return;
    }

    /* Auto-reload + downcount disabled => free-running up counter */
    XTmrCtr_SetOptions(&g_mon_tmr, MON_TMR_CNTR, 0);

    XTmrCtr_Reset(&g_mon_tmr, MON_TMR_CNTR);
    XTmrCtr_Start(&g_mon_tmr, MON_TMR_CNTR);

    g_mon_inited = 1;
}

/* Helper function to safely print 64-bit unsigned integers in Xilinx baremetal */
static void print_u64_stat(const char *label, u64 val)
{
    xil_printf("%s", label);
    char buf[24];
    int i = 22;
    buf[23] = '\0';
    
    if (val == 0) {
        buf[i] = '0';
        i--;
    } else {
        while (val > 0) {
            buf[i] = (char)('0' + (val % 10ull));
            val /= 10ull;
            i--;
        }
    }
    xil_printf("%s\r\n", &buf[i + 1]);
}

/* Call periodically to prevent timer wrap-around loss */
void FTL_MonTick(void)
{
    (void)mon_now_ns();
}

/* Reset all monitor statistics. */
void FTL_MonReset(void)
{
    memset(&g_ftl_mon, 0, sizeof(g_ftl_mon));

    mon_timer_init();
    XTmrCtr_Reset(&g_mon_tmr, MON_TMR_CNTR);
    XTmrCtr_Start(&g_mon_tmr, MON_TMR_CNTR);

    g_mon_time_inited = 0;
    g_mon_last_ticks  = 0;
    g_mon_acc_ticks   = 0;
}

/* Print monitor summary. */
void FTL_MonPrint(void)
{
#if !FTL_MON_ENABLE
    xil_printf("\r\n[FTL_MON] Disabled at compile time (FTL_MON_ENABLE=0)\r\n");
    return;
#else
    u64 writes = g_ftl_mon.host_write_pages;

    /* Average latency in ns (integer division). */
    u64 avg_ns = 0;
    if (writes != 0) {
        avg_ns = g_ftl_mon.t_write_ns_sum / writes;
    }

    /* Convert to us for easier reading. */
    u64 avg_us = avg_ns / 1000ull;
    u64 max_us = g_ftl_mon.t_write_ns_max / 1000ull;

    xil_printf("\r\n==================== FTL Monitor ====================\r\n");
    print_u64_stat("Host write pages      : ", writes);
    print_u64_stat("Write latency avg(us) : ", avg_us);
    print_u64_stat("Write latency max(us) : ", max_us);

    xil_printf("\r\n--- Slow Path Breakdown ---\r\n");
    print_u64_stat("Slow writes > 1ms     : ", g_ftl_mon.slow_write_1ms);
    print_u64_stat("Slow writes >10ms     : ", g_ftl_mon.slow_write_10ms);
    print_u64_stat("  FAST (Slow)         : ", g_ftl_mon.slow_gt_1ms_fast);
    print_u64_stat("  GC (Slow)           : ", g_ftl_mon.slow_gt_1ms_gc);
    print_u64_stat("  LOGFULL (Slow)      : ", g_ftl_mon.slow_gt_1ms_logfull);

    xil_printf("\r\n--- FTL Events ---\r\n");
    print_u64_stat("write_invalid_lpn     : ", g_ftl_mon.write_invalid_lpn);
    print_u64_stat("gc_trigger_no_free_log: ", g_ftl_mon.gc_trigger_no_free_log);
    print_u64_stat("gc_free_one_log_count : ", g_ftl_mon.gc_free_one_log_count);
    print_u64_stat("merge_count           : ", g_ftl_mon.merge_count);
    print_u64_stat("merge_trigger_log_full: ", g_ftl_mon.merge_trigger_log_full);
    
    print_u64_stat("merge_plan_skip_pages : ", g_ftl_mon.merge_plan_skip_pages);
    print_u64_stat("merge_plan_from_log   : ", g_ftl_mon.merge_plan_from_log_pages);
    print_u64_stat("merge_plan_from_old   : ", g_ftl_mon.merge_plan_from_old_pages);
    xil_printf("merge_last(skip/log/old): %u/%u/%u\r\n",
           (unsigned)g_ftl_mon.merge_last_skip_count,
           (unsigned)g_ftl_mon.merge_last_from_log_count,
           (unsigned)g_ftl_mon.merge_last_from_old_count);

    xil_printf("\r\n--- Merge CPU Profiling ---\r\n");
    print_u64_stat("merge_cpu_compute_avg(us): ", 
        (g_ftl_mon.merge_count != 0u) ? ((g_ftl_mon.merge_cpu_compute_ns_sum / g_ftl_mon.merge_count) / 1000ull) : 0ull);
    print_u64_stat("merge_cpu_compute_max(us): ", g_ftl_mon.merge_cpu_compute_ns_max / 1000ull);
    
    print_u64_stat("merge_cpu_stall_avg(us)  : ", 
        (g_ftl_mon.merge_count != 0u) ? ((g_ftl_mon.merge_cpu_stall_ns_sum / g_ftl_mon.merge_count) / 1000ull) : 0ull);
    print_u64_stat("merge_cpu_stall_max(us)  : ", g_ftl_mon.merge_cpu_stall_ns_max / 1000ull);
    
    /* In this pure SW design, hw_exec maps to pure I/O data copy time */
    print_u64_stat("merge_io_copy_avg(us)    : ", 
        (g_ftl_mon.merge_count != 0u) ? ((g_ftl_mon.merge_hw_exec_ns_sum / g_ftl_mon.merge_count) / 1000ull) : 0ull);
    print_u64_stat("merge_io_copy_max(us)    : ", g_ftl_mon.merge_hw_exec_ns_max / 1000ull);

    xil_printf("\r\n--- Physical Ops & DMA ---\r\n");
    print_u64_stat("phy_prog_pages        : ", g_ftl_mon.phy_prog_pages);
    print_u64_stat("phy_read_pages        : ", g_ftl_mon.phy_read_pages);
    print_u64_stat("phy_erase_blocks      : ", g_ftl_mon.phy_erase_blocks);
    print_u64_stat("dma_mm2s_bytes        : ", g_ftl_mon.dma_mm2s_bytes);
    print_u64_stat("dma_s2mm_bytes        : ", g_ftl_mon.dma_s2mm_bytes);
    print_u64_stat("dma_total_bytes       : ", g_ftl_mon.dma_total_bytes);
    print_u64_stat("dma_total_MB          : ", g_ftl_mon.dma_total_bytes / (1024ull * 1024ull));

    if (writes != 0) {
        u64 dma_per_host = g_ftl_mon.dma_total_bytes / writes;
        print_u64_stat("DMA per host write(B) : ", dma_per_host);
    }

    if (writes != 0) {
        u64 wa_x1000_u64 = (g_ftl_mon.phy_prog_pages * 1000ull) / writes;
        u32 wa_int  = (u32)(wa_x1000_u64 / 1000ull);
        u32 wa_frac = (u32)(wa_x1000_u64 % 1000ull);

        xil_printf("Write Amplification   : %u.", wa_int);
        if (wa_frac < 10)      xil_printf("00%u", wa_frac);
        else if (wa_frac < 100) xil_printf("0%u", wa_frac);
        else                   xil_printf("%u", wa_frac);
        xil_printf(" (phy_prog/host)\r\n");
    } else {
        xil_printf("Write Amplification   : N/A (host_write_pages=0)\r\n");
    }

    {
        u64 now = mon_now_ns();
        u32 hi  = (u32)(now >> 32);
        u32 lo  = (u32)(now & 0xFFFFFFFFu);
        /* Safe hex print for 64-bit split */
        xil_printf("Now (ns)              : 0x%08x%08x\r\n", (unsigned)hi, (unsigned)lo);
    }
    xil_printf("=====================================================\r\n\r\n");
#endif
}

uint64_t mon_now_ns(void)
{
    mon_timer_init();

    uint32_t cur = (uint32_t)XTmrCtr_GetValue(&g_mon_tmr, MON_TMR_CNTR);

    if (!g_mon_time_inited) {
        /* First sample defines base; time starts at 0 */
        g_mon_last_ticks = cur;
        g_mon_acc_ticks  = 0;
        g_mon_time_inited = 1;
    } else {
        /* Wrap-around safe delta */
        uint32_t delta = (uint32_t)(cur - g_mon_last_ticks);

        /* Optional warning: large time gap between samples. */
#if defined(MON_WARN_GAP_TICKS)
        if ((MON_WARN_GAP_TICKS != 0u) && (delta > (uint32_t)(MON_WARN_GAP_TICKS))) {
            xil_printf("[FTL_MON] Warning: large sample gap. last=%u cur=%u delta=%u\r\n",
                       (unsigned)g_mon_last_ticks, (unsigned)cur, (unsigned)delta);
        }
#endif

        /* Always accumulate to keep time correct and monotonic */
        g_mon_acc_ticks += (uint64_t)delta;
        g_mon_last_ticks = cur;
    }

    /* ticks -> ns without overflow */
    uint64_t hz  = (uint64_t)MON_TMR_CLK_HZ;
    uint64_t sec = g_mon_acc_ticks / hz;
    uint64_t rem = g_mon_acc_ticks % hz;

    return sec * 1000000000ull + (rem * 1000000000ull) / hz;
}
