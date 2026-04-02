module nand_mmcm(
//    input  clk_in_p,
//    input  clk_in_n,
    input  clk_in,       // 50M
    input  reset,
    output clk_out_fast, // 400M
    output clk_out_slow, // 100M
    output clk_reset,
    output usr_resetn,
    output clk_out_usr,   // 50M
    output refclk         // 200M

);

wire testclk;

//localparam DELAY_NUM_FAST = 1;
localparam DELAY_NUM = 1;

//reg [DELAY_NUM_FAST-1 : 0]  rst_dly;
reg [DELAY_NUM-1 : 0] rstn_dly;
wire clk_locked;


// PLL

  clk_wiz_0 clk_mmcm
   (
    // Clock out ports
    .clk_out_fast    (clk_out_fast),     // output clk_out_fast 400M
    .user_clk        (clk_out_usr ),     // output user_clk     50M
    .refclk          (refclk      ),     // output refclk       200M
    .clk_out_slow    (clk_out_slow),     // output clk_out_slow 100M
    // Status and control signals
    .testclk(testclk),
    .reset           (reset       ),     // input reset
    .locked          (clk_locked  ),     // output locked
   // Clock in ports
    .clk_in          (clk_in      )      // input clk_in        50M
    );      





genvar i;

assign clk_reset = ~clk_locked;

generate for(i = 0; i < DELAY_NUM; i = i + 1) begin: slow_clk_rstn_delay
    if(i == 0) begin
        always@(posedge clk_out_usr or negedge clk_locked)
        if(~clk_locked) begin
            rstn_dly[0] <= 1'h0;
        end else begin
            rstn_dly[0] <= 1'h1;
        end
    end else begin
        always@(posedge clk_out_usr or negedge clk_locked)
        if(~clk_locked) begin
            rstn_dly[i] <= 1'h0;
        end else begin
            rstn_dly[i] <= rstn_dly[i-1];
        end
    end
end
endgenerate

assign usr_resetn = rstn_dly[DELAY_NUM-1];




endmodule
