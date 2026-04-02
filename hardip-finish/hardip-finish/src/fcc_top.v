`timescale 1ns / 1ps

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


// Response Entry Format
// Dword 0-1 : [63 : 0]  command specific
// Dword 2   : [15 : 0]  CID, Command ID
// ########################################################################
// fcc_top:
//   1. request/response interfaces with handshaking
//   2. master/slave axi-stream interfaces with internal data FIFOs
//   3. m_axis with tid and tuser
//   4. s_axis provide left FIFO space 
//   5. req/res, m_axis/s_axis interfaces within "clk" domain
// ######################################################################## 


module fcc_top #(
    parameter DATA_WIDTH = 32,   // cannot change
    parameter WAY_NUM    = 1,    // number of ways (NAND_CE & NAND_RB)
    parameter PATCH      = "FALSE"   // patch due to unproper FMC pinmap for DQS2/3
)(
    input                         clk,
    input                         rst_n,
    
    // NAND Flash Clock Domain
    input                         nand_clk_fast, //200M
    input                         nand_clk_slow,//50M
    input                         nand_clk_reset,
    input                         nand_usr_rstn,
    input                         nand_usr_clk,//50M
    input                         ref_clk,   // reference clock for IDELAYCTRL 200M
//    input                         nand_clk_locked,

    // channel 0 (single channel)
    // request fifo write ports
    output                        o_req_fifo_ready_0,  // 56
    input                         i_req_fifo_valid_0,
    input                 [263:0] i_req_fifo_data_0,
    
    output                        req_fifo_almost_full,
    output [7:0]                  o_sr_0,
    output [1:0]                  o_status_0,
    output                        o_cmd_done,
    
    // write data fifo axi-stream interfaces
    output [23 : 0]               s_data_avail_0,  // availiable data number to write
    output                        s_axis_tready_0, 
    input                         s_axis_tvalid_0,                     
    input  [DATA_WIDTH - 1 : 0]   s_axis_tdata_0, 
    input                         s_axis_tlast_0, 
    
    // read data fifo axi-stream interfaces
    input                         m_axis_tready_0,
    output                        m_axis_tvalid_0,                        
    output [  DATA_WIDTH - 1 : 0] m_axis_tdata_0,
    output [DATA_WIDTH/8 - 1 : 0] m_axis_tkeep_0,
    output                        m_axis_tlast_0,
    output               [15 : 0] m_axis_tid_0, 
    output               [ 3 : 0] m_axis_tuser_0,
    
    // NAND Flash Physicial INterfaces
    output      [WAY_NUM - 1 : 0] O_NAND_CE_N,
    input       [WAY_NUM - 1 : 0] I_NAND_RB_N,
    output                        O_NAND_WE_N,
    output                        O_NAND_CLE, 
    output                        O_NAND_ALE, 
    output                        O_NAND_WP_N,
    output                        O_NAND_RE_P,  
    output                        O_NAND_RE_N, 
    inout                         IO_NAND_DQS_P, 
    inout                         IO_NAND_DQS_N,
    inout                [ 7 : 0] IO_NAND_DQ 
);

localparam
        DATA_WIDTH_INTER = 32;   
        

wire                          o_cmd_ready_0;
wire                          i_cmd_valid_0;
wire [15 : 0]                 i_cmd_0;
wire [15 : 0]                 i_cmd_id_0;
wire [47 : 0]                 i_addr_0;
wire [23 : 0]                 i_len_0;
wire [63 : 0]                 i_data_0;
wire [ 7 : 0]                 i_col_num_0; // additional read column number
wire [63 : 0]                 i_col_addr_len_0; // additional read column address and length



wire                          i_rpage_buf_ready_0;
wire                          i_rready_0;
wire                          o_rvalid_0;
wire [DATA_WIDTH_INTER-1 : 0] o_rdata_0;
wire [ 3 : 0]                 o_ruser_0;
wire [15 : 0]                 o_rid_0;
wire                          o_rlast_0;

wire                          o_wready_0;
wire                          i_wvalid_0;
wire [DATA_WIDTH_INTER-1 : 0] i_wdata_0;
wire                          i_wlast_0;
wire [23 : 0]                 i_wdata_avail_0;

// #######################################################
// fcc_wrapper providing:
//   1. cross-clock-domain transfer
//   2. request/response interfaces with handshaking
//   3. request/response FIFOs with shadow depth
//   4. s_axis/m_axis interfaces with handshaking
//   5. s_axis/m_axis data FIFOs with page-level depth
// ####################################################### 

fcc_wrapper fcc_wrapper_0(
    .clk                (clk                ),  // input                         clk                           
    .rst_n              (rst_n              ),  // input                         rst_n       
    .nand_usr_clk       (nand_usr_clk       ),  // input                         nand_usr_clk
    .nand_usr_rstn      (nand_usr_rstn      ),  // input                         nand_usr_rstn    
    .o_req_fifo_ready   (o_req_fifo_ready_0 ),  // output                        o_req_fifo_ready             
    .i_req_fifo_valid   (i_req_fifo_valid_0 ),  // input                         i_req_fifo_valid     
    .i_req_fifo_data    (i_req_fifo_data_0  ),  // input                 [255:0] i_req_fifo_data     
    .req_fifo_almost_full(req_fifo_almost_full),   
    .s_data_avail       (s_data_avail_0     ),  //  output [23 : 0]               s_data_avail       
    .s_axis_tready      (s_axis_tready_0    ),  // output                        s_axis_tready             
    .s_axis_tvalid      (s_axis_tvalid_0    ),  // input                         s_axis_tvalid                                 
    .s_axis_tdata       (s_axis_tdata_0     ),  // input  [DATA_WIDTH - 1 : 0]   s_axis_tdata             
    .s_axis_tlast       (s_axis_tlast_0     ),  // input                         s_axis_tlast             
    .m_axis_tready      (m_axis_tready_0    ),  // input                         m_axis_tready            
    .m_axis_tvalid      (m_axis_tvalid_0    ),  // output                        m_axis_tvalid                                    
    .m_axis_tdata       (m_axis_tdata_0     ),  // output [  DATA_WIDTH - 1 : 0] m_axis_tdata            
    .m_axis_tkeep       (m_axis_tkeep_0     ),  // output [DATA_WIDTH/8 - 1 : 0] m_axis_tkeep            
    .m_axis_tlast       (m_axis_tlast_0     ),  // output                        m_axis_tlast            
    .m_axis_tid         (m_axis_tid_0       ),  // output               [15 : 0] m_axis_tid             
    .m_axis_tuser       (m_axis_tuser_0     ),  // output               [15 : 0] m_axis_tuser   
    .i_cmd_ready        (o_cmd_ready_0      ),          
    .o_cmd_valid        (i_cmd_valid_0      ),          
    .o_cmd              (i_cmd_0            ),    
    .o_cmd_id           (i_cmd_id_0         ),   
    .o_addr             (i_addr_0           ),     
    .o_len              (i_len_0            ),    
    .o_data             (i_data_0           ),     
    .o_col_num          (i_col_num_0        ),         // additional read column number
    .o_col_addr_len     (i_col_addr_len_0   ),         // additional read column address and length
    .o_rpage_buf_ready  (i_rpage_buf_ready_0),          
    .i_rvalid           (o_rvalid_0         ),       
    .i_rdata            (o_rdata_0          ),      
    .i_ruser            (o_ruser_0          ),    
    .i_rid              (o_rid_0            ),   
    .i_rlast            (o_rlast_0          ),      
    .i_wready           (o_wready_0         ),       
    .o_wvalid           (i_wvalid_0         ),       
    .o_wdata            (i_wdata_0          ),      
    .o_wlast            (i_wlast_0          ),  
    .o_wdata_avail      (i_wdata_avail_0    )
);
    
    
// ########################################################################
// fcc_core:
// Flash channel controller with single channel
//   1. request interface with handshake, while response interface not
//   2. master/slave axi-stream interfaces connect to external buffers(FIFO...)
//   3. m_axis no blocking, external buffer has at least one-page space
//   4. s_axis no stopping, external buffer has at least one-page data 
// ########################################################################        
fcc_core #(
    .WAY_NUM              (WAY_NUM         ),
    .PATCH                (PATCH           )
) fcc_core(
    .clk_fast             (nand_clk_fast      ),   
    .clk_div              (nand_clk_slow      ),   
    .clk_reset            (nand_clk_reset     ),
    .usr_clk              (nand_usr_clk       ),  
    .usr_rst              (~nand_usr_rstn     ), 
    .ref_clk              (ref_clk            ),

    .o_sr_0               (o_sr_0             ),
    .o_status_0           (o_status_0         ),
    .o_cmd_done           (o_cmd_done),
    
    .o_cmd_ready_0        (o_cmd_ready_0      ),          
    .i_cmd_valid_0        (i_cmd_valid_0      ),          
    .i_cmd_0              (i_cmd_0            ),    
    .i_cmd_id_0           (i_cmd_id_0         ),   
    .i_addr_0             (i_addr_0           ),     
    .i_len_0              (i_len_0            ),    
    .i_data_0             (i_data_0           ),     
    .i_col_num_0          (i_col_num_0        ),         // additional read column number
    .i_col_addr_len_0     (i_col_addr_len_0   ),         // additional read column address and length
    .i_rpage_buf_ready_0  (i_rpage_buf_ready_0),          
    .o_rvalid_0           (o_rvalid_0         ),       
    .o_rdata_0            (o_rdata_0          ),      
    .o_ruser_0            (o_ruser_0          ),    
    .o_rid_0              (o_rid_0            ),   
    .o_rlast_0            (o_rlast_0          ),      
    .o_wready_0           (o_wready_0         ),       
    .i_wvalid_0           (i_wvalid_0         ),       
    .i_wdata_0            (i_wdata_0          ),      
    .i_wlast_0            (i_wlast_0          ),  
    .i_wdata_avail_0      (i_wdata_avail_0    ),
    .O_NAND_CE_N          (O_NAND_CE_N        ),   
    .I_NAND_RB_N          (I_NAND_RB_N        ),   
    .O_NAND_WE_N          (O_NAND_WE_N        ),                                    
    .O_NAND_CLE           (O_NAND_CLE         ),                                    
    .O_NAND_ALE           (O_NAND_ALE         ),                                    
    .O_NAND_WP_N          (O_NAND_WP_N        ),                                    
    .O_NAND_RE_P          (O_NAND_RE_P        ),                                      
    .O_NAND_RE_N          (O_NAND_RE_N        ),                                     
    .IO_NAND_DQS_P        (IO_NAND_DQS_P      ),                                       
    .IO_NAND_DQS_N        (IO_NAND_DQS_N      ),                                      
    .IO_NAND_DQ           (IO_NAND_DQ         ) 
);    
    
    
      
endmodule
