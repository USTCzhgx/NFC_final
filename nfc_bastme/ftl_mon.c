#include "ftl_mon.h"
#include "xil_printf.h"
#include <string.h>
#include "xparameters.h"
#include "xtmrctr.h"
#include "xil_types.h"

/* ---------- Configuration ---------- */
#ifndef XPAR_TMRCTR_0_DEVICE_ID
#error "AXI Timer driver not found: please add AXI Timer in Vivado and rebuild BSP."
#endif

#define MON_TMR_DEV_ID   XPAR_TMRCTR_0_DEVICE_ID
#define MON_TMR_LO_CNTR  0
#define MON_TMR_HI_CNTR  1

/* Set to 1 after enabling AXI Timer 64-bit mode in Vivado. In cascade mode,
 * counter 0 is the low 32 bits and counter 1 is the high 32 bits.
 */
#ifndef MON_TMR_USE_64BIT
#define MON_TMR_USE_64BIT 1
#endif

#if defined(XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ)
#define MON_TMR_CLK_HZ   XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ
#elif defined(XPAR_CPU_M_AXI_DP_FREQ_HZ)
#define MON_TMR_CLK_HZ   XPAR_CPU_M_AXI_DP_FREQ_HZ
#else
#error "Cannot determine timer clock frequency (MON_TMR_CLK_HZ)."
#endif

static XTmrCtr g_mon_tmr;
static int g_mon_inited = 0;
FtlMonStats g_ftl_mon = {0};

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

static void mon_timer_init(void)
{
    u32 opt_lo;
    u32 opt_hi;

    if (g_mon_inited) {
        return;
    }

    if (XTmrCtr_Initialize(&g_mon_tmr, MON_TMR_DEV_ID) != XST_SUCCESS) {
        g_mon_inited = 0;
        return;
    }

    XTmrCtr_SetResetValue(&g_mon_tmr, MON_TMR_LO_CNTR, 0u);

#if MON_TMR_USE_64BIT
    XTmrCtr_SetResetValue(&g_mon_tmr, MON_TMR_HI_CNTR, 0u);

    opt_lo = XTC_AUTO_RELOAD_OPTION |
             XTC_CASCADE_MODE_OPTION |
             XTC_ENABLE_ALL_OPTION;
    opt_hi = XTC_AUTO_RELOAD_OPTION;

    XTmrCtr_SetOptions(&g_mon_tmr, MON_TMR_LO_CNTR, opt_lo);
    XTmrCtr_SetOptions(&g_mon_tmr, MON_TMR_HI_CNTR, opt_hi);

    XTmrCtr_Reset(&g_mon_tmr, MON_TMR_HI_CNTR);
    XTmrCtr_Reset(&g_mon_tmr, MON_TMR_LO_CNTR);
    XTmrCtr_Start(&g_mon_tmr, MON_TMR_LO_CNTR);
#else
    XTmrCtr_SetOptions(&g_mon_tmr, MON_TMR_LO_CNTR, XTC_AUTO_RELOAD_OPTION);
    XTmrCtr_Reset(&g_mon_tmr, MON_TMR_LO_CNTR);
    XTmrCtr_Start(&g_mon_tmr, MON_TMR_LO_CNTR);
#endif

    g_mon_inited = 1;
}

static void mon_timer_reset_running(void)
{
    if (!g_mon_inited) {
        return;
    }

    XTmrCtr_Stop(&g_mon_tmr, MON_TMR_LO_CNTR);
    XTmrCtr_SetResetValue(&g_mon_tmr, MON_TMR_LO_CNTR, 0u);

#if MON_TMR_USE_64BIT
    XTmrCtr_Stop(&g_mon_tmr, MON_TMR_HI_CNTR);
    XTmrCtr_SetResetValue(&g_mon_tmr, MON_TMR_HI_CNTR, 0u);
    XTmrCtr_Reset(&g_mon_tmr, MON_TMR_HI_CNTR);
#endif

    XTmrCtr_Reset(&g_mon_tmr, MON_TMR_LO_CNTR);
    XTmrCtr_Start(&g_mon_tmr, MON_TMR_LO_CNTR);
}

