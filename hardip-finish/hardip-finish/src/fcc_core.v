`timescale 1ns / 1ps



`include "nfc_param.vh"

module fcc_core #(
    parameter DATA_WIDTH = 32,  // cannot change
    parameter WAY_NUM    = 1,    // number of ways (NAND_CE & NAND_RB)
    parameter PATCH      = "FALSE"   // patch due to unproper FMC pinmap for DQS2/3
)(
    input                          clk_fast,        // 400M
    input                          clk_div,    // 100M
    input                          clk_reset,    
    input                          usr_rst,
    input                          usr_clk,    // 50M
    input                          ref_clk,    // reference clock for IDELAYCTRL

    output  [7:0]                  o_sr_0,
    output  [1:0]                  o_status_0,
    output                         o_cmd_done,

    output                         o_cmd_ready_0,
    input                          i_cmd_valid_0,
    input  [15 : 0]                i_cmd_0,
    input  [15 : 0]                i_cmd_id_0,
    input  [47 : 0]                i_addr_0,
    input  [23 : 0]                i_len_0,
    input  [63 : 0]                i_data_0,
    input  [ 7 : 0]                i_col_num_0, // additional read column number
    input  [63 : 0]                i_col_addr_len_0, // additional read column address and length
    input                          i_rpage_buf_ready_0, // has enough buffer space 
    output                         o_rvalid_0,
    output [DATA_WIDTH-1 : 0]      o_rdata_0,
    output [ 3 : 0]                o_ruser_0,
    output [15 : 0]                o_rid_0,
    output                         o_rlast_0,
    output                         o_wready_0,
    input                          i_wvalid_0,
    input  [DATA_WIDTH-1 : 0]      i_wdata_0,
    input                          i_wlast_0,
    input  [23 : 0]                i_wdata_avail_0, // availiable (bufferred) data number
    output [WAY_NUM - 1 : 0]       O_NAND_CE_N,
    input  [WAY_NUM - 1 : 0]       I_NAND_RB_N,
    output                         O_NAND_WE_N,
    output                         O_NAND_CLE, 
    output                         O_NAND_ALE, 
    output                         O_NAND_WP_N,
    output                         O_NAND_RE_P,  
    output                         O_NAND_RE_N, 
    inout                          IO_NAND_DQS_P, 
    inout                          IO_NAND_DQS_N,
    inout  [         7 : 0]        IO_NAND_DQ 
);
                                                              


reg                       i_page_cmd_ready_0; // fcc_scheduler input 
reg                       i_page_cmd_valid_0; // fcc_executer input
wire                      o_page_cmd_ready_0; // fcc_executer output
wire                      o_page_cmd_valid_0; // fcc_scheduler output
wire  [15 : 0]            o_page_cmd_0;
wire  [15 : 0]            o_page_cmd_id_0;
wire  [47 : 0]            o_page_addr_0;
wire  [63 : 0]            o_page_data_0;
wire  [31 : 0]            o_page_cmd_param_0;    
wire  [ 1 : 0]            o_page_cmd_type_0;
wire                      o_page_rd_not_last_0;

reg                       i_keep_wait_0;


reg   [WAY_NUM - 1 : 0] i_ce_n;                                     
wire  [WAY_NUM - 1 : 0] o_rb_n;                                     
reg                        i_we_n;                                     
reg                        i_cle;                                     
reg                        i_ale;                                     
reg                        i_wp_n;                                     
reg              [  3 : 0] i_re;                                     
reg                        i_dqs_tri_en;  // 1 - reg, 0 - wire
reg              [  3 : 0] i_dqs;        
wire             [  3 : 0] o_dqs;        
reg                        i_dq_tri_en;   // 1 - reg, 0 - wire
reg              [ 31 : 0] i_dq;                                     
wire             [ 31 : 0] o_dq; 

wire                       io_busy_0;
wire                       o_ce_n_0;                                                                          
wire                       o_we_n_0;                                     
wire                       o_cle_0;                                     
wire                       o_ale_0;                                     
wire                       o_wp_n_0;                                     
wire             [  3 : 0] o_re_0;                                     
wire                       o_dqs_tri_en_0;  // 1 - reg, 0 - wire
wire             [  3 : 0] o_dqs_0;             
wire                       o_dq_tri_en_0;   // 1 - reg, 0 - wire
wire             [ 31 : 0] o_dq_0;     
wire                       i_rb_n_0;
wire             [  3 : 0] i_dqs_0; 
wire             [ 31 : 0] i_dq_0;


//////////////////////////////////////////////////////////////////////////////////
//// ** WAY Level CMDs ** /////

