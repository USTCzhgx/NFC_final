
//////////////////////////////////////////////////////////////////////////////////
// NAND Flash timing parameters
//////////////////////////////////////////////////////////////////////////////////
// 83.3M // 50M 
// CMD & ADDR timimg parameter
`define tCMD_ADDR   6
`define tADL        15
`define tWB         5
`define tFEAT      50
`define tVDLY       3
// DATA OUTPUT timimg parameter
`define tWHR        4
`define tRPRE       7 //1
`define tDQSRH      1
`define tRPST       8 //2
`define tRPSTH      10
// DATA INPUT timimg parameter
`define tCCS        20
`define tWPRE       1
`define tWPST       1
`define tWPSTH      1
`define tDBSY       25

// NAND Flash Architecture
`define MAIN_PAGE_BYTE      8192
`define SPARE_PAGE_BYTE     2048
`define PAGE_BYTE           10240
`define PAGE_UTIL_BYTE      8192
`define PAGE_PER_BLOCK      384
`define BLOCK_PER_PLANE     1005
`define BLOCK_PER_LUN       2012
`define PLANE_PER_LUN       2

// Plane Address location at 48-bit Flash Address, must within 24 - 31
`define PLANE_BIT_LOC       27

// Read warmup cycle
`define RD_WARMUP       4'h0
// Program warmup cycle
`define PG_WARMUP       4'h0

