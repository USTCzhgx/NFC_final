`timescale 1ns/1ps
`ifndef PAGE_UTIL_BYTE
`define PAGE_UTIL_BYTE 24'd16384
`endif

module tb_nfc_test_top;

    localparam CHAN_NUM   = 1;
    localparam WAY_NUM    = 1;
    localparam DATA_WIDTH = 32;

    localparam [15:0] OPC_READ_NORMAL   = 16'h3000;
    localparam [15:0] OPC_PROG_NORMAL   = 16'h1080;
    localparam [15:0] OPC_READ_COPYBACK = 16'h3500;
    localparam [15:0] OPC_PROG_COPYBACK = 16'h1085;

    localparam [1:0] SRC_SKIP     = 2'b00;
    localparam [1:0] SRC_FROM_LOG = 2'b01;
    localparam [1:0] SRC_FROM_OLD = 2'b10;

    reg                         sys_clk;
    reg                         sys_rst_n;
    reg                         s_axil_aclk;
    reg                         s_axil_aresetn;

    reg  [5:0]                  axil_awaddr;
    reg  [2:0]                  axil_awprot;
    reg                         axil_awvalid;
    wire                        axil_awready;

    reg  [31:0]                 axil_wdata;
    reg  [3:0]                  axil_wstrb;
    reg                         axil_wvalid;
    wire                        axil_wready;

    wire [1:0]                  axil_bresp;
    wire                        axil_bvalid;
    reg                         axil_bready;

    reg  [5:0]                  axil_araddr;
    reg  [2:0]                  axil_arprot;
    reg                         axil_arvalid;
    wire                        axil_arready;

    wire [31:0]                 axil_rdata;
    wire [1:0]                  axil_rresp;
    wire                        axil_rvalid;
    reg                         axil_rready;

    reg                         s_axis_tvalid;
    wire                        s_axis_tready;
    reg  [DATA_WIDTH-1:0]       s_axis_tdata;
    reg  [DATA_WIDTH/8-1:0]     s_axis_tkeep;
    reg                         s_axis_tlast;

    wire                        m_axis_tvalid;
    reg                         m_axis_tready;
    wire [DATA_WIDTH-1:0]       m_axis_tdata;
    wire [DATA_WIDTH/8-1:0]     m_axis_tkeep;
    wire [15:0]                 m_axis_tid;
    wire [3:0]                  m_axis_tuser;
    wire                        m_axis_tlast;

    wire [31:0]                 addrb;
    wire                        enb;
    wire [31:0]                 dinb;
    reg  [31:0]                 doutb;
    wire [3:0]                  web;

    wire [CHAN_NUM*WAY_NUM-1:0] O_NAND_CE_N;
    reg  [CHAN_NUM*WAY_NUM-1:0] I_NAND_RB_N;
    wire [CHAN_NUM-1:0]         O_NAND_WE_N;
    wire [CHAN_NUM-1:0]         O_NAND_CLE;
    wire [CHAN_NUM-1:0]         O_NAND_ALE;
    wire [CHAN_NUM-1:0]         O_NAND_WP_N;
    wire [CHAN_NUM-1:0]         O_NAND_RE_P;
    wire [CHAN_NUM-1:0]         O_NAND_RE_N;
    tri  [CHAN_NUM-1:0]         IO_NAND_DQS_P;
    tri  [CHAN_NUM-1:0]         IO_NAND_DQS_N;
    tri  [CHAN_NUM*8-1:0]       IO_NAND_DQ;

    reg  [31:0]                 plan_mem [0:255];

    reg                         mon_rd_req_d1;
    reg                         mon_rd_req_d2;
    reg  [31:0]                 mon_rd_addr_d1;
    reg  [31:0]                 mon_rd_addr_d2;

    integer                     i;
    integer                     timeout_cnt;
    integer                     err_count;
    integer                     cmd_count;
    integer                     prog_word_count;

    nfc_test_top #(
        .CHAN_NUM   (CHAN_NUM),
        .WAY_NUM    (WAY_NUM),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .sys_clk         (sys_clk),
        .sys_rst_n       (sys_rst_n),
        .s_axil_aclk     (s_axil_aclk),
        .s_axil_aresetn  (s_axil_aresetn),

        .axil_awaddr     (axil_awaddr),
        .axil_awprot     (axil_awprot),
        .axil_awvalid    (axil_awvalid),
        .axil_awready    (axil_awready),

        .axil_wdata      (axil_wdata),
        .axil_wstrb      (axil_wstrb),
        .axil_wvalid     (axil_wvalid),
        .axil_wready     (axil_wready),

        .axil_bresp      (axil_bresp),
        .axil_bvalid     (axil_bvalid),
        .axil_bready     (axil_bready),

        .axil_araddr     (axil_araddr),
        .axil_arprot     (axil_arprot),
        .axil_arvalid    (axil_arvalid),
        .axil_arready    (axil_arready),

        .axil_rdata      (axil_rdata),
        .axil_rresp      (axil_rresp),
        .axil_rvalid     (axil_rvalid),
        .axil_rready     (axil_rready),

        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tready   (s_axis_tready),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tkeep    (s_axis_tkeep),
        .s_axis_tlast    (s_axis_tlast),

        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tkeep    (m_axis_tkeep),
        .m_axis_tid      (m_axis_tid),
        .m_axis_tuser    (m_axis_tuser),
        .m_axis_tlast    (m_axis_tlast),

        .addrb           (addrb),
        .enb             (enb),
        .dinb            (dinb),
        .doutb           (doutb),
        .web             (web),

        .O_NAND_CE_N     (O_NAND_CE_N),
        .I_NAND_RB_N     (I_NAND_RB_N),
        .O_NAND_WE_N     (O_NAND_WE_N),
        .O_NAND_CLE      (O_NAND_CLE),
        .O_NAND_ALE      (O_NAND_ALE),
        .O_NAND_WP_N     (O_NAND_WP_N),
        .O_NAND_RE_P     (O_NAND_RE_P),
        .O_NAND_RE_N     (O_NAND_RE_N),
        .IO_NAND_DQS_P   (IO_NAND_DQS_P),
        .IO_NAND_DQS_N   (IO_NAND_DQS_N),
        .IO_NAND_DQ      (IO_NAND_DQ)
    );

    initial begin
        sys_clk = 1'b0;
        s_axil_aclk = 1'b0;
        forever #5 sys_clk = ~sys_clk;
    end

    initial begin
        forever #5 s_axil_aclk = ~s_axil_aclk;
    end

    /*
     * ----------------------------------------------------------------
     * External BRAM pins are not used in this TB.
     * Read data is injected directly into dut.u_merge.u_bramif.
     * ----------------------------------------------------------------
     */
    initial begin
        doutb = 32'd0;
    end

    /*
     * ----------------------------------------------------------------
     * Direct read-data injection for merge_engine BRAM interface
     * Assumption: merge_engine instantiates the BRAM IF as u_bramif
     * ----------------------------------------------------------------
     */
    always @(posedge dut.user_clk) begin
        if (!sys_rst_n) begin
            mon_rd_req_d1  <= 1'b0;
            mon_rd_req_d2  <= 1'b0;
            mon_rd_addr_d1 <= 32'd0;
            mon_rd_addr_d2 <= 32'd0;

            force dut.u_merge.u_bramif.rd_valid = 1'b0;
            force dut.u_merge.u_bramif.rd_data  = 32'd0;
        end else begin
            mon_rd_req_d1  <= dut.u_merge.u_bramif.rd_req;
            mon_rd_req_d2  <= mon_rd_req_d1;
            mon_rd_addr_d1 <= dut.u_merge.u_bramif.rd_addr;
            mon_rd_addr_d2 <= mon_rd_addr_d1;

            force dut.u_merge.u_bramif.rd_valid = mon_rd_req_d2;

            if (mon_rd_req_d2)
                force dut.u_merge.u_bramif.rd_data = plan_mem[mon_rd_addr_d2[31:2]];
            else
                force dut.u_merge.u_bramif.rd_data = dut.u_merge.u_bramif.rd_data;
        end
    end

    /*
     * ----------------------------------------------------------------
     * Optional sanity monitor for the unused external BRAM interface
     * ----------------------------------------------------------------
     */
    always @(posedge dut.user_clk) begin
        if (enb) begin
            $display("[%0t] EXT BRAM port observed: enb=1 web=%h addrb=%h dinb=%h",
                     $time, web, addrb, dinb);
        end
    end

    /*
     * ----------------------------------------------------------------
     * Feed read-data stream into merge_fifo_ctrl for normal read path
     * ----------------------------------------------------------------
     */
    task send_normal_read_page;
        integer k;
        reg [31:0] word_data;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                word_data = 32'hA5000000 + k;
                force dut.nfc_axis_rvalid = 1'b1;
                force dut.nfc_axis_rdata  = word_data;
                force dut.nfc_axis_rkeep  = 4'hF;
                force dut.nfc_axis_rid    = 16'd0;
                force dut.nfc_axis_ruser  = 4'd0;
                force dut.nfc_axis_rlast  = (k == 7);
                @(posedge dut.user_clk);
                while (dut.nfc_axis_rready !== 1'b1) begin
                    @(posedge dut.user_clk);
                end
            end

            force dut.nfc_axis_rvalid = 1'b0;
            force dut.nfc_axis_rdata  = 32'd0;
            force dut.nfc_axis_rkeep  = 4'd0;
            force dut.nfc_axis_rid    = 16'd0;
            force dut.nfc_axis_ruser  = 4'd0;
            force dut.nfc_axis_rlast  = 1'b0;
        end
    endtask

    /*
     * ----------------------------------------------------------------
     * Consume write-data stream from merge_fifo_ctrl during normal program
     * ----------------------------------------------------------------
     */
    initial begin
        force dut.nfc_axis_wready = 1'b1;
    end

    always @(posedge dut.user_clk) begin
        if (!sys_rst_n) begin
            prog_word_count <= 0;
        end else begin
            if (dut.nfc_axis_wvalid && dut.nfc_axis_wready) begin
                $display("[%0t] WDATA beat: data=%h last=%b",
                         $time, dut.nfc_axis_wdata, dut.nfc_axis_wlast);

                if (dut.nfc_axis_wlast)
                    prog_word_count <= 0;
                else
                    prog_word_count <= prog_word_count + 1;
            end
        end
    end

    /*
     * ----------------------------------------------------------------
     * Command responder for nfc_channel_test_0 side-effects
     * We force ready/done behavior directly from TB.
     * ----------------------------------------------------------------
     */
    initial begin
        force dut.nfc_cmd_ready = 1'b1;
        force dut.o_cmd_done    = 1'b0;
        I_NAND_RB_N             = {CHAN_NUM*WAY_NUM{1'b1}};
        err_count               = 0;
        cmd_count               = 0;
        prog_word_count         = 0;
    end

    always @(posedge dut.user_clk) begin
        force dut.o_cmd_done = 1'b0;

        if (dut.nfc_cmd_valid && dut.nfc_cmd_ready) begin
            cmd_count = cmd_count + 1;

            $display("[%0t] CMD%0d handshake: opc=%h lba=%h len=%0d mg_busy=%b rd_cap=%b wr_feed=%b",
                     $time, cmd_count, dut.nfc_cmd_opc, dut.nfc_cmd_lba, dut.nfc_cmd_len,
                     dut.mg_busy, dut.mg_rd_capture_en, dut.mg_wr_feed_en);

            case (dut.nfc_cmd_opc)
                OPC_READ_COPYBACK: begin
                    if (dut.mg_rd_capture_en !== 1'b0) begin
                        err_count = err_count + 1;
                        $display("[TB][ERROR] Copyback read should not enable FIFO capture.");
                    end
                    fork
                        begin
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b1;
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b0;
                        end
                    join
                end

                OPC_PROG_COPYBACK: begin
                    if (dut.mg_wr_feed_en !== 1'b0) begin
                        err_count = err_count + 1;
                        $display("[TB][ERROR] Copyback program should not enable FIFO drain.");
                    end
                    fork
                        begin
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b1;
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b0;
                        end
                    join
                end

                OPC_READ_NORMAL: begin
                    if (dut.mg_rd_capture_en !== 1'b1) begin
                        err_count = err_count + 1;
                        $display("[TB][ERROR] Normal read without mg_rd_capture_en.");
                    end
                    fork
                        begin
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b1;
                            send_normal_read_page();
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b0;
                        end
                    join
                end

                OPC_PROG_NORMAL: begin
                    if (dut.mg_wr_feed_en !== 1'b1) begin
                        err_count = err_count + 1;
                        $display("[TB][ERROR] Normal program without mg_wr_feed_en.");
                    end
                    fork
                        begin
                            wait (dut.mg_page_drain_done == 1'b1);
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b1;
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b0;
                        end
                    join
                end

                default: begin
                    err_count = err_count + 1;
                    $display("[TB][ERROR] Unexpected opcode %h", dut.nfc_cmd_opc);
                    fork
                        begin
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b1;
                            @(posedge dut.user_clk);
                            force dut.o_cmd_done = 1'b0;
                        end
                    join
                end
            endcase
        end
    end

    task apply_merge_cfg;
        input [31:0] cfg_plan_lbn;
        input [15:0] cfg_new_pbn;
        input [15:0] cfg_old_pbn;
        input [31:0] cfg_entry_count;
        input [31:0] cfg_plan_base_word;
        begin
            force dut.plan_lbn_axil         = cfg_plan_lbn;
            force dut.plan_new_pbn_axil     = cfg_new_pbn;
            force dut.plan_old_pbn_axil     = cfg_old_pbn;
            force dut.plan_entry_count_axil = cfg_entry_count;
            force dut.plan_base_word_axil   = cfg_plan_base_word;
        end
    endtask

    task release_merge_cfg;
        begin
            release dut.plan_lbn_axil;
            release dut.plan_new_pbn_axil;
            release dut.plan_old_pbn_axil;
            release dut.plan_entry_count_axil;
            release dut.plan_base_word_axil;
        end
    endtask

    task pulse_merge_start;
        begin
            @(posedge dut.user_clk);
            force dut.merge_start_pulse_axil = 1'b1;
            @(posedge dut.user_clk);
            force dut.merge_start_pulse_axil = 1'b0;
            @(posedge dut.user_clk);
            release dut.merge_start_pulse_axil;
        end
    endtask

    task wait_merge_done;
        begin
            timeout_cnt = 0;
            while (dut.merge_done_user !== 1'b1) begin
                @(posedge dut.user_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 200000) begin
                    $display("[TB][ERROR] Merge timeout.");
                    $stop;
                end
            end
            @(posedge dut.user_clk);
        end
    endtask

    task clear_plan_mem;
        begin
            for (i = 0; i < 256; i = i + 1)
                plan_mem[i] = 32'h0000_0000;
        end
    endtask

    task run_copyback_case;
        begin
            $display("[TB] ===== Copyback case start =====");

            /*
             * idx=0: FROM_LOG, src_pbn=101, new_pbn=201 => same parity => copyback
             * idx=1: FROM_OLD, old_pbn=301, new_pbn=201 => same parity => copyback
             */
            plan_mem[32] = {SRC_FROM_LOG, 14'd101, 16'd7};
            plan_mem[33] = {SRC_FROM_OLD, 14'd0,   16'd0};

            apply_merge_cfg(32'd0, 16'd201, 16'd301, 32'd2, 32'd32);
            pulse_merge_start();
            wait_merge_done();
            release_merge_cfg();

            $display("[TB] ===== Copyback case done =====");
        end
    endtask

    task run_normal_case;
        begin
            $display("[TB] ===== Normal case start =====");

            /*
             * idx=0: FROM_LOG, src_pbn=100, new_pbn=201 => different parity => normal
             * idx=1: FROM_OLD, old_pbn=300, new_pbn=201 => different parity => normal
             */
            plan_mem[48] = {SRC_FROM_LOG, 14'd100, 16'd11};
            plan_mem[49] = {SRC_FROM_OLD, 14'd0,   16'd0};

            apply_merge_cfg(32'd0, 16'd201, 16'd300, 32'd2, 32'd48);
            pulse_merge_start();
            wait_merge_done();
            release_merge_cfg();

            $display("[TB] ===== Normal case done =====");
        end
    endtask

    initial begin
        sys_rst_n      = 1'b0;
        s_axil_aresetn = 1'b0;

        axil_awaddr    = 6'd0;
        axil_awprot    = 3'd0;
        axil_awvalid   = 1'b0;
        axil_wdata     = 32'd0;
        axil_wstrb     = 4'hF;
        axil_wvalid    = 1'b0;
        axil_bready    = 1'b1;
        axil_araddr    = 6'd0;
        axil_arprot    = 3'd0;
        axil_arvalid   = 1'b0;
        axil_rready    = 1'b1;

        s_axis_tvalid  = 1'b0;
        s_axis_tdata   = {DATA_WIDTH{1'b0}};
        s_axis_tkeep   = {DATA_WIDTH/8{1'b1}};
        s_axis_tlast   = 1'b0;

        m_axis_tready  = 1'b1;

        clear_plan_mem();

        repeat (20) @(posedge sys_clk);
        sys_rst_n      = 1'b1;
        s_axil_aresetn = 1'b1;

        repeat (20) @(posedge dut.user_clk);

        run_copyback_case();

        repeat (50) @(posedge dut.user_clk);

        run_normal_case();

        repeat (100) @(posedge dut.user_clk);

        if (err_count == 0)
            $display("[TB] PASS");
        else
            $display("[TB] FAIL, err_count=%0d", err_count);

        $finish;
    end

endmodule