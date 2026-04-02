#ifndef NAND_PARA_H
#define NAND_PARA_H
// Address layout uses block[0] at bit 27; there is no separate plane bit.

/* NAND geometry parameters */
#define NAND_PAGE_MAIN_SIZE_BYTES      8*1024
#define NAND_PAGE_SPARE_SIZE_BYTES     2048
#define NAND_PAGE_TOTAL_SIZE_BYTES     (NAND_PAGE_MAIN_SIZE_BYTES + NAND_PAGE_SPARE_SIZE_BYTES)

#define PAGE_NUM            384//1152
#define BLOCK_NUM           2010//1005


//FTL 
#define USER_BLOCK          100    // USER available block
#define USER_PAGE           100    // USER available PAGE
#define MAX_LOG_BLOCKS      2
#define MAX_LBA_ADDRESS     (USER_BLOCK * USER_PAGE) 
#define FTL_PAGE_BYTES  NAND_PAGE_MAIN_SIZE_BYTES  


#define COL_SHIFT     0
#define PAGE_SHIFT    16
#define BLOCK_SHIFT   27
#define LUN_SHIFT     39



//phy address
static inline u64 MAKE_NAND_ADDR(
        u16 block,
        u16 page,
        u8  plane,
        u8  lun,
        u16 column)
{
    (void)plane;
    return  ((u64)column << COL_SHIFT)  |
            ((u64)page   << PAGE_SHIFT) |
            ((u64)block  << BLOCK_SHIFT)|
            ((u64)lun    << LUN_SHIFT);
}


#endif
