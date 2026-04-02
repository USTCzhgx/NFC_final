#include "nfc_reg.h"
#include "nfc.h"
/* ============================================================
 * NFC register write/read
 * ============================================================ */
void NFC_SetOpcode(uint32_t opcode)
{
    /* opcode uses lower 16 bits */
    NFC_WR32(NFC_OPCODE_REG, opcode & 0xFFFFu);
}

void NFC_SetLen(uint32_t len)
{
    /* length uses lower 24 bits */
    NFC_WR32(NFC_LEN_REG, len & 0xFFFFFFu);
}

void NFC_SetLBA(uint64_t lba)
{
    uint32_t lba_low  = (uint32_t)(lba & 0xFFFFFFFFull);
    uint32_t lba_high = (uint32_t)((lba >> 32) & 0xFFFFull);

    NFC_WR32(NFC_LBALOW_REG,  lba_low);
    NFC_WR32(NFC_LBAHIGH_REG, lba_high & 0xFFFFu);
}

uint32_t NFC_GetStatus(void)
{
    return NFC_RD32(NFC_STATUS_REG);
}

void NFC_Start(void)
{
    /* start is a 1-cycle trigger (write-1 pulse) */
    NFC_WR32(NFC_START_REG, 1u);
}

/* ============================================================
 * NFC flow control helpers
 * ============================================================ */
uint32_t NFC_TopStatus(uint32_t status)
{
    return (status & NFC_STAT_TOP_STATUS_MASK) >> NFC_STAT_TOP_STATUS_SHIFT;
}

void NFC_WaitCanSend(void)
{
    /* Wait until request FIFO has space and NFC reports ready */
    while (NFC_GetStatus() & NFC_STAT_REQ_AFULL_MASK) { }
    while ((NFC_GetStatus() & NFC_STAT_NFC_READY_MASK) == 0u) { }
}

void NFC_SendCmd(uint16_t opc, uint64_t lba, uint32_t len)
{
    NFC_WaitCanSend();
    NFC_SetOpcode((uint32_t)opc);
    NFC_SetLBA(lba);
    NFC_SetLen(len);
    NFC_Start();
}

void NFC_WaitDone(void)
{
    /* Busy wait until status is not BUSY(01) and not WAIT(10) */
    uint32_t ts;
    do {
        ts = NFC_TopStatus(NFC_GetStatus());
    } while ((ts == 1u) || (ts == 2u));
}

/* ============================================================
 * BRAM helpers
 * ============================================================ */
void BRAM_WriteWords(uint32_t base_word, const uint32_t *src, uint32_t count)
{
    volatile uint32_t *dst = BRAM_WORD_PTR(base_word);
    uint32_t i;

    for (i = 0; i < count; i++) {
        dst[i] = src[i];
    }

    /* Optional: readback barrier */
    (void)dst[0];
}

/* ============================================================
 * MergePlan helpers
 * ============================================================ */
void MERGE_SetHeader(uint32_t lbn,
                     uint16_t new_pbn,
                     uint16_t old_pbn,
                     uint32_t entry_cnt,
                     uint32_t base_word)
{
    NFC_WR32(NFC_PLAN_LBN_REG, lbn);
    NFC_WR32(NFC_PLAN_PBN_REG, ((uint32_t)old_pbn << 16) | (uint32_t)new_pbn);
    NFC_WR32(NFC_PLAN_ENTRY_CNT_REG, entry_cnt);
    NFC_WR32(NFC_PLAN_BASE_WORD_REG, base_word);
}

void MERGE_Start(void)
{
    /* merge_start is a 1-cycle trigger (write-1 pulse) */
    NFC_WR32(NFC_MERGE_CTRL_REG, 1u);
}

uint32_t MERGE_GetStatus(void)
{
    return NFC_RD32(NFC_MERGE_STATUS_REG);
}

void MERGE_WaitBusyClear(void)
{
    /* Prefer BUSY level to avoid missing DONE pulse */
    while (MERGE_GetStatus() & NFC_MG_STAT_BUSY_MASK) { }
}
