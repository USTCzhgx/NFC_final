`timescale 1ns / 1ps
module cmd_mux (
    input  wire        clk,
    input  wire        rstn,

    // Source 0: regfile manual commands
    input  wire        rf_valid,
    input  wire [15:0] rf_opc,
    input  wire [47:0] rf_lba,
    input  wire [23:0] rf_len,
    output wire        rf_ready,

    // Source 1: merge engine commands
    input  wire        mg_valid,
    input  wire [15:0] mg_opc,
    input  wire [47:0] mg_lba,
    input  wire [23:0] mg_len,
    output wire        mg_ready,

    // Merge status for arbitration (optional but useful)
    input  wire        mg_busy,

    // Sink: NFC command interface
    output wire        nfc_valid,
    output wire [15:0] nfc_opc,
    output wire [47:0] nfc_lba,
    output wire [23:0] nfc_len,
    input  wire        nfc_ready
);

    // Arbitration: merge has priority when busy; otherwise merge still wins if it has valid
    wire sel_mg = (mg_busy && mg_valid) || (!rf_valid && mg_valid) || (mg_busy && !rf_valid);

    assign nfc_valid = sel_mg ? mg_valid : rf_valid;
    assign nfc_opc   = sel_mg ? mg_opc   : rf_opc;
    assign nfc_lba   = sel_mg ? mg_lba   : rf_lba;
    assign nfc_len   = sel_mg ? mg_len   : rf_len;

    assign mg_ready  = sel_mg ? nfc_ready : 1'b0;
    assign rf_ready  = sel_mg ? 1'b0      : nfc_ready;

endmodule