//
// Send FA data to neighbours
//
module cellComm #(
    parameter ADC_COUNT     = 4,
    parameter FOFB_IDX_WIDTH = 9,
    parameter DATA_WIDTH    = 32) (
    input  wire                   sysClk, sysCsrStrobe, sysFaToggle,
    input  wire  [DATA_WIDTH-1:0] sysGpioData,
    output wire  [DATA_WIDTH-1:0] sysCsr,
    input  wire  [DATA_WIDTH-1:0] sysFA_X, sysFA_Y, sysFA_S,
    input  wire   [ADC_COUNT-1:0] sysClippedAdc,
    input  wire                   GTX_REFCLK,
    output wire                   CCW_TX_N, CCW_TX_P, CCW_LED0, CCW_LED1,
    input  wire                   CCW_RX_N, CCW_RX_P,
    output wire                   CW_TX_N,  CW_TX_P,  CW_LED0,  CW_LED1,
    input  wire                   CW_RX_N,  CW_RX_P,
    output reg   [DATA_WIDTH-1:0] ccwCRCfaults = 0,
    output reg   [DATA_WIDTH-1:0] cwCRCfaults = 0);

// Reduce ADC status to a single bit
wire sysIsClipping;
assign sysIsClipping = |sysClippedAdc;

//
// Microblaze interface
//
reg sysAuroraResetCW=1, sysGtResetCW=1, sysAuroraResetCCW=1, sysGtResetCCW=1;
reg                     sysFOFBvalid = 0;
reg [FOFB_IDX_WIDTH-1:0] sysFOFBindex = ~0;
assign sysCsr = { {16-1-FOFB_IDX_WIDTH{1'b0}}, sysFOFBvalid, sysFOFBindex,
                  1'b0, cwHardErr, cwSoftErr, cwFrameErr,
                  1'b0, ccwHardErr, ccwSoftErr, ccwFrameErr,
                  CW_LED1, CW_LED0, CCW_LED1, CCW_LED0,
                  sysAuroraResetCW, sysGtResetCW, sysAuroraResetCCW, sysGtResetCCW };
always @(posedge sysClk) begin
    if (sysCsrStrobe) begin
        sysGtResetCCW     <= sysGpioData[0];
        sysAuroraResetCCW <= sysGpioData[1];
        sysGtResetCW      <= sysGpioData[2];
        sysAuroraResetCW  <= sysGpioData[3];
        if (sysGpioData[FOFB_IDX_WIDTH+16+1]) begin
            sysFOFBvalid <= sysGpioData[FOFB_IDX_WIDTH+16];
            sysFOFBindex <= sysGpioData[FOFB_IDX_WIDTH+16-1:16];
        end
    end
end

///////////////////////////////////////////////////////////////////////////////
//                                 CCW link                                  //
///////////////////////////////////////////////////////////////////////////////
// Tx AXI
wire [31:0] ccwAxiTxTdata;
wire        ccwAxiTxTready;
wire        ccwAxiTxTvalid, ccwAxiTxTlast;
// Rx AXI
wire [31:0] ccwAxiRxTdata;
wire        ccwAxiRxTvalid, ccwAxiRxTlast, ccwAxiRxCRCvalid, ccwAxiRxCRCpass;
// Aurora status
wire ccwChannelUp, ccwHardErr, ccwSoftErr, ccwFrameErr;
// Aurora support
wire ccwTxOutClk, ccwUserClk, ccwSyncClk, ccwAuroraReset, ccwWarnCC, ccwDoCC;
wire ccwTxLock;

//
// CCW Aurora block
//
auroraCellCommCCW auroraCellCommCCW (.S_AXI_TX_TDATA(ccwAxiTxTdata),
                                     .S_AXI_TX_TKEEP(4'hF),
                                     .S_AXI_TX_TVALID(ccwAxiTxTvalid),
                                     .S_AXI_TX_TLAST(ccwAxiTxTlast),
                                     .S_AXI_TX_TREADY(ccwAxiTxTready),
                                     .M_AXI_RX_TDATA(ccwAxiRxTdata),
                                     .M_AXI_RX_TKEEP(),
                                     .M_AXI_RX_TVALID(ccwAxiRxTvalid),
                                     .M_AXI_RX_TLAST(ccwAxiRxTlast),
                                     .RXP(CCW_RX_P),
                                     .RXN(CCW_RX_N),
                                     .TXP(CCW_TX_P),
                                     .TXN(CCW_TX_N),
                                     .GT_REFCLK1(GTX_REFCLK),
                                     .HARD_ERR(ccwHardErr),
                                     .SOFT_ERR(ccwSoftErr),
                                     .FRAME_ERR(ccwFrameErr),
                                     .CRC_PASS_FAIL_N(ccwAxiRxCRCpass),
                                     .CRC_VALID(ccwAxiRxCRCvalid),
                                     .CHANNEL_UP(ccwChannelUp),
                                     .LANE_UP(),
                                     .WARN_CC(ccwWarnCC),
                                     .DO_CC(ccwDoCC),
                                     .USER_CLK(ccwUserClk),
                                     .SYNC_CLK(ccwSyncClk),
                                     .RESET(ccwAuroraReset),
                                     .POWER_DOWN(1'b0),
                                     .LOOPBACK(3'b000),
                                     .GT_RESET(sysGtResetCCW),
                                     .TX_OUT_CLK(ccwTxOutClk),
                                     .INIT_CLK_IN(sysClk),
                                     .RXEQMIX_IN(3'b111),
                                     .DADDR_IN(8'b0),
                                     .DCLK_IN(sysClk),
                                     .DEN_IN(1'b0),
                                     .DI_IN(16'b0),
                                     .DRDY_OUT(),
                                     .DRPDO_OUT(),
                                     .TX_LOCK(ccwTxLock),
                                     .DWE_IN(1'b0));

//
// CCW Aurora support
//
cellCommAuroraSupport auroraSupportCCW(.sysAuroraReset(sysAuroraResetCCW),
                                      .userClk(ccwUserClk),
                                      .auroraReset(ccwAuroraReset),
                                      .channelUp(ccwChannelUp),
                                      .channelRx(ccwAxiRxTlast),
                                      .sfpLEDs({CCW_LED1, CCW_LED0}));
wire ccwPllNotLocked;
auroraCellCommCCW_CLOCK_MODULE auroraCellCommCCW_CLOCK_MODULE(
                                        .GT_CLK(ccwTxOutClk),
                                        .GT_CLK_LOCKED(ccwTxLock),
                                        .USER_CLK(ccwUserClk),
                                        .SYNC_CLK(ccwSyncClk),
                                        .PLL_NOT_LOCKED(ccwPllNotLocked));
auroraCellCommCCW_STANDARD_CC_MODULE auroraCellCommCCW_STANDARD_CC_MODULE(
                                    .RESET(!ccwChannelUp),
                                    .WARN_CC(ccwWarnCC),
                                    .DO_CC(ccwDoCC),
                                    .PLL_NOT_LOCKED(ccwPllNotLocked),
                                    .USER_CLK(ccwUserClk));

///////////////////////////////////////////////////////////////////////////////
//                                 CW link                                  //
///////////////////////////////////////////////////////////////////////////////
// Tx AXI
wire [31:0] cwAxiTxTdata;
wire        cwAxiTxTready;
wire        cwAxiTxTvalid, cwAxiTxTlast;
// Rx AXI
wire [31:0] cwAxiRxTdata;
wire        cwAxiRxTvalid, cwAxiRxTlast, cwAxiRxCRCvalid, cwAxiRxCRCpass;
// Aurora status
wire cwChannelUp, cwHardErr, cwSoftErr, cwFrameErr;
// Aurora support
wire cwTxOutClk, cwUserClk, cwSyncClk, cwWarnCC, cwDoCC, cwAuroraReset;
wire cwTxLock;

//
// CW Aurora block
//
auroraCellCommCW auroraCellCommCW (.S_AXI_TX_TDATA(cwAxiTxTdata),
                                   .S_AXI_TX_TKEEP(4'hF),
                                   .S_AXI_TX_TVALID(cwAxiTxTvalid),
                                   .S_AXI_TX_TLAST(cwAxiTxTlast),
                                   .S_AXI_TX_TREADY(cwAxiTxTready),
                                   .M_AXI_RX_TDATA(cwAxiRxTdata),
                                   .M_AXI_RX_TKEEP(),
                                   .M_AXI_RX_TVALID(cwAxiRxTvalid),
                                   .M_AXI_RX_TLAST(cwAxiRxTlast),
                                   .RXP(CW_RX_P),
                                   .RXN(CW_RX_N),
                                   .TXP(CW_TX_P),
                                   .TXN(CW_TX_N),
                                   .GT_REFCLK1(GTX_REFCLK),
                                   .HARD_ERR(cwHardErr),
                                   .SOFT_ERR(cwSoftErr),
                                   .FRAME_ERR(cwFrameErr),
                                   .CRC_PASS_FAIL_N(cwAxiRxCRCpass),
                                   .CRC_VALID(cwAxiRxCRCvalid),
                                   .CHANNEL_UP(cwChannelUp),
                                   .LANE_UP(),
                                   .WARN_CC(cwWarnCC),
                                   .DO_CC(cwDoCC),
                                   .USER_CLK(cwUserClk),
                                   .SYNC_CLK(cwSyncClk),
                                   .RESET(cwAuroraReset),
                                   .POWER_DOWN(1'b0),
                                   .LOOPBACK(3'b000),
                                   .GT_RESET(sysGtResetCW),
                                   .TX_OUT_CLK(cwTxOutClk),
                                   .INIT_CLK_IN(sysClk),
                                   .RXEQMIX_IN(3'b111),
                                   .DADDR_IN(8'b0),
                                   .DCLK_IN(sysClk),
                                   .DEN_IN(1'b0),
                                   .DI_IN(16'b0),
                                   .DRDY_OUT(),
                                   .DRPDO_OUT(),
                                   .TX_LOCK(cwTxLock),
                                   .DWE_IN(1'b0));

//
// CW Aurora support
//
cellCommAuroraSupport auroraSupportCW(.sysAuroraReset(sysAuroraResetCW),
                                      .userClk(cwUserClk),
                                      .auroraReset(cwAuroraReset),
                                      .channelUp(cwChannelUp),
                                      .channelRx(cwAxiRxTlast),
                                      .sfpLEDs({CW_LED1, CW_LED0}));
wire cwPllNotLocked;
auroraCellCommCW_CLOCK_MODULE auroraCellCommCW_CLOCK_MODULE(
                                        .GT_CLK(cwTxOutClk),
                                        .GT_CLK_LOCKED(cwTxLock),
                                        .USER_CLK(cwUserClk),
                                        .SYNC_CLK(cwSyncClk),
                                        .PLL_NOT_LOCKED(cwPllNotLocked));
auroraCellCommCW_STANDARD_CC_MODULE auroraCellCommCW_STANDARD_CC_MODULE(
                                    .RESET(!cwChannelUp),
                                    .WARN_CC(cwWarnCC),
                                    .DO_CC(cwDoCC),
                                    .PLL_NOT_LOCKED(cwPllNotLocked),
                                    .USER_CLK(cwUserClk));

///////////////////////////////////////////////////////////////////////////////
//                             Data Forwarding                               //
///////////////////////////////////////////////////////////////////////////////
cellCommDataSwitch sendToCCW(.sysClk(sysClk),
                             .sysFaToggle(sysFaToggle),
                             .sysIsClipping(sysIsClipping),
                             .sysFA_X(sysFA_X),
                             .sysFA_Y(sysFA_Y),
                             .sysFA_S(sysFA_S),
                             .sysFOFBvalid(sysFOFBvalid),
                             .sysFOFBindex(sysFOFBindex),
                             .rxClk(cwUserClk),
                             .rxValid(cwAxiRxTvalid),
                             .rxLast(cwAxiRxTlast),
                             .rxData(cwAxiRxTdata),
                             .rxCRCvalid(cwAxiRxCRCvalid),
                             .rxCRCpass(cwAxiRxCRCpass),
                             .txClk(ccwUserClk),
                             .txAuroraChannelUp(ccwChannelUp),
                             .txValid(ccwAxiTxTvalid),
                             .txLast(ccwAxiTxTlast),
                             .txData(ccwAxiTxTdata),
                             .txReady(ccwAxiTxTready));

always @(posedge cwUserClk) begin
    if (cwAxiRxCRCvalid && !cwAxiRxCRCpass) cwCRCfaults <= cwCRCfaults + 1;
end

cellCommDataSwitch sendToCW(.sysClk(sysClk),
                            .sysFaToggle(sysFaToggle),
                            .sysIsClipping(sysIsClipping),
                            .sysFA_X(sysFA_X),
                            .sysFA_Y(sysFA_Y),
                            .sysFA_S(sysFA_S),
                            .sysFOFBvalid(sysFOFBvalid),
                            .sysFOFBindex(sysFOFBindex),
                            .rxClk(ccwUserClk),
                            .rxValid(ccwAxiRxTvalid),
                            .rxLast(ccwAxiRxTlast),
                            .rxData(ccwAxiRxTdata),
                            .rxCRCvalid(ccwAxiRxCRCvalid),
                            .rxCRCpass(ccwAxiRxCRCpass),
                            .txClk(cwUserClk),
                            .txAuroraChannelUp(cwChannelUp),
                            .txValid(cwAxiTxTvalid),
                            .txLast(cwAxiTxTlast),
                            .txData(cwAxiTxTdata),
                            .txReady(cwAxiTxTready));

always @(posedge ccwUserClk) begin
    if (ccwAxiRxCRCvalid && !ccwAxiRxCRCpass) ccwCRCfaults <= ccwCRCfaults + 1;
end
endmodule
