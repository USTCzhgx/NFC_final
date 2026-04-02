`timescale 1ns / 1ps

module data_fifo_wr #(
    parameter S_DATA_WIDTH = 32,
    parameter M_DATA_WIDTH = 32
)(
    input                         s_aclk,
    input                         s_aresetn,
    input                         m_aclk,
    output     [23 : 0]           m_data_avail, // data available to read (used space)
    output reg [23 : 0]           s_data_avail, // data available to write (left space)
    output                        s_axis_tready, 
    input                         s_axis_tvalid,                     
    input  [S_DATA_WIDTH - 1 : 0] s_axis_tdata, 
    input                         s_axis_tlast,           
    input                         m_axis_tready,
    output                        m_axis_tvalid,                        
    output [M_DATA_WIDTH - 1 : 0] m_axis_tdata,
    output                        m_axis_tlast         
);

wire [10 : 0] axis_wr_data_count;
wire [10 : 0] axis_rd_data_count;

assign m_data_avail = {axis_rd_data_count, 2'h0};

always@(posedge s_aclk or negedge s_aresetn)
if(~s_aresetn) begin
    s_data_avail <= 24'h0;
end else begin
    s_data_avail[23:2] <= 22'h400 - axis_wr_data_count;
end
    
asyn_fifo_wr asyn_fifo_wr ( // depth 1024
      .m_aclk            (m_aclk            ),     // input wire m_aclk
      .s_aclk            (s_aclk            ),     // input wire s_aclk
      .s_aresetn         (s_aresetn         ),     // input wire s_aresetn
      .s_axis_tvalid     (s_axis_tvalid     ),     // input wire s_axis_tvalid
      .s_axis_tready     (s_axis_tready     ),     // output wire s_axis_tready
      .s_axis_tdata      (s_axis_tdata      ),     // input wire [31 : 0] s_axis_tdata
      .s_axis_tlast      (s_axis_tlast      ),     // input wire s_axis_tlast
      .m_axis_tvalid     (m_axis_tvalid     ),     // output wire m_axis_tvalid
      .m_axis_tready     (m_axis_tready     ),     // input wire m_axis_tready
      .m_axis_tdata      (m_axis_tdata      ),     // output wire [31 : 0] m_axis_tdata
      .m_axis_tlast      (m_axis_tlast      ),     // output wire m_axis_tlast
      .axis_wr_data_count(axis_wr_data_count),     // output wire [10 : 0] axis_wr_data_count
      .axis_rd_data_count(axis_rd_data_count)      // output wire [10 : 0] axis_rd_data_count
);
    
    
endmodule
