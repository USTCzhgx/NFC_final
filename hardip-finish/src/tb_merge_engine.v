`timescale 1ns/1ps
`ifndef PAGE_UTIL_BYTE
`define PAGE_UTIL_BYTE 24'd16384
`endif

module tb_merge_engine;

    reg         clk;
    reg         rstn;

    reg         start;
    reg  [31:0] plan_lbn;
    reg  [15:0] new_pbn;
    reg  [15:0] old_pbn;
    reg  [31:0] entry_count;
    reg  [31:0] plan_base_word;

    wire        busy;
    wire        done_pulse;

    reg  [1:0]  o_status;
    reg         o_cmd_done;

    wire [31:0] addrb;
    wire        enb;
    wire [31:0] dinb;
    reg  [31:0] doutb;
    wire [3:0]  web;

    wire        cmd_valid;
    wire [15:0] cmd_opc;
    wire [47:0] cmd_lba;
    wire [23:0] cmd_len;
    reg         cmd_ready;

    wire        rd_capture_en;
    wire        wr_feed_en;
    reg         page_fill_done;
    reg         page_drain_done;

    reg [31:0]  plan_mem [0:255];

    reg         mon_rd_req_d1;
    reg         mon_rd_req_d2;
    reg  [31:0] mon_rd_addr_d1;
    reg  [31:0] mon_rd_addr_d2;

    integer     i;
    integer     timeout_cnt;
    integer     cmd_count;
    integer     err_count;

    localparam [15:0] OPC_READ_NORMAL   = 16'h3000;
    localparam [15:0] OPC_PROG_NORMAL   = 16'h1080;
    localparam [15:0] OPC_READ_COPYBACK = 16'h3500;
    localparam [15:0] OPC_PROG_COPYBACK = 16'h1085;

    localparam [1:0] SRC_SKIP     = 2'b00;
    localparam [1:0] SRC_FROM_LOG = 2'b01;
    localparam [1:0] SRC_FROM_OLD = 2'b10;

    merge_engine dut (
        .clk             (clk),
        .rstn            (rstn),
        .start           (start),
        .plan_lbn        (plan_lbn),
        .new_pbn         (new_pbn),
        .old_pbn         (old_pbn),
        .entry_count     (entry_count),
        .plan_base_word  (plan_base_word),
        .busy            (busy),
        .done_pulse      (done_pulse),
        .o_status        (o_status),
        .o_cmd_done      (o_cmd_done),
        .addrb           (addrb),
        .enb             (enb),
        .dinb            (dinb),
        .doutb           (doutb),
        .web             (web),
        .cmd_valid       (cmd_valid),
        .cmd_opc         (cmd_opc),
        .cmd_lba         (cmd_lba),
        .cmd_len         (cmd_len),
        .cmd_ready       (cmd_ready),
        .rd_capture_en   (rd_capture_en),
        .wr_feed_en      (wr_feed_en),
        .page_fill_done  (page_fill_done),
        .page_drain_done (page_drain_done)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task pulse_start;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    task wait_done;
        begin
            timeout_cnt = 0;
            while (done_pulse !== 1'b1) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 5000) begin
                    $display("[TB][ERROR] Timeout waiting done_pulse.");
                    $stop;
                end
            end
            @(posedge clk);
        end
    endtask

    task clear_plan_mem;
        begin
            for (i = 0; i < 256; i = i + 1)
                plan_mem[i] = 32'h0000_0000;
        end
    endtask

    task check_no_error;
        begin
            if (err_count == 0)
                $display("[TB] PASS");
            else
                $display("[TB] FAIL, err_count=%0d", err_count);
        end
    endtask

    /*
     * Plan entry format:
     * [31:30] src_type
     * [29:16] src_pbn
     * [15:0]  src_page
     */
    task load_case_mixed;
        begin
            plan_mem[32] = {SRC_FROM_LOG, 14'd101, 16'd7};
            plan_mem[33] = {SRC_FROM_LOG, 14'd100, 16'd11};
            plan_mem[34] = {SRC_FROM_OLD, 14'd0,   16'd0};
            plan_mem[35] = {SRC_SKIP,     14'd0,   16'd0};
        end
    endtask

    task load_case_from_old_normal;
        begin
            plan_mem[64] = {SRC_FROM_OLD, 14'd0,   16'd0};
        end
    endtask

    /*
     * ----------------------------------------------------------------
     * Direct read-data injection for bram_portb_driver inside DUT
     * This bypasses doutb timing issues in TB.
     * Assumption: merge_engine instantiates bram_portb_driver as u_bram_portb_driver
     * ----------------------------------------------------------------
     */
    always @(posedge clk) begin
        if (!rstn) begin
            mon_rd_req_d1  <= 1'b0;
            mon_rd_req_d2  <= 1'b0;
            mon_rd_addr_d1 <= 32'd0;
            mon_rd_addr_d2 <= 32'd0;

            force dut.u_bramif.rd_valid = 1'b0;
            force dut.u_bramif.rd_data  = 32'd0;
        end else begin
            mon_rd_req_d1  <= dut.u_bramif.rd_req;
            mon_rd_req_d2  <= mon_rd_req_d1;
            mon_rd_addr_d1 <= dut.u_bramif.rd_addr;
            mon_rd_addr_d2 <= mon_rd_addr_d1;

            force dut.u_bramif.rd_valid = mon_rd_req_d2;

            if (mon_rd_req_d2)
                force dut.u_bramif.rd_data = plan_mem[mon_rd_addr_d2[31:2]];
            else
                force dut.u_bramif.rd_data = dut.u_bramif.rd_data;
        end
    end

    /*
     * Keep external BRAM port inputs inactive because rd_data/rd_valid are injected directly.
     */
    initial begin
        doutb = 32'd0;
    end

    /*
     * ----------------------------------------------------------------
     * Command responder
     * ----------------------------------------------------------------
     */
    initial begin
        cmd_ready       = 1'b1;
        o_cmd_done      = 1'b0;
        page_fill_done  = 1'b0;
        page_drain_done = 1'b0;
        cmd_count       = 0;
        err_count       = 0;
    end

    always @(posedge clk) begin
        o_cmd_done      <= 1'b0;
        page_fill_done  <= 1'b0;
        page_drain_done <= 1'b0;

        if (cmd_valid && cmd_ready) begin
            cmd_count = cmd_count + 1;

            $display("[%0t] CMD%0d handshake: opc=%h lba=%h len=%0d rd_capture_en=%b wr_feed_en=%b",
                     $time, cmd_count, cmd_opc, cmd_lba, cmd_len, rd_capture_en, wr_feed_en);

            case (cmd_opc)
                OPC_READ_COPYBACK: begin
                    fork
                        begin
                            @(posedge clk);
                            o_cmd_done <= 1'b1;
                        end
                    join
                end

                OPC_PROG_COPYBACK: begin
                    fork
                        begin
                            @(posedge clk);
                            o_cmd_done <= 1'b1;
                        end
                    join
                end

                OPC_READ_NORMAL: begin
                    if (rd_capture_en !== 1'b1) begin
                        err_count = err_count + 1;
                        $display("[TB][ERROR] Normal read issued without rd_capture_en high.");
                    end
                    fork
                        begin
                            @(posedge clk);
                            o_cmd_done     <= 1'b1;
                            page_fill_done <= 1'b1;
                        end
                    join
                end

                OPC_PROG_NORMAL: begin
                    fork
                        begin
                            @(posedge clk);
                            o_cmd_done      <= 1'b1;
                            page_drain_done <= 1'b1;
                        end
                    join
                end

                default: begin
                    err_count = err_count + 1;
                    $display("[TB][ERROR] Unexpected opcode %h", cmd_opc);
                    fork
                        begin
                            @(posedge clk);
                            o_cmd_done <= 1'b1;
                        end
                    join
                end
            endcase
        end
    end

    /*
     * ----------------------------------------------------------------
     * Sequence checking
     * ----------------------------------------------------------------
     */
    always @(posedge clk) begin
        if (cmd_valid && cmd_ready) begin
            if ((cmd_opc == OPC_READ_COPYBACK) && (rd_capture_en !== 1'b0)) begin
                err_count = err_count + 1;
                $display("[TB][ERROR] Copyback read should not enable rd_capture_en.");
            end

            if ((cmd_opc == OPC_PROG_COPYBACK) && (wr_feed_en !== 1'b0)) begin
                err_count = err_count + 1;
                $display("[TB][ERROR] Copyback program should not require wr_feed_en.");
            end
        end
    end

    initial begin
        rstn           = 1'b0;
        start          = 1'b0;
        plan_lbn       = 32'd0;
        new_pbn        = 16'd0;
        old_pbn        = 16'd0;
        entry_count    = 32'd0;
        plan_base_word = 32'd0;
        o_status       = 2'b00;

        clear_plan_mem();

        repeat (10) @(posedge clk);
        rstn <= 1'b1;
        repeat (5) @(posedge clk);

        $display("[TB] ===== Test 1: mixed case =====");
        clear_plan_mem();
        load_case_mixed();

        /*
         * idx=0: FROM_LOG, src_pbn=101, new_pbn=201 -> same parity -> copyback
         * idx=1: FROM_LOG, src_pbn=100, new_pbn=201 -> different parity -> normal
         * idx=2: FROM_OLD, old_pbn=301, new_pbn=201 -> same parity -> copyback
         * idx=3: SKIP
         */
        plan_lbn       = 32'd0;
        new_pbn        = 16'd201;
        old_pbn        = 16'd301;
        entry_count    = 32'd4;
        plan_base_word = 32'd32;

        pulse_start();
        wait_done();

        repeat (20) @(posedge clk);

        $display("[TB] ===== Test 2: FROM_OLD forced normal =====");
        clear_plan_mem();
        load_case_from_old_normal();

        /*
         * idx=0: FROM_OLD, old_pbn=300, new_pbn=201 -> different parity -> normal
         */
        plan_lbn       = 32'd0;
        new_pbn        = 16'd201;
        old_pbn        = 16'd300;
        entry_count    = 32'd1;
        plan_base_word = 32'd64;

        pulse_start();
        wait_done();

        repeat (20) @(posedge clk);

        check_no_error();
        $display("[TB] ===== ALL TESTS DONE =====");
        $finish;
    end

endmodule