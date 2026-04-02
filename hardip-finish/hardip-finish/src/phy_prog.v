`timescale 1ns / 1ps

// i_cmd[15:0]
//    [7:0] first cmd cycle, eg. 80h
//   [15:8] second cmd cycle, eg. 10h

// i_addr[47:0]
//     {row3, row2, row1, colum2, colum1}

// i_cmd_param[31:0]
//    [0:0] has second cmd ? 1 - yes, 0 - no
//    [3:1] number of addr
//   [15:4] busy time, eg. 12'h0 - 0 clock cycle
//          [15:14]: 0x - fixed time; 10 - read status; 11 - read status enhanced 
//  [30:16] number of data (bytes)
//  [31:31] data_src, 0 - i_wdata, 1 - i_data

// o_status [1:0]
//    2'b00 : IDLE
//    2'b01 : BUSY (DQ bus busy)
//    2'b10 : WAIT (wait RB_n ready)
//    2'b11 : READY (RB_n ready)

`include "nfc_param.vh"

module phy_prog #(
    parameter DATA_WIDTH = 32  // cannot change
)(
    input                          iswfirst,
    input                          clk,
    input                          rst,
    output reg                     o_cmd_ready,
    input                          i_cmd_valid,
    input  [15 : 0]                i_cmd,
    input  [15 : 0]                i_cmd_id,
    input  [47 : 0]                i_addr,
    input  [63 : 0]                i_data,
    input  [31 : 0]                i_cmd_param,
    
    output                         o_wready,
    input                          i_wvalid,
    input  [DATA_WIDTH-1 : 0]      i_wdata,
    input                          i_wlast,
    
    input                          i_keep_wait, // keep in WAIT state
    
    output reg [1:0]               o_status,
    output reg                     o_cmd_done,
    
    output  reg                    o_rd_st_req,
    output  reg [31 : 0]           o_rd_st_addr,
    output  reg [15 : 0]           o_rd_st_id,
    output  reg [ 2 : 0]           o_rd_st_type, // [2]? bypass : not 
                                                   // [1]? (read status + read mode) : read status 
                                                   // [0]? read status enhanced  : read status 
//    input                          i_rd_st_ack,
//    input   [ 7 : 0]               i_sr,


    output  reg                    io_busy,
    output  reg                    o_ce_n,
    input                          i_rb_n,
    output  reg                    o_we_n,
    output  reg                    o_cle,
    output  reg                    o_ale,
    output      [ 3 : 0]           o_re,
    output                         o_dqs_tri_en, // 1 - output, 0 - input
    input       [ 3 : 0]           i_dqs,
    output  reg [ 3 : 0]           o_dqs,
    output  reg                    o_dq_tri_en, // 1 - output, 0 - input
    output  reg [31 : 0]           o_dq
//    input       [31 : 0]           i_dq

);


localparam
    CMD0  = 11'b100_0000_0000,
    IDLE  = 11'b000_0000_0001,
    CMD1  = 11'b000_0000_0010,
    ADDR  = 11'b000_0000_0100,    
    WPRE  = 11'b000_0000_1000,
    DATA  = 11'b000_0001_0000,
    WPST  = 11'b000_0010_0000,
    CMD2  = 11'b000_0100_0000,
    BUSY  = 11'b000_1000_0000,
    LOCK  = 11'b001_0000_0000,
    WAIT  = 11'b010_0000_0000;
    
