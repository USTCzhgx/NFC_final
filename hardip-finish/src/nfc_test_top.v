`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// File Name: nfc_test_top.v
// Description: NFC test top module (direct regfile -> merge_engine connection)
// Date: 2025.12.7
// Author: SCMI ZGX
//
// Change summary:
// - Remove CDC toggle sync and header sampling logic.
// - Directly connect regfile MergePlan outputs to merge_engine inputs.
// - Directly feed merge_busy/merge_done back to regfile (assume same clock domain).
// - Fix gen_valid/gen_ready to scalar (CHAN_NUM=1 use-case).
////////////////////////////////////////////////////////////////////////////////

module nfc_test_top #(
    parameter CHAN_NUM   = 1,
    parameter WAY_NUM    = 1,
    parameter DATA_WIDTH = 32
)(
    // Clock & Reset Inputs
    input                         sys_clk,
    input                         sys_rst_n,
    input                         s_axil_aclk,
    input                         s_axil_aresetn,

    // AXI LITE Slave Interface
    input  [5:0]                  axil_awaddr,
    input  [2:0]                  axil_awprot,
    input                         axil_awvalid,
    output                        axil_awready,

    input  [31:0]                 axil_wdata,
    input  [3:0]                  axil_wstrb,
    input                         axil_wvalid,
    output                        axil_wready,

    output [1:0]                  axil_bresp,
    output                        axil_bvalid,
    input                         axil_bready,

    input  [5:0]                  axil_araddr,
    input  [2:0]                  axil_arprot,
    input                         axil_arvalid,
    output                        axil_arready,

    output [31:0]                 axil_rdata,
    output [1:0]                  axil_rresp,
    output                        axil_rvalid,
    input                         axil_rready,

    // AXI Stream interface
    input  wire                        s_axis_tvalid,
    output wire                        s_axis_tready,
    input  wire [DATA_WIDTH-1:0]       s_axis_tdata,
    input  wire [DATA_WIDTH/8-1:0]     s_axis_tkeep,
    input  wire                        s_axis_tlast,

    output wire                        m_axis_tvalid,
    input  wire                        m_axis_tready,
    output wire [DATA_WIDTH-1:0]       m_axis_tdata,
    output wire [DATA_WIDTH/8-1:0]     m_axis_tkeep,
    output wire [15:0]                 m_axis_tid,
    output wire [3:0]                  m_axis_tuser,
    output wire                        m_axis_tlast,

    // BRAM Port B physical interfaces
    output wire [31:0] addrb,
    output wire        enb,
    output wire [31:0] dinb,
    input  wire [31:0] doutb,
    output wire [3:0]  web,

    // NAND Flash Physical Interfaces
    output [CHAN_NUM*WAY_NUM-1:0]      O_NAND_CE_N,
    input  [CHAN_NUM*WAY_NUM-1:0]      I_NAND_RB_N,
    output [CHAN_NUM-1:0]              O_NAND_WE_N,
    output [CHAN_NUM-1:0]              O_NAND_CLE,
    output [CHAN_NUM-1:0]              O_NAND_ALE,
    output [CHAN_NUM-1:0]              O_NAND_WP_N,
    output [CHAN_NUM-1:0]              O_NAND_RE_P,
    output [CHAN_NUM-1:0]              O_NAND_RE_N,
    inout  [CHAN_NUM-1:0]              IO_NAND_DQS_P,
    inout  [CHAN_NUM-1:0]              IO_NAND_DQS_N,
    inout  [CHAN_NUM*8-1:0]            IO_NAND_DQ
);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // NFC control signals and parameters (scalar for CHAN_NUM=1)
    wire                   gen_ready;
    wire                   gen_valid;
    wire [15:0]            gen_opc;
    wire [47:0]            gen_lba;
    wire [23:0]            gen_len;

    wire  [7:0]            o_sr_0;
    wire  [1:0]            o_status_0;
    wire                   req_fifo_almost_full;

    // Clock and reset signals
    wire                   user_clk;
    wire                   nand_clk_fast;
    wire                   nand_clk_slow;
    wire                   nand_clk_rst;
    wire                   nand_usr_rstn;
    wire                   refclk;

    // MergePlan header/control from regfile (AXI domain)
    wire [31:0] plan_lbn_axil;
    wire [15:0] plan_new_pbn_axil;
    wire [15:0] plan_old_pbn_axil;
    wire [31:0] plan_entry_count_axil;
    wire [31:0] plan_base_word_axil;
    wire        merge_start_pulse_axil;

    // Merge status (direct, assume same clock domain)
    wire        merge_busy_user;
    wire        merge_done_user;
    wire        merge_busy_axil;
    wire        merge_done_axil;

    // Merge -> NFC command channel
    wire        mg_cmd_valid;
    wire [15:0] mg_cmd_opc;
    wire [47:0] mg_cmd_lba;
    wire [23:0] mg_cmd_len;
    wire        mg_cmd_ready;

    wire        mg_busy;
    wire        mg_rd_capture_en;
    wire        mg_wr_feed_en;
    wire        mg_page_fill_done;
    wire        mg_page_drain_done;
(* MARK_DEBUG="true" *)    wire        mg_rd_capture_ready;
    wire        mg_wr_tvalid;
    wire [DATA_WIDTH-1:0] mg_wr_tdata;
    wire        mg_wr_tlast;
    wire [23:0] mg_fifo_data_avail;
    wire        mg_fifo_empty;

    wire                        nfc_axis_wvalid;
    wire                        nfc_axis_wready;
    wire [DATA_WIDTH-1:0]       nfc_axis_wdata;
    wire [DATA_WIDTH/8-1:0]     nfc_axis_wkeep;
    wire                        nfc_axis_wlast;

    wire                        nfc_axis_rvalid;
(* MARK_DEBUG="true" *)    wire                        nfc_axis_rready;
    wire [DATA_WIDTH-1:0]       nfc_axis_rdata;
    wire [DATA_WIDTH/8-1:0]     nfc_axis_rkeep;
    wire [15:0]                 nfc_axis_rid;
    wire [3:0]                  nfc_axis_ruser;
    wire                        nfc_axis_rlast;

    // NFC cmd mux output
    wire        nfc_cmd_valid;
    wire [15:0] nfc_cmd_opc;
    wire [47:0] nfc_cmd_lba;
    wire [23:0] nfc_cmd_len;
    wire        nfc_cmd_ready;

    // Command done from NFC channel test
    wire        o_cmd_done;

    // =========================================================================
    // Clock Management Module
    // =========================================================================
    nand_mmcm nand_mmcm (
        .clk_in       (sys_clk),
        .reset        (~sys_rst_n),
        .clk_out_fast (nand_clk_fast),
        .clk_out_slow (nand_clk_slow),
        .clk_reset    (nand_clk_rst),
        .usr_resetn   (nand_usr_rstn),
        .clk_out_usr  (user_clk),
        .refclk       (refclk)
    );

    // =========================================================================
    // AXI Lite Slave Register File
    // =========================================================================
    regfile u_regfile (
        .S_AXI_ACLK      (s_axil_aclk),
        .S_AXI_ARESETN   (s_axil_aresetn),

        .S_AXI_AWADDR    (axil_awaddr),
        .S_AXI_AWVALID   (axil_awvalid),
        .S_AXI_AWREADY   (axil_awready),

        .S_AXI_WDATA     (axil_wdata),
        .S_AXI_WSTRB     (axil_wstrb),
        .S_AXI_WVALID    (axil_wvalid),
        .S_AXI_WREADY    (axil_wready),

        .S_AXI_BRESP     (axil_bresp),
        .S_AXI_BVALID    (axil_bvalid),
        .S_AXI_BREADY    (axil_bready),

        .S_AXI_ARADDR    (axil_araddr),
        .S_AXI_ARVALID   (axil_arvalid),
        .S_AXI_ARREADY   (axil_arready),

        .S_AXI_RDATA     (axil_rdata),
        .S_AXI_RRESP     (axil_rresp),
        .S_AXI_RVALID    (axil_rvalid),
        .S_AXI_RREADY    (axil_rready),

        // NFC basic command regs
        .nfc_opcode      (gen_opc),
        .nfc_lba         (gen_lba),
        .nfc_len         (gen_len),
        .nfc_ready       (gen_ready),
        .nfc_valid       (gen_valid),

        .req_fifo_almost_full (req_fifo_almost_full),
        .o_sr_0               (o_sr_0),
        .o_status_0           (o_status_0),

        // MergePlan header/control outputs
        .plan_lbn             (plan_lbn_axil),
        .plan_new_pbn         (plan_new_pbn_axil),
        .plan_old_pbn         (plan_old_pbn_axil),
        .plan_entry_count     (plan_entry_count_axil),
        .plan_base_word       (plan_base_word_axil),
        .merge_start_pulse    (merge_start_pulse_axil),

        // Merge status inputs (assume same clock domain; no CDC)
        .merge_busy_axil      (merge_busy_axil),
        .merge_done_axil      (merge_done_axil)
    );

    // =========================================================================
    // Direct regfile -> merge_engine connection (no CDC)
    // IMPORTANT: This assumes s_axil_aclk and user_clk are effectively the same
    // (same domain). If not, you must restore CDC logic.
    // =========================================================================
    assign merge_busy_axil = merge_busy_user;
    assign merge_done_axil = merge_done_user;

    merge_engine u_merge (
        .clk        (user_clk),
        .rstn       (nand_usr_rstn),

        .start          (merge_start_pulse_axil),
        .plan_lbn       (plan_lbn_axil),
        .new_pbn        (plan_new_pbn_axil),
        .old_pbn        (plan_old_pbn_axil),
        .entry_count    (plan_entry_count_axil),
        .plan_base_word (plan_base_word_axil),

        .busy           (merge_busy_user),
        .done_pulse     (merge_done_user),

        .o_status       (o_status_0),
        .o_cmd_done     (o_cmd_done),

        .addrb      (addrb),
        .enb        (enb),
        .dinb       (dinb),
        .doutb      (doutb),
        .web        (web),

        .cmd_valid  (mg_cmd_valid),
        .cmd_opc    (mg_cmd_opc),
        .cmd_lba    (mg_cmd_lba),
        .cmd_len    (mg_cmd_len),
        .cmd_ready  (mg_cmd_ready),

        .rd_capture_en   (mg_rd_capture_en),
        .wr_feed_en      (mg_wr_feed_en),
        .page_fill_done  (mg_page_fill_done),
        .page_drain_done (mg_page_drain_done)
    );

    assign mg_busy = merge_busy_user;

    merge_fifo_ctrl u_merge_fifo_ctrl (
        .clk             (user_clk),
        .rstn            (nand_usr_rstn),
        .rd_capture_en   (mg_rd_capture_en),
        .rd_capture_ready(mg_rd_capture_ready),
        .rd_tvalid       (nfc_axis_rvalid),
        .rd_tdata        (nfc_axis_rdata),
        .rd_tlast        (nfc_axis_rlast),
        .wr_feed_en      (mg_wr_feed_en),
        .wr_tready       (nfc_axis_wready),
        .wr_tvalid       (mg_wr_tvalid),
        .wr_tdata        (mg_wr_tdata),
        .wr_tlast        (mg_wr_tlast),
        .page_fill_done  (mg_page_fill_done),
        .page_drain_done (mg_page_drain_done),
        .fifo_data_avail (mg_fifo_data_avail),
        .fifo_empty      (mg_fifo_empty)
    );

    assign nfc_axis_wvalid = mg_wr_feed_en ? mg_wr_tvalid : s_axis_tvalid;
    assign nfc_axis_wdata  = mg_wr_feed_en ? mg_wr_tdata  : s_axis_tdata;
    assign nfc_axis_wkeep  = mg_wr_feed_en ? {DATA_WIDTH/8{1'b1}} : s_axis_tkeep;
    assign nfc_axis_wlast  = mg_wr_feed_en ? mg_wr_tlast  : s_axis_tlast;
    assign s_axis_tready   = mg_wr_feed_en ? 1'b0 : nfc_axis_wready;

    assign nfc_axis_rready = mg_rd_capture_en ? mg_rd_capture_ready : m_axis_tready;
    assign m_axis_tvalid   = mg_rd_capture_en ? 1'b0 : nfc_axis_rvalid;
    assign m_axis_tdata    = nfc_axis_rdata;
    assign m_axis_tkeep    = nfc_axis_rkeep;
    assign m_axis_tid      = nfc_axis_rid;
    assign m_axis_tuser    = nfc_axis_ruser;
    assign m_axis_tlast    = nfc_axis_rlast;

    // =========================================================================
    // Command mux: regfile cmds vs merge cmds
    // =========================================================================
    cmd_mux u_cmd_mux (
        .clk       (user_clk),
        .rstn      (nand_usr_rstn),

        .rf_valid  (gen_valid),
        .rf_opc    (gen_opc),
        .rf_lba    (gen_lba),
        .rf_len    (gen_len),
        .rf_ready  (gen_ready),

        .mg_valid  (mg_cmd_valid),
        .mg_opc    (mg_cmd_opc),
        .mg_lba    (mg_cmd_lba),
        .mg_len    (mg_cmd_len),
        .mg_ready  (mg_cmd_ready),

        .mg_busy   (mg_busy),

        .nfc_valid (nfc_cmd_valid),
        .nfc_opc   (nfc_cmd_opc),
        .nfc_lba   (nfc_cmd_lba),
        .nfc_len   (nfc_cmd_len),
        .nfc_ready (nfc_cmd_ready)
    );

    // =========================================================================
    // NFC Channel Test Module
    // =========================================================================
    nfc_channel_test #(
        .DATA_WIDTH (32),
        .WAY_NUM    (1),
        .PATCH      ("FALSE")
    ) nfc_channel_test_0 (
        .nand_clk_fast (nand_clk_fast),
        .nand_clk_slow (nand_clk_slow),
        .nand_clk_rst  (nand_clk_rst),
        .nand_usr_rstn (nand_usr_rstn),
        .nand_usr_clk  (user_clk),
        .ref_clk       (refclk),

        .o_ready (nfc_cmd_ready),
        .i_valid (nfc_cmd_valid),
        .i_opc   (nfc_cmd_opc),
        .i_lba   (nfc_cmd_lba),
        .i_len   (nfc_cmd_len),

        .req_fifo_almost_full (req_fifo_almost_full),
        .o_sr_0         (o_sr_0),
        .o_status_0     (o_status_0),
        .o_cmd_done     (o_cmd_done),

        .axis_wvalid_0  (nfc_axis_wvalid),
        .axis_wready_0  (nfc_axis_wready),
        .axis_wdata_0   (nfc_axis_wdata),
        .axis_wkeep_0   (nfc_axis_wkeep),
        .axis_wlast_0   (nfc_axis_wlast),

        .axis_rvalid_0  (nfc_axis_rvalid),
        .axis_rready_0  (nfc_axis_rready),
        .axis_rdata_0   (nfc_axis_rdata),
        .axis_rkeep_0   (nfc_axis_rkeep),
        .axis_rid_0     (nfc_axis_rid),
        .axis_ruser_0   (nfc_axis_ruser),
        .axis_rlast_0   (nfc_axis_rlast),

        .O_NAND_CE_N    (O_NAND_CE_N[0]),
        .I_NAND_RB_N    (I_NAND_RB_N[0]),
        .O_NAND_WE_N    (O_NAND_WE_N[0]),
        .O_NAND_CLE     (O_NAND_CLE[0]),
        .O_NAND_ALE     (O_NAND_ALE[0]),
        .O_NAND_WP_N    (O_NAND_WP_N[0]),
        .O_NAND_RE_P    (O_NAND_RE_P[0]),
        .O_NAND_RE_N    (O_NAND_RE_N[0]),
        .IO_NAND_DQS_P  (IO_NAND_DQS_P[0]),
        .IO_NAND_DQS_N  (IO_NAND_DQS_N[0]),
        .IO_NAND_DQ     (IO_NAND_DQ[7:0])
    );

endmodule
