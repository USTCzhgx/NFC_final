`timescale 1ns / 1ps

module tb_fcc_sdr;

reg clk = 0;
reg clk_sdr_slow = 0;
reg rst_n = 0;

// DUT 接口
reg                 req_fifo_valid = 0;
reg  [263:0]        req_fifo_data  = 0;
wire                req_fifo_ready;
reg                 cmd_ready = 0;

reg [263:0] req_data_array [0:3];
    integer i;
// 时钟生成
always #5  clk = ~clk;           // 100MHz
always #40 clk_sdr_slow = ~clk_sdr_slow; // 12.5MHz

// DUT 实例
fcc_sdr dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .clk_sdr_slow   (clk_sdr_slow),
    .req_fifo_ready (req_fifo_ready),
    .req_fifo_valid (req_fifo_valid),
    .req_fifo_data  (req_fifo_data),
    .cmd_ready      (cmd_ready)
);

initial begin

    $display("Start simulation...");
    $dumpfile("wave.vcd"); // GTKWave查看波形
    $dumpvars(0, tb_fcc_sdr);

    // 初始化
    rst_n = 0;
    #100;
    rst_n = 1;
    #1000;

    // 准备多条请求


    req_data_array[0] = {
        24'h123456, 8'h01, 64'h1122334455667788, 64'hdeadbeefcafef00d,
        24'h000100, 48'h000012345678, 16'h0002, 16'h0090
    };
    req_data_array[1] = {
        24'habcdef, 8'h02, 64'h2233445566778899, 64'hcafedeadbeefbabe,
        24'h000200, 48'h0000abcdef12, 16'h0003, 16'h00A0
    };
    req_data_array[2] = {
        24'h112233, 8'h03, 64'h33445566778899aa, 64'hfeedface12345678,
        24'h000300, 48'h000055aa66bb, 16'h0004, 16'h00B0
    };
    req_data_array[3] = {
        24'h445566, 8'h04, 64'h445566778899aabb, 64'h87654321deadbeef,
        24'h000400, 48'h0000a1b2c3d4, 16'h0005, 16'h00C0
    };

    // 逐条送入

    for (i = 0; i < 4; i = i + 1) begin
        @(posedge clk);
        req_fifo_data  = req_data_array[i];
        req_fifo_valid = 1;
        @(posedge clk);
        req_fifo_valid = 0;

        // 每发一条延迟几个周期，模拟非连续写入
        repeat(5) @(posedge clk);
    end

    // SDR 侧 cmd_ready 拉高，接收处理
    #500;
    @(posedge clk_sdr_slow);
    cmd_ready = 1;

    // 等待多拍给足处理时间
    repeat(30) @(posedge clk_sdr_slow);
    cmd_ready = 0;

    repeat(10) @(posedge clk_sdr_slow);
    $display("Simulation done.");
    $finish;
end

endmodule