static uint64_t mon_read_hw_ticks(void)
{
#if MON_TMR_USE_64BIT
    u32 hi_1;
    u32 hi_2;
    u32 lo;

    do {
        hi_1 = XTmrCtr_GetValue(&g_mon_tmr, MON_TMR_HI_CNTR);
        lo   = XTmrCtr_GetValue(&g_mon_tmr, MON_TMR_LO_CNTR);
        hi_2 = XTmrCtr_GetValue(&g_mon_tmr, MON_TMR_HI_CNTR);
    } while (hi_1 != hi_2);

    return (((uint64_t)hi_1) << 32) | (uint64_t)lo;
#else
    return (uint64_t)XTmrCtr_GetValue(&g_mon_tmr, MON_TMR_LO_CNTR);
#endif
}

/* Helper function to safely print 64-bit unsigned integers in Xilinx baremetal */
static void print_u64_stat(const char *label, u64 val)
{
    char buf[24];
    int i = 22;

    print_cstr(label);
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

    print_cstr(&buf[i + 1]);
    print_cstr("\r\n");
}

static void print_u32_dec(u32 val)
{
    char buf[12];
    int i = 10;

    buf[11] = '\0';

    if (val == 0u) {
        buf[i] = '0';
        i--;
    } else {
        while (val > 0u) {
            buf[i] = (char)('0' + (val % 10u));
            val /= 10u;
            i--;
        }
    }

    print_cstr(&buf[i + 1]);
}

static void print_u32_hex8(u32 val)
{
    static const char hex[] = "0123456789abcdef";
    char buf[9];

    for (int i = 0; i < 8; i++) {
        buf[7 - i] = hex[val & 0xFu];
        val >>= 4;
    }
    buf[8] = '\0';

    print_cstr(buf);
}

void FTL_MonTick(void)
{
    (void)mon_now_ns();
}

void FTL_MonReset(void)
{
    mon_timer_init();
    memset(&g_ftl_mon, 0, sizeof(g_ftl_mon));
    mon_timer_reset_running();
}

