#include "nfc_reg.h"

/* ============================================================
 * Register Write Functions
 * ============================================================ */
void NFC_SetOpcode(u32 opcode)
{
    /* opcode only uses lower 16 bits */
    Xil_Out32(NFC_REG_BASEADDR + NFC_OPCODE_REG, opcode & 0xFFFF);
}

void NFC_SetLen(u32 len)
{
    /* length uses lower 24 bits */
    Xil_Out32(NFC_REG_BASEADDR + NFC_LEN_REG, len & 0xFFFFFF);
}

void NFC_SetLBA(u64 lba)
{
    u32 lba_low  = (u32)(lba & 0xFFFFFFFF);
    u32 lba_high = (u32)((lba >> 32) & 0xFFFF);

    Xil_Out32(NFC_REG_BASEADDR + NFC_LBALOW_REG,  lba_low);
    Xil_Out32(NFC_REG_BASEADDR + NFC_LBAHIGH_REG, lba_high);
}

/* ============================================================
 * Register Read Functions
 * ============================================================ */
u32 NFC_GetStatus(void)
{
    return Xil_In32(NFC_REG_BASEADDR + NFC_STATUS_REG);
}

/* ============================================================
 * Debug Functions
 * ============================================================ */
void print_nfc_status(u32 status)
{
    xil_printf("NFC Status Register: 0x%08X\r\n", status);

    xil_printf("  [0] REQ FIFO FULL     : %d\r\n", (status >> 0) & 0x1);
    // xil_printf("  [1] RDFIFO Empty      : %d\r\n", (status >> 1) & 0x1);
    // xil_printf("  [2] WRFIFO Full       : %d\r\n", (status >> 2) & 0x1);
    // xil_printf("  [3] NFC Busy          : %d\r\n", (status >> 3) & 0x1);
    // xil_printf("  [4] Error Flag        : %d\r\n", (status >> 4) & 0x1);
    // xil_printf("  [5] ECC Ready         : %d\r\n", (status >> 5) & 0x1);
    // xil_printf("  [6] DMA Req           : %d\r\n", (status >> 6) & 0x1);
    // xil_printf("  [7] Operation Done    : %d\r\n", (status >> 7) & 0x1);

    xil_printf("\r\n");
}

/* ============================================================
 * NFC Trigger
 * ============================================================ */
void NFC_Start(void)
{
    Xil_Out32(NFC_REG_BASEADDR + NFC_START_REG, 0x1);
}
