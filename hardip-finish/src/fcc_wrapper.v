`timescale 1ns / 1ps
/*
2025.11.13 SCMI ZGX 

*/

module fcc_wrapper#(
    parameter DATA_WIDTH = 32,  // cannot change
    parameter DATA_WIDTH_INTER = 32
)(

    input                         clk,
    input                         rst_n,
    
    // NAND Flash Clock Domain
    input                         nand_usr_clk,
    input                         nand_usr_rstn,
    
    // channel 0
    // request fifo write ports
    output                        o_req_fifo_ready,  // 56
    input                         i_req_fifo_valid,
    input                 [263:0] i_req_fifo_data,
    
    output                        req_fifo_almost_full,
    
    // write data fifo axi-stream interfaces
    output [23 : 0]               s_data_avail,  // availiable data number to write
    output                        s_axis_tready, 
    input                         s_axis_tvalid,                     
    input  [DATA_WIDTH - 1 : 0]   s_axis_tdata, 
    input                         s_axis_tlast, 
    
    // read data fifo axi-stream interfaces
     input                         m_axis_tready,
     output                        m_axis_tvalid,                        
     output [  DATA_WIDTH - 1 : 0] m_axis_tdata,
    output [DATA_WIDTH/8 - 1 : 0] m_axis_tkeep,
    output                        m_axis_tlast,
    output               [15 : 0] m_axis_tid, 
    output               [ 3 : 0] m_axis_tuser,
    
    input                           i_cmd_ready,
    output reg                      o_cmd_valid,
    (* MARK_DEBUG="true" *) output [15 : 0]                 o_cmd,
    (* MARK_DEBUG="true" *) output [15 : 0]                 o_cmd_id,
    output [47 : 0]                 o_addr,
    output [23 : 0]                 o_len,
    output [63 : 0]                 o_data,
    output [ 7 : 0]                 o_col_num, // additional read column number
    output [63 : 0]                 o_col_addr_len, // additional read column address and length
   
    output                          o_rpage_buf_ready, // has enough buffer space
    input                           i_rvalid,
    input  [DATA_WIDTH_INTER-1 : 0] i_rdata,
    input  [ 3 : 0]                 i_ruser,
    input  [15 : 0]                 i_rid,
    input                           i_rlast,
    input                           i_wready,
    output                          o_wvalid,
    output [DATA_WIDTH_INTER-1 : 0] o_wdata,
    output                          o_wlast,
    output [23 : 0]                 o_wdata_avail // availiable (bufferred) data number
);

        
localparam
        IDLE = 1'b0,
        WAIT = 1'b1; 
        

       
reg                           req_state;
reg  [  7 : 0]                cnt;

wire                          req_fifo_wen;  
wire                          req_fifo_ren;      
wire [263 : 0]                req_fifo_rdata;    
wire                          req_fifo_full;     
wire                          req_fifo_empty;
wire                          req_fifo_prog_full;  // 56



reg [31:0] debug_wr_cnt;
reg [31:0] debug_rd_cnt;

reg cmd_ready_reg;



// Request Async FIFO, depth = 16
asyn_req_fifo asyn_req_fifo (
  .rst      (~nand_usr_rstn    ),    // input wire rst
  .wr_clk   (clk               ),    // input wire wr_clk
  .rd_clk   (nand_usr_clk      ),    // input wire rd_clk
  .din      (i_req_fifo_data   ),    // input wire [263 : 0] din
  .wr_en    (req_fifo_wen      ),    // input wire wr_en
  .rd_en    (req_fifo_ren      ),    // input wire rd_en
  .dout     (req_fifo_rdata    ),    // output wire [263 : 0] dout
  .full     (req_fifo_full     ),    // output wire full
  .empty    (req_fifo_empty    ),    // output wire empty
  .prog_full(req_fifo_prog_full)     // output wire prog_full
);

assign o_req_fifo_ready = ~req_fifo_prog_full;
assign req_fifo_wen   = i_req_fifo_valid & o_req_fifo_ready;
assign req_fifo_ren   = (req_state == IDLE) & i_cmd_ready & (~req_fifo_empty);
assign o_cmd          = req_fifo_rdata[15:0];
assign o_cmd_id       = req_fifo_rdata[31:16];
assign o_addr         = req_fifo_rdata[79:32];
assign o_len          = req_fifo_rdata[103:80];
assign o_data         = req_fifo_rdata[167:104];
assign o_col_addr_len = req_fifo_rdata[231:168];
assign o_col_num      = req_fifo_rdata[239:232];
assign req_fifo_almost_full = req_fifo_prog_full;

always@(posedge nand_usr_clk or negedge nand_usr_rstn)
if(~nand_usr_rstn) begin
    req_state   <= IDLE;
    o_cmd_valid <= 1'b0;   
    cnt         <= 8'h0;  
end else begin
    case(req_state)
        IDLE: begin
            if(i_cmd_ready & (~req_fifo_empty)) begin
                req_state   <= WAIT;
                o_cmd_valid <= 1'b1;
                cnt         <= 8'h0;
            end else begin
                req_state   <= IDLE;
                o_cmd_valid <= 1'b0;
            end
        end
        
        WAIT: begin
            if(~i_cmd_ready) begin 
                req_state   <= IDLE;
                o_cmd_valid <= 1'b0;
                cnt         <= 8'h0;
            end else if(cnt < 8'h8) begin
                req_state   <= WAIT;
                o_cmd_valid <= 1'b1; 
                cnt         <= cnt + 8'h1;
            end else begin
                req_state   <= IDLE;
                o_cmd_valid <= 1'b0;
                cnt         <= 8'h0;
            end
        end
    endcase
end




// Write (program) Data FIFO, 64KB
data_fifo_wr data_fifo_wr (
      .s_aclk       (clk           ),    // input wire aclk
      .s_aresetn    (rst_n         ),    // input wire aresetn
      .m_aclk       (nand_usr_clk  ),
      .m_data_avail (o_wdata_avail ),    // output [23 : 0] m_data_avail,
      .s_data_avail (s_data_avail  ),    // output [23 : 0] s_data_avail,
      .s_axis_tvalid(s_axis_tvalid ),    // input wire s_axis_tvalid
      .s_axis_tready(s_axis_tready ),    // output wire s_axis_tready
      .s_axis_tdata (s_axis_tdata  ),    // input wire [31 : 0] s_axis_tdata
      .s_axis_tlast (s_axis_tlast  ),    // input wire s_axis_tlast
      .m_axis_tvalid(o_wvalid      ),    // output wire m_axis_tvalid
      .m_axis_tready(i_wready      ),    // input wire m_axis_tready
      .m_axis_tdata (o_wdata       ),    // output wire [31 : 0] m_axis_tdata
      .m_axis_tlast (o_wlast       )     // output wire m_axis_tlast
);


// Read Data (page data or parameter data) FIFO, 64KB
data_fifo_rd data_fifo_rd(
    .s_aclk        (nand_usr_clk     ),  // input                           s_aclk               
    .s_aresetn     (nand_usr_rstn    ),  // input                           s_aresetn               
    .m_aclk        (clk              ),  // input                           m_aclk               
    .m_aresetn     (rst_n            ),  // input                           m_aresetn               
    .s_fifo_ready  (o_rpage_buf_ready),  // output                          s_fifo_ready               
    .s_axis_tready (o_rready         ),  // output                          s_axis_tready                
    .s_axis_tvalid (i_rvalid         ),  // input                           s_axis_tvalid                                    
    .s_axis_tdata  (i_rdata          ),  // input  [  S_DATA_WIDTH - 1 : 0] s_axis_tdata                
    .s_axis_tlast  (i_rlast          ),  // input                           s_axis_tlast                 
    .s_axis_tid    (i_rid            ),  // input                  [15 : 0] s_axis_tid                
    .s_axis_tuser  (i_ruser          ),  // input                   [3 : 0] s_axis_tuser                     
    .m_axis_tready (m_axis_tready    ),  // input                           m_axis_tready               
    .m_axis_tvalid (m_axis_tvalid    ),  // output                          m_axis_tvalid                                       
    .m_axis_tdata  (m_axis_tdata     ),  // output [  M_DATA_WIDTH - 1 : 0] m_axis_tdata               
    .m_axis_tkeep  (m_axis_tkeep     ),  // output [M_DATA_WIDTH/8 - 1 : 0] m_axis_tkeep               
    .m_axis_tlast  (m_axis_tlast     ),  // output                          m_axis_tlast               
    .m_axis_tid    (m_axis_tid       ),  // output                 [15 : 0] m_axis_tid                 
    .m_axis_tuser  (m_axis_tuser     )   // output                 [ 3 : 0] m_axis_tuser        
);    
   

// ��ʱ���������Ӽ�����
always @(posedge nand_usr_clk or negedge nand_usr_rstn)
if(~nand_usr_rstn) begin
    debug_wr_cnt <= 32'h0;
    debug_rd_cnt <= 32'h0;
end else begin
    if(s_axis_tvalid & s_axis_tready)
        debug_wr_cnt <= debug_wr_cnt + 1;
    if(m_axis_tvalid & m_axis_tready)
        debug_rd_cnt <= debug_rd_cnt + 1;
end

endmodule
