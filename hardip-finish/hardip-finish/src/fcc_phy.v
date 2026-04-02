`timescale 1ns / 1ps
/*
2025.11.14 SCMI ZGX 
将dataout的dqs边缘改成对齐dq的中间

*/


module fcc_phy#(
    parameter WAY_NUM  = 1,        // number of ways (NAND_CE & NAND_RB)
    parameter PATCH    = "FALSE"   // patch due to unproper FMC pinmap for DQS2/3
)(
    input                       clk,    // 400M
    input                       clk_div,   // 100M
    input                       clk_reset,
//    input                       clk_locked,
    input                       usr_rst,
    input                       usr_clk,   // 50M, phase aligned with clk
    input                       ref_clk,   // reference clock for IDELAYCTRL 200M
//    output                      rst_seq_done,
  input     [WAY_NUM - 1 : 0] i_ce_n,
  output    [WAY_NUM - 1 : 0] o_rb_n,
  input                       i_we_n,
  input                       i_cle,
  input                       i_ale,
  input                       i_wp_n,
    input              [ 3 : 0] i_re,
    input                       i_dqs_tri_en, // 1 - input, 0 - output
    input              [ 3 : 0] i_dqs, // toggle signal:0101..., 2bits (01) dqs - 8bits dq
    output             [ 3 : 0] o_dqs,
    input                       i_dq_tri_en, // 1 - input, 0 - output
    input              [31 : 0] i_dq,
    output             [31 : 0] o_dq,

    // 333.3M
    output    [WAY_NUM - 1 : 0] O_NAND_CE_N,
    input     [WAY_NUM - 1 : 0] I_NAND_RB_N,
    output                      O_NAND_WE_N,
    output                      O_NAND_CLE, 
    output                      O_NAND_ALE, 
    output                      O_NAND_WP_N,
    output                      O_NAND_RE_P,  
    output                      O_NAND_RE_N, 
    inout                       IO_NAND_DQS_P, 
    inout                       IO_NAND_DQS_N,
    inout              [ 7 : 0] IO_NAND_DQ  
);


// All the I/O pins except RB_N use DDR 8:1 mode
// For fabric of ce_n, we_n, ale, cle, wp_n,
//    data from fabric are copied 8 times to reduce data width
// For fabric of re, dqs, dq,
//    data from fabric are copied 2 times to reduce data width

// DQS & DQ receiving
// find valid DQS period
// 4X sample per cycle
// match pattern 7'b00xx111 to improve robustness


localparam
    DATA_WIDTH      = 8,
    IDELAY_VALUE    = 0,
    REFCLK_FREQ     = 200, // 400, //
    DLY_NUM         = 1;  

genvar i;    
//wire        rst_seq_done_dqs;
//wire [ 7:0] rst_seq_done_dq;    
 (* MARK_DEBUG="true" *)    wire     [7:0] dq_bus;
  (* MARK_DEBUG="true" *)   wire     out_sync_o_rb_n;
  (* MARK_DEBUG="true" *)   wire     dqs;









wire [ 7:0] i_re_tmp;
wire [ 7:0] i_dqs_tmp;
 wire [ 7:0] o_dqs_tmp;
reg         o_dqs_tmp_valid;
//reg         o_dqs_tmp_valid_dly;
wire [ 7:0] i_dq_tmp [7:0];  
wire [ 7:0] o_dq_tmp [7:0]; 
//wire [ 7:0] o_dq_tmp_valid;
wire [ 7:0] o_dqs_w;
wire [63:0] o_dq_w;

 reg  [  7:0] o_dqs_r;
reg  [ 63:0] o_dq_r;
 wire [ 15:0] o_dqs_two;
 wire [127:0] o_dq_two;
reg  [ 15:0] r_dqs_two;
reg  [127:0] r_dq_two;

reg         match;
 reg  [ 2:0] dqs_rs; // right shift
 reg  [ 5:0] dq_rs; 
reg  [ 1:0] o_dqs_2b;
reg  [63:0] o_dq_64b;


wire    [WAY_NUM - 1 : 0] sync_i_ce_n;
wire    [WAY_NUM - 1 : 0] sync_o_rb_n;
wire                      sync_i_we_n;
wire                      sync_i_cle;
wire                      sync_i_ale;
wire                      sync_i_wp_n;
 wire             [ 1 : 0] sync_i_re;
wire                      sync_i_dqs_tri_en; // 1 - input; 0 - output
wire             [ 1 : 0] sync_i_dqs; // toggle signal:0101...; 2bits (01) dqs - 8bits dq
reg              [ 1 : 0] sync_o_dqs;
wire                      sync_i_dq_tri_en; // 1 - input; 0 - output
wire             [15 : 0] sync_i_dq;
reg              [15 : 0] sync_o_dq;

reg state;


wire tri_t_dq;
wire tri_t_dqs;

reg  [DLY_NUM-1 : 0] dqs_tri_dly;

// ####################################################################################
//
// PHY Interface data width convert and cross-clock-domain convert
//
// ####################################################################################
phy_dwidth_convert#(
    .WAY_NUM (WAY_NUM)
) phy_dwidth_convert(    
    .clk_a          (usr_clk          ),         
    .rst_a          (usr_rst          ),         
    .clk_b          (clk_div          ),                         
    .i_ce_n_a       (i_ce_n           ),         
    .o_rb_n_a       (o_rb_n           ),         
    .i_we_n_a       (i_we_n           ),         
    .i_cle_a        (i_cle            ),         
    .i_ale_a        (i_ale            ),         
    .i_wp_n_a       (i_wp_n           ),         
    .i_re_a         (i_re             ),         
    .i_dqs_tri_en_a (i_dqs_tri_en     ),         
    .i_dqs_a        (i_dqs            ),         
    .o_dqs_a        (o_dqs            ),         
    .i_dq_tri_en_a  (i_dq_tri_en      ),         
    .i_dq_a         (i_dq             ),         
    .o_dq_a         (o_dq             ),         
    .i_ce_n_b       (sync_i_ce_n      ),         
    .o_rb_n_b       (sync_o_rb_n      ),         
    .i_we_n_b       (sync_i_we_n      ),         
    .i_cle_b        (sync_i_cle       ),         
    .i_ale_b        (sync_i_ale       ),         
    .i_wp_n_b       (sync_i_wp_n      ),         
    .i_re_b         (sync_i_re        ),         
    .i_dqs_tri_en_b (sync_i_dqs_tri_en),         
    .i_dqs_b        (sync_i_dqs       ),         
    .o_dqs_b        (sync_o_dqs       ),         
    .i_dq_tri_en_b  (sync_i_dq_tri_en ),         
    .i_dq_b         (sync_i_dq        ),         
    .o_dq_b         (sync_o_dq        )         
);


// ####################################################################################
//
// PHY Interface to User logic
//
// ####################################################################################

sync_cell #(.C_SYNC_STAGE(7), .C_DW(2), .pTCQ(0)) 
    sync_cell_tri_t(.src_data({sync_i_dq_tri_en, sync_i_dqs_tri_en}), .dest_clk(clk), .dest_data({tri_t_dq, tri_t_dqs}));
    

generate for( i = 0; i < DLY_NUM; i = i + 1) begin : tri_dly
  if(i == 0) begin
      always@(posedge clk_div) begin
          dqs_tri_dly[i] <= sync_i_dqs_tri_en;
//          dq_tri_dly[i]  <= i_dq_tri_en;
      end 
  end else begin
      always@(posedge clk_div) begin
          dqs_tri_dly[i] <= dqs_tri_dly[i-1];
//          dq_tri_dly[i]  <= dq_tri_dly[i-1];
      end
  end
end 
endgenerate

//assign o_dqs_tmp_valid = dqs_tri_dly[DLY_NUM-1];


always @(posedge clk_div or posedge usr_rst)
if (usr_rst) begin
    o_dqs_tmp_valid <= 1'b0;
end else begin
    o_dqs_tmp_valid <= dqs_tri_dly[DLY_NUM-1] & sync_i_dqs_tri_en;
end



generate for( i = 0; i < WAY_NUM; i = i + 1) begin : target
    // RB_N & CE_N
    IBUF Inst_RBIBUF(
        .I(I_NAND_RB_N[i]),
        .O(sync_o_rb_n[i])
    ); 
    assign out_sync_o_rb_n = sync_o_rb_n[0];
    
    phy_out #(
        .SIG_TYPE_DIFF  ("FALSE"        ),
        .DATA_WIDTH     (DATA_WIDTH     ),
        .INIT_VALUE     (1'b1           ),
        .OSERDES_CLK_INV(1'b0           )
    ) phy_out_ce_n(
        .clk_in                 (clk                    ),
        .clk_div_in             (clk_div                ),
        .reset                  (clk_reset              ),
        .data_from_fabric       ({8{sync_i_ce_n[i]}}    ),
        .data_to_pins_p         (O_NAND_CE_N[i]         ),
        .data_to_pins_n         (                       )
            ); 
end
endgenerate


phy_out #(
    .SIG_TYPE_DIFF  ("FALSE"        ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .INIT_VALUE     (1'b0           ),
    .OSERDES_CLK_INV(1'b0           )
) phy_out_cle(
    .clk_in                 (clk                    ),
    .clk_div_in             (clk_div                ),
    .reset                  (clk_reset              ),
    .data_from_fabric       ({8{sync_i_cle}}        ),
    .data_to_pins_p         (O_NAND_CLE             ),
    .data_to_pins_n         (                       )

); 

phy_out #(
    .SIG_TYPE_DIFF  ("FALSE"        ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .INIT_VALUE     (1'b0           ),
    .OSERDES_CLK_INV(1'b0           )
) phy_out_ale(
    .clk_in                 (clk                    ),
    .clk_div_in             (clk_div                ),
    .reset                  (clk_reset              ),
    .data_from_fabric       ({8{sync_i_ale}}        ),
    .data_to_pins_p         (O_NAND_ALE             ),
    .data_to_pins_n         (                       )

);  


phy_out #(
    .SIG_TYPE_DIFF  ("FALSE"        ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .INIT_VALUE     (1'b1           ),
    .OSERDES_CLK_INV(1'b0           )
) phy_out_we_n(
    .clk_in                 (clk                    ),
    .clk_div_in             (clk_div                ),
    .reset                  (clk_reset              ),
    .data_from_fabric       ({8{sync_i_we_n}}       ),
    .data_to_pins_p         (O_NAND_WE_N            ),
    .data_to_pins_n         (                       )

);  

phy_out #(
    .SIG_TYPE_DIFF  ("FALSE"        ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .INIT_VALUE     (1'b1           ),
    .OSERDES_CLK_INV(1'b0           )
) phy_out_wp_n(
    .clk_in                 (clk                    ),
    .clk_div_in             (clk_div                ),
    .reset                  (clk_reset              ),
    .data_from_fabric       ({8{sync_i_wp_n}}       ),
    .data_to_pins_p         (O_NAND_WP_N            ),
    .data_to_pins_n         (                       )

);  


assign i_re_tmp = {{4{sync_i_re[1]}}, {4{sync_i_re[0]}}};  

phy_out #(
    .SIG_TYPE_DIFF  ("TRUE"         ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .INIT_VALUE     (1'b1           ),
    .OSERDES_CLK_INV(1'b0           )
) phy_out_re(
    .clk_in                 (clk                    ),
    .clk_div_in             (clk_div                ),
    .reset                  (clk_reset              ),
    .data_from_fabric       (i_re_tmp               ),
    .data_to_pins_p         (O_NAND_RE_P            ),
    .data_to_pins_n         (O_NAND_RE_N            )
);   

// 01 -> 00111100
assign i_dqs_tmp = {{2{sync_i_dqs[1]}}, {4{sync_i_dqs[0]}}, {2{sync_i_dqs[1]}}};    
//assign o_dqs_w = {o_dqs_tmp[6], o_dqs_tmp[4], o_dqs_tmp[2], o_dqs_tmp[0]};

generate 
if(PATCH == "TRUE") begin: patch_true
wire [ 7:0] o_dqs_tmp_patch;
assign o_dqs_tmp = ~o_dqs_tmp_patch;
phy_inout #(
    .SIG_TYPE_DIFF  ("TRUE"         ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .INIT_VALUE     (1'b1           ),
    .IDELAY_VALUE   (IDELAY_VALUE   ),
    .OSERDES_CLK_INV(1'b0           ),
    .REFCLK_FREQ    (REFCLK_FREQ    ) // IDELAYCTRL clock input frequency in MHz (200.0-2667.0)
) phy_inout_dqs(
    .clk_in                 (clk                    ),
    .clk_div_in             (clk_div                ),
    .reset                  (clk_reset              ),
    .ref_clk                (ref_clk                ),
//    .rst_seq_done           (rst_seq_done_dqs       ),
    .tri_t                  (tri_t_dqs              ),
    .data_from_fabric       (~i_dqs_tmp             ),
    .data_to_fabric         (o_dqs_tmp_patch        ),
//    .data_to_fabric_valid   (o_dqs_tmp_valid        ),
    .data_to_and_from_pins_p(IO_NAND_DQS_N          ),
    .data_to_and_from_pins_n(IO_NAND_DQS_P          )
);

end else begin: patch_false
phy_inout #(
    .SIG_TYPE_DIFF  ("TRUE"         ),
    .DATA_WIDTH     (DATA_WIDTH     ),
    .INIT_VALUE     (1'b1           ),
    .IDELAY_VALUE   (16   ),
    .OSERDES_CLK_INV(1'b1           ),
    .REFCLK_FREQ    (REFCLK_FREQ    ) // IDELAYCTRL clock input frequency in MHz (200.0-2667.0)
) phy_inout_dqs(
    .clk_in                 (clk                    ),
    .clk_div_in             (clk_div                ),
    .reset                  (clk_reset              ),
    .ref_clk                (ref_clk                ),
//    .rst_seq_done           (rst_seq_done_dqs       ),
    .tri_t                  (tri_t_dqs              ),
    .data_from_fabric       (i_dqs_tmp              ),
    .data_to_fabric         (o_dqs_tmp              ),
//    .data_to_fabric_valid   (o_dqs_tmp_valid        ),
    .data_to_and_from_pins_p(IO_NAND_DQS_P          ),
    .data_to_and_from_pins_n(IO_NAND_DQS_N          ),
    .dq_read_internal(dqs)
);

end 
endgenerate



generate for( i = 0; i < 8; i = i + 1) begin: dq_inout
    assign i_dq_tmp[i]  = {{4{sync_i_dq[8+i]}}, {4{sync_i_dq[i]}}}; // 4:1
    assign o_dq_w[i]    = o_dq_tmp[i][0];
    assign o_dq_w[8+i]  = o_dq_tmp[i][1];
    assign o_dq_w[16+i] = o_dq_tmp[i][2];
    assign o_dq_w[24+i] = o_dq_tmp[i][3];
    assign o_dq_w[32+i] = o_dq_tmp[i][4];
    assign o_dq_w[40+i] = o_dq_tmp[i][5];
    assign o_dq_w[48+i] = o_dq_tmp[i][6];
    assign o_dq_w[56+i] = o_dq_tmp[i][7];
    
    phy_inout #(
        .SIG_TYPE_DIFF  ("FALSE"        ),
        .DATA_WIDTH     (DATA_WIDTH     ),
        .INIT_VALUE     (1'b0           ),
        .IDELAY_VALUE   (IDELAY_VALUE   ),
        .OSERDES_CLK_INV(1'b0           ),
        .REFCLK_FREQ    (REFCLK_FREQ    ) // IDELAYCTRL clock input frequency in MHz (200.0-2667.0)
    ) phy_inout_dq(
        .clk_in                 (clk                    ),
        .clk_div_in             (clk_div                ),
        .reset                  (clk_reset              ),
        .ref_clk                (ref_clk                ),
//        .rst_seq_done           (rst_seq_done_dq[i]     ),
        .tri_t                  (tri_t_dq               ),
        .data_from_fabric       (i_dq_tmp[i]            ),
        .data_to_fabric         (o_dq_tmp[i]            ),
//        .data_to_fabric_valid   (o_dq_tmp_valid[i]      ),
        .data_to_and_from_pins_p(IO_NAND_DQ[i]          ),
        .data_to_and_from_pins_n(                       ),
        .dq_read_internal(dq_bus[i])
    );
end
endgenerate


// Bitslip for the parallel output of ISERDES for DQS and DQ
//     match pattern: DQS[7:0] == 8'hf
always @(posedge clk_div or posedge usr_rst)
if (usr_rst) begin
    o_dqs_r <= 8'h0;
    o_dq_r  <= 64'h0;
end else begin
    o_dqs_r <= o_dqs_tmp;
    o_dq_r  <= o_dq_w;
end

assign o_dqs_two = {o_dqs_tmp, o_dqs_r};
assign o_dq_two  = {o_dq_w,o_dq_r};

always @(posedge clk_div or posedge usr_rst)
if (usr_rst) begin
    r_dqs_two <= 16'h0;
    r_dq_two  <= 128'h0;
end else begin
    r_dqs_two <= o_dqs_two;
    r_dq_two  <= o_dq_two;
end


// find valid DQS period
// 8X sample per cycle
// match pattern 7'b00xx111 to improve robustness
always @(posedge clk_div or posedge usr_rst)
if (usr_rst) begin
    match  <= 1'b0;
    dqs_rs <= 3'd0;
    dq_rs  <= 6'd0;
end else if(o_dqs_tmp_valid & (~match)) begin // find 7'b00xx111
    if((o_dqs_two[6:0] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end else if((o_dqs_two[7:1] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end else if((o_dqs_two[8:2] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end else if((o_dqs_two[9:3] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end else if((o_dqs_two[10:4] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end else if((o_dqs_two[11:5] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end else if((o_dqs_two[12:6] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end else if((o_dqs_two[13:7] & 7'b1100111) == 7'h7) begin
        match  <= 1'b1;
    end
    dqs_rs <= 3'h6;
    dq_rs  <= 6'h30;
end else if(~o_dqs_tmp_valid) begin
    match <= 1'b0;
end
//assign o_dqs = (r_dqs_two >> dqs_rs) & 4'hff;
//assign o_dq  = (r_dq_two >> dq_rs) & 32'hffff_ffff;

always @(posedge clk_div or posedge usr_rst)
if (usr_rst) begin
    o_dqs_2b <= 2'h0;
    o_dq_64b <= 64'h0;
//end else if(match & ((r_dqs_two >> dqs_rs) & 8'hff) == 8'hf) begin
end else if(match & (((r_dqs_two >> dqs_rs) & 8'hff) != 8'h0) & (((r_dqs_two >> dqs_rs) & 8'hff) != 8'hff)) begin
    o_dqs_2b <= 2'h1;      
    o_dq_64b <= (r_dq_two >> dq_rs);
end else begin
    o_dqs_2b <= 2'h0;
    o_dq_64b <= 64'h0;
end 


always @(posedge clk_div or posedge usr_rst)
if (usr_rst) begin
    sync_o_dqs <= 2'h0;
    sync_o_dq  <= 16'h0;
end else begin
    sync_o_dqs <= o_dqs_2b;
    sync_o_dq  <= {o_dq_64b[47:40], o_dq_64b[15:8]};
end 

    
    
endmodule
