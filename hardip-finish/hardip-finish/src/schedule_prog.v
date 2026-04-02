`timescale 1ns / 1ps
/*
2025.11.14 SCMI ZGX 
���� 1080 ����д������
��Ҫ�޸ģ�
ɾ�����в�����ص����룺i_col_num �� i_col_addr_len
ɾ�������в���Ҫ��״̬��COLUMN��COL_LAST��MPP_ONE��MPP_TWO
��״̬��Ϊ����״̬��IDLE��PROG��WAIT
ɾ�������в���Ҫ�ļĴ������źţ��� remain_col_num��right_shift��col_addr_len��row_addr �ȣ�
���� PROG ״̬��ִֻ�� 1080 д����
���� IDLE ״̬��ֻ��������д����
*/
`include "nfc_param.vh"

module schedule_prog(
    input                     clk,
    input                     rst,
    output                    o_cmd_ready,
    input                     i_cmd_valid,
    input  [15 : 0]           i_wcmd_id,
    input  [47 : 0]           i_waddr, // LBA, Plane address at [16]
    input  [23 : 0]           i_wlen,
    input  [15 : 0]           i_wcmd,
    input  [23 : 0]           i_wdata_avail, // availiable (bufferred) data number
    
    input                     i_page_cmd_ready,
    output reg                o_page_cmd_valid,
    output reg [15 : 0]       o_page_cmd,
    output reg                o_page_cmd_last,
    output reg [15 : 0]       o_page_cmd_id,
    output reg [47 : 0]       o_page_addr, // LBA
    output reg [31 : 0]       o_page_cmd_param
);

localparam
    IDLE     = 2'b00,   
    PROG     = 2'b01,
    COPR     = 2'b10,
    WAIT     = 2'b11;
    
reg  [ 1:0] state;
reg  [ 1:0] nxt_state;

assign o_cmd_ready = (state == IDLE) & i_page_cmd_ready;

always@(posedge clk or posedge rst)
if(rst) begin
    state          <= IDLE;
    nxt_state      <= IDLE;
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
            if(i_cmd_valid & i_page_cmd_ready & (i_wcmd[7:0]==8'h80)) begin
                state <= PROG; 
            end
            else if (i_cmd_valid & i_page_cmd_ready & (i_wcmd[7:0]==8'h85)) begin
                state <= COPR;
            end
        end
        PROG: begin
            if(i_page_cmd_ready & (i_wdata_avail > 24'h0)) begin
                state            <= WAIT;
                nxt_state        <= IDLE;
                o_page_cmd_valid <= 1'b1;
                o_page_cmd       <= 16'h1080;
                o_page_cmd_last  <= 1'b1;
                o_page_cmd_id    <= i_wcmd_id;
                o_page_addr      <= i_waddr;
                o_page_cmd_param <= {i_wlen[15:0], 12'h800, 3'h6, 1'b1};
            end        
        end
        COPR: begin
            if(i_page_cmd_ready) begin
                state            <= WAIT;
                nxt_state        <= IDLE;
                o_page_cmd_valid <= 1'b1;
                o_page_cmd       <= 16'h1085;
                o_page_cmd_last  <= 1'b1;
                o_page_cmd_id    <= i_wcmd_id;
                o_page_addr      <= i_waddr;
                o_page_cmd_param <= {16'h0, 12'h800, 3'h6, 1'b1};
            end        
        end

        WAIT: begin
            o_page_cmd_valid <= 1'b0;
            if(~(i_page_cmd_ready | o_page_cmd_valid)) begin
                state <= nxt_state;
            end 
        end
        default: begin
            state <= IDLE;
        end
    endcase
end






endmodule
