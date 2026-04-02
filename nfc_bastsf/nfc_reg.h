#ifndef NFC_REG_H
#define NFC_REG_H

#include "xil_io.h"
#include "sleep.h"

/* ============================================================
 * Base Address Definitions
 * ============================================================ */
#define NFC_REG_BASEADDR       0x44A00000U
#define AXIUART_BASEADDR       0x40600000U
#define MB_BRAM_BASEADDR       0x00000000U


/* ============================================================
 * NFC Register Offsets
 * ============================================================ */
#define NFC_OPCODE_REG         0x00
#define NFC_LEN_REG            0x04
#define NFC_LBALOW_REG         0x08
#define NFC_LBAHIGH_REG        0x0C
#define NFC_START_REG          0x10
#define NFC_STATUS_REG         0x14

#define NFC_STAT_REQ_AFULL_MASK      (1u << 11)    /* bit11 */
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
 * Function Prototypes
 * ============================================================ */
void NFC_SetOpcode(u32 opcode);
void NFC_SetLen(u32 len);
void NFC_SetLBA(u64 lba);
void NFC_SetSel(u32 sel);

u32  NFC_GetStatus(void);

void NFC_WaitIdle(void);

#endif /* NFC_REG_H */
