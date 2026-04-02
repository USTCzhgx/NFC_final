`timescale 1ns / 1ps

module tb_uart_write_cmd;

    // 参数定义
    parameter UADDR_W = 16;
    parameter UDATA_W = 32;

    // 信号定义
    reg                  clk;
    reg                  rst_n;
    reg                  uart_rx_done;
    reg  [7:0]           uart_rx_data;
    wire                 wr_en;
    wire [UADDR_W-1:0]   waddr;
    wire [UDATA_W-1:0]   wdata;

    // DUT 实例
    uart_write_cmd #(
        .UADDR_W(UADDR_W),
        .UDATA_W(UDATA_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_done(uart_rx_done),
        .uart_rx_data(uart_rx_data),
        .wr_en(wr_en),
        .waddr(waddr),
        .wdata(wdata)
    );

    // 时钟生成
    always #10 clk = ~clk;

    // 模拟发送一个字节
    task send_uart_byte(input [7:0] byte);
    begin
        uart_rx_data  = byte;
        uart_rx_done  = 1;
        #20;
        uart_rx_done  = 0;
        #40;
    end
    endtask

    initial begin
        // 初始化
        clk = 0;
        rst_n = 0;
        uart_rx_done = 0;
        uart_rx_data = 8'h00;

        #100;
        rst_n = 1;
        #50;

        // 发送命令：16'h0010, 32'h00000000
        send_uart_byte(8'h00);  // addr[15:8]
        send_uart_byte(8'h18);  // addr[7:0]
        send_uart_byte(8'h00);  // data[31:24]
        send_uart_byte(8'h00);  // data[23:16]
        send_uart_byte(8'h00);  // data[15:8]
        send_uart_byte(8'h40);  // data[7:0]

        #100;

        // 打印结果
        $display("WADDR = 0x%h, WDATA = 0x%h, WREN = %b", waddr, wdata, wr_en);

        #100;
        $finish;
    end

endmodule
