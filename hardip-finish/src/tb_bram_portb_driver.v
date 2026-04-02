`timescale 1ns/1ps

module tb_bram_portb_driver;

    // Parameters
    localparam CLK_PERIOD = 10;

    // Inputs
    reg         clkb;
    reg         rstbn;
    reg         rd_req;
    reg  [31:0] rd_addr;
    reg         wr_req;
    reg  [31:0] wr_addr;
    reg  [31:0] wr_data;
    reg  [3:0]  wr_be;
    reg  [31:0] doutb;

    // Outputs
    wire [31:0] rd_data;
    wire        rd_valid;
    wire [31:0] addrb;
    wire        enb;
    wire [31:0] dinb;
    wire [3:0]  web;

    // Instantiate the Unit Under Test (UUT)
    bram_portb_driver uut (
        .clkb    (clkb),
        .rstbn   (rstbn),
        .rd_req  (rd_req),
        .rd_addr (rd_addr),
        .rd_data (rd_data),
        .rd_valid(rd_valid),
        .wr_req  (wr_req),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .wr_be   (wr_be),
        .addrb   (addrb),
        .enb     (enb),
        .dinb    (dinb),
        .doutb   (doutb),
        .web     (web)
    );

    // Clock generation
    initial begin
        clkb = 0;
        forever #(CLK_PERIOD/2) clkb = ~clkb;
    end

    // Mock BRAM Behavioral Model
    // Simulate BRAM: Read data is usually available 1 cycle after address
    reg [31:0] mock_mem [0:255];
    always @(posedge clkb) begin
        if (enb && |web) begin
            mock_mem[addrb[7:0]] <= dinb; // Simplified 8-bit index for mock
        end
        // BRAM standard read latency is 1 cycle
        doutb <= mock_mem[addrb[7:0]];
    end

    // Test Procedure
    initial begin
        // Initialize
        rstbn   = 0;
        rd_req  = 0;
        rd_addr = 0;
        wr_req  = 0;
        wr_addr = 0;
        wr_data = 0;
        wr_be   = 0;

        // Reset
        #(CLK_PERIOD * 5);
        rstbn = 1;
        #(CLK_PERIOD * 2);

        // Case 1: Simple Write
        write_task(32'h0000_0004, 32'hDEAD_BEEF, 4'hF);
        write_task(32'h0000_0008, 32'hCAFE_BABE, 4'hF);
        
        // Case 2: Simple Read (Check 2-cycle latency)
        read_task(32'h0000_0004);
        #(CLK_PERIOD * 3); // Wait for pipeline to empty

        // Case 3: Write and Read Conflict (Write Priority)
        // Here we try to read Addr 0x8 while writing to Addr 0xC
        // The driver logic 'rd_fire = rd_req & ~wr_req' should kill the read
        @(posedge clkb);
        wr_req  <= 1'b1;
        wr_addr <= 32'h0000_000C;
        wr_data <= 32'hAAAA_5555;
        wr_be   <= 4'hF;
        rd_req  <= 1'b1;
        rd_addr <= 32'h0000_0008;
        
        @(posedge clkb);
        wr_req  <= 1'b0;
        rd_req  <= 1'b0;

        // Case 4: Pipeline Read
        #(CLK_PERIOD * 5);
        read_task(32'h0000_0004);
        read_task(32'h0000_0008);
        read_task(32'h0000_000C);
        
        #(CLK_PERIOD * 10);
        $display("Simulation Finished");
        $finish;
    end

    // Helper Tasks
    task write_task(input [31:0] addr, input [31:0] data, input [3:0] be);
        begin
            @(posedge clkb);
            wr_req  <= 1'b1;
            wr_addr <= addr;
            wr_data <= data;
            wr_be   <= be;
            @(posedge clkb);
            wr_req  <= 1'b0;
            wr_be   <= 0;
        end
    endtask

    task read_task(input [31:0] addr);
        begin
            @(posedge clkb);
            rd_req  <= 1'b1;
            rd_addr <= addr;
            @(posedge clkb);
            rd_req  <= 1'b0;
        end
    endtask

endmodule