localparam WARMUP_DATA_NUM = (`PG_WARMUP << 1);

reg  [ 10:0] state;
reg  [ 10:0] state_r;
reg         has_cmd2;
reg         data_src;
reg  [ 2:0] addr_num;
reg  [11:0] busy_time;
reg  [14:0] data_num;

reg  [ 7:0] ca_cnt;
reg  [ 2:0] addr_cnt;
reg  [10:0] busy_cnt;
reg  [14:0] data_cnt;
reg  [ 7:0] wpre_cnt;
reg  [ 7:0] wpst_cnt;
reg  [ 7:0] tWPRE;
wire is_latch_edge;
wire is_we_edge;

reg  flag;
reg  flag_r;

//localparam DELAY_NUM = 10;

//reg [DELAY_NUM-1 : 0] dqs_out_en;


//assign {data_src, data_num, busy_time, addr_num, has_cmd2} = i_cmd_param;

always@(posedge clk or posedge rst)
if(rst) begin
    {data_src, data_num, busy_time, addr_num, has_cmd2} <= 32'h0;
end else if(i_cmd_valid & o_cmd_ready) begin
    {data_src, data_num, busy_time, addr_num, has_cmd2} <= i_cmd_param;
end

always@(posedge clk or posedge rst)
if(rst) begin
    ca_cnt <= 8'h0;
end else if((state == CMD0) || (state == CMD1) || (state == ADDR) || (state == CMD2))begin
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
end else if((state == LOCK) || ((state == WAIT) && (i_rb_n != 1'h1))) begin // WAIT status
    o_status <= 2'h2;
end else if((state == WAIT) && (i_rb_n == 1'h1)) begin // READY status
    o_status <= 2'h3;
end else begin // BUSY status
    o_status <= 2'h1;
end

always@(posedge clk or posedge rst)
if(rst) begin
    tWPRE <= 8'h0;
end else if((state == CMD1) && (i_cmd[7:0] == 8'h85))begin
    tWPRE <= `tCCS;
end else if(state == CMD1) begin
    tWPRE <= `tADL;
end

reg       inflight;

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
    wpre_cnt <= 8'h0;
    wpst_cnt <= 8'h0;
    data_cnt <= 15'h0;
end else begin
    case(state)
        IDLE: begin
            if(i_cmd_valid && iswfirst && (i_cmd[7:0]==8'h80||i_cmd[7:0]==8'h85)) begin
                state <= CMD0;
            end
            else if(i_cmd_valid) begin
            addr_cnt <= 3'h0;
            busy_cnt <= 11'h0;
            wpre_cnt <= 8'h0;
            wpst_cnt <= 8'h0;
            data_cnt <= 15'h0;
            state <= CMD1;
            end
        end
        
        CMD0: begin      
            addr_cnt <= 3'h0;
            busy_cnt <= 11'h0;
            wpre_cnt <= 8'h0;
            wpst_cnt <= 8'h0;
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
            end else if(data_num == 15'h0) begin
                state    <= CMD2;
            end else begin
                state    <= WPRE;
            end
        end
        WPRE: begin
            if(wpre_cnt == tWPRE-8'h1) begin
                state <= DATA;
            end else begin
                state    <= WPRE;
                wpre_cnt <= wpre_cnt + 8'h1;
            end
        end
        DATA: begin
            if((~data_src) & (~i_wvalid)) begin
                state    <= DATA;            
            end else if( (data_cnt < (data_num + WARMUP_DATA_NUM - 15'h4)) && (data_num + WARMUP_DATA_NUM > 15'h4) )begin
                state    <= DATA;
                data_cnt <= data_cnt + 15'h4;
            end else begin
                state    <= WPST;
            end
        end
        WPST: begin
            if(wpst_cnt < `tWPST + `tWPSTH - 8'h1) begin
                state    <= WPST;
                wpst_cnt <= wpst_cnt + 8'h1;
            end else if(has_cmd2) begin
                state    <= CMD2;
            end else if(busy_time != 12'h0) begin
                state    <= BUSY;
            end else begin
                state    <= IDLE;
            end
        end
        CMD2: begin
            if(~is_latch_edge) begin
                state <= CMD2;
            end else begin
                state <= BUSY;
            end
        end
        BUSY: begin
            if(busy_time[11]) begin
                state <= LOCK;
            end else if(busy_cnt == busy_time[10:0]) begin
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
            // if((i_rb_n == 1'h1) && (~i_keep_wait)) begin
            if(i_rb_n == 1'h1) begin
                state <= IDLE;
            end
        end
        
    endcase
end


always@(posedge clk or posedge rst)
if(rst) begin
    flag <= 1'h0;
end else if((state == WPST) & has_cmd2)begin
    flag <= 1'h1;
end else if((state == CMD2) & is_latch_edge) begin
    flag <= 1'h0;
end


always@(posedge clk or posedge rst)
if(rst) begin
    flag_r <= 1'h0;
end else begin
    flag_r <= flag;
end


always@(posedge clk or posedge rst)
if(rst) begin
    io_busy <= 1'h0;
end else if(((state == IDLE) & (~i_cmd_valid)) || (state == LOCK) || (state == WAIT))begin
    io_busy <= 1'h0;
end else begin
    io_busy <= 1'h1;
end

always@(posedge clk or posedge rst)
if(rst) begin
    o_we_n <= 1'h1;
end else if(((state == CMD0) || (state == CMD1) || (state == ADDR) || (state == CMD2)) && is_we_edge)begin
    o_we_n <= ~o_we_n;
end

always@(posedge clk or posedge rst)
if(rst) begin
    o_cle <= 1'h0;
end else if((state == CMD0) || (state == CMD1) || (state == CMD2) || flag || (i_cmd_valid && (i_cmd[7:0] == 8'h85)))begin
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
    state_r <= 11'h0;
end else begin
    state_r <= state;
end




always@(posedge clk or posedge rst)
if(rst) begin
    o_rd_st_req  <= 1'h0;
    o_rd_st_type <= 3'h0;
    o_rd_st_addr <= 32'h0;
    o_rd_st_id   <= 16'h0;
end else if((state == WAIT) && (i_rb_n == 1'h1) && (~i_keep_wait))begin // need to read status, return result from nfc_phy_status module
    o_rd_st_req  <= 1'h1;
    o_rd_st_type <= {2'b0, busy_time[10]};
    o_rd_st_addr <= i_addr[47:16];
    o_rd_st_id   <= i_cmd_id;            //70
end else begin
    o_rd_st_req  <= 1'h0;
    o_rd_st_type <= 3'h0;
    o_rd_st_addr <= 32'h0;
    o_rd_st_id   <= 16'h0;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_ce_n <= 1'h1;
end else if(((state == IDLE) & (~i_cmd_valid)) || (state == LOCK) || (state == WAIT))begin
    o_ce_n <= 1'h1;
end else begin
    o_ce_n <= 1'h0;
end

assign o_re = 4'hf;
assign o_dqs_tri_en = 1'h0;



always@(posedge clk or posedge rst)
if(rst) begin
    o_dqs <= 4'hf;
end else if((state == DATA) & (~data_src) & (~i_wvalid))begin
    o_dqs <= {4{o_dqs[3]}};
end else if(state == DATA)begin
    o_dqs <= 4'h5;
end else if((state_r == WPRE) || (state == WPST) || (state_r == WPST) || (flag | flag_r))begin // || ((state == CMD1) && (i_cmd[7:0] == 8'h85))
    o_dqs <= 4'h0; // has second command or first command is 85h, dqs should = 0 
end else begin
    o_dqs <= 4'hf;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_dq_tri_en <= 1'h1;
end else if( (state == CMD0) || (state == CMD1) || (state == ADDR) || (state == CMD2) || (state == DATA) )begin
    o_dq_tri_en <= 1'h0;  // output
end else begin
    o_dq_tri_en <= 1'h1;
end


wire [7:0] dq_addr;
assign dq_addr = (i_addr >> {addr_cnt, 3'h0}) & 8'hff;
reg  [31:0] dq_data;
//assign dq_data = (i_data >> {data_cnt, 3'h0}) & 32'hffff_ffff;
always @*
if(data_cnt < WARMUP_DATA_NUM) begin
    dq_data = i_data[31:0];
end else begin
    dq_data = (i_data >> ({data_cnt, 3'h0} - (WARMUP_DATA_NUM << 3))) & 32'hffff_ffff;
end


always@(posedge clk or posedge rst)
if(rst) begin
    o_dq <= 32'h0;
end else if(state == CMD0)begin
    o_dq <= {4{8'hDA}};
end else if(state == CMD1)begin
    o_dq <= {4{i_cmd[7:0]}};
end else if(state == CMD2)begin
    o_dq <= {4{i_cmd[15:8]}};
end else if(state == ADDR) begin
    o_dq <= {4{dq_addr}};
end else if((state == DATA) & data_src)begin
    o_dq <= dq_data;
end else if((state == DATA) & (~data_src) & (~i_wvalid))begin
    o_dq <= {4{i_wdata[31:24]}};
end else if((state == DATA) & (~data_src))begin
    o_dq <= i_wdata;
end else begin
    o_dq <= 32'h0;
end

assign o_wready = (state == DATA) & (data_cnt >= WARMUP_DATA_NUM);




endmodule
