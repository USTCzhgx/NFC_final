`timescale 1ns / 1ps

`include "nfc_param.vh"
/*
2025.11.17 SCMI ZGX 
修改了地址相关逻辑
现在适配了已有的芯片PA0在row addr的第12位
可以进行正确的块地址递增逻辑
*/
module schedule_erase(
    input                     clk,
    input                     rst,
    output                    o_cmd_ready,
    input                     i_cmd_valid,
    input  [15 : 0]           i_ecmd_id,
    input  [31 : 0]           i_eaddr, // LBA, Plane address at [0]
    input  [23 : 0]           i_elen, // block number
    
    input                     i_page_cmd_ready,
    output reg                o_page_cmd_valid,
    output reg [15 : 0]       o_page_cmd,
    output reg                o_page_cmd_last,
    output reg [15 : 0]       o_page_cmd_id,
    output reg [47 : 0]       o_page_addr, // LBA
    output reg [31 : 0]       o_page_cmd_param
);

// Support TWO Planes
// MPE_XXX: Multi-Plane Erase, last command is Erase Block
localparam
    IDLE     = 2'h0,
    MPE_ONE  = 2'h1,
    MPE_TWO  = 2'h2,
    WAIT     = 2'h3;
    
reg  [ 1:0] state;
reg  [ 1:0] nxt_state;
reg  [31:0] row_addr;
reg  [23:0] remain_len;
wire [11:0] t_dbsy;

assign t_dbsy = `tDBSY;

assign o_cmd_ready = (state == IDLE) & i_page_cmd_ready;


always@(posedge clk or posedge rst)
if(rst) begin
    state          <= IDLE;
    nxt_state      <= IDLE;
    row_addr       <= 32'h0;
    remain_len     <= 24'h0;
    o_page_cmd_valid <= 1'b0;
    o_page_cmd       <= 16'h0;
    o_page_cmd_last  <= 1'b0;
    o_page_cmd_id    <= 'h0;
    o_page_addr      <= 'h0;
    o_page_cmd_param <= 'h0; 
end else begin
    case(state)
        IDLE: begin
            o_page_cmd_valid <= 1'b0;
            if(i_cmd_valid & (~i_eaddr[0]) & (i_elen > 24'h1)) begin // plane = 0
                state          <= MPE_ONE; 
                row_addr       <= i_eaddr; 
                remain_len     <= i_elen;       
            end else if(i_cmd_valid) begin
                state          <= MPE_TWO; 
                row_addr       <= i_eaddr; 
                remain_len     <= i_elen;  
            end
        end 
        MPE_ONE: begin
            if(i_page_cmd_ready) begin
                state            <= WAIT;
                nxt_state        <= MPE_TWO;
                row_addr         <= row_addr + 32'h00000800;
                remain_len       <= remain_len - 24'h1; 
                o_page_cmd_valid <= 1'b1;
                o_page_cmd       <= 16'hD160; // Erase Block Multi-plane
                o_page_cmd_last  <= 1'b0;
                o_page_cmd_id    <= i_ecmd_id;
                o_page_addr      <= row_addr;
                o_page_cmd_param <= {16'h0, t_dbsy, 3'h4, 1'b1};                
            end 
        end
        MPE_TWO: begin
            if(i_page_cmd_ready & (remain_len <= 24'h1)) begin
                state            <= WAIT;
                nxt_state        <= IDLE;
                o_page_cmd_valid <= 1'b1;
                o_page_cmd       <= 16'hD060; // Final multi-plane command: Erase block
                o_page_cmd_last  <= 1'b1;
                o_page_cmd_id    <= i_ecmd_id;
                o_page_addr      <= row_addr;
                o_page_cmd_param <= {16'h0, 12'h800, 3'h4, 1'b1};                  
            end else if(i_page_cmd_ready & (remain_len == 24'h2)) begin 
                state            <= WAIT;
                nxt_state        <= MPE_TWO;
                row_addr         <= row_addr + 32'h00000800;
                remain_len       <= remain_len - 24'h1; 
                o_page_cmd_valid <= 1'b1;
                o_page_cmd       <= 16'hD060; 
                o_page_cmd_last  <= 1'b0;
                o_page_cmd_id    <= i_ecmd_id;
                o_page_addr      <= row_addr;
                o_page_cmd_param <= {16'h0, 12'h800, 3'h4, 1'b1}; 
            end else if(i_page_cmd_ready) begin 
                state            <= WAIT;
                nxt_state        <= MPE_ONE;
                row_addr         <= row_addr + 32'h00000800;
                remain_len       <= remain_len - 24'h1; 
                o_page_cmd_valid <= 1'b1;
                o_page_cmd       <= 16'hD060; 
                o_page_cmd_last  <= 1'b0;
                o_page_cmd_id    <= i_ecmd_id;
                o_page_addr      <= row_addr;
                o_page_cmd_param <= {16'h0, 12'h800, 3'h4, 1'b1}; 
            end        
        end
        WAIT: begin
            o_page_cmd_valid <= 1'b0;
            if(~(i_page_cmd_ready | o_page_cmd_valid)) begin
                state        <= nxt_state;
            end 
        end
    endcase
end


endmodule
