`timescale 1ns / 1ps
`include "nfc_param.vh"

module nfc_test #(
    parameter WAY_NUM    = 1,    // number of ways (NAND_CE & NAND_RB)
    parameter DATA_WIDTH = 8
)(
    input                          clk,
    input                          rst_n,
    

    output                         o_ready,
    input                          i_valid,
    input  [15:0]                  i_opc, 
    input  [47:0]                  i_lba, // logical block address 
    input  [23:0]                  i_len, // transfer data length in bytes
    
    input                          i_req_ready,
    output reg                     o_req_valid,
    output reg [263:0]             o_req_data
);
    
    
// #####################################3
// OPC:
// 00FFh: Reset
// 01EFh: Set Timing mode
// 02EFh: Set NVDDR2
// 00ECh: Get Parameter page
// 3000h: Read Page
// 1080h: Program page
// D060h: Erase Block

// Request Entry Format
// Dword 0   : [31 : 16] CID, Command ID
//             [15 : 0]  OPC, Opcode
// Dword 1-2 : [47 : 0]  nand address 
//             [63 : 40] data length
// Dword 3-4 : [63 : 0]  metadata
// Dword 5   : [31 : 16] colum address
//             [15 : 0]  data length
// Dword 6   : [31 : 16] colum address
//             [15 : 0]  data length
// Dword 7  :  [ 7 : 0]  colum operation number



localparam
    PAGE_SIZE = `PAGE_UTIL_BYTE;
    
    
reg [15:0] cmd_id=0;

localparam
    IDLE   = 2'd0,
    REQ    = 2'd1;

localparam DATA_BYTE = DATA_WIDTH >> 3;

    
reg  state;

//reg [15:0] cnt;
//reg        hold;

assign o_ready = (state == IDLE);



always@(posedge clk or negedge rst_n)
if(~rst_n) begin
    state        <= IDLE;
    o_req_valid  <= 1'h0;
    o_req_data   <= 264'h0;

end else begin
    case(state) 
        IDLE: begin
            if(i_valid & (i_opc == 16'h1080)) begin
                state       <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, i_len[23:0], i_lba[47:0], cmd_id, i_opc};
            end else if(i_valid & (i_opc == 16'h1085)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, i_len[23:0], i_lba[47:0], cmd_id, i_opc};
            end else if(i_valid & (i_opc == 16'h3000)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, i_len[23:0], i_lba[47:0], cmd_id, i_opc};
            end else if(i_valid & (i_opc == 16'h3500)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, i_len[23:0], i_lba[47:0], cmd_id, i_opc};
            end else if(i_valid & (i_opc == 16'hD060)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, i_len[23:0], i_lba[47:0], cmd_id, i_opc};
            end else if(i_valid & (i_opc == 16'hFF)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, 72'h0, cmd_id, i_opc};
            end else if(i_valid & (i_opc == 16'h01EF)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h24, 24'h0, 48'h01, cmd_id, 16'h00EF};
            end else if(i_valid & (i_opc == 16'h02EF)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {`PG_WARMUP, `RD_WARMUP, 8'h07, 24'h0, 48'h02, cmd_id, 16'h00EF};
            end else if(i_valid & (i_opc == 16'h00EC)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, 24'h100, 48'h0, cmd_id, 16'h00EC};
            end else if(i_valid & (i_opc == 16'h01EE)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, 24'h100, 48'h01, cmd_id, 16'h00EE};
            end else if(i_valid & (i_opc == 16'h2090)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, 24'h00, 48'h20, cmd_id, 16'h0090};    
            end else if(i_valid & (i_opc == 16'h0090)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, 24'h00, 48'h0, cmd_id, 16'h0090}; 
            end else if(i_valid & (i_opc == 16'h00ED)) begin
                state      <= REQ;
                o_req_valid <= 1'h1;
                o_req_data  <= {64'h0, 24'h00, 48'h0, cmd_id, 16'h00ED};
            end 
        end        
        REQ: begin
                    // hold valid until downstream accepts
                    if (o_req_valid && i_req_ready) begin
                        // accepted
                        o_req_valid <= 1'b0;
                        // increment cmd id on acceptance (deterministic)
                        cmd_id <= cmd_id + 16'h1;
                        // go back to IDLE to accept next
                        state <= IDLE;
                    end else begin
                        // keep o_req_valid and o_req_data stable while waiting
                        o_req_valid <= o_req_valid;
                        o_req_data  <= o_req_data;
                    end
                end
        default: begin
                    state <= IDLE;
                 end
    endcase
end





 
    
endmodule
