`timescale 1ns / 1ps

module nfc_channel_test_tb(
    );

// 时钟与复位参数
parameter XDMA_CLK_PERIOD = 10;   // 100 MHz
parameter NAND_CLK_FAST_PERIOD = 2.5;  // 400 MHz
parameter NAND_CLK_SLOW_PERIOD = 10; // 100 MHz
parameter NAND_CLK_USR_PERIOD = 20; // 50 MHz

// 模块参数
parameter DATA_WIDTH = 32;
parameter WAY_NUM = 4;
parameter PATCH = "FALSE";

// 时钟与复位信号
reg xdma_clk;
reg nand_clk_fast;
reg nand_clk_slow;
reg nand_usr_clk;
reg xdma_resetn;
reg nand_clk_rst;
reg nand_usr_rstn;


// 控制信号
reg [3:0] i_init;
reg [3:0] i_start;
wire [3:0] o_done;
reg [7:0] i_mode;
reg [47:0] i_lba;
reg [23:0] i_len;
reg [31:0] i_page_num;
reg [31:0] i_req_num;

// 状态与错误信号
wire [31:0] res_cnt_0, res_cnt_1, res_cnt_2, res_cnt_3;
wire [31:0] data_err_num_0, data_err_num_1, data_err_num_2, data_err_num_3;
wire [63:0] run_cycles_0, run_cycles_1, run_cycles_2, run_cycles_3;

// NAND Flash接口
wire [WAY_NUM-1:0] O_NAND_CE_N;
reg [WAY_NUM-1:0] I_NAND_RB_N;
wire O_NAND_WE_N;
wire O_NAND_CLE;
wire O_NAND_ALE;
wire O_NAND_WP_N;
wire O_NAND_RE_P;
wire O_NAND_RE_N;
wire IO_NAND_DQS_P;
wire IO_NAND_DQS_N;
wire [7:0] IO_NAND_DQ;

// 被测模块实例化
nfc_channel_test #(
    .DATA_WIDTH(DATA_WIDTH),
    .WAY_NUM(WAY_NUM),
    .PATCH(PATCH)
) uut (
    .xdma_clk(xdma_clk),
    .xdma_resetn(xdma_resetn),
    .nand_clk_fast(nand_clk_fast),
    .nand_clk_slow(nand_clk_slow),
    .nand_clk_rst(nand_clk_rst),
    .nand_usr_rstn(nand_usr_rstn),
    .nand_usr_clk(nand_usr_clk), 
    .i_init(i_init),
    .i_start(i_start),
    .o_done(o_done),
    .i_mode(i_mode),
    .i_lba(i_lba),
    .i_len(i_len),
    .i_page_num(i_page_num),
    .i_req_num(i_req_num),
    .res_cnt_0(res_cnt_0),
    .data_err_num_0(data_err_num_0),
    .run_cycles_0(run_cycles_0),
    .res_cnt_1(res_cnt_1),
    .data_err_num_1(data_err_num_1),
    .run_cycles_1(run_cycles_1),
    .res_cnt_2(res_cnt_2),
    .data_err_num_2(data_err_num_2),
    .run_cycles_2(run_cycles_2),
    .res_cnt_3(res_cnt_3),
    .data_err_num_3(data_err_num_3),
    .run_cycles_3(run_cycles_3),
    .O_NAND_CE_N(O_NAND_CE_N),
    .I_NAND_RB_N(I_NAND_RB_N),
    .O_NAND_WE_N(O_NAND_WE_N),
    .O_NAND_CLE(O_NAND_CLE),
    .O_NAND_ALE(O_NAND_ALE),
    .O_NAND_WP_N(O_NAND_WP_N),
    .O_NAND_RE_P(O_NAND_RE_P),
    .O_NAND_RE_N(O_NAND_RE_N),
    .IO_NAND_DQS_P(IO_NAND_DQS_P),
    .IO_NAND_DQS_N(IO_NAND_DQS_N),
    .IO_NAND_DQ(IO_NAND_DQ)
);

// 生成XDMA时钟
initial begin
    xdma_clk = 1'b0;
    forever #(XDMA_CLK_PERIOD/2) xdma_clk = ~xdma_clk;
end

// 生成NAND快速时钟
initial begin
    nand_clk_fast = 1'b0;
    forever #(NAND_CLK_FAST_PERIOD/2) nand_clk_fast = ~nand_clk_fast;
end

// 生成NAND慢速时钟
initial begin
    nand_clk_slow = 1'b0;
    forever #(NAND_CLK_SLOW_PERIOD/2) nand_clk_slow = ~nand_clk_slow;
end
// 生成NAND用户时钟
initial begin
    nand_usr_clk = 1'b0;
    forever #(NAND_CLK_USR_PERIOD/2) nand_usr_clk = ~nand_usr_clk;
end

// 测试主程序
initial begin
    // 初始化信号
    xdma_resetn = 1'b0;
    nand_clk_rst = 1'b1;
    nand_usr_rstn = 1'b0;
    i_init = 4'b0;
    i_start = 4'b0;
    i_mode = 8'h0;
    i_lba = 40'h0;
    i_len = 24'h100; // 256字节
    i_page_num = 32'h1;
    i_req_num = 32'h1;
    I_NAND_RB_N = 4'b1111; // 初始状态为就绪

    // 复位过程
    #100;
    xdma_resetn = 1'b1;
    nand_clk_rst = 1'b0;
    nand_usr_rstn = 1'b1;

     #200;

//     // 测试步骤1：初始化通道0
//     $display("[%t] Initializing Channel 0...", $time);
//     i_init[0] = 1'b1;
//     #XDMA_CLK_PERIOD;
//     i_init[0] = 1'b0;
    
    // // // // 等待初始化完成
    // // // wait(o_done[0] == 1'b1);
    // // // $display("[%t] Channel 0 Initialization Done", $time);
    #200;

    // 测试步骤2：启动读操作
    $display("[%t] Starting Read Operation on Channel 0...", $time);
    i_mode = 8'h0; // 模式 0为写操作  1为读操作  2为擦操作
    i_lba = 48'h778833445566; // 示例LBA地址
    i_len = 24'hff;       // 传输长度 4KB
    i_start[0] = 1'b1;
    
    
//    #20
//    i_start[0] = 1'b0;
    

    
    
//        $display("[%t] Starting Read Operation on Channel 0...", $time);
//    i_mode = 8'h1; // 假设模式1为读操作
//    i_lba = 48'h665544332211; // 示例LBA地址48'b0001_0001_0001_0001_0001_1001_1010_0010_0101_0101_0110_0110
////
//    i_len = 24'hff;       // 传输长度 4KB
//    i_start[0] = 1'b1;
//    #1000
//    nand_usr_rstn = 1'b1;
    // #XDMA_CLK_PERIOD;
    // i_start[0] = 1'b0;

//     // 模拟NAND Flash响应：操作开始后进入忙碌状态
//     #50;
//     I_NAND_RB_N[0] = 1'b1; // 进入忙碌
//     $display("[%t] NAND Flash Busy...", $time);
    
//     // 假设操作需要1000ns完成
//     #1000;
//     I_NAND_RB_N[0] = 1'b0; // 返回就绪状态
//     $display("[%t] NAND Flash Ready", $time);

//     // 等待操作完成
//    wait(o_done[0] == 1'b1);
//    $display("[%t] Read Operation Completed", $time);
    
//     // 检查错误计数器
//     if(data_err_num_0 == 0) 
//         $display("TEST PASSED: No data errors detected");
//     else
//         $display("TEST FAILED: Data errors = %d", data_err_num_0);
    
//     #100;
//     $finish;
// end

// // 监视关键信号
// always @(posedge xdma_clk) begin
//     if(o_done[0])
//         $display("[%t] Channel 0 Done detected", $time);
end


endmodule
