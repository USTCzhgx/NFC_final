`timescale 1ns/1ps

module bram_portb_driver (
    input  wire        clkb,
    input  wire        rstbn,

    input  wire        rd_req,
    input  wire [31:0] rd_addr,
    output reg  [31:0] rd_data,
    output reg         rd_valid,

    input  wire        wr_req,
    input  wire [31:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_be,

    output wire [31:0] addrb,
    output wire        enb,
    output wire [31:0] dinb,
    input  wire [31:0] doutb,
    output wire [3:0]  web
);

    // Write priority mux (combinational)
    assign enb   = wr_req | rd_req;
    assign web   = wr_req ? wr_be : 4'b0000;
    assign addrb = wr_req ? wr_addr : rd_addr;
    assign dinb  = wr_data;

    // Read valid align (BRAM read latency = 2)
    reg  rd_fire_d1;
    reg  rd_fire_d2;
    wire rd_fire = rd_req & ~wr_req; // read is issued only if not overridden by write

    always @(posedge clkb) begin
        if (~rstbn) begin
            rd_fire_d1 <= 1'b0;
            rd_fire_d2 <= 1'b0;
            rd_valid   <= 1'b0;
            rd_data    <= 32'd0;
        end else begin
            // pipeline the issued-read flag by 2 cycles
            rd_fire_d1 <= rd_fire;
            rd_fire_d2 <= rd_fire_d1;

            // valid when the request reaches stage 2
            rd_valid <= rd_fire_d2;

            // sample doutb at N+2
            if (rd_fire_d2) begin
                rd_data <= doutb;
            end
        end
    end

endmodule