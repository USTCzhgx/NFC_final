#include "app_cli.h"
#include "nand_para.h"
#include "ftl_core.h"
#include "nfc.h"


#define RX_WORD_COUNT (NAND_PAGE_MAIN_SIZE_BYTES / 4) //one page size  max 16k
#define TX_WORD_COUNT (NAND_PAGE_MAIN_SIZE_BYTES / 4)

static u32 RxBuffer[RX_WORD_COUNT];
static u32 TxBuffer[TX_WORD_COUNT];
static u8  FtlTxBuf[NAND_PAGE_MAIN_SIZE_BYTES];
static u8  FtlRxBuf[NAND_PAGE_MAIN_SIZE_BYTES];




int main(void)
{


    AppContext ctx;

    ctx.starting_address = MAKE_NAND_ADDR(50,0,0,0,0);
    ctx.start_lpn        = 1;
    ctx.current_lpn      = 0;

    ctx.RxBuffer  = RxBuffer;
    ctx.TxBuffer  = TxBuffer;
    ctx.ByteCount = RX_WORD_COUNT * 4;

    ctx.FtlTxBuf  = FtlTxBuf;
    ctx.FtlRxBuf  = FtlRxBuf;

    if (App_InitPlatform(&ctx) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    if (NAND_init()!= XST_SUCCESS) {
            return XST_FAILURE;
        }

    Read_BBT_Bitmap();

    FTL_Init();
    App_PrintMenu(&ctx);

    while (1) {
        u8 ch;
        if (XUartLite_Recv(&ctx.UartLite, &ch, 1) != 0) {
            App_DispatchCmd(&ctx, ch);
        }
    }

    return 0;
}
