//////////////////////////////////////////////////////////////////////////////
//
// Send or forward data to AXI stream.
//
// Nets beginning with 'sys' are in the sysClk domain.
// Nets beginning with 'rx' are in the receiver Aurora user clock domain.
// Nets beginning with 'tx' are in the transmitter Aurora user clock domain.
//
module cellCommDataSwitch #(
    parameter DATA_WIDTH    = 32,
    parameter FOFB_IDX_WIDTH = 9) (
    input  wire                      sysClk,
    input  wire                      sysFaToggle, sysIsClipping,
    input  wire     [DATA_WIDTH-1:0] sysFA_X, sysFA_Y, sysFA_S,
    input  wire                      sysFOFBvalid,
    input  wire [FOFB_IDX_WIDTH-1:0] sysFOFBindex,
    input  wire                      rxClk, rxValid, rxLast,
    input  wire                      rxCRCvalid, rxCRCpass,
    input  wire     [DATA_WIDTH-1:0] rxData,
    input  wire                      txClk, txReady, txAuroraChannelUp,
    output wire                      txValid, txLast,
    output wire     [DATA_WIDTH-1:0] txData);

// Data to send FIFO
wire                  txSendValid, txSendLast;
wire [DATA_WIDTH-1:0] txSendData;

// Data from receive FIFO
wire        txFwValid, txFwLast,txFwReady;
wire [31:0] txFwData;

// Fast orbit feedback identification number
wire                     txFOFBvalid;
wire [FOFB_IDX_WIDTH-1:0] txFOFBindex;
forwardData #(.DATA_WIDTH(1+FOFB_IDX_WIDTH)) cellFOFB (
                                        .inClk(sysClk),
                                        .inData({sysFOFBvalid, sysFOFBindex}),
                                        .outClk(txClk),
                                        .outData({txFOFBvalid, txFOFBindex}));

//
// Send or forward data
//
reg       txLocActive = 0, txFwActive = 0;
reg [5:0] txFwWatchdog;
reg [1:0] txCount;
(* ASYNC_REG="TRUE" *) reg txFaToggle_m = 0, txFaToggle = 0;
reg txFaMatch = 0;
(* ASYNC_REG="TRUE" *) reg txIsClipping_m = 0, txIsClipping = 0;
assign txFwReady = txFwActive || !txAuroraChannelUp;
// A one in the most significant bit of final word indicates an invalid packet
wire [31:0] rxFwData;
assign rxFwData[30:0] = rxData[30:0];
assign rxFwData[31] = rxLast && (!rxCRCvalid || !rxCRCpass) ? 1 : rxData[31];

reg                  txLocValid = 0, txLocLast = 0;
reg [DATA_WIDTH-1:0] txLocData;

wire [DATA_WIDTH-1:0] txPkHeader;
assign txPkHeader = { 16'hA5BE, {16-FOFB_IDX_WIDTH{1'b0}}, txFOFBindex };

// Multiplex values into transmitter
assign {txSendValid, txSendLast, txSendData} = txFwActive ?
                                    { txFwValid,  txFwLast,  txFwData} :
                                    {txLocValid, txLocLast, txLocData};

always @(posedge txClk) begin
    txIsClipping_m <= sysIsClipping;
    txIsClipping <= txIsClipping_m;
    txFaToggle_m <= sysFaToggle;
    txFaToggle <= txFaToggle_m;
    if ((txFaMatch != txFaToggle) && !txLocActive && !txFwActive) begin
        txFaMatch <= txFaToggle;
        if (txFOFBvalid && txAuroraChannelUp) begin
            txLocActive <= 1;
            txCount <= 0;
            txLocData <= txPkHeader;
            txLocValid <= 1;
        end
    end
    else if (txLocActive) begin
        txCount <= txCount + 1;
        case (txCount)
        0: begin
            txLocData <= sysFA_X;
           end
        1: begin
            txLocData <= sysFA_Y;
           end
        2: begin
            txLocData <= {1'b0, txIsClipping, sysFA_S[DATA_WIDTH-3:0]};
            txLocLast <= 1;
           end
        3: begin
            txLocActive <= 0;
            txLocLast <= 0;
            txLocValid <= 0;
           end
        default: ;
        endcase
    end
    else begin
        if (txFwActive) begin
            txFwWatchdog <= txFwWatchdog - 1;
            if (txFwLast || (txFwWatchdog == 0)) begin
                txFwActive <= 0;
            end
        end
        else begin
            if (txFwValid) begin
                txFwActive <=1;
                txFwWatchdog <= ~0;
            end
        end
    end
end

//
// FIFO outgoing data to relieve us of the need to deal
// with back pressure from the Aurora transmitter.
//
cellCommSendFIFO cellCommSendFIFO (
              .s_aclk(txClk),                // input s_aclk
              .s_aresetn(1'b1),              // input s_aresetn
              .s_axis_tvalid(txSendValid),   // input s_axis_tvalid
              .s_axis_tready(),              // output s_axis_tready
              .s_axis_tdata(txSendData),     // input [31 : 0] s_axis_tdata
              .s_axis_tlast(txSendLast),     // input s_axis_tlast
              .m_axis_tvalid(txValid),       // output m_axis_tvalid
              .m_axis_tready(txReady),       // input m_axis_tready
              .m_axis_tdata(txData),         // output [31 : 0] m_axis_tdata
              .m_axis_tlast(txLast));        // output m_axis_tlast

//
// FIFO incoming data to get into the 'tx' clock domain and
// to provide buffering when a packet arrvies while we are
// already busy sending our data.
//
cellCommFIFO cellCommFIFO (
              .m_aclk(txClk),                // input m_aclk
              .s_aclk(rxClk),                // input s_aclk
              .s_aresetn(1'b1),              // input s_aresetn
              .s_axis_tvalid(rxValid),       // input s_axis_tvalid
              .s_axis_tready(),              // output s_axis_tready
              .s_axis_tdata(rxFwData),       // input [31 : 0] s_axis_tdata
              .s_axis_tlast(rxLast),         // input s_axis_tlast
              .m_axis_tvalid(txFwValid),     // output m_axis_tvalid
              .m_axis_tready(txFwReady),     // input m_axis_tready
              .m_axis_tdata(txFwData),       // output [31 : 0] m_axis_tdata
              .m_axis_tlast(txFwLast));      // output m_axis_tlast

endmodule
