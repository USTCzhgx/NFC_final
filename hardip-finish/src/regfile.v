`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// File Name: regfile.v
// Description: AXI4-Lite register file (extended for MergePlan header/control)
// Date: 2025.12.7
// Author: SCMI ZGX
////////////////////////////////////////////////////////////////////////////////
//
// Notes:
// - This version keeps the original NFC register mapping (idx 0~4) and status (idx 5).
// - Adds MergePlan header/control/status registers at idx 6~11.
// - merge_busy_axil / merge_done_axil are assumed already synchronized into S_AXI_ACLK domain.
//
// Address map (word index = addr[5:2], 4-byte aligned):
//   idx0  (0x00): NFC opcode etc (kept)
//   idx1  (0x04): NFC len[23:0]  (kept)
//   idx2  (0x08): NFC lba[31:0]  (kept)
//   idx3  (0x0C): NFC lba[47:32] (kept)
//   idx4  (0x10): NFC valid trigger (write bit0 pulse) (kept)
//   idx5  (0x14): STATUS (read-only) (kept)
//
//   idx6  (0x18): PLAN_LBN
//   idx7  (0x1C): PLAN_PBN {OLD_PBN[31:16], NEW_PBN[15:0]}
//   idx8  (0x20): PLAN_ENTRY_COUNT
//   idx9  (0x24): PLAN_BASE_WORD (BRAM word address base)
//   idx10 (0x28): MERGE_CTRL (write bit0 pulse = merge_start_pulse)
//   idx11 (0x2C): MERGE_STATUS (read-only) {30'd0, done, busy}
//
// IMPORTANT:
// - To access idx>7, AXI_ADDR_WIDTH must be >= 6 and the top-level AXI address ports
//   (axil_awaddr/axil_araddr) must be widened accordingly.
//
////////////////////////////////////////////////////////////////////////////////

module regfile #(
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 6     // widened for 12 regs (idx 0..11)
)(
    input                           S_AXI_ACLK,
    input                           S_AXI_ARESETN,

    // AXI4-Lite Write Address
    input  [AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input                           S_AXI_AWVALID,
    output                          S_AXI_AWREADY,

    // AXI4-Lite Write Data
    input  [AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  [(AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input                           S_AXI_WVALID,
    output                          S_AXI_WREADY,

    // AXI4-Lite Write Response
    output [1:0]                    S_AXI_BRESP,
    output                          S_AXI_BVALID,
    input                           S_AXI_BREADY,

    // AXI4-Lite Read Address
    input  [AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input                           S_AXI_ARVALID,
    output                          S_AXI_ARREADY,

    // AXI4-Lite Read Data
    output [AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output [1:0]                    S_AXI_RRESP,
    output                          S_AXI_RVALID,
    input                           S_AXI_RREADY,

    // NFC control signals output (kept)
    output [47:0]                   nfc_lba,
    output [23:0]                   nfc_len,
    output [15:0]                   nfc_opcode,
    input                           nfc_ready,
    output                          nfc_valid,

    // Top status inputs (kept)
    input                           req_fifo_almost_full,
    input  [7:0]                    o_sr_0,
    input  [1:0]                    o_status_0,

    // MergePlan header/control outputs (new)
    output [31:0]                   plan_lbn,
    output [15:0]                   plan_new_pbn,
    output [15:0]                   plan_old_pbn,
    output [31:0]                   plan_entry_count,
    output [31:0]                   plan_base_word,
    output                          merge_start_pulse,

    // Merge status inputs (new, must be in AXI clock domain already)
    input                           merge_busy_axil,
    input                           merge_done_axil
);

////////////////////////////////////////////////////////////////////////////////
// AXI-lite basic signals
////////////////////////////////////////////////////////////////////////////////

wire [31:0] reg_status;

reg axi_awready, axi_wready;
reg axi_bvalid;
reg axi_arready, axi_rvalid;
reg [1:0] axi_rresp, axi_bresp;
reg [AXI_ADDR_WIDTH-1:0] axi_awaddr, axi_araddr;
reg [AXI_DATA_WIDTH-1:0] axi_rdata;

reg req_fifo_almost_full_r;
reg nfc_ready_r;
reg [1:0] top_status;
reg [7:0] top_sr_r;

assign S_AXI_AWREADY = axi_awready;
assign S_AXI_WREADY  = axi_wready;
assign S_AXI_BRESP   = axi_bresp;
assign S_AXI_BVALID  = axi_bvalid;

assign S_AXI_ARREADY = axi_arready;
assign S_AXI_RDATA   = axi_rdata;
assign S_AXI_RRESP   = axi_rresp;
assign S_AXI_RVALID  = axi_rvalid;

////////////////////////////////////////////////////////////////////////////////
// Slave Registers
////////////////////////////////////////////////////////////////////////////////

// idx 0..11 are implemented as storage regs.
// idx 5 and idx 11 are read-only in read mux; writes to them are ignored by software convention.
reg [31:0] slv_reg [0:11];

wire slv_reg_wren = S_AXI_WVALID && axi_wready && S_AXI_AWVALID && axi_awready;

integer i;
wire [3:0] wr_idx = axi_awaddr[5:2];
wire [3:0] rd_idx = axi_araddr[5:2];

////////////////////////////////////////////////////////////////////////////////
// Write Address Ready
////////////////////////////////////////////////////////////////////////////////
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_awready <= 1'b0;
        axi_awaddr  <= {AXI_ADDR_WIDTH{1'b0}};
    end else begin
        if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID)
            axi_awready <= 1'b1;
        else
            axi_awready <= 1'b0;

        if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID)
            axi_awaddr <= S_AXI_AWADDR;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Write Data Ready
////////////////////////////////////////////////////////////////////////////////
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN)
        axi_wready <= 1'b0;
    else begin
        if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID)
            axi_wready <= 1'b1;
        else
            axi_wready <= 1'b0;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Write response
////////////////////////////////////////////////////////////////////////////////
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_bvalid <= 1'b0;
        axi_bresp  <= 2'b00;
    end else begin
        if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && ~axi_bvalid)
            axi_bvalid <= 1'b1;
        else if (S_AXI_BREADY && axi_bvalid)
            axi_bvalid <= 1'b0;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Read Address
////////////////////////////////////////////////////////////////////////////////
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_arready <= 1'b0;
        axi_araddr  <= {AXI_ADDR_WIDTH{1'b0}};
    end else begin
        if (~axi_arready && S_AXI_ARVALID) begin
            axi_arready <= 1'b1;
            axi_araddr  <= S_AXI_ARADDR;
        end else
            axi_arready <= 1'b0;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Read Data
////////////////////////////////////////////////////////////////////////////////
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        axi_rvalid <= 1'b0;
        axi_rresp  <= 2'b00;
    end else begin
        if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            axi_rvalid <= 1'b1;
            axi_rresp  <= 2'b00;
        end else if (axi_rvalid && S_AXI_RREADY)
            axi_rvalid <= 1'b0;
    end
end

////////////////////////////////////////////////////////////////////////////////
// Register write
////////////////////////////////////////////////////////////////////////////////
always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN) begin
        for (i = 0; i < 12; i = i + 1)
            slv_reg[i] <= 32'd0;
    end else if (slv_reg_wren) begin
        // Software convention: do not write idx5 (status) and idx11 (merge_status)
        if ((wr_idx != 4'd5) && (wr_idx != 4'd11)) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (S_AXI_WSTRB[i]) slv_reg[wr_idx][8*i +: 8] <= S_AXI_WDATA[8*i +: 8];
            end
        end
    end
end

////////////////////////////////////////////////////////////////////////////////
// Capture status inputs (kept)
////////////////////////////////////////////////////////////////////////////////
always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
    if (!S_AXI_ARESETN) begin
        top_status <= 2'd0;
        top_sr_r   <= 8'd0;
        req_fifo_almost_full_r <= 1'b0;
        nfc_ready_r <= 1'b0;
    end else begin
        top_status <= o_status_0;
        top_sr_r   <= o_sr_0;
        req_fifo_almost_full_r <= req_fifo_almost_full;
        nfc_ready_r <= nfc_ready;
    end
end

assign reg_status = {20'd0, req_fifo_almost_full_r,top_status, top_sr_r, nfc_ready_r};


////////////////////////////////////////////////////////////////////////////////
// Register read mux
////////////////////////////////////////////////////////////////////////////////
always @(*) begin
    case (rd_idx)
        4'd0:  axi_rdata = slv_reg[0];
        4'd1:  axi_rdata = slv_reg[1];
        4'd2:  axi_rdata = slv_reg[2];
        4'd3:  axi_rdata = slv_reg[3];
        4'd4:  axi_rdata = slv_reg[4];
        4'd5:  axi_rdata = reg_status;

        4'd6:  axi_rdata = slv_reg[6];  // PLAN_LBN
        4'd7:  axi_rdata = slv_reg[7];  // PLAN_PBN
        4'd8:  axi_rdata = slv_reg[8];  // PLAN_ENTRY_COUNT
        4'd9:  axi_rdata = slv_reg[9];  // PLAN_BASE_WORD
        4'd10: axi_rdata = slv_reg[10]; // MERGE_CTRL shadow
        4'd11: axi_rdata = {30'd0, merge_done_axil, merge_busy_axil}; // MERGE_STATUS (RO)

        default: axi_rdata = 32'hDEAD_BEEF;
    endcase
end

////////////////////////////////////////////////////////////////////////////////
// NFC output mapping (kept)
////////////////////////////////////////////////////////////////////////////////
assign nfc_opcode = slv_reg[0][15:0];
assign nfc_len    = slv_reg[1][23:0];
assign nfc_lba    = {slv_reg[3][15:0], slv_reg[2][31:0]};

// nfc_valid pulse: write idx4 bit0 = 1 raises 1-cycle pulse
reg valid_pulse;

always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN)
        valid_pulse <= 1'b0;
    else begin
        if (slv_reg_wren && (wr_idx == 4'd4))
            valid_pulse <= S_AXI_WDATA[0];
        else
            valid_pulse <= 1'b0;
    end
end

assign nfc_valid = valid_pulse;

////////////////////////////////////////////////////////////////////////////////
// MergePlan header outputs (new)
////////////////////////////////////////////////////////////////////////////////
assign plan_lbn         = slv_reg[6];
assign plan_new_pbn     = slv_reg[7][15:0];
assign plan_old_pbn     = slv_reg[7][31:16];
assign plan_entry_count = slv_reg[8];
assign plan_base_word   = slv_reg[9];

// merge_start_pulse: write idx10 bit0 = 1 raises 1-cycle pulse
reg merge_start_pulse_r;

always @(posedge S_AXI_ACLK) begin
    if (~S_AXI_ARESETN)
        merge_start_pulse_r <= 1'b0;
    else begin
        if (slv_reg_wren && (wr_idx == 4'd10))
            merge_start_pulse_r <= S_AXI_WDATA[0];
        else
            merge_start_pulse_r <= 1'b0;
    end
end

assign merge_start_pulse = merge_start_pulse_r;

endmodule