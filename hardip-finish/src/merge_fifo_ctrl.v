module merge_fifo_ctrl #(
    parameter DATA_WIDTH = 32,
    parameter PAGE_BYTES = 16384
)(
    input  wire                    clk,
    input  wire                    rstn,

(* MARK_DEBUG="true" *)    input  wire                    rd_capture_en,
    output wire                    rd_capture_ready,
    input  wire                    rd_tvalid,
(* MARK_DEBUG="true" *)    input  wire [DATA_WIDTH-1:0]   rd_tdata,
(* MARK_DEBUG="true" *)    input  wire                    rd_tlast,

(* MARK_DEBUG="true" *)    input  wire                    wr_feed_en,
    input  wire                    wr_tready,
    output wire                    wr_tvalid,
(* MARK_DEBUG="true" *)    output wire [DATA_WIDTH-1:0]   wr_tdata,
(* MARK_DEBUG="true" *)    output wire                    wr_tlast,

    output reg                     page_fill_done,
    output reg                     page_drain_done,
    output wire [23:0]             fifo_data_avail,
    output wire                    fifo_empty
);

wire                    wr_rst_busy;
wire                    rd_rst_busy;
wire                    s_aclk;
wire                    s_aresetn;
wire                    s_axis_tvalid;
wire                    s_axis_tready;
wire [DATA_WIDTH-1:0]   s_axis_tdata;
wire                    s_axis_tlast;
wire                    m_axis_tvalid_i;
wire                    m_axis_tready;
wire [DATA_WIDTH-1:0]   m_axis_tdata_i;
wire                    m_axis_tlast_i;
(* MARK_DEBUG="true" *) wire [11:0]             axis_data_count;

assign s_aclk        = clk;
assign s_aresetn     = rstn;
assign s_axis_tvalid = rd_capture_en & rd_tvalid;
assign s_axis_tdata  = rd_tdata;
assign s_axis_tlast  = rd_tlast;

assign rd_capture_ready = s_axis_tready;

assign m_axis_tready = wr_feed_en & wr_tready;
assign wr_tvalid     = wr_feed_en & m_axis_tvalid_i;
assign wr_tdata      = m_axis_tdata_i;
assign wr_tlast      = m_axis_tlast_i;

assign fifo_data_avail = {12'd0, axis_data_count} << 2;
assign fifo_empty      = (axis_data_count == 12'd0);

merge_fifo fifo0 (
  .wr_rst_busy(wr_rst_busy),          // output wire wr_rst_busy
  .rd_rst_busy(rd_rst_busy),          // output wire rd_rst_busy
  .s_aclk(s_aclk),                    // input wire s_aclk
  .s_aresetn(s_aresetn),              // input wire s_aresetn
  .s_axis_tvalid(s_axis_tvalid),      // input wire s_axis_tvalid
  .s_axis_tready(s_axis_tready),      // output wire s_axis_tready
  .s_axis_tdata(s_axis_tdata),        // input wire [31 : 0] s_axis_tdata
  .s_axis_tlast(s_axis_tlast),        // input wire s_axis_tlast
  .m_axis_tvalid(m_axis_tvalid_i),    // output wire m_axis_tvalid
  .m_axis_tready(m_axis_tready),      // input wire m_axis_tready
  .m_axis_tdata(m_axis_tdata_i),      // output wire [31 : 0] m_axis_tdata
  .m_axis_tlast(m_axis_tlast_i),      // output wire m_axis_tlast
  .axis_data_count(axis_data_count)  // output wire [11 : 0] axis_data_count
);

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        page_fill_done  <= 1'b0;
        page_drain_done <= 1'b0;
    end else begin
        page_fill_done  <= rd_capture_en & rd_tvalid & s_axis_tready & rd_tlast;
        page_drain_done <= wr_feed_en & m_axis_tvalid_i & wr_tready & m_axis_tlast_i;
    end
end

endmodule
