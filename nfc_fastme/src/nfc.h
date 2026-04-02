/**
 * @file    nfc.h
 * @brief   NFC Controller Driver Interface
 *
 * This header defines the high-level API for controlling a NAND Flash
 * controller, including:
 * - Device reset
 * - Timing and configuration setup
 * - Feature access
 * - ONFI parameter page read
 * - Block erase, page program, and page read operations
 *
 * @version 1.1
 * @date    2025-09-26
 * @author  SCMI ZHGX
 */
#ifndef NFC_H
#define NFC_H


#include "xil_types.h"   /* u8/u16/u32/u64 */
#include "xstatus.h"
#include "nand_para.h"   /* BLOCK_NUM, NAND_PAGE_MAIN_SIZE_BYTES, etc. */

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Bad Block Table (Bitmap)
 * ============================================================ */
#define BBT_BLOCK_INDEX 2011u /* physical block  if counted from 1 */
#define BBT_ADDRESS                 MAKE_NAND_ADDR(BBT_BLOCK_INDEX, 0, 0, 0, 0)
#define BBT_SIZE_BYTES  ((BLOCK_NUM + 7) / 8)
#define BBT_SIZE_WORDS  ((BLOCK_NUM + 31) / 32)

extern u8  BBT_Bitmap[BBT_SIZE_BYTES];
extern u32 BBT[BBT_SIZE_WORDS];

/* Mark/test bad block bit */
#define MARK_BAD_BLOCK(blk)   (BBT_Bitmap[(blk) / 8] |=  (u8)(1u << ((blk) % 8)))
#define IS_BAD_BLOCK(blk)     (BBT_Bitmap[(blk) / 8] &   (u8)(1u << ((blk) % 8)))


//void Init_Bad_Block_Table();
void Read_BBT_Bitmap();
int  Write_BBT_Bitmap(void);
void NFC_ScanBadBlocks(void);
void Print_Bad_Block_Info();

//=================================================


/* ============================================================
 * Fundamental Commands
 * ============================================================ */

void NFC_Reset(void);
void NFC_SetTimingMode(void);
void NFC_SetConfiguration(void);
void NFC_GetFeatures(void);
void NFC_ReadParameter(void);


/* ============================================================
 * Optional Extended Commands
 * (Enable when needed)
 * ============================================================ */
// void NFC_ReadONFISignature(void);      /**< 2090h: ONFI Signature ID Read      */
// void NFC_ReadManufacturerID(void);     /**< 0090h: Manufacturer ID Read        */
// void NFC_ReadUniqueID(void);           /**< 00EDh: Unique ID Read              */


/* ============================================================
 * Core Operations
 * ============================================================ */

void NFC_Erase(u64 lba, u32 len);
void NFC_Program(u64 lba, u32 len);
void NFC_Read(u64 lba, u32 len);

int  NFCparameter(u32 *RxBuffer, u32 WordCount);
int  Read(u64 lba, u32 len, u32 *RxBuffer);
int  Write(u64 lba, u32 len, u32 *TxBuffer);

int  Copyback(u64 src_lba, u64 dst_lba);


/* ============================================================
 * DMA Initialization Interface
 * ============================================================ */

int  init_dma(void);


/* ============================================================
 * NFC Status Wait Interface
 * ============================================================ */

void wait_reqfifo(void);

#ifdef __cplusplus
}
#endif

#endif /* NFC_H */
