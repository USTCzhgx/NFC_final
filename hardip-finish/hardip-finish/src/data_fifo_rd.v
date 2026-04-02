`timescale 1ns / 1ps



module data_fifo_rd#(
    parameter S_DATA_WIDTH = 32,
    parameter M_DATA_WIDTH = 32
)(
    input                           s_aclk,
    input                           s_aresetn,
    input                           m_aclk,
    input                           m_aresetn,
    output                          s_fifo_ready,
    output                          s_axis_tready, 
    input                           s_axis_tvalid,                     
    input  [  S_DATA_WIDTH - 1 : 0] s_axis_tdata, 
    input                           s_axis_tlast,  
    input                  [15 : 0] s_axis_tid, 
    input                   [3 : 0] s_axis_tuser,      
    input                           m_axis_tready,
    output                          m_axis_tvalid,                        
    output [  M_DATA_WIDTH - 1 : 0] m_axis_tdata,
    output [M_DATA_WIDTH/8 - 1 : 0] m_axis_tkeep,
    output                          m_axis_tlast,
    output                 [15 : 0] m_axis_tid,  
    output                 [ 3 : 0] m_axis_tuser        
);

wire axis_prog_full;

assign s_fifo_ready = ~axis_prog_full;
//assign m_axis_tuser = m_axis_tuser_tmp[3:0];
assign m_axis_tkeep = 4'hf;
    
asyn_fifo_rd asyn_fifo_rd (
      .m_aclk            (m_aclk            ),     // input wire m_aclk
      .s_aclk            (s_aclk            ),     // input wire s_aclk
      .s_aresetn         (s_aresetn         ),     // input wire s_aresetn
      .s_axis_tvalid     (s_axis_tvalid     ),     // input wire s_axis_tvalid
      .s_axis_tready     (s_axis_tready     ),     // output wire s_axis_tready
      .s_axis_tdata      (s_axis_tdata      ),     // input wire [31 : 0] s_axis_tdata
      .s_axis_tlast      (s_axis_tlast      ),     // input wire s_axis_tlast
      .s_axis_tid        (s_axis_tid        ),     // input wire [15 : 0] s_axis_tid
      .s_axis_tuser      (s_axis_tuser      ),     // input wire [3 : 0] s_axis_tuser
      .m_axis_tvalid     (m_axis_tvalid     ),     // output wire m_axis_tvalid
      .m_axis_tready     (m_axis_tready     ),     // input wire m_axis_tready
      .m_axis_tdata      (m_axis_tdata      ),     // output wire [31 : 0] m_axis_tdata
      .m_axis_tlast      (m_axis_tlast      ),     // output wire m_axis_tlast
      .m_axis_tid        (m_axis_tid        ),     // output wire [15 : 0] m_axis_tid
      .m_axis_tuser      (m_axis_tuser      ),     // output wire [3 : 0] m_axis_tuser
      .axis_prog_full    (axis_prog_full    )      // output wire axis_prog_full
);
    
    


    
endmodule
