`timescale 1ns / 1ps


module nfc_channel_test#(
    parameter DATA_WIDTH = 32,
    parameter WAY_NUM    = 1,    // number of ways (NAND_CE & NAND_RB)
    parameter PATCH      = "FALSE"   // patch due to unproper FMC pinmap for DQS2/3
)(

    // NAND Flash Clock Domai
    input                         nand_clk_fast,
    input                         nand_clk_slow,
    input                         nand_clk_rst,
    input                         nand_usr_rstn,
    input                         nand_usr_clk,
    input                         ref_clk,   // reference clock for IDELAYCTRL

    output                        o_ready,
    input                         i_valid,
    output                        o_done,
    input  [15:0]                 i_opc, 
    input  [47:0]                 i_lba, // logical block address 111
    input  [23:0]                 i_len, // transfer data length in bytes

    output                        req_fifo_almost_full,
    output  [7:0]                 o_sr_0,
    output [1:0]                  o_status_0,
    output                        o_cmd_done,

    input  wire                        axis_wvalid_0,
    output wire                        axis_wready_0,
    input  wire [DATA_WIDTH-1 : 0]     axis_wdata_0,
    input  wire [DATA_WIDTH/8-1 : 0]   axis_wkeep_0,
    input  wire                        axis_wlast_0,

    output wire                        axis_rvalid_0,
    input  wire                        axis_rready_0,
    output wire [DATA_WIDTH-1 : 0]     axis_rdata_0,
    output wire [DATA_WIDTH/8-1 : 0]   axis_rkeep_0,
    output wire [15 : 0]               axis_rid_0,
    output wire [ 3 : 0]               axis_ruser_0,
    output wire                        axis_rlast_0,
    
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


wire [23 : 0]                axis_data_avail_0;




wire                         i_req_ready_0;
wire                         o_req_valid_0;
wire [263:0]                 o_req_data_0;


    
nfc_test #(
    .DATA_WIDTH(DATA_WIDTH)
)nfc_test_0(
    .clk          (nand_usr_clk     ), 
    .rst_n        (nand_usr_rstn  ), 
    .o_ready      (o_ready       ), 
    .i_valid      (i_valid      ), 
    .i_opc        (i_opc        ),
    .i_lba        (i_lba        ), 
    .i_len        (i_len        ), 


    .i_req_ready  (i_req_ready_0), 
    .o_req_valid  (o_req_valid_0), 
    .o_req_data   (o_req_data_0 ) 
);    


fcc_top  #(
    .PATCH                (PATCH           )
) fcc_top(
    .clk                  (nand_usr_clk             ),
    .rst_n                (nand_usr_rstn          ),
    .nand_clk_fast        (nand_clk_fast        ),
    .nand_clk_slow        (nand_clk_slow        ),
    .nand_clk_reset       (nand_clk_rst         ),
    .nand_usr_rstn        (nand_usr_rstn        ),
    .nand_usr_clk         (nand_usr_clk         ),
    .ref_clk              (ref_clk              ),

    .req_fifo_almost_full (req_fifo_almost_full),
    .o_sr_0               (o_sr_0               ),
    .o_status_0           (o_status_0           ),
    .o_cmd_done           (o_cmd_done),

    .o_req_fifo_ready_0   (i_req_ready_0        ),
    .i_req_fifo_valid_0   (o_req_valid_0        ),
    .i_req_fifo_data_0    (o_req_data_0         ),
    
    
    .s_data_avail_0       (axis_data_avail_0    ),
    .s_axis_tready_0      (axis_wready_0        ),
    .s_axis_tvalid_0      (axis_wvalid_0        ),
    .s_axis_tdata_0       (axis_wdata_0         ),
    .s_axis_tlast_0       (axis_wlast_0         ),
    
    .m_axis_tready_0      (axis_rready_0        ),
    .m_axis_tvalid_0      (axis_rvalid_0        ),
    .m_axis_tdata_0       (axis_rdata_0         ),
    .m_axis_tkeep_0       (axis_rkeep_0         ),
    .m_axis_tlast_0       (axis_rlast_0         ),
    .m_axis_tid_0         (axis_rid_0           ),
    .m_axis_tuser_0       (axis_ruser_0         ),
    
    .O_NAND_CE_N          (O_NAND_CE_N          ),
    .I_NAND_RB_N          (I_NAND_RB_N          ),
    .O_NAND_WE_N          (O_NAND_WE_N          ),
    .O_NAND_CLE           (O_NAND_CLE           ),
    .O_NAND_ALE           (O_NAND_ALE           ),
    .O_NAND_WP_N          (O_NAND_WP_N          ),
    .O_NAND_RE_P          (O_NAND_RE_P          ),
    .O_NAND_RE_N          (O_NAND_RE_N          ),
    .IO_NAND_DQS_P        (IO_NAND_DQS_P        ),
    .IO_NAND_DQS_N        (IO_NAND_DQS_N        ),
    .IO_NAND_DQ           (IO_NAND_DQ           ) 
);
    

    
    
    
    
    
    
    
endmodule
