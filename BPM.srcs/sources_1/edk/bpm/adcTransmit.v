//
// Transmit ADC values to SFP
// Allows other equipment to store or processes raw ADC values.
// Nets starting with 'adc' are in the adcClk domain.
// Other nets are in the Aurora transmit clock domain.
module adcTransmit #(
    parameter ADC_WIDTH  = 16,
    parameter NADC       = 4,
    parameter DATA_WIDTH = 32
    ) (
    input                            sysClk,
    input                            sysCsrStrobe,
    input           [DATA_WIDTH-1:0] sysGpioData,
    output          [DATA_WIDTH-1:0] sysCsr,

    input                            adcClk,
    input       [NADC*ADC_WIDTH-1:0] adcRawData,
    input                            adcTurnMarker,

    input                            GTX_REFCLK,
    output wire                      TXD_LANE_1_P,
    output wire                      TXD_LANE_1_N,
    output wire                      TXD_LANE_2_P,
    output wire                      TXD_LANE_2_N);

// AXI is twice as wide as ADC stream
localparam ADC_STREAM_WIDTH = NADC * ADC_WIDTH;
localparam AXI_WIDTH        = 2 * ADC_STREAM_WIDTH;
wire [ADC_STREAM_WIDTH-1:0] adcStream = {
                    adcRawData[ADC_STREAM_WIDTH-1-:ADC_WIDTH-1], adcTurnMarker,
                    adcRawData[ADC_STREAM_WIDTH-ADC_WIDTH-1:0] };
reg [ADC_STREAM_WIDTH-1:0] adcLatch;
reg                        adcStore = 0;
always @(posedge adcClk) begin
    adcStore <= !adcStore;
    adcLatch <= adcStream;
end

// Control/status register
reg sysAuroraReset = 1, sysPMAinit = 1;
wire [1:0] TX_LANE_UP;
wire       TX_CHANNEL_UP, TX_HARD_ERR, TX_SOFT_ERR;
wire       MMCM_NOT_LOCKED;
assign sysCsr = { 16'b0,
                  1'b0, MMCM_NOT_LOCKED, TX_HARD_ERR, TX_SOFT_ERR,
                  1'b0, TX_CHANNEL_UP, TX_LANE_UP,
                  6'b0, sysAuroraReset, sysPMAinit };
always @(posedge sysClk) begin
    if (sysCsrStrobe) begin
        sysPMAinit     <= sysGpioData[0];
        sysAuroraReset <= sysGpioData[1];
    end
end

// Generate assorted Aurora clocks
wire TX_OUT_CLK, auroraClk, shimClk, syncClk;
aurora_adc_raw_CLOCK_MODULE adcRawClocks (
    .CLK(TX_OUT_CLK),
    .CLK_LOCKED(1'b1),
    .USER_CLK(auroraClk),
    .SYNC_CLK(syncClk),
    .SHIM_CLK(shimClk),
    .MMCM_NOT_LOCKED(MMCM_NOT_LOCKED));

// Move ADC data into Aurora transmitter clock domain
wire auroraTVALID, auroraTREADY;
wire [AXI_WIDTH-1:0] auroraTDATA;
fifo_adc_raw fifoRawADC (
  .m_aclk(auroraClk),
  .s_aclk(adcClk),
  .s_aresetn(1'b1),
  .s_axis_tvalid(adcStore),
  .s_axis_tready(),
  .s_axis_tdata({adcStream, adcLatch}),
  .m_axis_tvalid(auroraTVALID),
  .m_axis_tready(auroraTREADY),
  .m_axis_tdata(auroraTDATA));

// Send ADC data
aurora_adc_raw auroraRawADC (
    .S_AXI_TX_TDATA(auroraTDATA), 
    .S_AXI_TX_TVALID(auroraTVALID), 
    .S_AXI_TX_TREADY(auroraTREADY), 
    .DO_CC(1'b0), 
    .TXP({TXD_LANE_2_P, TXD_LANE_1_P}), 
    .TXN({TXD_LANE_2_N, TXD_LANE_1_N}), 
    .GTXQ3(GTX_REFCLK), 
    .TX_HARD_ERR(TX_HARD_ERR), 
    .TX_SOFT_ERR(TX_SOFT_ERR), 
    .TX_CHANNEL_UP(TX_CHANNEL_UP), 
    .TX_LANE_UP(TX_LANE_UP), 
    .MMCM_NOT_LOCKED(MMCM_NOT_LOCKED), 
    .USER_CLK(auroraClk), 
    .SYNC_CLK(syncClk), 
    .SHIM_CLK(shimClk), 
    .RESET(sysAuroraReset), 
    .POWER_DOWN(1'b0), 
    .PMA_INIT(sysPMAinit), 
    .DRP_CLK_IN(sysClk), 
    .DRPADDR_IN(8'b0), 
    .DRPDI_IN(16'b0), 
    .DRPDO_OUT(), 
    .DRPRDY_OUT(), 
    .DRPEN_IN(1'b0), 
    .DRPWE_IN(1'b0), 
    .DRPDO_OUT_LANE1(), 
    .DRPRDY_OUT_LANE1(), 
    .DRPEN_IN_LANE1(1'b0), 
    .DRPWE_IN_LANE1(1'b0), 
    .MMCM_LOCK(), 
    .TX_OUT_CLK(TX_OUT_CLK));

endmodule
