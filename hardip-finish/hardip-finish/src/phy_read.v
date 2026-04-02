`timescale 1ns / 1ps

// i_cmd[15:0]
//    [7:0] first cmd cycle, eg. 00h
//   [15:8] second cmd cycle, eg. 30h

// i_addr[39:0]
//     {row3, row2, row1, colum2, colum1}

// i_cmd_param[31:0]
//    [0:0] has second cmd ? 1 - yes, 0 - no
//    [3:1] number of addr
//   [15:4] busy time, eg. 12'h0 - 0 clock cycle
//          [15:14]: 0x - fixed time; 10 - read status; 11 - read status enhanced 
//  [30:16] number of data (bytes)
//  [31:31] reserved

// o_status [1:0]
//    2'b00 : IDLE
//    2'b01 : BUSY (DQ bus busy)
//    2'b10 : WAIT (wait RB_n ready)
//    2'b11 : READY (RB_n ready)

`include "nfc_param.vh"

module phy_read #(
    parameter DATA_WIDTH = 32  // cannot change
)(
    input                          isrfirst,
    input                          clk,
    input                          rst,
    output reg                     o_cmd_ready,
    input                          i_cmd_valid,
    input  [15 : 0]                i_cmd,
    input  [15 : 0]                i_cmd_id,
    input  [47 : 0]                i_addr,
    input  [31 : 0]                i_cmd_param,
    
    input                          i_keep_wait, // keep in WAIT state
    
    output reg [1:0]               o_status,
    output reg                     o_cmd_done,

    input                          i_rready, // has enough available space, not handshake
    output  reg                    o_rvalid,
    output  reg [DATA_WIDTH-1 : 0] o_rdata,
    output                         o_rlast,
    output  reg [15:0]             o_rid,
    output  reg [15:0]             o_ruser,
    
    
    output  reg                    io_busy,
    output  reg                    o_ce_n,
    input                          i_rb_n,
    output  reg                    o_we_n,
    output  reg                    o_cle,
    output  reg                    o_ale,
    output  reg [ 3 : 0]           o_re,
    output  reg                    o_dqs_tri_en, // 1 - output, 0 - input
    input       [ 3 : 0]           i_dqs,
    output      [ 3 : 0]           o_dqs,   
    output  reg                    o_dq_tri_en, // 1 - output, 0 - input
    output  reg [31 : 0]           o_dq,
    input       [31 : 0]           i_dq

);


localparam
    CMD0  = 11'b100_0000_0000,
    IDLE  = 11'b000_0000_0001,
    CMD1  = 11'b000_0000_0010,
    ADDR  = 11'b000_0000_0100,
    CMD2  = 11'b000_0000_1000,
    BUSY  = 11'b000_0001_0000,
    LOCK  = 11'b000_0010_0000,
    WAIT  = 11'b000_0100_0000,
    RPRE  = 11'b000_1000_0000,
    DATA  = 11'b001_0000_0000,
    RPST  = 11'b010_0000_0000;
    
localparam WARMUP_DATA_NUM = (`RD_WARMUP << 1);


     reg  [ 10:0] state;
reg         has_cmd2;
reg  [ 2:0] addr_num;
reg  [11:0] busy_time;
reg  [14:0] data_num;

reg  [ 7:0] ca_cnt;
reg  [ 2:0] addr_cnt;
reg  [10:0] busy_cnt;
reg  [14:0] data_cnt;
reg  [ 7:0] rpre_cnt;
reg  [ 7:0] rpst_cnt;
wire is_latch_edge;
wire is_we_edge;


//assign {data_num, busy_time, addr_num, has_cmd2} = i_cmd_param;

always@(posedge clk or posedge rst)
if(rst) begin
    {data_num, busy_time, addr_num, has_cmd2} <= 31'h0;
end else if(i_cmd_valid & o_cmd_ready) begin
    {data_num, busy_time, addr_num, has_cmd2} <= i_cmd_param[30:0];
end

always@(posedge clk or posedge rst)
if(rst) begin
    ca_cnt <= 8'h0;
end else if((state == CMD0) ||(state == CMD1) || (state == ADDR) || (state == CMD2))begin
    if(ca_cnt == `tCMD_ADDR - 1) 
        ca_cnt <= 8'h0;
    else
        ca_cnt <= ca_cnt + 8'h1;
