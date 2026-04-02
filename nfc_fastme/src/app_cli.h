#ifndef APP_CLI_H
#define APP_CLI_H

#include "xil_types.h"
#include "xuartlite.h"

/* Runtime context for CLI test application */
typedef struct {
    XUartLite UartLite;

    u64 starting_address;
    u32 start_lpn;
    u32 current_lpn;

    u32 *RxBuffer;
    u32 *TxBuffer;
    u32  ByteCount;

    u8  *FtlTxBuf;
    u8  *FtlRxBuf;
} AppContext;

int  NAND_init(void);
int  App_InitPlatform(AppContext *ctx);
void App_PrintMenu(const AppContext *ctx);
void App_DispatchCmd(AppContext *ctx, u8 recv_char);

#endif /* APP_CLI_H */
