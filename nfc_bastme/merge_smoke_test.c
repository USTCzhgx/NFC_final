#include "nfc_reg.h"
#include "xil_printf.h"
#include <stdint.h>
#include "merge_smoke_test.h"

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

static void print_u32_dec(uint32_t val)
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

static void print_u32_hex8(uint32_t val)
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
 * Optional: timeout wait to avoid deadlock during bring-up
 * ------------------------------------------------------------ */
static int merge_wait_busy_clear_timeout(uint32_t max_iters)
{
    while (max_iters--) {
        if ((MERGE_GetStatus() & NFC_MG_STAT_BUSY_MASK) == 0u) {
            return 0;
        }
    }
    return -1;
}

/* ------------------------------------------------------------
 * Smoke test for normal path
 * All valid entries are forced to cross-plane migration.
 * ------------------------------------------------------------ */
int merge_smoke_test(void)
{
    const uint32_t entry_cnt      = 6u;
    const uint32_t plan_base_word = 0x000000f0u; /* WORD index in BRAM */
    const uint32_t plan_lbn       = 12u;

    /* Force destination block to even plane */
    const uint16_t new_pbn        = 52u;

    /* Force old block to odd plane so FROM_OLD also goes normal path */
    const uint16_t old_pbn        = 51u;

    uint32_t plan[6];

    /* Plan meaning:
     * idx=0: FROM_LOG -> src = (pbn=51,page=0), dst = (new_pbn,page=0)
     * idx=1: FROM_OLD -> src = (old_pbn,page=1), dst = (new_pbn,page=1)
     * idx=2: SKIP     -> no NFC command
     * idx=3: FROM_LOG -> src = (pbn=51,page=2), dst = (new_pbn,page=3)
     * idx=4: SKIP     -> no NFC command
     * idx=5: FROM_LOG -> src = (pbn=51,page=3), dst = (new_pbn,page=5)
     *
     * Plane rule:
     *   odd block  -> one plane
     *   even block -> the other plane
     *
     * With new_pbn = 52 (even) and all source blocks = 51 (odd),
     * every valid entry must take the normal path instead of copyback.
     *
     * IMPORTANT:
     *   For FROM_OLD (idx=1), entry src_pbn/src_page are ignored by HW.
     *   HW should override source with:
     *       src_pbn  = old_pbn
     *       src_page = dst_page
     */
    plan[0] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_FROM_LOG, 51u, 0u);
    plan[1] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_FROM_OLD, 0u,  0u);
    plan[2] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_SKIP,     0u,  0u);
    plan[3] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_FROM_LOG, 51u, 2u);
    plan[4] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_SKIP,     0u,  0u);
    plan[5] = MERGE_PLAN_PACK(MERGE_PLAN_SRC_FROM_LOG, 51u, 3u);

    xil_printf("\r\n[merge_smoke_test] start normal-path test\r\n");
    print_cstr("  plan_base_word=0x");
    print_u32_hex8(plan_base_word);
    print_cstr(" entry_cnt=");
    print_u32_dec(entry_cnt);
    print_cstr("\r\n");
    print_cstr("  new_pbn=");
    print_u32_dec(new_pbn);
    print_cstr(" old_pbn=");
    print_u32_dec(old_pbn);
    print_cstr("\r\n");
    xil_printf("  Expectation: all valid entries use normal path\r\n");

    /* 1) Write plan into BRAM (WORD addressing) */
    BRAM_WriteWords(plan_base_word, plan, entry_cnt);

    /* 2) Optional readback for sanity */
    {
        volatile uint32_t *p = BRAM_WORD_PTR(plan_base_word);
        print_cstr("  BRAM[base+0]=0x");
        print_u32_hex8(p[0]);
        print_cstr("\r\n");
        print_cstr("  BRAM[base+1]=0x");
        print_u32_hex8(p[1]);
        print_cstr("\r\n");
        print_cstr("  BRAM[base+3]=0x");
        print_u32_hex8(p[3]);
        print_cstr("\r\n");
        print_cstr("  BRAM[base+5]=0x");
        print_u32_hex8(p[5]);
        print_cstr("\r\n");
    }

    /* 3) Program merge header */
    MERGE_SetHeader(plan_lbn, new_pbn, old_pbn, entry_cnt, plan_base_word);
    usleep(10);

    /* 4) Trigger merge */
    MERGE_Start();
    usleep(10);

    /* 5) Wait done */
    if (merge_wait_busy_clear_timeout(2000000u) != 0) {
        print_cstr("  ERROR: merge busy timeout, MERGE_STATUS=0x");
        print_u32_hex8(MERGE_GetStatus());
        print_cstr("\r\n");
        return -1;
    }

    print_cstr("  merge done, MERGE_STATUS=0x");
    print_u32_hex8(MERGE_GetStatus());
    print_cstr("\r\n");
    xil_printf("[merge_smoke_test] PASS\r\n");
    return 0;
}
