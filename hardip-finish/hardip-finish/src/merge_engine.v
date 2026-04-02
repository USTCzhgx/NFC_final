`timescale 1ns/1ps
`include "nfc_param.vh"

module merge_engine (
    input  wire        clk,
    input  wire        rstn,

    (* MARK_DEBUG="true" *) input  wire        start,
    input  wire [31:0] plan_lbn,
    input  wire [15:0] new_pbn,
    input  wire [15:0] old_pbn,
    input  wire [31:0] entry_count,
    input  wire [31:0] plan_base_word,

    output reg         busy,
    output reg         done_pulse,

    // Status from NFC
    input  wire [1:0]  o_status,
    (* MARK_DEBUG="true" *) input  wire        o_cmd_done,

    // BRAM Port B (driven by bram_portb_driver)
    (* MARK_DEBUG="true" *) output wire [31:0] addrb,
    (* MARK_DEBUG="true" *) output wire        enb,
    (* MARK_DEBUG="true" *) output wire [31:0] dinb,
    (* MARK_DEBUG="true" *) input  wire [31:0] doutb,
    (* MARK_DEBUG="true" *) output wire [3:0]  web,

    // Command interface to NFC wrapper
    (* MARK_DEBUG="true" *) output reg         cmd_valid,
    (* MARK_DEBUG="true" *) output reg  [15:0] cmd_opc,
    (* MARK_DEBUG="true" *) output reg  [47:0] cmd_lba,
    (* MARK_DEBUG="true" *) output reg  [23:0] cmd_len,
    (* MARK_DEBUG="true" *) input  wire        cmd_ready,

    // Normal merge path control
    output reg         rd_capture_en,
    output reg         wr_feed_en,
    input  wire        page_fill_done,
    input  wire        page_drain_done
);

    // ------------------------------------------------------------
    // BRAM driver interface (Port B)
    // ------------------------------------------------------------
    reg         rd_req;
    reg  [31:0] rd_addr;
    wire [31:0] rd_data;
    wire        rd_valid;

    reg         wr_req;
    reg  [31:0] wr_addr;
    reg  [31:0] wr_data;
    reg  [3:0]  wr_be;

    bram_portb_driver u_bramif (
        .clkb     (clk),
        .rstbn    (rstn),

        .rd_req   (rd_req),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rd_valid (rd_valid),

        .wr_req   (wr_req),
        .wr_addr  (wr_addr),
        .wr_data  (wr_data),
        .wr_be    (wr_be),

        .addrb    (addrb),
        .enb      (enb),
        .dinb     (dinb),
        .doutb    (doutb),
        .web      (web)
    );

    // ------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------
    localparam IDLE      = 4'd0;
    localparam REQ       = 4'd1;
    localparam WAIT_DATA = 4'd2;
    localparam CHOOSE    = 4'd3;

    localparam CORD_SEND = 4'd4;
    localparam CORD_WAIT = 4'd5;

    localparam COPR_SEND = 4'd6;
    localparam COPR_WAIT = 4'd7;

    localparam NORD_SEND = 4'd8;
    localparam NORD_WAIT = 4'd9;

    localparam NOPG_SEND = 4'd10;
    localparam NOPG_WAIT = 4'd11;

    localparam NEXT      = 4'd12;

    (* MARK_DEBUG="true" *) reg [3:0] st;

    (* MARK_DEBUG="true" *) reg [31:0] idx;
    reg [31:0] entry_count_r;
    reg [31:0] plan_base_word_r;
    reg [15:0] new_pbn_r;
    reg [15:0] old_pbn_r;

    reg [1:0]  src_type;
    reg [13:0] src_pbn;
    reg [15:0] src_page;

    // Command completion control
    reg cmd_done_armed;
    reg cmd_done_seen;
    reg page_fill_seen;
    reg page_drain_seen;

    // Start edge detect
    reg start_d;
    wire start_pulse;

    assign start_pulse = start & ~start_d;

    // Current destination page index (SLC pages_per_block < 512 assumption)
    wire [8:0] dst_page = idx[8:0];

    // Effective source override for FROM_OLD (2'b10):
    //   src_pbn = old_pbn_r
    //   src_page = dst_page
    wire [10:0] src_pbn_eff  = (src_type == 2'b10) ? old_pbn_r[10:0] : src_pbn[10:0];
    wire [8:0]  src_page_eff = (src_type == 2'b10) ? dst_page        : src_page[8:0];
    wire        can_copyback = (src_pbn_eff[0] == new_pbn_r[0]);

    localparam [23:0] PAGE_LEN = 8192;

    // ------------------------------------------------------------
    // Helper: pack row address
    // Note: This function uses 9-bit page for SLC pages_per_block < 512.
    // ------------------------------------------------------------
    function automatic [47:0] pack_row_addr(input [10:0] pbn, input [8:0] page);
        begin
            pack_row_addr = {6'b0, 3'b0, 1'b0, pbn, 2'b0, page, 16'b0};
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            st <= IDLE;

            idx              <= 32'd0;
            entry_count_r    <= 32'd0;
            plan_base_word_r <= 32'd0;
            new_pbn_r        <= 16'd0;
            old_pbn_r        <= 16'd0;

            src_type <= 2'd0;
            src_pbn  <= 14'd0;
            src_page <= 16'd0;

            rd_req  <= 1'b0;
            rd_addr <= 32'd0;

            wr_req  <= 1'b0;
            wr_addr <= 32'd0;
            wr_data <= 32'd0;
            wr_be   <= 4'd0;

            cmd_valid <= 1'b0;
            cmd_opc   <= 16'd0;
            cmd_lba   <= 48'd0;
            cmd_len   <= 24'd0;

            busy       <= 1'b0;
            done_pulse <= 1'b0;

            cmd_done_armed <= 1'b0;
            cmd_done_seen  <= 1'b0;
            page_fill_seen <= 1'b0;
            page_drain_seen <= 1'b0;

            start_d <= 1'b0;
            rd_capture_en <= 1'b0;
            wr_feed_en    <= 1'b0;
        end else begin
            // Default one-cycle pulse outputs
            rd_req     <= 1'b0;
            wr_req     <= 1'b0;
            wr_be      <= 4'd0;
            done_pulse <= 1'b0;

            // Delay register for start edge detect
            start_d <= start;

            // Latch command-done pulse until FSM consumes it
            if (o_cmd_done) begin
                cmd_done_seen <= 1'b1;
            end
            if (page_fill_done) begin
                page_fill_seen <= 1'b1;
            end
            if (page_drain_done) begin
                page_drain_seen <= 1'b1;
            end

            case (st)
                IDLE: begin
                    busy           <= 1'b0;
                    idx            <= 32'd0;
                    cmd_valid      <= 1'b0;
                    cmd_done_armed <= 1'b0;
                    cmd_done_seen  <= 1'b0;
                    page_fill_seen <= 1'b0;
                    page_drain_seen <= 1'b0;
                    rd_capture_en  <= 1'b0;
                    wr_feed_en     <= 1'b0;

                    if (start_pulse) begin
                        busy <= 1'b1;

                        entry_count_r    <= entry_count;
                        plan_base_word_r <= plan_base_word;
                        new_pbn_r        <= new_pbn;
                        old_pbn_r        <= old_pbn;

                        if (entry_count == 32'd0) begin
                            busy       <= 1'b0;
                            done_pulse <= 1'b1;
                            st         <= IDLE;
                        end else begin
                            st <= REQ;
                        end
                    end
                end

                REQ: begin
                    // plan_base_word_r is WORD addressing
                    // BRAM port uses BYTE addressing, so multiply by 4
                    rd_req  <= 1'b1;
                    rd_addr <= (plan_base_word_r + idx) << 2;
                    st      <= WAIT_DATA;
                end

                WAIT_DATA: begin
                    if (rd_valid) begin
                        src_type <= rd_data[31:30];
                        src_pbn  <= rd_data[29:16];
                        src_page <= rd_data[15:0];
                        st       <= CHOOSE;
                    end
                end

                CHOOSE: begin
                    cmd_done_seen   <= 1'b0;
                    page_fill_seen  <= 1'b0;
                    page_drain_seen <= 1'b0;

                    if (src_type == 2'b00) begin
                        // SKIP
                        st <= NEXT;
                    end else if ((src_type == 2'b01) || (src_type == 2'b10)) begin
                        if (can_copyback) begin
                            cmd_opc   <= 16'h3500;
                            cmd_lba   <= pack_row_addr(src_pbn_eff, src_page_eff);
                            cmd_len   <= 24'd0;
                            cmd_valid <= 1'b1;
                            st        <= CORD_SEND;
                        end else begin
                            rd_capture_en <= 1'b1;
                            cmd_opc       <= 16'h3000;
                            cmd_lba       <= pack_row_addr(src_pbn_eff, src_page_eff);
                            cmd_len       <= PAGE_LEN;
                            cmd_valid     <= 1'b1;
                            st            <= NORD_SEND;
                        end
                    end else begin
                        // RESERVED => treat as SKIP
                        st <= NEXT;
                    end
                end

                // --------------------------------------------------------
                // CORD_SEND: keep valid asserted until handshake completes
                // --------------------------------------------------------
                CORD_SEND: begin
                    if (cmd_ready) begin
                        cmd_valid      <= 1'b0;
                        cmd_done_armed <= 1'b1;

                        // If done already happened before or at this cycle,
                        // consume it immediately and move on.
                        if (cmd_done_seen || o_cmd_done) begin
                            cmd_done_armed <= 1'b0;
                            cmd_done_seen  <= 1'b0;

                            cmd_opc   <= 16'h1085;
                            cmd_lba   <= pack_row_addr(new_pbn_r[10:0], dst_page);
                            cmd_len   <= 24'd0;
                            cmd_valid <= 1'b1;

                            st <= COPR_SEND;
                        end else begin
                            st <= CORD_WAIT;
                        end
                    end
                end

                CORD_WAIT: begin
                    if (cmd_done_armed && cmd_done_seen) begin
                        cmd_done_armed <= 1'b0;
                        cmd_done_seen  <= 1'b0;

                        // Issue COPR command
                        cmd_opc   <= 16'h1085;
                        cmd_lba   <= pack_row_addr(new_pbn_r[10:0], dst_page);
                        cmd_len   <= 24'd0;
                        cmd_valid <= 1'b1;

                        st <= COPR_SEND;
                    end
                end

                NORD_SEND: begin
                    if (cmd_ready) begin
                        cmd_valid      <= 1'b0;
                        cmd_done_armed <= 1'b1;

                        if ((cmd_done_seen || o_cmd_done) && (page_fill_seen || page_fill_done)) begin
                            cmd_done_armed <= 1'b0;
                            cmd_done_seen  <= 1'b0;
                            page_fill_seen <= 1'b0;
                            rd_capture_en  <= 1'b0;
                            wr_feed_en     <= 1'b0;
                            page_drain_seen <= 1'b0;

                            cmd_opc   <= 16'h1080;
                            cmd_lba   <= pack_row_addr(new_pbn_r[10:0], dst_page);
                            cmd_len   <= PAGE_LEN;
                            cmd_valid <= 1'b1;

                            st <= NOPG_SEND;
                        end else begin
                            st <= NORD_WAIT;
                        end
                    end
                end

                NORD_WAIT: begin
                    if (cmd_done_armed && cmd_done_seen && page_fill_seen) begin
                        cmd_done_armed <= 1'b0;
                        cmd_done_seen  <= 1'b0;
                        page_fill_seen <= 1'b0;
                        rd_capture_en  <= 1'b0;
                        wr_feed_en     <= 1'b0;
                        page_drain_seen <= 1'b0;

                        cmd_opc   <= 16'h1080;
                        cmd_lba   <= pack_row_addr(new_pbn_r[10:0], dst_page);
                        cmd_len   <= PAGE_LEN;
                        cmd_valid <= 1'b1;

                        st <= NOPG_SEND;
                    end
                end

                NOPG_SEND: begin
                    if (cmd_ready) begin
                        cmd_valid      <= 1'b0;
                        cmd_done_armed <= 1'b1;
                        wr_feed_en     <= 1'b1;

                        if ((cmd_done_seen || o_cmd_done) && (page_drain_seen || page_drain_done)) begin
                            cmd_done_armed  <= 1'b0;
                            cmd_done_seen   <= 1'b0;
                            page_drain_seen <= 1'b0;
                            wr_feed_en      <= 1'b0;
                            st              <= NEXT;
                        end else begin
                            st <= NOPG_WAIT;
                        end
                    end
                end

                NOPG_WAIT: begin
                    if (cmd_done_armed && cmd_done_seen && page_drain_seen) begin
                        cmd_done_armed  <= 1'b0;
                        cmd_done_seen   <= 1'b0;
                        page_drain_seen <= 1'b0;
                        wr_feed_en      <= 1'b0;
                        st              <= NEXT;
                    end
                end

                // --------------------------------------------------------
                // COPR_SEND: keep valid asserted until handshake completes
                // --------------------------------------------------------
                COPR_SEND: begin
                    if (cmd_ready) begin
                        cmd_valid      <= 1'b0;
                        cmd_done_armed <= 1'b1;

                        // If done already happened before or at this cycle,
                        // consume it immediately and go to next entry.
                        if (cmd_done_seen || o_cmd_done) begin
                            cmd_done_armed <= 1'b0;
                            cmd_done_seen  <= 1'b0;
                            st             <= NEXT;
                        end else begin
                            st <= COPR_WAIT;
                        end
                    end
                end

                COPR_WAIT: begin
                    if (cmd_done_armed && cmd_done_seen) begin
                        cmd_done_armed <= 1'b0;
                        cmd_done_seen  <= 1'b0;
                        st             <= NEXT;
                    end
                end

                NEXT: begin
                    rd_capture_en <= 1'b0;
                    wr_feed_en    <= 1'b0;
                    if (idx + 32'd1 >= entry_count_r) begin
                        busy       <= 1'b0;
                        done_pulse <= 1'b1;
                        st         <= IDLE;
                    end else begin
                        idx <= idx + 32'd1;
                        st  <= REQ;
                    end
                end

                default: begin
                    st <= IDLE;
                end
            endcase
        end
    end

endmodule
