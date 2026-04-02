`timescale 1ns / 1ps
module nand_mmcm_tb();
    reg  clk_in;
    reg  reset;
    wire clk_out_fast; // 400M
    wire clk_out_slow; // 100M
    wire clk_reset;
    wire usr_resetn;
//    output clk_locked,
    wire clk_out_usr;   // 50M
    wire clk_out_xdma;   //125M
    wire refclk;
        wire clk_sdr_fast; // 10MHz
    wire clk_sdr_slow;  // 1.25MHz

// 20ns 时钟周期 = 50MHz

nand_mmcm mmcm1(

      clk_in,
      reset,
     clk_out_fast, // 400M
     clk_out_slow, // 100M
     clk_reset,
     usr_resetn,
//    output clk_locked,
    clk_out_usr,   // 50M
     clk_out_xdma,   //125M
      refclk, //200M
     clk_sdr_fast,
     clk_sdr_slow
);

    initial clk_in = 0;
    always #10 clk_in = ~clk_in; // 10ns 翻转一次，20ns 为一个周期

    initial begin
    reset = 1;
    #20
    reset = 0;
end
endmodule
