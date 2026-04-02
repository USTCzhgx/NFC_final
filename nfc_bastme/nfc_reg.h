#ifndef NFC_REG_H
#define NFC_REG_H

#include "xil_io.h"
#include "sleep.h"
#include <stdint.h>

/* ============================================================
 * Base Address Definitions
 * ============================================================ */
#define NFC_REG_BASEADDR       0x44A00000U
#define BRAM_BASEADDR          0xC0000000U

/* ============================================================
 * NFC Register Offsets
 * ============================================================ */
#define NFC_OPCODE_REG         0x00
#define NFC_LEN_REG            0x04
#define NFC_LBALOW_REG         0x08
#define NFC_LBAHIGH_REG        0x0C
#define NFC_START_REG          0x10
#define NFC_STATUS_REG         0x14

/* ============================================================
 * MergePlan Register Offsets (idx6..idx11)
 * ============================================================ */
#define NFC_PLAN_LBN_REG        0x18
#define NFC_PLAN_PBN_REG        0x1C  /* {OLD[31:16], NEW[15:0]} */
#define NFC_PLAN_ENTRY_CNT_REG  0x20
#define NFC_PLAN_BASE_WORD_REG  0x24  /* word address base */
#define NFC_MERGE_CTRL_REG      0x28  /* write bit0 pulse */
#define NFC_MERGE_STATUS_REG    0x2C  /* {30'd0, done, busy} */

/* ============================================================
 * STATUS bit definitions (must match your regfile packing!)
 * Current assumed packing:
 *   reg_status = {..., req_fifo_almost_full(bit11), top_status[10:9], top_sr[8:1], nfc_ready(bit0)}
 * ============================================================ */
#define NFC_STAT_NFC_READY_MASK      (1u << 0)     /* bit0 */
#define NFC_STAT_TOP_SR_SHIFT        1
#define NFC_STAT_TOP_SR_MASK         (0xFFu << NFC_STAT_TOP_SR_SHIFT)
#define NFC_STAT_TOP_STATUS_SHIFT    9             /* bits[10:9] */
#define NFC_STAT_TOP_STATUS_MASK     (3u << NFC_STAT_TOP_STATUS_SHIFT)
#define NFC_STAT_REQ_AFULL_MASK      (1u << 11)    /* bit11 */

/* Merge status bits */
#define NFC_MG_STAT_BUSY_MASK        (1u << 0)
#define NFC_MG_STAT_DONE_MASK        (1u << 1)

/* MergePlan entry encoding (Scheme A) */
#define MERGE_PLAN_SRC_SKIP          0u
#define MERGE_PLAN_SRC_FROM_LOG      1u
#define MERGE_PLAN_SRC_FROM_OLD      2u

#define MERGE_PLAN_SRC_TYPE_SHIFT    30u
#define MERGE_PLAN_SRC_PBN_SHIFT     16u
#define MERGE_PLAN_SRC_TYPE_MASK     0x3u
#define MERGE_PLAN_SRC_PBN_MASK      0x3FFFu
#define MERGE_PLAN_SRC_PAGE_MASK     0xFFFFu

#define MERGE_PLAN_PACK(src_type, src_pbn, src_page) \
    ((((uint32_t)(src_type) & MERGE_PLAN_SRC_TYPE_MASK) << MERGE_PLAN_SRC_TYPE_SHIFT) | \
     (((uint32_t)(src_pbn)  & MERGE_PLAN_SRC_PBN_MASK)  << MERGE_PLAN_SRC_PBN_SHIFT)  | \
     ((uint32_t)(src_page)  & MERGE_PLAN_SRC_PAGE_MASK))

/* ============================================================
 * NFC Commands
 * ============================================================ */
#define NFC_CMD_RESET              0x00FF
#define NFC_CMD_SET_Timing         0x01EF
#define NFC_CMD_SET_Configuration  0x02EF

#define NFC_CMD_GET_FEATURE        0x01EE

#define NFC_CMD_READ_PARAM1        0x00EC
#define NFC_CMD_READ_PARAM2        0x2090
#define NFC_CMD_READ_PARAM3        0x0090
#define NFC_CMD_READ_UNIQUE        0x00ED

#define NFC_CMD_BLOCK_ERASE        0xD060
#define NFC_CMD_PAGE_PROG          0x1080
#define NFC_CMD_PAGE_READ          0x3000

/* ============================================================
 * MMIO helpers
 * ============================================================ */
#define NFC_WR32(off, val)   Xil_Out32((NFC_REG_BASEADDR + (off)), (uint32_t)(val))
#define NFC_RD32(off)        Xil_In32 ((NFC_REG_BASEADDR + (off)))

/* BRAM is word-addressed by plan_base_word in HW. */
#define BRAM_WORD_PTR(word_index) \
    ((volatile uint32_t *)(BRAM_BASEADDR + ((uint32_t)(word_index) << 2)))

/* ============================================================
 * NFC low-level register APIs
 * ============================================================ */
void NFC_SetOpcode(uint32_t opcode);
void NFC_SetLen(uint32_t len);
void NFC_SetLBA(uint64_t lba);

uint32_t NFC_GetStatus(void);
void     NFC_Start(void);

/* ============================================================
 * NFC safe send APIs
 * ============================================================ */
uint32_t NFC_TopStatus(uint32_t status);
void     NFC_WaitCanSend(void);
void     NFC_SendCmd(uint16_t opc, uint64_t lba, uint32_t len);
void     NFC_WaitDone(void);

/* ============================================================
 * BRAM helpers for plan table
 * ============================================================ */
void BRAM_WriteWords(uint32_t base_word, const uint32_t *src, uint32_t count);

/* ============================================================
 * MergePlan helpers
 * ============================================================ */
void MERGE_SetHeader(uint32_t lbn,
                     uint16_t new_pbn,
                     uint16_t old_pbn,
                     uint32_t entry_cnt,
                     uint32_t base_word);

void MERGE_Start(void);
uint32_t MERGE_GetStatus(void);
void MERGE_WaitBusyClear(void);

#endif /* NFC_REG_H */
