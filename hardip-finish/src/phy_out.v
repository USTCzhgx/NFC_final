`timescale 1ns / 1ps

module phy_out #(
    parameter SIG_TYPE_DIFF   = "FALSE",
    parameter DATA_WIDTH      = 8,
    parameter INIT_VALUE      = 0,
    parameter OSERDES_CLK_INV = 0
)(
    input                       clk_in,
    input                       clk_div_in,
    input                       reset,
    input  [DATA_WIDTH - 1 : 0] data_from_fabric,
    inout                       data_to_pins_p,
    inout                       data_to_pins_n
    
);

wire iob_din;  // ∑¿÷π Vivado ”≈ªØµÙ



generate
if(SIG_TYPE_DIFF == "TRUE") begin: o_pin_diff
    OBUFDS OBUFDS_inst (
       .O (data_to_pins_p),
       .OB(data_to_pins_n),
       .I (iob_din)
    );
end else begin: o_pin_se
    OBUF OBUF_inst (
       .O(data_to_pins_p),
       .I(iob_din)
    );
end
endgenerate

OSERDESE2 #(
    .DATA_RATE_OQ("DDR"),
    .DATA_RATE_TQ("SDR"),
    .DATA_WIDTH(DATA_WIDTH),
    .INIT_OQ(1'b0),
    .INIT_TQ(1'b0),
    .SERDES_MODE("MASTER"),
    .SRVAL_OQ(1'b0),
    .SRVAL_TQ(1'b0),
    .TRISTATE_WIDTH(1)
) OSERDESE2_inst (
    .OQ(iob_din),
    .TQ(),
    .CLK(clk_in),
    .CLKDIV(clk_div_in),
    .D1(data_from_fabric[0]),
    .D2(data_from_fabric[1]),
    .D3(data_from_fabric[2]),
    .D4(data_from_fabric[3]),
    .D5(data_from_fabric[4]),
    .D6(data_from_fabric[5]),
    .D7(data_from_fabric[6]),
    .D8(data_from_fabric[7]),
    .T1(1'b0),
    .RST(reset),
    .OCE(1'b1),
    .TCE(1'b0)
);

endmodule