fcc_scheduler fcc_scheduler_0(
    .clk              (usr_clk           ),
    .rst              (usr_rst           ),
    .o_cmd_ready      (o_cmd_ready_0     ),
    .i_cmd_valid      (i_cmd_valid_0     ),
    .i_cmd            (i_cmd_0           ),
    .i_cmd_id         (i_cmd_id_0        ),
    .i_addr           (i_addr_0          ),
    .i_len            (i_len_0           ),
    .i_data           (i_data_0          ),
    .i_col_num        (i_col_num_0       ), // additional read column number
    .i_col_addr_len   (i_col_addr_len_0  ), // additional read column address and length
    

    
    .i_wdata_avail    (i_wdata_avail_0   ),
    .i_rpage_buf_ready(i_rpage_buf_ready_0),
    .i_page_cmd_ready (i_page_cmd_ready_0), 
    .o_page_cmd_valid (o_page_cmd_valid_0), 
    .o_page_cmd       (o_page_cmd_0      ),
    .o_page_cmd_id    (o_page_cmd_id_0   ),
    .o_page_addr      (o_page_addr_0     ),
    .o_page_data      (o_page_data_0     ),
    .o_page_cmd_param (o_page_cmd_param_0),
    .o_page_rd_not_last(o_page_rd_not_last_0),
    .o_page_cmd_type  (o_page_cmd_type_0 )
);


//////////////////////////////////////////////////////////////////////////////////
//// ** WAY level control ** /////
// Single channel - simplified control logic

localparam
    IDLE = 2'd0,
    WAIT = 2'd1,
    LOCK = 2'd2,
    FIN  = 2'd3;

reg [1:0] state_0;
 wire is_busy_0;


always@(posedge usr_clk or posedge usr_rst)    
if(usr_rst) begin 
    state_0 <= IDLE;                                                                            
end else begin
    case(state_0)
        IDLE: begin
            if(o_page_cmd_valid_0) begin  // pre-fectch cmd
                state_0 <= WAIT;
            end
        end
        WAIT: begin
            if(i_page_cmd_valid_0) begin // wait cmd is allowed to transmit
                state_0 <= LOCK; 
            end
        end
        LOCK: begin
            if(~o_page_cmd_ready_0) begin // target module executes  cmds
                state_0 <= FIN; 
            end
        end
        FIN: begin
            if(o_page_cmd_ready_0) begin // target module completes  cmds 
                state_0 <= IDLE; 
            end
        end
    endcase
end

always@(posedge usr_clk or posedge usr_rst)    
if(usr_rst) begin                                                                 
    i_page_cmd_ready_0 <= 1'h0;  
end else if((state_0 == IDLE) && (~o_page_cmd_valid_0))begin
    i_page_cmd_ready_0 <= 1'h1;  
end else begin
    i_page_cmd_ready_0 <= 1'h0;
end

//assign is_busy_0 = (o_status_0 == 2'h1);

// Single channel - directly connect scheduler to executer
always@(posedge usr_clk or posedge usr_rst)    
if(usr_rst) begin                                                                 
    i_page_cmd_valid_0 <= 1'h0;  
    i_keep_wait_0      <= 1'h0;
end else begin
    // Pass through command when scheduler has valid command
    i_page_cmd_valid_0 <= o_page_cmd_valid_0;
    i_keep_wait_0      <= 1'h0;  // No need to wait for other channels
end    
   
// keep waiting when other WAYs in BUSY status
//always@(posedge usr_clk or posedge usr_rst)    
//if(usr_rst) begin                                                                      
//    i_keep_wait_0 <= 1'h0;        
//end else if(o_status_1 == 2'h1) begin
//    i_keep_wait_0 <= 1'h1;
//end else begin
//    i_keep_wait_0 <= 1'h0;
//end

//always@(posedge usr_clk or posedge usr_rst)    
//if(usr_rst) begin                                                                      
//    i_keep_wait_1 <= 1'h0;        
//end else if(o_status_0 == 2'h1) begin
//    i_keep_wait_1 <= 1'h1;
//end else begin
//    i_keep_wait_1 <= 1'h0;
//end


