#ifndef FTL_CORE_H
#define FTL_CORE_H

/* =========================================
 * file: ftl_core.h
 * Flash Translation Layer (FTL) Core
 *
 * This header defines the common FTL
 * interface and data structures for:
 *   - BAST-FTL (block-associative sector translation)
 * ========================================= */

#include "nfc.h"
#include "xil_types.h"
#include "nand_para.h"
#include "xil_printf.h"
#include <string.h>

/* =========================================
 * Data mapping and Block-Associative Log blocks
 * ========================================= */

#define INVALID_PBN   0xFFFF
#define INVALID_LPN   0xFFFFFFFFu
#define INVALID_LBN   0xFFFF

/* LPN decomposition */
#define LPN_TO_LBN(lpn)    ((u16)((lpn) / USER_PAGE))
#define LPN_OFFSET(lpn)    ((u16)((lpn) % USER_PAGE))

/* One log block is associated with at most one LBN at a time. */
typedef struct {
    u32 pbn;                    /* physical block number of this log block */
    u16 write_ptr;              /* next free physical page index (append-only) */
    u16 assoc_lbn;              /* associated LBN, INVALID_LBN if free */
    u32 gen;                    /* allocation generation: larger means newer */
    u32 lpn[USER_PAGE];         /* per-log-page tag: which LPN is stored here */
} LogBlock_t;

extern LogBlock_t Log_Table[MAX_LOG_BLOCKS];
extern u16        BMT[USER_BLOCK];          /* LBN -> Data PBN */

/* =========================================
 * FTL return status
 * ========================================= */
#define FTL_OK         0u    /* operation success */
#define FTL_ERR        1u    /* generic error */
#define FTL_NO_SPACE   2u    /* no free block / log block */

/* =========================================
 * Public APIs
 * ========================================= */
void FTL_Init(void);

/* Allocate a free physical block (skipping bad/in-use blocks) */
u16 Allocate_Free_Block(void);
int ME_MergeOneLbn(u16 lbn);

u32 FTL_Write(u32 lpn, u8 *buffer);
u32 FTL_Read(u32 lpn, u8 *buffer);

#endif /* FTL_CORE_H */
