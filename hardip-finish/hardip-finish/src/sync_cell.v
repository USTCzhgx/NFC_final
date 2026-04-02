`timescale 1ns / 1ps


module sync_cell
#(
    parameter   C_SYNC_STAGE        = 2,
    parameter   C_DW                = 4,
    parameter   pTCQ                = 100
)
(
  input  wire  [C_DW-1:0]                 src_data,

  input  wire                             dest_clk,
  output wire  [C_DW-1:0]                 dest_data
);

(* async_reg = "true" *) reg [C_DW-1:0] sync_flop[C_SYNC_STAGE-1:0];

genvar i;
generate for(i = 0; i < C_SYNC_STAGE; i = i + 1) begin: sync
    if(i == 0) begin
        always @ ( posedge dest_clk )
        begin
            sync_flop[0] <= #pTCQ src_data;
        end
    end else begin
        always @ ( posedge dest_clk )
        begin
            sync_flop[i] <= #pTCQ sync_flop[i-1];
        end
    end
end
endgenerate


assign dest_data = sync_flop[C_SYNC_STAGE-1];


endmodule