void FTL_MonPrint(void)
{
#if !FTL_MON_ENABLE
    xil_printf("\r\n[FTL_MON] Disabled at compile time (FTL_MON_ENABLE=0)\r\n");
    return;
#else
    u64 writes = g_ftl_mon.host_write_pages;

    u64 avg_ns = 0;
    if (writes != 0) {
        avg_ns = g_ftl_mon.t_write_ns_sum / writes;
    }

    u64 avg_us = avg_ns / 1000ull;
    u64 max_us = g_ftl_mon.t_write_ns_max / 1000ull;

    xil_printf("\r\n==================== FTL Monitor ====================\r\n");
    print_u64_stat("Host write pages      : ", writes);
    print_u64_stat("Write latency avg(us) : ", avg_us);
    print_u64_stat("Write latency max(us) : ", max_us);

    xil_printf("\r\n--- Slow Path Breakdown ---\r\n");
    print_u64_stat("Slow writes > 1ms      : ", g_ftl_mon.slow_write_1ms);
    print_u64_stat("Slow writes >10ms      : ", g_ftl_mon.slow_write_10ms);
    print_u64_stat("  FAST (Slow)          : ", g_ftl_mon.slow_gt_1ms_fast);
    print_u64_stat("  GC (Slow)            : ", g_ftl_mon.slow_gt_1ms_gc);
    print_u64_stat("  LOGFULL (Slow)       : ", g_ftl_mon.slow_gt_1ms_logfull);

    xil_printf("\r\n--- FTL Events ---\r\n");
    print_u64_stat("write_invalid_lpn      : ", g_ftl_mon.write_invalid_lpn);
    print_u64_stat("gc_trigger_no_free_log : ", g_ftl_mon.gc_trigger_no_free_log);
    print_u64_stat("gc_free_one_log_count  : ", g_ftl_mon.gc_free_one_log_count);
    print_u64_stat("merge_count            : ", g_ftl_mon.merge_count);
    print_u64_stat("merge_trigger_log_full : ", g_ftl_mon.merge_trigger_log_full);

    print_u64_stat("merge_plan_skip_pages  : ", g_ftl_mon.merge_plan_skip_pages);
    print_u64_stat("merge_plan_from_log_pgs: ", g_ftl_mon.merge_plan_from_log_pages);
    print_u64_stat("merge_plan_from_old_pgs: ", g_ftl_mon.merge_plan_from_old_pages);
    print_cstr("merge_last(skip/log/old): ");
    print_u32_dec(g_ftl_mon.merge_last_skip_count);
    outbyte('/');
    print_u32_dec(g_ftl_mon.merge_last_from_log_count);
    outbyte('/');
    print_u32_dec(g_ftl_mon.merge_last_from_old_count);
    print_cstr("\r\n");

    xil_printf("\r\n--- Merge CPU Profiling ---\r\n");
    print_u64_stat("merge_cpu_compute_avg(us): ",
        (g_ftl_mon.merge_count != 0u) ? ((g_ftl_mon.merge_cpu_compute_ns_sum / g_ftl_mon.merge_count) / 1000ull) : 0ull);
    print_u64_stat("merge_cpu_compute_max(us): ", g_ftl_mon.merge_cpu_compute_ns_max / 1000ull);

    print_u64_stat("merge_cpu_stall_avg(us)  : ",
        (g_ftl_mon.merge_count != 0u) ? ((g_ftl_mon.merge_cpu_stall_ns_sum / g_ftl_mon.merge_count) / 1000ull) : 0ull);
    print_u64_stat("merge_cpu_stall_max(us)  : ", g_ftl_mon.merge_cpu_stall_ns_max / 1000ull);

    xil_printf("\r\n--- HW Merge Engine ---\r\n");
    print_u64_stat("merge_hw_timeout_count : ", g_ftl_mon.merge_hw_timeout_count);
    print_u64_stat("merge_hw_last_us       : ", g_ftl_mon.merge_hw_time_ns_last / 1000ull);
    print_u64_stat("merge_hw_avg_us        : ",
        (g_ftl_mon.merge_count != 0u) ? ((g_ftl_mon.merge_hw_time_ns_sum / g_ftl_mon.merge_count) / 1000ull) : 0ull);
    print_u64_stat("merge_hw_max_us        : ", g_ftl_mon.merge_hw_time_ns_max / 1000ull);

    xil_printf("\r\n--- Physical Ops & DMA ---\r\n");
    print_u64_stat("phy_prog_pages         : ", g_ftl_mon.phy_prog_pages);
    print_u64_stat("phy_read_pages         : ", g_ftl_mon.phy_read_pages);
    print_u64_stat("phy_erase_blocks       : ", g_ftl_mon.phy_erase_blocks);

    print_u64_stat("dma_mm2s_bytes         : ", g_ftl_mon.dma_mm2s_bytes);
    print_u64_stat("dma_s2mm_bytes         : ", g_ftl_mon.dma_s2mm_bytes);
    print_u64_stat("total_bytes            : ", g_ftl_mon.dma_total_bytes);
    print_u64_stat("total_MB               : ", g_ftl_mon.dma_total_bytes / (1024ull * 1024ull));

    if (writes != 0) {
        u64 dma_per_host = g_ftl_mon.dma_total_bytes / writes;
        print_u64_stat("DMA per host write(B)  : ", dma_per_host);
    }

    if (writes != 0) {
        u64 wa_x1000_u64 = (g_ftl_mon.phy_prog_pages * 1000ull) / writes;

        u32 wa_int  = (u32)(wa_x1000_u64 / 1000ull);
        u32 wa_frac = (u32)(wa_x1000_u64 % 1000ull);

        print_cstr("Write Amplification    : ");
        print_u32_dec(wa_int);
        outbyte('.');
        if (wa_frac < 10u) {
            print_cstr("00");
        } else if (wa_frac < 100u) {
            print_cstr("0");
        }
        print_u32_dec(wa_frac);
        print_cstr(" (phy_prog/host)\r\n");
    } else {
        xil_printf("Write Amplification    : N/A (host_write_pages=0)\r\n");
    }

    {
        u64 now = mon_now_ns();
        u32 hi  = (u32)(now >> 32);
        u32 lo  = (u32)(now & 0xFFFFFFFFu);

        print_cstr("Now (ns)               : 0x");
        print_u32_hex8(hi);
        print_u32_hex8(lo);
        print_cstr("\r\n");
    }

    xil_printf("=====================================================\r\n\r\n");
#endif
}

uint64_t mon_now_ns(void)
{
    uint64_t ticks;
    uint64_t hz;
    uint64_t sec;
    uint64_t rem;

    mon_timer_init();
    if (!g_mon_inited) {
        return 0;
    }

    ticks = mon_read_hw_ticks();
    hz = (uint64_t)MON_TMR_CLK_HZ;
    sec = ticks / hz;
    rem = ticks % hz;

    return sec * 1000000000ull + (rem * 1000000000ull) / hz;
}