end

assign is_we_edge    = (ca_cnt == (`tCMD_ADDR >> 1)) || (ca_cnt == 8'h0);
assign is_latch_edge = (ca_cnt == `tCMD_ADDR - 1);

//assign o_cmd_ready = (state == IDLE);
always@(posedge clk or posedge rst)
if(rst) begin
    o_cmd_ready <= 1'h0;
end else if((state == IDLE) & (~i_cmd_valid))begin
    o_cmd_ready <= 1'h1;
end else begin
    o_cmd_ready <= 1'h0;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_status <= 2'h0;
end else if(state == IDLE) begin // IDLE status
    o_status <= 2'h0;
end else if((state == WAIT) && (i_rb_n == 1'h1) && (data_num != 15'h0)) begin // READY status
    o_status <= 2'h3;
end else if((state == LOCK) || (state == WAIT)) begin // WAIT status
    o_status <= 2'h2;
end else begin // BUSY status
    o_status <= 2'h1;
end


reg [10:0] state_r;
reg       inflight;

// Track previous state
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state_r <= IDLE;
    end else begin
        state_r <= state;
    end
end

// Done pulse generation (1-cycle)
// - inflight set when a command is accepted
// - done when returning to IDLE from non-IDLE
always @(posedge clk or posedge rst) begin
    if (rst) begin
        inflight  <= 1'b0;
        o_cmd_done    <= 1'b0;
    end else begin
        o_cmd_done <= 1'b0; // default

        // Command accepted -> mark inflight and latch id
        if (i_cmd_valid && o_cmd_ready) begin
            inflight  <= 1'b1;
        end

        // Return-to-IDLE edge -> done
        if (inflight && (state == IDLE) && (state_r != IDLE)) begin
            o_cmd_done   <= 1'b1;
            inflight <= 1'b0;
        end
    end
end


always@(posedge clk or posedge rst)
if(rst) begin
    state    <= IDLE;
    addr_cnt <= 3'h0;
    busy_cnt <= 11'h0;
    rpre_cnt <= 8'h0;
    rpst_cnt <= 8'h0;
    data_cnt <= 15'h0;
end else begin
    case(state)
        IDLE: begin
            if((i_cmd_valid && isrfirst && i_cmd[15:0]==16'h3000)||(i_cmd_valid && i_cmd[15:0]==16'h3500)) begin
                state <= CMD0;
            end
            else if(i_cmd_valid) begin
            addr_cnt <= 3'h0;
            busy_cnt <= 11'h0;
            rpre_cnt <= 8'h0;
            rpst_cnt <= 8'h0;
            data_cnt <= 15'h0;
            state <= CMD1;
            end
            else 
            state <= IDLE;
        end
        
        CMD0: begin       
            addr_cnt <= 3'h0;
            busy_cnt <= 11'h0;
            rpre_cnt <= 8'h0;
            rpst_cnt <= 8'h0;
            data_cnt <= 15'h0; 
            if(~is_latch_edge) begin
                state <= CMD0;
            end else begin
            state <= CMD1;
            end
        end 
        
        CMD1: begin

            if(~is_latch_edge) begin
                state <= CMD1;
            end else if(addr_num == 3'h0) begin
                state <= BUSY;
            end else begin
                state <= ADDR;
            end
        end 
        ADDR: begin
            if((addr_cnt < addr_num-3'h1) || (~is_latch_edge)) begin
                state    <= ADDR;
                addr_cnt <= addr_cnt + is_latch_edge;
            end else if(has_cmd2) begin
                state    <= CMD2;
            end else if(busy_time != 12'h0) begin
                state    <= BUSY;
            end else begin
                state    <= RPRE;
            end
        end
        CMD2: begin
            if(~is_latch_edge) begin
                state <= CMD2;
            end else if(busy_time != 12'h0) begin
                state    <= BUSY;
            end else begin
                state    <= RPRE;
            end
        end
        BUSY: begin
            if(busy_time[11]) begin
                state <= LOCK;
            end else if((busy_cnt == busy_time[10:0]) & (data_num != 15'h0)) begin // need to read data
                state <= RPRE;
            end else if(busy_cnt == busy_time[10:0]) begin // do not need to read data
                state <= IDLE;
            end else begin
                state    <= BUSY;
                busy_cnt <= busy_cnt + 11'h1;
            end
        end
        LOCK: begin
            if(i_rb_n == 1'h0) begin
                state <= WAIT;
            end
        end
        WAIT: begin
            if((i_rb_n != 1'h1) || (i_keep_wait & (data_num != 15'h0))) begin
                state <= WAIT;
            end else if(data_num == 15'h0) begin
                state <= IDLE;
            end else begin
                state <= RPRE;
            end
        end
        RPRE: begin
            if(rpre_cnt == `tRPRE - 8'h1) begin
                state <= DATA;
            end else begin
                state    <= RPRE;
                rpre_cnt <= rpre_cnt + 8'h1;
            end
        end
        DATA: begin
            if(~i_rready) begin
                state    <= DATA;
            end else if(data_cnt + 15'h4 < data_num + WARMUP_DATA_NUM)begin
                state    <= DATA;
                data_cnt <= data_cnt + 15'h4;
            end else begin
                state <= RPST;
            end
        end
        RPST: begin
            if((rpst_cnt >= `tRPST + `tRPSTH - 8'h1) && (i_dqs == 4'h0)) begin
                state <= IDLE;
            end else if(rpst_cnt < 8'hff) begin
                state    <= RPST;
                rpst_cnt <= rpst_cnt + 8'h1;
            end else begin
                state    <= RPST;
                rpst_cnt <= rpst_cnt;
            end
        end
    endcase
end

always@(posedge clk or posedge rst)
if(rst) begin
    io_busy <= 1'h0;
end else if((state == IDLE) || (state == LOCK) || (state == WAIT))begin
    io_busy <= 1'h0;
end else begin
    io_busy <= 1'h1;
end

always@(posedge clk or posedge rst)
if(rst) begin
    o_we_n <= 1'h1;
end else if(((state == CMD0) ||(state == CMD1) || (state == ADDR) || (state == CMD2)) && is_we_edge)begin
    o_we_n <= ~o_we_n;
end

always@(posedge clk or posedge rst)
if(rst) begin
    o_cle <= 1'h0;
end else if((state == CMD0) ||(state == CMD1) || (state == CMD2))begin
    o_cle <= 1'h1;
end else begin
    o_cle <= 1'h0;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_ale <= 1'h0;
end else if(state == ADDR)begin
    o_ale <= 1'h1;
end else begin
    o_ale <= 1'h0;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_re <= 4'hf;
end else if(((state == RPRE) && (rpre_cnt > 8'h1)) || (state == RPST))begin
    o_re <= 4'h0;
end else if((state == DATA) & (~i_rready))begin
    o_re <= {4{o_re[3]}};
end else if(state == DATA)begin
    o_re <= 4'h5;
end else begin
    o_re <= 4'hf;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_ce_n <= 1'h1;
end else if(((state == IDLE) & (~i_cmd_valid)) || ((state == RPST) && (rpst_cnt >= `tRPST)) || (state == LOCK) || (state == WAIT))begin
    o_ce_n <= 1'h1;
end else begin
    o_ce_n <= 1'h0;
end

assign o_dqs  = 4'hf;

always@(posedge clk or posedge rst)
if(rst) begin
    o_dqs_tri_en <= 1'h0;
end else if( ((state == RPRE) && (rpre_cnt >= `tDQSRH)) || ((state == DATA) || (state == RPST)))begin
    o_dqs_tri_en <= 1'h1;  // input
end else begin
    o_dqs_tri_en <= 1'h0;
end

always@(posedge clk or posedge rst)
if(rst) begin
    o_dq_tri_en <= 1'h1;
end else if((state == CMD0) || (state == CMD1) || (state == ADDR) || (state == CMD2) )begin
    o_dq_tri_en <= 1'h0;  // output
end else begin
    o_dq_tri_en <= 1'h1;
end


wire [7:0] dq_addr;
assign dq_addr = (i_addr >> {addr_cnt, 3'h0}) & 8'hff;                

always@(posedge clk or posedge rst)
if(rst) begin
    o_dq <= 32'h0;
end else if(state == CMD0 )begin
    o_dq <= {4{8'hDA}};
end else if(state == CMD1)begin
    o_dq <= {4{i_cmd[7:0]}};
end else if(state == CMD2)begin
    o_dq <= {4{i_cmd[15:8]}};
end else if(state == ADDR) begin
    o_dq <= {4{dq_addr}};
end else begin
    o_dq <= 32'h0;
end


//localparam DELAY_NUM = 18;

//reg [DELAY_NUM-1 : 0] dqs_out_en;

//genvar i;
//generate for(i = 0; i < DELAY_NUM; i = i + 1) begin: dqs_delay
//    if(i == 0) begin
//        always@(posedge clk or posedge rst)
//        if(rst) begin
//            dqs_out_en[i] <= 1'h0;
//        end else begin
//            dqs_out_en[i] <= (state == DATA) || (state == RPST);
//        end
//    end else begin
//        always@(posedge clk or posedge rst)
//        if(rst) begin
//            dqs_out_en[i] <= 1'h0;
//        end else begin
//            dqs_out_en[i] <= dqs_out_en[i-1];
//        end
//    end
//end
//endgenerate


//reg  [15:0] i_cmd_id_dly;
//reg  [15:0] i_cmd_dly;

//always@(posedge clk or posedge rst)
//if(rst) begin
//    i_cmd_id_dly <= 16'h0;
//    i_cmd_dly    <= 16'h0;
//end else if(state == RPRE)begin
//    i_cmd_id_dly <= i_cmd_id;
//    i_cmd_dly    <= i_cmd;
//end 

wire       dqs_out_en;
reg  [3:0] din_cnt;

assign dqs_out_en = ((state == DATA) || (state == RPST));

always@(posedge clk or posedge rst)
if(rst) begin
    din_cnt <= 4'h0;
end else if(state == RPRE) begin
    din_cnt <= 4'h0;
end else if(dqs_out_en && (i_dqs == 4'h5) && (din_cnt < WARMUP_DATA_NUM)) begin
    din_cnt <= din_cnt + 4'h4;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_rvalid <= 1'h0;
    o_rdata  <= 'h0;
    o_rid    <= 16'h0;
    o_ruser  <= 16'h0;
end else if( dqs_out_en && (i_dqs == 4'h5) && (din_cnt >= WARMUP_DATA_NUM))begin
    o_rvalid <= 1'b1;
    o_rdata  <= i_dq;
    o_rid    <= i_cmd_id;
    o_ruser  <= i_cmd;
end else begin
    o_rvalid <= 1'h0;
//    o_rdata  <= 'h0;
//    o_rid    <= 16'h0;
//    o_ruser  <= 16'h0;
end


reg [3:0] dqs_r;
always@(posedge clk or posedge rst)
if(rst) begin
    dqs_r <= 4'hf;
end else if(state == RPST) begin
    dqs_r <= i_dqs;
end else begin
    dqs_r <= 4'hf;
end

assign o_rlast = (i_dqs == 4'h0) && (dqs_r == 4'h5);
//assign o_rlast = dqs_out_en[DELAY_NUM-1] && (i_dqs == 4'h0) && (dqs_r == 4'h5);

//always@(posedge clk or posedge rst)
//if(rst) begin
//    o_rlast <= 1'h0;
//end else if((state == RPST) && (i_dqs == 8'h0) && (dqs_r == 8'h33)) begin
//    o_rlast <= 1'h1;
//end else begin
//    o_rlast <= 1'h0;
//end


endmodule
