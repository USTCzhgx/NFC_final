`timescale 1ns / 1ps

module tb_phy_inout();

    reg clk_in;
    reg clk_div_in;
    reg reset;
    reg tri_t;
    reg [7:0] data_from_fabric;

    wire [7:0] data_to_fabric;
    wire data_pin;

    // 连接单端口模拟IO
    wire iob_tri_t_internal;

    // 实例化被测模块
    phy_inout #(
        .SIG_TYPE_DIFF("FALSE"),
        .DATA_WIDTH(8),
        .IDELAY_VALUE(0),
        .REFCLK_FREQ(400.0)
    ) dut (
        .clk_in(clk_in),
        .clk_div_in(clk_div_in),
        .reset(reset),
        .tri_t(tri_t),
        .data_from_fabric(data_from_fabric),
        .data_to_fabric(data_to_fabric),
        .data_to_and_from_pins_p(data_pin),
        .data_to_and_from_pins_n()   // 单端口不用连接
    );

    // 时钟生成
    initial begin
        clk_in = 0;
        forever #5 clk_in = ~clk_in;  // 100 MHz
    end

    initial begin
        clk_div_in = 0;
        forever #20 clk_div_in = ~clk_div_in;  // 12.5 MHz (clk_div)
    end

    initial begin
        // 初始化信号
        reset = 1;
        tri_t = 0;
        data_from_fabric = 8'hAA; // 任意数据

        #105;
        reset = 0;

        // 观察 tri_t 的不同输入对 iob_tri_t 输出的影响
        tri_t = 1;
        #80;  // 保持几个高速时钟周期

        tri_t = 0;
        #80;

        tri_t = 1;
        #80;

        tri_t = 0;
        #80;

        $finish;
    end

endmodule
