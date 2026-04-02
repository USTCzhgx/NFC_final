`timescale 1ns / 1ps

module phy_sdr_fifo_tb;

// === Parameters ===
parameter WAY_NUM = 2;

// === Clock and Reset ===
reg clk_a = 0;
reg clk_b = 0;
reg rst_a = 1;

// === a domain (high freq) inputs ===
reg  [WAY_NUM-1:0] i_ce_n_a;
wire [WAY_NUM-1:0] o_rb_n_a;
reg               i_we_n_a;
reg               i_cle_a;
reg               i_ale_a;
reg               i_wp_n_a;
reg               i_re_n_a;
reg               i_dqs_tri_en_a;
reg               i_dq_tri_en_a;
reg  [15:0]        i_dq_a;
wire [15:0]        o_dq_a;

// === b domain (low freq) outputs ===
wire [WAY_NUM-1:0] i_ce_n_b;
reg  [WAY_NUM-1:0] o_rb_n_b;
wire              i_we_n_b;
wire              i_cle_b;
wire              i_ale_b;
wire              i_wp_n_b;
wire              i_re_n_b;
wire              i_dqs_tri_en_b;
wire              i_dq_tri_en_b;
wire [15:0]        i_dq_b;
reg  [15:0]        o_dq_b;

// === Clocks ===
always #5  clk_a = ~clk_a;  // 100MHz
always #10 clk_b = ~clk_b;  // 50MHz

// === DUT ===
phy_sdr_fifo #(
    .WAY_NUM(WAY_NUM)
) dut (
    .clk_a(clk_a),
    .rst_a(rst_a),
    .clk_b(clk_b),
    .i_ce_n_a(i_ce_n_a),
    .o_rb_n_a(o_rb_n_a),
    .i_we_n_a(i_we_n_a),
    .i_cle_a(i_cle_a),
    .i_ale_a(i_ale_a),
    .i_wp_n_a(i_wp_n_a),
    .i_re_n_a(i_re_n_a),
    .i_dqs_tri_en_a(i_dqs_tri_en_a),
    .i_dq_tri_en_a(i_dq_tri_en_a),
    .i_dq_a(i_dq_a),
    .o_dq_a(o_dq_a),
    .i_ce_n_b(i_ce_n_b),
    .o_rb_n_b(o_rb_n_b),
    .i_we_n_b(i_we_n_b),
    .i_cle_b(i_cle_b),
    .i_ale_b(i_ale_b),
    .i_wp_n_b(i_wp_n_b),
    .i_re_n_b(i_re_n_b),
    .i_dqs_tri_en_b(i_dqs_tri_en_b),
    .i_dq_tri_en_b(i_dq_tri_en_b),
    .i_dq_b(i_dq_b),
    .o_dq_b(o_dq_b)
);

// === Test ===
initial begin
    // Initialize inputs
    i_ce_n_a         = 2'b11;
    i_we_n_a         = 1;
    i_cle_a          = 0;
    i_ale_a          = 0;
    i_wp_n_a         = 1;
    i_re_n_a         = 1;
    i_dqs_tri_en_a   = 0;
    i_dq_tri_en_a    = 0;
    i_dq_a           = 16'h0000;

    o_rb_n_b         = 2'b00;  // Ready
    o_dq_b           = 16'hBEEF;

    // Wait for clocks to stabilize
    #50;
    rst_a = 0;

    // === Write data from clk_a domain ===
    repeat (4) begin
        @(posedge clk_a);
        i_ce_n_a       = 2'b01;
        i_we_n_a       = 0;
        i_cle_a        = $random;
        i_ale_a        = $random;
        i_wp_n_a       = 1;
        i_re_n_a       = $random;
        i_dqs_tri_en_a = 1;
        i_dq_tri_en_a  = 1;
        i_dq_a         = $random;
    end

    // Return to idle
    @(posedge clk_a);
    i_we_n_a = 1;
    i_ce_n_a = 2'b11;

    // === Simulate B-domain generating data for A-domain ===
    repeat (4) begin
        @(posedge clk_b);
        o_dq_b   = $random;
        o_rb_n_b = 2'b00;
    end

    // Let A-domain read it
    #200;

    // Finish simulation
    $display("Test completed.");
    $finish;
end

endmodule