fcc_executer fcc_executer_0(
    .clk            (usr_clk           ),
    .rst            (usr_rst          ),         
    .o_cmd_ready    (o_page_cmd_ready_0),                   
    .i_cmd_valid    (i_page_cmd_valid_0),                   
    .i_cmd          (o_page_cmd_0      ),  
    .i_cmd_id       (o_page_cmd_id_0   ),           
    .i_addr         (o_page_addr_0     ), 
    .i_data         (o_page_data_0     ),              
    .i_cmd_param    (o_page_cmd_param_0), 
    .i_cmd_type     (o_page_cmd_type_0 ), 
    .i_keep_wait    (i_keep_wait_0     ),
    
    .o_status       (o_status_0        ),                                   
    .o_sr_r         (o_sr_0             ),
    .o_cmd_done     (o_cmd_done),
    .i_rready       (i_rpage_buf_ready_0),
    .o_rvalid       (o_rvalid_0        ),                
    .o_rdata        (o_rdata_0         ), 
    .o_ruser        (o_ruser_0         ),   
    .o_rid          (o_rid_0           ),            
    .o_rlast        (o_rlast_0         ), 
       
    .o_wready       (o_wready_0        ),                
    .i_wvalid       (i_wvalid_0        ),               
    .i_wdata        (i_wdata_0         ),  
    .i_wlast        (i_wlast_0         ), 
     
    .io_busy        (io_busy_0         ),                     
    .o_ce_n         (o_ce_n_0          ), 
    .o_wp_n         (o_wp_n_0          ), 
    .i_rb_n         (i_rb_n_0          ), 
    .o_we_n         (o_we_n_0          ), 
    .o_cle          (o_cle_0           ), 
    .o_ale          (o_ale_0           ), 
    .o_re           (o_re_0            ), 
    .o_dqs_tri_en   (o_dqs_tri_en_0    ),     // 1 - input,   0 - output
    .o_dqs          (o_dqs_0           ), 
    .i_dqs          (i_dqs_0           ), 
    .o_dq_tri_en    (o_dq_tri_en_0     ),     // 1 - input,   0 - output
    .o_dq           (o_dq_0            ), 
    .i_dq           (i_dq_0            )
);

assign i_rb_n_0 = o_rb_n[0];
assign i_dqs_0  = o_dqs;
assign i_dq_0   = o_dq;

// Single channel - directly connect channel 0 to physical layer
always@(posedge usr_clk or posedge usr_rst)    
if(usr_rst) begin                                                                      
    i_ce_n <= 'hf;        
end else begin
    i_ce_n <= o_ce_n_0;
end   

always@(posedge usr_clk or posedge usr_rst)    
if(usr_rst) begin                                                                      
    i_we_n       <= 1'h1;                                    
    i_cle        <= 1'h0;                                    
    i_ale        <= 1'h0;                                    
    i_wp_n       <= 1'h1;                                    
    i_re         <= 4'hf;                                    
    i_dqs_tri_en <= 1'h0;  // 1 - input, 0 - output
    i_dqs        <= 4'hf;              
    i_dq_tri_en  <= 1'h1;  // 1 - input, 0 - output
    i_dq         <= 32'h0; 
end else begin                                          
    i_we_n       <= o_we_n_0;      
    i_cle        <= o_cle_0;       
    i_ale        <= o_ale_0;       
    i_wp_n       <= o_wp_n_0;      
    i_re         <= o_re_0;        
    i_dqs_tri_en <= o_dqs_tri_en_0;
    i_dqs        <= o_dqs_0;       
    i_dq_tri_en  <= o_dq_tri_en_0; 
    i_dq         <= o_dq_0;
end


fcc_phy #(
    .WAY_NUM             (WAY_NUM          ),
    .PATCH               (PATCH            )
) fcc_phy(
    .clk                 (clk_fast         ),
    .clk_div             (clk_div          ),
    .clk_reset           (clk_reset        ),
    .usr_rst             (usr_rst          ),
    .usr_clk             (usr_clk          ),
    .ref_clk             (ref_clk          ),
    .i_ce_n              (i_ce_n           ),
    .o_rb_n              (o_rb_n           ),
    .i_we_n              (i_we_n           ),
    .i_cle               (i_cle            ),
    .i_ale               (i_ale            ),
    .i_wp_n              (i_wp_n           ),
    .i_re                (i_re             ),
    .i_dqs_tri_en        (i_dqs_tri_en     ),
    .i_dqs               (i_dqs            ),
    .o_dqs               (o_dqs            ),
    .i_dq_tri_en         (i_dq_tri_en      ),
    .i_dq                (i_dq             ),
    .o_dq                (o_dq             ),

    .O_NAND_CE_N         (O_NAND_CE_N      ),
    .I_NAND_RB_N         (I_NAND_RB_N      ),
    .O_NAND_WE_N         (O_NAND_WE_N      ),
    .O_NAND_CLE          (O_NAND_CLE       ),
    .O_NAND_ALE          (O_NAND_ALE       ),
    .O_NAND_WP_N         (O_NAND_WP_N      ),
    .O_NAND_RE_P         (O_NAND_RE_P      ),
    .O_NAND_RE_N         (O_NAND_RE_N      ),
    .IO_NAND_DQS_P       (IO_NAND_DQS_P    ),
    .IO_NAND_DQS_N       (IO_NAND_DQS_N    ),
    .IO_NAND_DQ          (IO_NAND_DQ       )
);




endmodule
