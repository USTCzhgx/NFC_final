`timescale 1ns / 1ps


module phy_inout #(
    parameter SIG_TYPE_DIFF   = "FALSE",
    parameter DATA_WIDTH      = 8,
    parameter INIT_VALUE      = 0,
    parameter IDELAY_VALUE    = 0,
    parameter OSERDES_CLK_INV = 0,
    parameter REFCLK_FREQ     = 200.0 // IDELAYCTRL clock input frequency in MHz (200.0-2667.0)
)(
    input                       clk_in,
    input                       clk_div_in,
    input                       ref_clk,//200M
    input                       reset,
//    output                      rst_seq_done,
    input                       tri_t,
    input  [DATA_WIDTH - 1 : 0] data_from_fabric,
    output [DATA_WIDTH - 1 : 0] data_to_fabric,
//    output reg                  data_to_fabric_valid,
    inout                       data_to_and_from_pins_p,
    inout                       data_to_and_from_pins_n,   
    output wire  dq_read_internal
);

wire iob_tri_t;
wire iob_din;
wire iob_dout;
wire iserdes_din;
wire fifo_empty;
wire idelayctrl_rdy;

IDELAYCTRL IDELAYCTRL_inst (
    .RDY(idelayctrl_rdy),
    .REFCLK(ref_clk),
    .RST(reset)
);

generate
if(SIG_TYPE_DIFF == "TRUE") begin: io_pin_diff
    IOBUFDS IOBUFDS_inst (
       .O  (iob_dout               ),     // 1-bit output: Buffer output
       .I  (iob_din                ),     // 1-bit input: Buffer input
       .IO (data_to_and_from_pins_p),     // 1-bit inout: Diff_p inout (connect directly to top-level port)
       .IOB(data_to_and_from_pins_n),     // 1-bit inout: Diff_n inout (connect directly to top-level port)
       .T  (iob_tri_t              )      // 1-bit input: 3-state enable input
    );
end else begin: io_pin_se
    IOBUF IOBUF_inst (
       .O (iob_dout               ),   // 1-bit output: Buffer output
       .I (iob_din                ),   // 1-bit input: Buffer input
       .IO(data_to_and_from_pins_p),   // 1-bit inout: Buffer inout (connect directly to top-level port)
       .T (iob_tri_t              )    // 1-bit input: 3-state enable input
    );
end
endgenerate




IDELAYE2 #(
   .CINVCTRL_SEL("FALSE"),               // Invert CTRL input (TRUE/FALSE)
   .DELAY_SRC("IDATAIN"),                // Delay input (IDATAIN, DATAIN)
   .HIGH_PERFORMANCE_MODE("TRUE"),       // Reduced jitter ("TRUE"), reduced power ("FALSE")
   .IDELAY_TYPE("FIXED"),                // FIXED, VARIABLE, or VAR_LOADABLE
   .IDELAY_VALUE(IDELAY_VALUE),          // Input delay tap setting

   .REFCLK_FREQUENCY(REFCLK_FREQ),       // Reference clock frequency for IDELAYCTRL in MHz (200.0 recommended)
   .SIGNAL_PATTERN("DATA")               // "DATA" for normal signals, "CLOCK" for clock signals
)
IDELAYE2_inst (
   .CNTVALUEOUT(),         // 5-bit output: Counter value output
   .DATAOUT    (iserdes_din), // 1-bit output: Delayed data output
   .C          (clk_div_in),  // 1-bit input: Clock input
   .CE         (1'b0),         // 1-bit input: Enable increment/decrement
   .CINVCTRL   (1'b0),         // 1-bit input: Dynamic clock inversion
   .CNTVALUEIN (5'h0),         // 5-bit input: Counter value input
   .DATAIN     (1'b0),         // 1-bit input: Data input (bypassed in IDATAIN mode)
   .IDATAIN    (iob_dout),     // 1-bit input: Data input from IOB
   .INC        (1'b0),         // 1-bit input: Increment / Decrement tap delay
   .LD         (1'b0),         // 1-bit input: Load IDELAY_VALUE
   .LDPIPEEN   (1'b0),         // 1-bit input: Enable pipeline delay
   .REGRST     (1'b0)          // 1-bit input: Asynchronous Reset
);




ISERDESE2 #(
    .DATA_RATE("DDR"),                   // DDR 模式
    .DATA_WIDTH(DATA_WIDTH),             // 并行数据宽度 (4 或 8)
    .INTERFACE_TYPE("NETWORKING"),       // 设置为 NETWORKING 模式
    .NUM_CE(1),                          // 使用一个时钟使能
    .SERDES_MODE("MASTER"),              // 主模式
    .INIT_Q1(1'b0),                      // Q1 的初始值
    .INIT_Q2(1'b0),                      // Q2 的初始值
    .INIT_Q3(1'b0),                      // Q3 的初始值
    .INIT_Q4(1'b0),                      // Q4 的初始值
    .SRVAL_Q1(1'b0),                     // 复位值
    .SRVAL_Q2(1'b0),
    .SRVAL_Q3(1'b0),
    .SRVAL_Q4(1'b0)
) ISERDESE2_inst (
    .Q1(data_to_fabric[7]),              // 并行数据输出位 1
    .Q2(data_to_fabric[6]),              // 并行数据输出位 2
    .Q3(data_to_fabric[5]),              // 并行数据输出位 3
    .Q4(data_to_fabric[4]),              // 并行数据输出位 4
    .Q5(data_to_fabric[3]),              // 并行数据输出位 5
    .Q6(data_to_fabric[2]),              // 并行数据输出位 6
    .Q7(data_to_fabric[1]),              // 并行数据输出位 7
    .Q8(data_to_fabric[0]),              // 并行数据输出位 8
    .BITSLIP(1'b0),                      // Bit-slip 使能
    .CE1(1'b1),                          // 时钟使能
    .CE2(1'b0),                          // 不使用第二使能
    .CLK(clk_in),                        // 高速时钟输入
    .CLKB(~clk_in),                      // 反向高速时钟 (UltraScale 的 `CLK_B`)
    .CLKDIV(clk_div_in),                 // 分频后的时钟
    .DDLY(1'b0), // ? 延迟后的信号走 DDLY
    .D(iob_dout),            // D 口空着，接0
    .RST(reset),                         // 异步复位
    .SHIFTIN1(1'b0),                     // 级联输入 (未使用)
    .SHIFTIN2(1'b0),                     // 级联输入 (未使用)
    .SHIFTOUT1(),                        // 级联输出 (未使用)
    .SHIFTOUT2()                         // 级联输出 (未使用)
);

// OSERDESE2: 输出串行器模块
// 功能: 将来自FPGA内部逻辑的并行数据(data_from_fabric)转换成高速串行数据流(iob_din)，并通过IO引脚发送出去。
//       同时，它也控制IO引脚的三态使能信号(iob_tri_t)。
OSERDESE2 #(
    // --- 参数配置 ---
    .DATA_RATE_OQ("DDR"),      // 数据输出(OQ)使用双倍数据速率(DDR)，在CLK的上升沿和下降沿都发送数据
    .DATA_RATE_TQ("SDR"),      // 三态控制(TQ)使用单倍数据速率(SDR)，在CLKDIV的上升沿变化，确保信号稳定
    .DATA_WIDTH(8),            // 并行数据输入的位宽为8位 (D1-D8)
    .INIT_OQ(1'b0),            // OQ端口初始值为0
    .INIT_TQ(1'b0),            // TQ端口初始值为0
    .SERDES_MODE("MASTER"),    // 设置为MASTER模式，作为独立的串行器使用
    .SRVAL_OQ(1'b0),           // 复位时OQ端口的值
    .SRVAL_TQ(1'b0),           // 复位时TQ端口的值
    .TRISTATE_WIDTH(1)         // 三态控制信号的宽度
) OSERDESE2_inst (
    // --- 输出端口 ---
    .OQ    (iob_din),          // 串行数据输出，连接到IOBUF的输入端
    .TQ    (iob_tri_t),        // 三态控制信号输出，连接到IOBUF的三态使能端
    // --- 时钟和复位 ---
    .CLK   (clk_in),           // 高速串行时钟
    .CLKDIV(clk_div_in),       // 低速并行时钟 (来自FPGA逻辑)
    .RST   (reset),            // 异步复位信号
    // --- 并行数据输入 ---
    .D1    (data_from_fabric[0]), // 并行数据输入位1
    .D2    (data_from_fabric[1]),
    .D3    (data_from_fabric[2]),
    .D4    (data_from_fabric[3]),
    .D5    (data_from_fabric[4]),
    .D6    (data_from_fabric[5]),
    .D7    (data_from_fabric[6]),
    .D8    (data_from_fabric[7]),
    .OCE   (1'b1),             // 输出时钟使能，高电平有效
    // --- 三态控制输入 ---
    .T1    (tri_t),            // 三态控制输入信号，来自上层逻辑
    .T2    (),                 // 未使用的三态控制输入
    .T3    (),
    .T4    (),
    .TCE   (1'b1),             // 三态控制时钟使能，高电平有效
    // --- 级联端口 (未使用) ---
    .SHIFTIN1(1'b0),
    .SHIFTIN2(1'b0),
    .SHIFTOUT1(),
    .SHIFTOUT2()
);

assign dq_read_internal = iob_dout;
assign dq_read_interna2 = ~dq_read_internal;

endmodule
