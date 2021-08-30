//----------------------------------------------------------------------------//
//                    BEAM POSITION MONITOR TOP-LEVEL MODULE                  //
//----------------------------------------------------------------------------//

module bpmTop #(
    parameter SYSCLK_RATE      = 100000000,
    parameter MAG_WIDTH        = 26,
    parameter ADC_COUNT        = 4,
    parameter ADC_WIDTH        = 16,
    parameter SFP_COUNT        = 6
    ) (
    input CLK_P, CLK_N,
    input GTX_REFCLK_P, GTX_REFCLK_N,

    output        ddr_memory_we_n,
    output        ddr_memory_ras_n,
    output        ddr_memory_odt,
    inout [7:0]   ddr_memory_dqs_n,
    inout [7:0]   ddr_memory_dqs,
    inout [63:0]  ddr_memory_dq,
    output [7:0]  ddr_memory_dm,
    output        ddr_memory_ddr3_rst,
    output        ddr_memory_cs_n,
    output [1:0]  ddr_memory_clk_n,
    output [1:0]  ddr_memory_clk,
    output        ddr_memory_cke,
    output        ddr_memory_cas_n,
    output [2:0]  ddr_memory_ba,
    output [14:0] ddr_memory_addr,

    output        RS232_Uart_1_sout,
    input         RS232_Uart_1_sin,

    output        Linear_Flash_we_n,
    output        Linear_Flash_oe_n,
    inout [15:0]  Linear_Flash_data,
    output        Linear_Flash_ce_n,
    output [25:0] Linear_Flash_address,

    output       ETHERNET_TX_ER,
    output       ETHERNET_TX_EN,
    output       ETHERNET_TX_CLK,
    output [7:0] ETHERNET_TXD,
    input        ETHERNET_RX_ER,
    input        ETHERNET_RX_DV,
    input        ETHERNET_RX_CLK,
    input [7:0]  ETHERNET_RXD,
    output       ETHERNET_PHY_RST_N,
    input        ETHERNET_MII_TX_CLK,
    inout        ETHERNET_MDIO,
    output       ETHERNET_MDC,
    output       PHY_CLK_25_MHZ,
    input        PHY_LED_LINK100_N,
    input        PHY_LED_LINK1000_N,
    input        PHY_LED_DUPLEX_N,
    input        PHY_LED_RX_N,
    input        PHY_LED_TX_N,
    output       RJ45_LED1,
    output       RJ45_LED2P,
    output       RJ45_LED2N,

    input      [SFP_COUNT-1:0] SFP_RXD_P, SFP_RXD_N,
    output     [SFP_COUNT-1:0] SFP_TXD_P, SFP_TXD_N,
    output     [SFP_COUNT-1:0] SFP_IIC_SCL,
    inout      [SFP_COUNT-1:0] SFP_IIC_SDA,
    output [(2*SFP_COUNT)-1:0] SFP_LED,

    output AFE_BUFFER_ENABLE,
    output AFE_REFCLK_P, AFE_REFCLK_N,
    output AFE_PLL_SPI_SCLK,
    output AFE_PLL_SPI_MOSI,
    input  AFE_PLL_SPI_MISO,
    output AFE_PLL_SPI_SSEL,
    output AFE_PLL_FUNC,
    input  AFE_PLL_STATUS,
    input  ADC_CLK_P, ADC_CLK_N,

    output FP_OUT0_P, FP_OUT0_N,
    output FP_OUT1_P, FP_OUT1_N,

    input                 ADC0_CLK_P,  ADC0_CLK_N,
    input [ADC_WIDTH-1:0] ADC0_DATA_P, ADC0_DATA_N,
    input                 ADC1_CLK_P,  ADC1_CLK_N,
    input [ADC_WIDTH-1:0] ADC1_DATA_P, ADC1_DATA_N,
    input                 ADC2_CLK_P,  ADC2_CLK_N,
    input [ADC_WIDTH-1:0] ADC2_DATA_P, ADC2_DATA_N,
    input                 ADC3_CLK_P,  ADC3_CLK_N,
    input [ADC_WIDTH-1:0] ADC3_DATA_P, ADC3_DATA_N,

    input DFE_FAN_TACH,

    output DFE_TEMPERATURE_SCL, AFE_TEMPERATURE_0_SCL, AFE_TEMPERATURE_1_SCL,
    inout  DFE_TEMPERATURE_SDA, AFE_TEMPERATURE_0_SDA, AFE_TEMPERATURE_1_SDA,

    output AFE_POWER_SCL,
    inout  AFE_POWER_SDA,

    output                 AFE_ATTEN_SCL, AFE_ATTEN_SDA,
    output [ADC_COUNT-1:0] AFE_ATTEN_LE,

    output wire ADC_RAND, ADC_DITH,
    output reg  ADC_SHDN = 0,
    output reg  ADC_PGA = 0,

    input  wire [19:0] DBG,
    output wire  [7:0] DBG_LED,
    output wire  [3:0] FP_LED
  );

/*
 * Site-specific configuration parameters.
 *
 * These values set the sizes of assorted fixed-point arithmetic FPGA
 * registers.  The values here need not be exact, but if they're too
 * far removed from reality it can result in overflows or excessive
 * quantization.  For example, it has been shown that a system built
 * with ALS settings works just fine for NSLS-II.  So in most cases
 * it's probably pretty safe to not worry about tweaking these at all.
 */

parameter SITE_ALS  = 0;
parameter SITE_NSLS = 1;

`include "site.v"

parameter SITE_SAMPLES_PER_TURN     = (SITE == SITE_ALS)  ? 77      :
                                      (SITE == SITE_NSLS) ? 310     : 0;
parameter SITE_CIC_FA_DECIMATE      = (SITE == SITE_ALS)  ? 76      :
                                      (SITE == SITE_NSLS) ? 38      : 0;
parameter SITE_CIC_SA_DECIMATE      = (SITE == SITE_ALS)  ? 1000    :
                                      (SITE == SITE_NSLS) ? 1000    : 0;
parameter SITE_CIC_STAGES           = (SITE == SITE_ALS)  ? 2       :
                                      (SITE == SITE_NSLS) ? 2       : 0;

//
// Indices into general-purpose I/O block.
// GPIO_IDX_xxxx parameters must match C #defines.
//
`include "gpioIDX.v"

//
// General-purpose I/O block
//
wire [31:0]                    GPIO_IN[0:GPIO_IDX_COUNT-1];
wire [31:0]                    GPIO_OUT;
wire [GPIO_IDX_COUNT-1:0]      GPIO_STROBES;
wire [(GPIO_IDX_COUNT*32)-1:0] GPIO_IN_FLATTENED;
genvar i;
generate
for (i = 0 ; i < GPIO_IDX_COUNT ; i = i + 1) begin : gpio_flatten
    assign GPIO_IN_FLATTENED[ (i*32)+31 : (i*32)+0 ] = GPIO_IN[i];
end
endgenerate

//
// Build date
//
`include "firmwareDate.v"
assign GPIO_IN[GPIO_IDX_FIRMWARE_DATE] = FIRMWARE_DATE;

//
// The three clock domains
// Net names starting with 'adc' or 'evr' are in those clock domains.
//
wire sysClk, adcClk, evrClk;

//
// Other clocks
//
wire clk200;

//
// Unused front panel LEDs
//
assign FP_LED[3:2] = { 2'b0 };
assign SFP_LED[11:6] = 0;

//
// Enable AFE whenever DFE is running.
//
assign AFE_BUFFER_ENABLE = 1;

//
// ADC clock from AFE
//
wire [4:0] adcDelayTap;
wire adcDelayCtrlLocked;
wire EVR_LossOfLock;
adcClkin adcClkin(.ADC_CLK_P(ADC_CLK_P),
                  .ADC_CLK_N(ADC_CLK_N),
                  .adcClk(adcClk),
                  .sysClk(sysClk),
                  .gpioStrobe(GPIO_STROBES[GPIO_IDX_CLOCK_STATUS]),
                  .gpioData(GPIO_OUT),
                  .delayTap(adcDelayTap),
                  .delayCtrlRefClk200(clk200),
                  .delayCtrlLocked(adcDelayCtrlLocked));
wire evrFaSynced, evrSaSynced, evrHeartbeatMarker;
assign GPIO_IN[GPIO_IDX_CLOCK_STATUS] = {
         16'b0,
         adcDelayCtrlLocked, 2'b0, adcDelayTap,
         sysAfePllUnlocked, evrFaSynced, evrSaSynced, sysAfePllUnlocked_latched,
         1'b0, afeRefClkSyncStatus, EVR_LossOfLock, adcLoSynced };

//
// ADC channels
//
wire                   adcUseThisSample, adcExceedsThreshold;
wire            [31:0] gpioAdcReadoutCsr;
wire   [ADC_COUNT-1:0] clkStates, clippedAdc;
wire [4*ADC_WIDTH-1:0] adcRawData;
wire   [ADC_WIDTH-1:0] adc0, adc1, adc2, adc3;
wire   [ADC_WIDTH-1:0] peakAdc0, peakAdc1, peakAdc2, peakAdc3;
assign GPIO_IN[GPIO_IDX_ADC_10_PEAK] = { peakAdc1, peakAdc0 };
assign GPIO_IN[GPIO_IDX_ADC_32_PEAK] = { peakAdc3, peakAdc2 };
assign GPIO_IN[GPIO_IDX_SELFTRIGGER_CSR] = { 3'b0, prelimProcOverflow,
                                             clippedAdc,
                                             gpioAdcReadoutCsr[23:0] };
adcReadout #(.QUANTIZE("true"))
  adcReadout(.adcClk(adcClk),
             .ADC0_CLK_P(ADC0_CLK_P),
             .ADC0_CLK_N(ADC0_CLK_N),
             .ADC0_DATA_P(ADC0_DATA_P),
             .ADC0_DATA_N(ADC0_DATA_N),
             .ADC1_CLK_P(ADC1_CLK_P),
             .ADC1_CLK_N(ADC1_CLK_N),
             .ADC1_DATA_P(ADC1_DATA_P),
             .ADC1_DATA_N(ADC1_DATA_N),
             .ADC2_CLK_P(ADC2_CLK_P),
             .ADC2_CLK_N(ADC2_CLK_N),
             .ADC2_DATA_P(ADC2_DATA_P),
             .ADC2_DATA_N(ADC2_DATA_N),
             .ADC3_CLK_P(ADC3_CLK_P),
             .ADC3_CLK_N(ADC3_CLK_N),
             .ADC3_DATA_P(ADC3_DATA_P),
             .ADC3_DATA_N(ADC3_DATA_N),
             .clkStates(clkStates),
             .adcRawData(adcRawData),
             .adc0(adc0),
             .adc1(adc1),
             .adc2(adc2),
             .adc3(adc3),
             .adcUseThisSample(adcUseThisSample),
             .adcExceedsThreshold(adcExceedsThreshold),
             .sysClk(sysClk),
             .clippedAdc(clippedAdc),
             .peak0(peakAdc0),
             .peak1(peakAdc1),
             .peak2(peakAdc2),
             .peak3(peakAdc3),
             .gpioStrobe(GPIO_STROBES[GPIO_IDX_SELFTRIGGER_CSR]),
             .gpioData(GPIO_OUT),
             .gpioCSR(gpioAdcReadoutCsr),
             .evrHeartbeatMarker(evrHeartbeatMarker));

//
// Event receiver
// Signals beginning with EVR_ are in event receiver clock domain.
//
wire  [7:0] EVR_triggerBus;
wire [63:0] EVR_timestamp;
assign SFP_LED[0] = !EVR_LossOfLock;
assign evrHeartbeatMarker = EVR_triggerBus[0];
assign SFP_LED[1] = evrHeartbeatMarker;

//
// Create slow (SA) and fast (FA) acquistion triggers
// based on event system trigger 0 (heartbeat).
//
wire evrFaMarker, evrSaMarker;
wire [31:0] sysFAstatus, sysSAstatus;
acqSync acqSync(
    .sysClk(sysClk),
    .sysGPIO_OUT(GPIO_OUT),
    .sysFAstrobe(GPIO_STROBES[GPIO_IDX_EVR_FA_RELOAD]),
    .sysSAstrobe(GPIO_STROBES[GPIO_IDX_EVR_SA_RELOAD]),
    .sysFAstatus(sysFAstatus),
    .sysSAstatus(sysSAstatus),
    .evrClk(evrClk),
    .evrHeartbeat(evrHeartbeatMarker),
    .evrFaMarker(evrFaMarker),
    .evrSaMarker(evrSaMarker));
assign GPIO_IN[GPIO_IDX_EVR_FA_RELOAD] = sysFAstatus;
assign GPIO_IN[GPIO_IDX_EVR_SA_RELOAD] = sysSAstatus;
assign evrFaSynced = sysFAstatus[31];
assign evrSaSynced = sysSAstatus[31];

//
//
// Forward the EVR trigger bus and time stamp to the system clock domain.
//
wire [63:0] timestamp;
wire [71:0] EVR_forward, forward_EVR;
assign EVR_forward = { EVR_triggerBus, EVR_timestamp };
forwardData #(.DATA_WIDTH(72))
  forwardEVR(.inClk(evrClk),
             .inData(EVR_forward),
             .outClk(sysClk),
             .outData(forward_EVR));
assign timestamp = forward_EVR[63:0];

//
// Waveform recorder triggers
// Stretch soft trigger to ensure it is seen across clock boundaries
//
reg [3:0] softTriggerStretch;
reg       softTrigger;
always @(posedge sysClk) begin
    if (GPIO_STROBES[GPIO_IDX_WFR_SOFT_TRIGGER]) begin
        softTrigger <= 1;
        softTriggerStretch <= ~0;
    end
    else if (softTriggerStretch) begin
        softTriggerStretch <= softTriggerStretch - 1;
    end
    else begin
        softTrigger <= 0;
    end
end
wire [7:0] recorderTriggerBus = { forward_EVR[71:68],
                                  1'b0,
                                  sysSingleTrig,
                                  lossOfBeamTrigger,
                                  softTrigger };

//
// Diagnostic pins now used for AFE/DFE serial number
//
assign DBG_LED = { 4'b0, clippedAdc };
assign GPIO_IN[GPIO_IDX_SERIAL_NUMBERS] = { 12'b0, DBG };

//
// AFE reference clock
//
wire [31:0] afeRefclkCSR;
wire        evrAfeRef;
wire        afeRefClkSyncStatus;
assign GPIO_IN[GPIO_IDX_AFE_REFCLK_CSR] = afeRefclkCSR;
assign afeRefClkSyncStatus = afeRefclkCSR[16];
afeRefClkGenerator afeRefClkGenerator(
                              .sysClk(sysClk),
                              .writeData(GPIO_OUT),
                              .csrStrobe(GPIO_STROBES[GPIO_IDX_AFE_REFCLK_CSR]),
                              .csr(afeRefclkCSR),
                              .evrClk(evrClk),
                              .evrFiducial(evrHeartbeatMarker),
                              .evrAfeRef(evrAfeRef));
OBUFDS afeRefClkBuf(.I(evrAfeRef), .O(AFE_REFCLK_P), .OB(AFE_REFCLK_N));
OBUFDS fp0Out(.I(evrAfeRef), .O(FP_OUT0_P), .OB(FP_OUT0_N));

//
// Ethernet RJ45 LEDs
// LED 1 -- On if link is full-duplex 1000BaseT (LED on when FPGA pin LOW).
// LED 2 -- Traffic indicator
//
assign RJ45_LED1 = !(PHY_LED_LINK1000_N==0 && PHY_LED_DUPLEX_N==0);
ethernetTrafficIndicator ethernetTrafficIndicator(.sysClk(sysClk),
                                                  .PHY_LED_RX_N(PHY_LED_RX_N),
                                                  .PHY_LED_TX_N(PHY_LED_TX_N),
                                                  .RJ45_LED2P(RJ45_LED2P),
                                                  .RJ45_LED2N(RJ45_LED2N));

//
// Front panel RED LED
// Blink if event receiver unsynchronized else on if AFE PLL unlocked else off.
//
assign FP_LED[0] = EVR_LossOfLock ? blinker : AFE_PLL_STATUS;

//
// DFE fan tachometer
//
wire [15:0]DFE_FAN_RPM;
fanMonitor dfeFanTachometer(.clk(sysClk),
                            .reset(1'b0),
                            .rpm(DFE_FAN_RPM),
                            .tach(DFE_FAN_TACH));

//
// Simple counter for fine timing delays and general-purpose timed values
//
reg [31:0] sysClkCounter = 0;
reg [31:0] secondsSinceBoot = 0;
reg [$clog2(SYSCLK_RATE-1)-1:0] sysClkDivider = 0;
always @(posedge sysClk) begin
    sysClkCounter <= sysClkCounter + 1;
    if (sysClkDivider == 0) begin
        sysClkDivider <= SYSCLK_RATE-1;
        secondsSinceBoot <= secondsSinceBoot + 1;
    end
    else begin
        sysClkDivider <= sysClkDivider - 1;
    end
end
wire blinker;
assign blinker = sysClkCounter[26];
assign GPIO_IN[GPIO_IDX_SYSCLK_COUNTER]     = sysClkCounter;
assign GPIO_IN[GPIO_IDX_SECONDS_SINCE_BOOT] = secondsSinceBoot;

//
// AFE AD9510 PLL
//
assign AFE_PLL_FUNC = 1; // Drive AFE PLL FUNCTION pin (RESETB) high.
wire       AFE_PLL_BUSY;
wire [7:0] AFE_PLL_READ_DATA;
ad9510 ad9510 (.clk(sysClk),
               .writeStrobe(GPIO_STROBES[GPIO_IDX_AFE_PLL_SPI]&&!GPIO_OUT[31]),
               .writeData(GPIO_OUT[23:0]),
               .busy(AFE_PLL_BUSY),
               .readData(AFE_PLL_READ_DATA),
               .SPI_CLK(AFE_PLL_SPI_SCLK),
               .SPI_SSEL(AFE_PLL_SPI_SSEL),
               .SPI_MOSI(AFE_PLL_SPI_MOSI),
               .SPI_MISO(AFE_PLL_SPI_MISO));
assign GPIO_IN[GPIO_IDX_AFE_PLL_SPI] = { 12'b0, clkStates,
                                         AFE_PLL_BUSY, sysAfePllUnlocked,
                                         6'b0, AFE_PLL_READ_DATA };
(* ASYNC_REG="TRUE" *) reg sysAfePllUnlocked_m=0;
reg sysAfePllUnlocked=0, sysAfePllUnlocked_latched=0;
always @(posedge sysClk) begin
    sysAfePllUnlocked_m <= AFE_PLL_STATUS;
    sysAfePllUnlocked   <= sysAfePllUnlocked_m;
    if (GPIO_STROBES[GPIO_IDX_AFE_PLL_SPI] && GPIO_OUT[31]) begin
        sysAfePllUnlocked_latched <= 0;
    end
    else if (sysAfePllUnlocked) begin
        sysAfePllUnlocked_latched <= 1;
    end
end

//
// DFE temperature monitors
//
wire [15:0] DFE_TEMP0, DFE_TEMP1, DFE_TEMP2, DFE_TEMP3;
adt7410 #(.BIT_RATE(20000)) dfeTemperature(.clk(sysClk),
                                            .temperatures({DFE_TEMP0,
                                                           DFE_TEMP1,
                                                           DFE_TEMP2,
                                                           DFE_TEMP3}),
                                           .SCL(DFE_TEMPERATURE_SCL),
                                           .SDA(DFE_TEMPERATURE_SDA));

//
// AFE temperature monitors
//
wire [15:0] AFE_TEMP0, AFE_TEMP1, AFE_TEMP2, AFE_TEMP3;
adt7410 #(.BIT_RATE(20000)) afeTemperature0(.clk(sysClk),
                                            .temperatures({AFE_TEMP0,
                                                           AFE_TEMP1,
                                                           AFE_TEMP2,
                                                           AFE_TEMP3}),
                                            .SCL(AFE_TEMPERATURE_0_SCL),
                                            .SDA(AFE_TEMPERATURE_0_SDA));
wire [15:0] AFE_TEMP4, AFE_TEMP5, AFE_TEMP6, AFE_TEMP7;
adt7410 #(.BIT_RATE(20000)) afeTemperature1(.clk(sysClk),
                                            .temperatures({AFE_TEMP4,
                                                           AFE_TEMP5,
                                                           AFE_TEMP6,
                                                           AFE_TEMP7}),
                                            .SCL(AFE_TEMPERATURE_1_SCL),
                                            .SDA(AFE_TEMPERATURE_1_SDA));

//
// AFE power monitors
//
wire [15:0] AFE_CURRENT0, AFE_VOLTAGE0;
wire [15:0] AFE_CURRENT1, AFE_VOLTAGE1;
wire [15:0] AFE_CURRENT2, AFE_VOLTAGE2;
ltc2945 #(.BIT_RATE(20000)) afePower(.clk(sysClk),
                                     .current0(AFE_CURRENT0),
                                     .voltage0(AFE_VOLTAGE0),
                                     .current1(AFE_CURRENT1),
                                     .voltage1(AFE_VOLTAGE1),
                                     .current2(AFE_CURRENT2),
                                     .voltage2(AFE_VOLTAGE2),
                                     .SCL(AFE_POWER_SCL),
                                     .SDA(AFE_POWER_SDA));

//
// AFE attenuators
//
wire AFE_ATTEN_BUSY;
pe43701 afeAtten(.clk(sysClk),
                 .data(GPIO_OUT[6:0]),
                 .enable(GPIO_OUT[11:8]),
                 .writeStrobe(GPIO_STROBES[GPIO_IDX_AFE_ATTEN]),
                 .busy(AFE_ATTEN_BUSY),
                 .SCL(AFE_ATTEN_SCL),
                 .SDA(AFE_ATTEN_SDA),
                 .LE(AFE_ATTEN_LE));

//
// ADC control
//
assign ADC_RAND = 0;
assign ADC_DITH = 0;
assign GPIO_IN[GPIO_IDX_ADC_CONTROL] = { 28'b0,
                                        ADC_SHDN, ADC_DITH, ADC_RAND, ADC_PGA };
always @(posedge sysClk) begin
    if (GPIO_STROBES[GPIO_IDX_ADC_CONTROL]) begin
        ADC_PGA  <= GPIO_OUT[0];
        ADC_SHDN <= GPIO_OUT[3];
    end
end

//
// Clock frequency monitors
//
wire [27:0] clkrateADC;
clkMonitor #(.SYSCLK_RATE(SYSCLK_RATE),
            .RESULT_WIDTH(28))
  adcClkMonitor(.sysClk(sysClk),
                .monClk(adcClk),
                .evrPPS(EVR_triggerBus[3]),
                .Hz(clkrateADC));
assign GPIO_IN[GPIO_IDX_AFE_CLOCK_RATE] = { 4'b0, clkrateADC[27:0] };

wire [27:0] clkrateEVR;
clkMonitor #(.SYSCLK_RATE(SYSCLK_RATE),
            .RESULT_WIDTH(28))
  evrClkMonitor(.sysClk(sysClk),
                .monClk(evrClk),
                .evrPPS(EVR_triggerBus[3]),
                .Hz(clkrateEVR));
assign GPIO_IN[GPIO_IDX_EVR_CLOCK_RATE] = { 4'b0, clkrateEVR[27:0] };

//
// SFP readout
//
wire        SFP_IIC_BUSY;
wire [95:0] SFP_IIC_READOUT;
wire [31:0] SFP_IIC_READOUT_5_4, SFP_IIC_READOUT_3_2, SFP_IIC_READOUT_1_0;
assign SFP_IIC_READOUT_5_4 = SFP_IIC_READOUT[95:64];
assign SFP_IIC_READOUT_3_2 = SFP_IIC_READOUT[63:32];
assign SFP_IIC_READOUT_1_0 = SFP_IIC_READOUT[31:0];
sfpReadout #(.BIT_RATE(20000)) sfpReadout(.clk(sysClk),
                              .writeStrobe(GPIO_STROBES[GPIO_IDX_SFP_READ_CSR]),
                              .address(GPIO_OUT[8:0]),
                              .busy(SFP_IIC_BUSY),
                              .readout(SFP_IIC_READOUT),
                              .SCL(SFP_IIC_SCL),
                              .SDA(SFP_IIC_SDA));

assign GPIO_IN[GPIO_IDX_DFE_TEMP_1_0]       = {DFE_TEMP1, DFE_TEMP0};
assign GPIO_IN[GPIO_IDX_DFE_TEMP_3_2]       = {DFE_TEMP3, DFE_TEMP2};
assign GPIO_IN[GPIO_IDX_AFE_TEMP_1_0]       = {AFE_TEMP1, AFE_TEMP0};
assign GPIO_IN[GPIO_IDX_AFE_TEMP_3_2]       = {AFE_TEMP3, AFE_TEMP2};
assign GPIO_IN[GPIO_IDX_AFE_TEMP_5_4]       = {AFE_TEMP5, AFE_TEMP4};
assign GPIO_IN[GPIO_IDX_AFE_TEMP_7_6]       = {AFE_TEMP7, AFE_TEMP6};
assign GPIO_IN[GPIO_IDX_AFE_POWER_IV0]      = {AFE_CURRENT0, AFE_VOLTAGE0};
assign GPIO_IN[GPIO_IDX_AFE_POWER_IV1]      = {AFE_CURRENT1, AFE_VOLTAGE1};
assign GPIO_IN[GPIO_IDX_AFE_POWER_IV2]      = {AFE_CURRENT2, AFE_VOLTAGE2};
assign GPIO_IN[GPIO_IDX_DFE_FAN_RPM]        = {16'b0, DFE_FAN_RPM};
assign GPIO_IN[GPIO_IDX_SFP_READ_CSR]       = { 31'b0, SFP_IIC_BUSY};
assign GPIO_IN[GPIO_IDX_SFP_READ_5_4]       = SFP_IIC_READOUT_5_4;
assign GPIO_IN[GPIO_IDX_SFP_READ_3_2]       = SFP_IIC_READOUT_3_2;
assign GPIO_IN[GPIO_IDX_SFP_READ_1_0]       = SFP_IIC_READOUT_1_0;
assign GPIO_IN[GPIO_IDX_AFE_ATTEN]          = { 31'b0, AFE_ATTEN_BUSY };

//
// Preliminary processing (compute magnitude of ADC signals)
//
wire                 sysSingleTrig;
wire [32-MAG_WIDTH-1:0] magPAD = 0;
wire                 adcLoSynced, adcTbtLoadAccumulator, adcTbtLatchAccumulator;
wire                 adcMtLoadAndLatch;
wire                 prelimProcTbtToggle;
wire [MAG_WIDTH-1:0] prelimProcRfTbtMag0, prelimProcRfTbtMag1;
wire [MAG_WIDTH-1:0] prelimProcRfTbtMag2, prelimProcRfTbtMag3;
wire                 prelimProcFaToggle;
wire [MAG_WIDTH-1:0] prelimProcRfFaMag0, prelimProcRfFaMag1;
wire [MAG_WIDTH-1:0] prelimProcRfFaMag2, prelimProcRfFaMag3;
wire                 prelimProcSaToggle;
wire [MAG_WIDTH-1:0] prelimProcRfMag0, prelimProcRfMag1;
wire [MAG_WIDTH-1:0] prelimProcRfMag2, prelimProcRfMag3;
wire [MAG_WIDTH-1:0] prelimProcPlMag0, prelimProcPlMag1;
wire [MAG_WIDTH-1:0] prelimProcPlMag2, prelimProcPlMag3;
wire [MAG_WIDTH-1:0] prelimProcPhMag0, prelimProcPhMag1;
wire [MAG_WIDTH-1:0] prelimProcPhMag2, prelimProcPhMag3;
wire prelimProcPtToggle, prelimProcOverflow;
assign FP_LED[1] = !prelimProcOverflow;  // First green LED
assign GPIO_IN[GPIO_IDX_PRELIM_RF_MAG_0] = { magPAD, prelimProcRfMag0 };
assign GPIO_IN[GPIO_IDX_PRELIM_RF_MAG_1] = { magPAD, prelimProcRfMag1 };
assign GPIO_IN[GPIO_IDX_PRELIM_RF_MAG_2] = { magPAD, prelimProcRfMag2 };
assign GPIO_IN[GPIO_IDX_PRELIM_RF_MAG_3] = { magPAD, prelimProcRfMag3 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_0] = { magPAD, prelimProcPlMag0 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_1] = { magPAD, prelimProcPlMag1 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_2] = { magPAD, prelimProcPlMag2 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_3] = { magPAD, prelimProcPlMag3 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_0] = { magPAD, prelimProcPhMag0 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_1] = { magPAD, prelimProcPhMag1 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_2] = { magPAD, prelimProcPhMag2 };
assign GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_3] = { magPAD, prelimProcPhMag3 };

preliminaryProcessing #(.SYSCLK_RATE(SYSCLK_RATE),
                        .MAG_WIDTH(MAG_WIDTH),
                        .SAMPLES_PER_TURN(SITE_SAMPLES_PER_TURN),
                        .CIC_STAGES(SITE_CIC_STAGES),
                        .CIC_FA_DECIMATE(SITE_CIC_FA_DECIMATE),
                        .CIC_SA_DECIMATE(SITE_CIC_SA_DECIMATE),
                        .GPIO_LO_RF_ROW_CAPACITY(GPIO_LO_RF_ROW_CAPACITY),
                        .GPIO_LO_PT_ROW_CAPACITY(GPIO_LO_PT_ROW_CAPACITY))
  prelimProc(
    .clk(sysClk),
    .adcClk(adcClk),
    .adc0(adc0),
    .adc1(adc1),
    .adc2(adc2),
    .adc3(adc3),
    .adcExceedsThreshold(adcExceedsThreshold),
    .adcUseThisSample(adcUseThisSample),
    .evrClk(evrClk),
    .evrFaMarker(evrFaMarker),
    .evrSaMarker(evrSaMarker),
    .evrTimestamp(EVR_timestamp),
    .evrPtTrigger(EVR_triggerBus[2]),
    .evrSinglePassTrigger(EVR_triggerBus[1]),
    .evrHbMarker(evrHeartbeatMarker),
    .sysSingleTrig(sysSingleTrig),
    .sysTimestamp(timestamp),
    .PT_P(FP_OUT1_P),
    .PT_N(FP_OUT1_N),
    .gpioData(GPIO_OUT),
    .localOscillatorAddressStrobe(GPIO_STROBES[GPIO_IDX_LOTABLE_ADDRESS]),
    .localOscillatorCsrStrobe(GPIO_STROBES[GPIO_IDX_LOTABLE_CSR]),
    .localOscillatorCsr(GPIO_IN[GPIO_IDX_LOTABLE_CSR]),
    .sumShiftCsrStrobe(GPIO_STROBES[GPIO_IDX_SUM_SHIFT_CSR]),
    .sumShiftCsr(GPIO_IN[GPIO_IDX_SUM_SHIFT_CSR]),
    .autotrimCsrStrobe(GPIO_STROBES[GPIO_IDX_AUTOTRIM_CSR]),
    .autotrimThresholdStrobe(GPIO_STROBES[GPIO_IDX_AUTOTRIM_THRESHOLD]),
    .autotrimGainStrobes({GPIO_STROBES[GPIO_IDX_ADC_GAIN_FACTOR_3],
                          GPIO_STROBES[GPIO_IDX_ADC_GAIN_FACTOR_2],
                          GPIO_STROBES[GPIO_IDX_ADC_GAIN_FACTOR_1],
                          GPIO_STROBES[GPIO_IDX_ADC_GAIN_FACTOR_0]}),
    .autotrimCsr(GPIO_IN[GPIO_IDX_AUTOTRIM_CSR]),
    .autotrimThreshold(GPIO_IN[GPIO_IDX_AUTOTRIM_THRESHOLD]),
    .gainRBK0(GPIO_IN[GPIO_IDX_ADC_GAIN_FACTOR_0]),
    .gainRBK1(GPIO_IN[GPIO_IDX_ADC_GAIN_FACTOR_1]),
    .gainRBK2(GPIO_IN[GPIO_IDX_ADC_GAIN_FACTOR_2]),
    .gainRBK3(GPIO_IN[GPIO_IDX_ADC_GAIN_FACTOR_3]),
    .adcLoSynced(adcLoSynced),
    .tbtToggle(prelimProcTbtToggle),
    .rfTbtMag0(prelimProcRfTbtMag0),
    .rfTbtMag1(prelimProcRfTbtMag1),
    .rfTbtMag2(prelimProcRfTbtMag2),
    .rfTbtMag3(prelimProcRfTbtMag3),
    .faToggle(prelimProcFaToggle),
    .adcTbtLoadAccumulator(adcTbtLoadAccumulator),
    .adcTbtLatchAccumulator(adcTbtLatchAccumulator),
    .adcMtLoadAndLatch(adcMtLoadAndLatch),
    .rfFaMag0(prelimProcRfFaMag0),
    .rfFaMag1(prelimProcRfFaMag1),
    .rfFaMag2(prelimProcRfFaMag2),
    .rfFaMag3(prelimProcRfFaMag3),
    .saToggle(prelimProcSaToggle),
    .sysSaTimestamp({GPIO_IN[GPIO_IDX_SA_TIMESTAMP_SEC],
                     GPIO_IN[GPIO_IDX_SA_TIMESTAMP_TICKS]}),
    .rfMag0(prelimProcRfMag0),
    .rfMag1(prelimProcRfMag1),
    .rfMag2(prelimProcRfMag2),
    .rfMag3(prelimProcRfMag3),
    .plMag0(prelimProcPlMag0),
    .plMag1(prelimProcPlMag1),
    .plMag2(prelimProcPlMag2),
    .plMag3(prelimProcPlMag3),
    .phMag0(prelimProcPhMag0),
    .phMag1(prelimProcPhMag1),
    .phMag2(prelimProcPhMag2),
    .phMag3(prelimProcPhMag3),
    .ptToggle(prelimProcPtToggle),
    .overflowFlag(prelimProcOverflow));

//
// Position calculation
//
wire [31:0] positionCalcCSR;
wire [31:0] positionCalcXcal, positionCalcYcal, positionCalcQcal;
wire [31:0] positionCalcTbtX, positionCalcTbtY;
wire [31:0] positionCalcTbtQ, positionCalcTbtS;
wire [31:0] positionCalcFaX, positionCalcFaY, positionCalcFaQ, positionCalcFaS;
wire [31:0] positionCalcSaX, positionCalcSaY, positionCalcSaQ, positionCalcSaS;
wire        positionCalcTbtToggle, positionCalcFaToggle, positionCalcSaToggle;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_CSR] = positionCalcCSR;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_XCAL] = positionCalcXcal;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_YCAL] = positionCalcYcal;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_QCAL] = positionCalcQcal;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_SA_X] = positionCalcSaX;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_SA_Y] = positionCalcSaY;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_SA_Q] = positionCalcSaQ;
assign GPIO_IN[GPIO_IDX_POSITION_CALC_SA_S] = positionCalcSaS;
positionCalc #(.MAG_WIDTH(MAG_WIDTH))
    positionCalc(.clk(sysClk),
               .gpioData(GPIO_OUT),
               .csrStrobe(GPIO_STROBES[GPIO_IDX_POSITION_CALC_CSR]),
               .xCalStrobe(GPIO_STROBES[GPIO_IDX_POSITION_CALC_XCAL]),
               .yCalStrobe(GPIO_STROBES[GPIO_IDX_POSITION_CALC_YCAL]),
               .qCalStrobe(GPIO_STROBES[GPIO_IDX_POSITION_CALC_QCAL]),
               .tbt0(prelimProcRfTbtMag0),
               .tbt1(prelimProcRfTbtMag1),
               .tbt2(prelimProcRfTbtMag2),
               .tbt3(prelimProcRfTbtMag3),
               .tbtInToggle(prelimProcTbtToggle),
               .fa0(prelimProcRfFaMag0),
               .fa1(prelimProcRfFaMag1),
               .fa2(prelimProcRfFaMag2),
               .fa3(prelimProcRfFaMag3),
               .faInToggle(prelimProcFaToggle),
               .sa0(prelimProcRfMag0),
               .sa1(prelimProcRfMag1),
               .sa2(prelimProcRfMag2),
               .sa3(prelimProcRfMag3),
               .saInToggle(prelimProcSaToggle),
               .csr(positionCalcCSR),
               .xCalibration(positionCalcXcal),
               .yCalibration(positionCalcYcal),
               .qCalibration(positionCalcQcal),
               .tbtX(positionCalcTbtX),
               .tbtY(positionCalcTbtY),
               .tbtQ(positionCalcTbtQ),
               .tbtS(positionCalcTbtS),
               .tbtToggle(positionCalcTbtToggle),
               .faX(positionCalcFaX),
               .faY(positionCalcFaY),
               .faQ(positionCalcFaQ),
               .faS(positionCalcFaS),
               .faToggle(positionCalcFaToggle),
               .saX(positionCalcSaX),
               .saY(positionCalcSaY),
               .saQ(positionCalcSaQ),
               .saS(positionCalcSaS),
               .saToggle(positionCalcSaToggle));

//
// Loss-of-beam detection
//
wire [31:0] lossOfBeamThreshold;
assign GPIO_IN[GPIO_IDX_LOSS_OF_BEAM_THRSH] = lossOfBeamThreshold;
wire lossOfBeamTrigger;
lossOfBeam lossOfBeam(.clk(sysClk),
                    .thresholdStrobe(GPIO_STROBES[GPIO_IDX_LOSS_OF_BEAM_THRSH]),
                    .gpioData(GPIO_OUT),
                    .threshold(lossOfBeamThreshold),
                    .turnByTurnToggle(positionCalcTbtToggle),
                    .buttonSum(positionCalcTbtS),
                    .lossOfBeamTrigger(lossOfBeamTrigger));

//
// RMS motion calculation
//
wire [31:0] wideXrms, wideYrms, narrowXrms, narrowYrms;
assign GPIO_IN[GPIO_IDX_RMS_X_WIDE] = wideXrms;
assign GPIO_IN[GPIO_IDX_RMS_Y_WIDE] = wideYrms;
assign GPIO_IN[GPIO_IDX_RMS_X_NARROW] = narrowXrms;
assign GPIO_IN[GPIO_IDX_RMS_Y_NARROW] = narrowYrms;
rmsCalc rmsCalc(.clk(sysClk),
                .faToggle(positionCalcFaToggle),
                .faX(positionCalcFaX),
                .faY(positionCalcFaY),
                .wideXrms(wideXrms),
                .wideYrms(wideYrms),
                .narrowXrms(narrowXrms),
                .narrowYrms(narrowYrms));

//
// Filter FA values before sending to neighbours
//
wire        recordAlternateFAchannels;
wire        filteredFaToggle;
wire [31:0] cellStreamFilterStatus, filteredFA_X, filteredFA_Y;
assign GPIO_IN[GPIO_IDX_CELL_FILTER_CSR] = cellStreamFilterStatus;
assign recordAlternateFAchannels = cellStreamFilterStatus[30];
cellStreamFilters cellStreamFilters (
                .clk(sysClk),
                .csrStrobe(GPIO_STROBES[GPIO_IDX_CELL_FILTER_CSR]),
                .dataStrobe(GPIO_STROBES[GPIO_IDX_CELL_FILTER_DATA]),
                .gpioData(GPIO_OUT),
                .status(cellStreamFilterStatus),
                .faToggle(positionCalcFaToggle),
                .inputFA_X(positionCalcFaX),
                .inputFA_Y(positionCalcFaY),
                .filteredFaToggle(filteredFaToggle),
                .filteredFA_X(filteredFA_X),
                .filteredFA_Y(filteredFA_Y));

//
// Send filtered FA values to neighbours
//
wire [31:0] cellCommCSR;
assign GPIO_IN[GPIO_IDX_CELL_COMM_CSR] = cellCommCSR;
wire GTX_REFCLK;
cellComm cellComm(.sysClk(sysClk),
                  .sysCsrStrobe(GPIO_STROBES[GPIO_IDX_CELL_COMM_CSR]),
                  .sysGpioData(GPIO_OUT),
                  .sysCsr(cellCommCSR),
                  .sysFaToggle(filteredFaToggle),
                  .sysFA_X(filteredFA_X),
                  .sysFA_Y(filteredFA_Y),
                  .sysFA_S(positionCalcFaS),
                  .sysClippedAdc(clippedAdc),
                  .GTX_REFCLK(GTX_REFCLK),
                  .CCW_TX_N(SFP_TXD_N[1]),
                  .CCW_TX_P(SFP_TXD_P[1]),
                  .CCW_RX_N(SFP_RXD_N[1]),
                  .CCW_RX_P(SFP_RXD_P[1]),
                  .CCW_LED0(SFP_LED[2]),
                  .CCW_LED1(SFP_LED[3]),
                  .CW_TX_N(SFP_TXD_N[2]),
                  .CW_TX_P(SFP_TXD_P[2]),
                  .CW_RX_N(SFP_RXD_N[2]),
                  .CW_RX_P(SFP_RXD_P[2]),
                  .CW_LED0(SFP_LED[4]),
                  .CW_LED1(SFP_LED[5]),
                  .ccwCRCfaults(GPIO_IN[GPIO_IDX_BPM_CCW_CRC_FAULTS]),
                  .cwCRCfaults(GPIO_IN[GPIO_IDX_BPM_CW_CRC_FAULTS]));

//
// ADC raw data transmission
//
wire [31:0] adcTransmitCSR;
assign GPIO_IN[GPIO_IDX_ADC_TRANSMIT_CSR] = adcTransmitCSR;
adcTransmit adcTransmit(.sysClk(sysClk),
                        .sysCsrStrobe(GPIO_STROBES[GPIO_IDX_ADC_TRANSMIT_CSR]),
                        .sysGpioData(GPIO_OUT),
                        .sysCsr(adcTransmitCSR),
                        .adcClk(adcClk),
                        .adcRawData(adcRawData),
                        .adcTurnMarker(adcTbtLoadAccumulator),
                        .GTX_REFCLK(GTX_REFCLK),
                        .TXD_LANE_1_P(SFP_TXD_P[3]),
                        .TXD_LANE_1_N(SFP_TXD_N[3]),
                        .TXD_LANE_2_P(SFP_TXD_P[4]),
                        .TXD_LANE_2_N(SFP_TXD_N[4]));

//
// ADC waveform recorder
//
wire  [31:0] wr_adc_axi_AWADDR;
wire   [7:0] wr_adc_axi_AWLEN;
wire         wr_adc_axi_AWVALID;
wire         wr_adc_axi_AWREADY;
wire [127:0] wr_adc_axi_WDATA;
wire         wr_adc_axi_WLAST;
wire         wr_adc_axi_WVALID;
wire         wr_adc_axi_WREADY;
wire   [1:0] wr_adc_axi_BRESP;
wire         wr_adc_axi_BVALID;
wire [31:0] adcWfrCSR, adcWfrPretrigCount, adcWfrAcqCount, adcWfrAcqAddr;
wire [63:0] adcWfrWhenTriggered;
assign GPIO_IN[GPIO_IDX_ADC_RECORDER_BASE+0] = adcWfrCSR;
assign GPIO_IN[GPIO_IDX_ADC_RECORDER_BASE+1] = adcWfrPretrigCount;
assign GPIO_IN[GPIO_IDX_ADC_RECORDER_BASE+2] = adcWfrAcqCount;
assign GPIO_IN[GPIO_IDX_ADC_RECORDER_BASE+3] = adcWfrAcqAddr;
assign GPIO_IN[GPIO_IDX_ADC_RECORDER_BASE+4] = adcWfrWhenTriggered[63:32];
assign GPIO_IN[GPIO_IDX_ADC_RECORDER_BASE+5] = adcWfrWhenTriggered[31:0];
wire [4*ADC_WIDTH-1:0] adcTestData;
assign adcTestData = { adc3[15:1], adcUseThisSample,
                       adc2[15:1], adcTbtLoadAccumulator,
                       adc1[15:1], adcTbtLatchAccumulator,
                       adc0[15:1], adcMtLoadAndLatch };
adcWaveformRecorder #(.ACQ_COUNT(GPIO_RECORDER_ADC_SAMPLE_CAPACITY))
  adcWaveformRecorder(.adcClk(adcClk),
                      .adcRawData(adcRawData),
                      .adcTestData(adcTestData),
                      .clk(sysClk),
                      .triggers(recorderTriggerBus),
                      .timestamp(timestamp),
                      .sysTicks(sysClkCounter),
                      .writeData(GPIO_OUT),
                      .regStrobes(GPIO_STROBES[GPIO_IDX_ADC_RECORDER_BASE+:4]),
                      .csr(adcWfrCSR),
                      .pretrigCount(adcWfrPretrigCount),
                      .acqCount(adcWfrAcqCount),
                      .acqAddress(adcWfrAcqAddr),
                      .whenTriggered(adcWfrWhenTriggered),
                      .axi_AWADDR(wr_adc_axi_AWADDR),
                      .axi_AWLEN(wr_adc_axi_AWLEN),
                      .axi_AWVALID(wr_adc_axi_AWVALID),
                      .axi_AWREADY(wr_adc_axi_AWREADY),
                      .axi_WDATA(wr_adc_axi_WDATA),
                      .axi_WLAST(wr_adc_axi_WLAST),
                      .axi_WVALID(wr_adc_axi_WVALID),
                      .axi_WREADY(wr_adc_axi_WREADY),
                      .axi_BRESP(wr_adc_axi_BRESP),
                      .axi_BVALID(wr_adc_axi_BVALID));

//
// TBT waveform recorder
//
wire  [31:0] wr_tbt_axi_AWADDR;
wire   [7:0] wr_tbt_axi_AWLEN;
wire         wr_tbt_axi_AWVALID;
wire         wr_tbt_axi_AWREADY;
wire [127:0] wr_tbt_axi_WDATA;
wire         wr_tbt_axi_WLAST;
wire         wr_tbt_axi_WVALID;
wire         wr_tbt_axi_WREADY;
wire   [1:0] wr_tbt_axi_BRESP;
wire         wr_tbt_axi_BVALID;
wire [127:0] tbtWdata;
assign tbtWdata = { positionCalcTbtS, positionCalcTbtQ,
                    positionCalcTbtY, positionCalcTbtX };
wire [31:0] tbtWfrCSR, tbtWfrPretrigCount, tbtWfrAcqCount, tbtWfrAcqAddr;
wire [63:0] tbtWfrWhenTriggered;
assign GPIO_IN[GPIO_IDX_TBT_RECORDER_BASE+0] = tbtWfrCSR;
assign GPIO_IN[GPIO_IDX_TBT_RECORDER_BASE+1] = tbtWfrPretrigCount;
assign GPIO_IN[GPIO_IDX_TBT_RECORDER_BASE+2] = tbtWfrAcqCount;
assign GPIO_IN[GPIO_IDX_TBT_RECORDER_BASE+3] = tbtWfrAcqAddr;
assign GPIO_IN[GPIO_IDX_TBT_RECORDER_BASE+4] = tbtWfrWhenTriggered[63:32];
assign GPIO_IN[GPIO_IDX_TBT_RECORDER_BASE+5] = tbtWfrWhenTriggered[31:0];
genericWaveformRecorder #(.ACQ_CAPACITY(GPIO_RECORDER_TBT_SAMPLE_CAPACITY))
  tbtWaveformRecorder(.clk(sysClk),
                      .data(tbtWdata),
                      .dataToggle(positionCalcTbtToggle),
                      .triggers(recorderTriggerBus),
                      .timestamp(timestamp),
                      .writeData(GPIO_OUT),
                      .regStrobes(GPIO_STROBES[GPIO_IDX_TBT_RECORDER_BASE+:4]),
                      .csr(tbtWfrCSR),
                      .pretrigCount(tbtWfrPretrigCount),
                      .acqCount(tbtWfrAcqCount),
                      .acqAddress(tbtWfrAcqAddr),
                      .whenTriggered(tbtWfrWhenTriggered),
                      .axi_AWADDR(wr_tbt_axi_AWADDR),
                      .axi_AWLEN(wr_tbt_axi_AWLEN),
                      .axi_AWVALID(wr_tbt_axi_AWVALID),
                      .axi_AWREADY(wr_tbt_axi_AWREADY),
                      .axi_WDATA(wr_tbt_axi_WDATA),
                      .axi_WLAST(wr_tbt_axi_WLAST),
                      .axi_WVALID(wr_tbt_axi_WVALID),
                      .axi_WREADY(wr_tbt_axi_WREADY),
                      .axi_BRESP(wr_tbt_axi_BRESP),
                      .axi_BVALID(wr_tbt_axi_BVALID));

//
// FA waveform recorder
//
wire  [31:0] wr_fa_axi_AWADDR;
wire   [7:0] wr_fa_axi_AWLEN;
wire         wr_fa_axi_AWVALID;
wire         wr_fa_axi_AWREADY;
wire [127:0] wr_fa_axi_WDATA;
wire         wr_fa_axi_WLAST;
wire         wr_fa_axi_WVALID;
wire         wr_fa_axi_WREADY;
wire   [1:0] wr_fa_axi_BRESP;
wire         wr_fa_axi_BVALID;
wire [127:0] faWdata;
assign faWdata = recordAlternateFAchannels ?
        {    filteredFA_Y,    filteredFA_X, positionCalcFaY, positionCalcFaX } :
        { positionCalcFaS, positionCalcFaQ, positionCalcFaY, positionCalcFaX };
wire [31:0] faWfrCSR, faWfrPretrigCount, faWfrAcqCount, faWfrAcqAddr;
wire [63:0] faWfrWhenTriggered;
assign GPIO_IN[GPIO_IDX_FA_RECORDER_BASE+0] = faWfrCSR;
assign GPIO_IN[GPIO_IDX_FA_RECORDER_BASE+1] = faWfrPretrigCount;
assign GPIO_IN[GPIO_IDX_FA_RECORDER_BASE+2] = faWfrAcqCount;
assign GPIO_IN[GPIO_IDX_FA_RECORDER_BASE+3] = faWfrAcqAddr;
assign GPIO_IN[GPIO_IDX_FA_RECORDER_BASE+4] = faWfrWhenTriggered[63:32];
assign GPIO_IN[GPIO_IDX_FA_RECORDER_BASE+5] = faWfrWhenTriggered[31:0];
genericWaveformRecorder #(.ACQ_CAPACITY(GPIO_RECORDER_FA_SAMPLE_CAPACITY))
  faWaveformRecorder(.clk(sysClk),
                     .data(faWdata),
                     .dataToggle(recordAlternateFAchannels ?
                                                     filteredFaToggle :
                                                     positionCalcFaToggle),
                     .triggers(recorderTriggerBus),
                     .timestamp(timestamp),
                     .writeData(GPIO_OUT),
                     .regStrobes(GPIO_STROBES[GPIO_IDX_FA_RECORDER_BASE+:4]),
                     .csr(faWfrCSR),
                     .pretrigCount(faWfrPretrigCount),
                     .acqCount(faWfrAcqCount),
                     .acqAddress(faWfrAcqAddr),
                     .whenTriggered(faWfrWhenTriggered),
                     .axi_AWADDR(wr_fa_axi_AWADDR),
                     .axi_AWLEN(wr_fa_axi_AWLEN),
                     .axi_AWVALID(wr_fa_axi_AWVALID),
                     .axi_AWREADY(wr_fa_axi_AWREADY),
                     .axi_WDATA(wr_fa_axi_WDATA),
                     .axi_WLAST(wr_fa_axi_WLAST),
                     .axi_WVALID(wr_fa_axi_WVALID),
                     .axi_WREADY(wr_fa_axi_WREADY),
                     .axi_BRESP(wr_fa_axi_BRESP),
                     .axi_BVALID(wr_fa_axi_BVALID));

//
// Low pilot tone waveform recorder
//
wire  [31:0] wr_pl_axi_AWADDR;
wire   [7:0] wr_pl_axi_AWLEN;
wire         wr_pl_axi_AWVALID;
wire         wr_pl_axi_AWREADY;
wire [127:0] wr_pl_axi_WDATA;
wire         wr_pl_axi_WLAST;
wire         wr_pl_axi_WVALID;
wire         wr_pl_axi_WREADY;
wire   [1:0] wr_pl_axi_BRESP;
wire         wr_pl_axi_BVALID;
wire [31:0] plWfrCSR, plWfrPretrigCount, plWfrAcqCount, plWfrAcqAddr;
wire [63:0] plWfrWhenTriggered;
assign GPIO_IN[GPIO_IDX_PL_RECORDER_BASE+0] = plWfrCSR;
assign GPIO_IN[GPIO_IDX_PL_RECORDER_BASE+1] = plWfrPretrigCount;
assign GPIO_IN[GPIO_IDX_PL_RECORDER_BASE+2] = plWfrAcqCount;
assign GPIO_IN[GPIO_IDX_PL_RECORDER_BASE+3] = plWfrAcqAddr;
assign GPIO_IN[GPIO_IDX_PL_RECORDER_BASE+4] = plWfrWhenTriggered[63:32];
assign GPIO_IN[GPIO_IDX_PL_RECORDER_BASE+5] = plWfrWhenTriggered[31:0];
genericWaveformRecorder #(.ACQ_CAPACITY(GPIO_RECORDER_PT_SAMPLE_CAPACITY))
  plWaveformRecorder(.clk(sysClk),
                     .data({GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_3],
                            GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_2],
                            GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_1],
                            GPIO_IN[GPIO_IDX_PRELIM_PT_LO_MAG_0]}),
                     .dataToggle(prelimProcPtToggle),
                     .triggers(recorderTriggerBus),
                     .timestamp(timestamp),
                     .writeData(GPIO_OUT),
                     .regStrobes(GPIO_STROBES[GPIO_IDX_PL_RECORDER_BASE+:4]),
                     .csr(plWfrCSR),
                     .pretrigCount(plWfrPretrigCount),
                     .acqCount(plWfrAcqCount),
                     .acqAddress(plWfrAcqAddr),
                     .whenTriggered(plWfrWhenTriggered),
                     .axi_AWADDR(wr_pl_axi_AWADDR),
                     .axi_AWLEN(wr_pl_axi_AWLEN),
                     .axi_AWVALID(wr_pl_axi_AWVALID),
                     .axi_AWREADY(wr_pl_axi_AWREADY),
                     .axi_WDATA(wr_pl_axi_WDATA),
                     .axi_WLAST(wr_pl_axi_WLAST),
                     .axi_WVALID(wr_pl_axi_WVALID),
                     .axi_WREADY(wr_pl_axi_WREADY),
                     .axi_BRESP(wr_pl_axi_BRESP),
                     .axi_BVALID(wr_pl_axi_BVALID));

//
// High pilot tone waveform recorder
//
wire  [31:0] wr_ph_axi_AWADDR;
wire   [7:0] wr_ph_axi_AWLEN;
wire         wr_ph_axi_AWVALID;
wire         wr_ph_axi_AWREADY;
wire [127:0] wr_ph_axi_WDATA;
wire         wr_ph_axi_WLAST;
wire         wr_ph_axi_WVALID;
wire         wr_ph_axi_WREADY;
wire   [1:0] wr_ph_axi_BRESP;
wire         wr_ph_axi_BVALID;
wire [31:0] phWfrCSR, phWfrPretrigCount, phWfrAcqCount, phWfrAcqAddr;
wire [63:0] phWfrWhenTriggered;
assign GPIO_IN[GPIO_IDX_PH_RECORDER_BASE+0] = phWfrCSR;
assign GPIO_IN[GPIO_IDX_PH_RECORDER_BASE+1] = phWfrPretrigCount;
assign GPIO_IN[GPIO_IDX_PH_RECORDER_BASE+2] = phWfrAcqCount;
assign GPIO_IN[GPIO_IDX_PH_RECORDER_BASE+3] = phWfrAcqAddr;
assign GPIO_IN[GPIO_IDX_PH_RECORDER_BASE+4] = phWfrWhenTriggered[63:32];
assign GPIO_IN[GPIO_IDX_PH_RECORDER_BASE+5] = phWfrWhenTriggered[31:0];
genericWaveformRecorder #(.ACQ_CAPACITY(GPIO_RECORDER_PT_SAMPLE_CAPACITY))
  phWaveformRecorder(.clk(sysClk),
                     .data({GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_3],
                            GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_2],
                            GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_1],
                            GPIO_IN[GPIO_IDX_PRELIM_PT_HI_MAG_0]}),
                     .dataToggle(prelimProcPtToggle),
                     .triggers(recorderTriggerBus),
                     .timestamp(timestamp),
                     .writeData(GPIO_OUT),
                     .regStrobes(GPIO_STROBES[GPIO_IDX_PH_RECORDER_BASE+:4]),
                     .csr(phWfrCSR),
                     .pretrigCount(phWfrPretrigCount),
                     .acqCount(phWfrAcqCount),
                     .acqAddress(phWfrAcqAddr),
                     .whenTriggered(phWfrWhenTriggered),
                     .axi_AWADDR(wr_ph_axi_AWADDR),
                     .axi_AWLEN(wr_ph_axi_AWLEN),
                     .axi_AWVALID(wr_ph_axi_AWVALID),
                     .axi_AWREADY(wr_ph_axi_AWREADY),
                     .axi_WDATA(wr_ph_axi_WDATA),
                     .axi_WLAST(wr_ph_axi_WLAST),
                     .axi_WVALID(wr_ph_axi_WVALID),
                     .axi_WREADY(wr_ph_axi_WREADY),
                     .axi_BRESP(wr_ph_axi_BRESP),
                     .axi_BVALID(wr_ph_axi_BVALID));

//
// Microblaze
//
  (* BOX_TYPE = "user_black_box" *)
system system_i (
      .CLK_P ( CLK_P ),
      .CLK_N ( CLK_N ),
      .sysClk ( sysClk ),
      .clk200 ( clk200 ),
      .RESET ( 1'b0 ), // DFE does not provide a SYS RESET signal (reset chip is not installed).

      .ddr_memory_we_n ( ddr_memory_we_n ),
      .ddr_memory_ras_n ( ddr_memory_ras_n ),
      .ddr_memory_odt ( ddr_memory_odt ),
      .ddr_memory_dqs_n ( ddr_memory_dqs_n ),
      .ddr_memory_dqs ( ddr_memory_dqs ),
      .ddr_memory_dq ( ddr_memory_dq ),
      .ddr_memory_dm ( ddr_memory_dm ),
      .ddr_memory_ddr3_rst ( ddr_memory_ddr3_rst ),
      .ddr_memory_cs_n ( ddr_memory_cs_n ),
      .ddr_memory_clk_n ( ddr_memory_clk_n ),
      .ddr_memory_clk ( ddr_memory_clk ),
      .ddr_memory_cke ( ddr_memory_cke ),
      .ddr_memory_cas_n ( ddr_memory_cas_n ),
      .ddr_memory_ba ( ddr_memory_ba ),
      .ddr_memory_addr ( ddr_memory_addr ),

      .RS232_Uart_1_sout ( RS232_Uart_1_sout ),
      .RS232_Uart_1_sin ( RS232_Uart_1_sin ),

      .Linear_Flash_we_n ( Linear_Flash_we_n ),
      .Linear_Flash_oe_n ( Linear_Flash_oe_n ),
      .Linear_Flash_data ( Linear_Flash_data ),
      .Linear_Flash_ce_n ( Linear_Flash_ce_n ),
      .Linear_Flash_address ( Linear_Flash_address ),

      .ETHERNET_TX_ER ( ETHERNET_TX_ER ),
      .ETHERNET_TX_EN ( ETHERNET_TX_EN ),
      .ETHERNET_TX_CLK ( ETHERNET_TX_CLK ),
      .ETHERNET_TXD ( ETHERNET_TXD ),
      .ETHERNET_RX_ER ( ETHERNET_RX_ER ),
      .ETHERNET_RX_DV ( ETHERNET_RX_DV ),
      .ETHERNET_RX_CLK ( ETHERNET_RX_CLK ),
      .ETHERNET_RXD ( ETHERNET_RXD ),
      .ETHERNET_PHY_RST_N ( ETHERNET_PHY_RST_N ),
      .ETHERNET_MII_TX_CLK ( ETHERNET_MII_TX_CLK ),
      .ETHERNET_MDIO ( ETHERNET_MDIO ),
      .ETHERNET_MDC ( ETHERNET_MDC ),
      .PHY_CLK_25_MHZ ( PHY_CLK_25_MHZ ),

      .EVR_GTX_RXD_P ( SFP_RXD_P[0] ),
      .EVR_GTX_RXD_N ( SFP_RXD_N[0] ),
      .EVR_GTX_TXD_P ( SFP_TXD_P[0] ),
      .EVR_GTX_TXD_N ( SFP_TXD_N[0] ),
      .EVR_GTX_REFCLK_P ( GTX_REFCLK_P ),
      .EVR_GTX_REFCLK_N ( GTX_REFCLK_N ),
      .EVR_GtxRefClk ( GTX_REFCLK ),
      .EVR_lossOfLock ( EVR_LossOfLock ),
      .EVR_triggerBus ( EVR_triggerBus ),
      .EVR_timestamp ( EVR_timestamp ),
      .evrClk ( evrClk ),

      .GPIO_IN ( GPIO_IN_FLATTENED ),
      .GPIO_OUT ( GPIO_OUT ),
      .GPIO_STROBES ( GPIO_STROBES ),

       .wr_adc_axi_AWADDR(wr_adc_axi_AWADDR),
       .wr_adc_axi_AWLEN(wr_adc_axi_AWLEN),
       .wr_adc_axi_AWVALID(wr_adc_axi_AWVALID),
       .wr_adc_axi_AWREADY(wr_adc_axi_AWREADY),
       .wr_adc_axi_WDATA(wr_adc_axi_WDATA),
       .wr_adc_axi_WLAST(wr_adc_axi_WLAST),
       .wr_adc_axi_WVALID(wr_adc_axi_WVALID),
       .wr_adc_axi_WREADY(wr_adc_axi_WREADY),
       .wr_adc_axi_BRESP(wr_adc_axi_BRESP),
       .wr_adc_axi_BVALID(wr_adc_axi_BVALID),

       .wr_tbt_axi_AWADDR(wr_tbt_axi_AWADDR),
       .wr_tbt_axi_AWLEN(wr_tbt_axi_AWLEN),
       .wr_tbt_axi_AWVALID(wr_tbt_axi_AWVALID),
       .wr_tbt_axi_AWREADY(wr_tbt_axi_AWREADY),
       .wr_tbt_axi_WDATA(wr_tbt_axi_WDATA),
       .wr_tbt_axi_WLAST(wr_tbt_axi_WLAST),
       .wr_tbt_axi_WVALID(wr_tbt_axi_WVALID),
       .wr_tbt_axi_WREADY(wr_tbt_axi_WREADY),
       .wr_tbt_axi_BRESP(wr_tbt_axi_BRESP),
       .wr_tbt_axi_BVALID(wr_tbt_axi_BVALID),

       .wr_fa_axi_AWADDR(wr_fa_axi_AWADDR),
       .wr_fa_axi_AWLEN(wr_fa_axi_AWLEN),
       .wr_fa_axi_AWVALID(wr_fa_axi_AWVALID),
       .wr_fa_axi_AWREADY(wr_fa_axi_AWREADY),
       .wr_fa_axi_WDATA(wr_fa_axi_WDATA),
       .wr_fa_axi_WLAST(wr_fa_axi_WLAST),
       .wr_fa_axi_WVALID(wr_fa_axi_WVALID),
       .wr_fa_axi_WREADY(wr_fa_axi_WREADY),
       .wr_fa_axi_BRESP(wr_fa_axi_BRESP),
       .wr_fa_axi_BVALID(wr_fa_axi_BVALID),

       .wr_pl_axi_AWADDR(wr_pl_axi_AWADDR),
       .wr_pl_axi_AWLEN(wr_pl_axi_AWLEN),
       .wr_pl_axi_AWVALID(wr_pl_axi_AWVALID),
       .wr_pl_axi_AWREADY(wr_pl_axi_AWREADY),
       .wr_pl_axi_WDATA(wr_pl_axi_WDATA),
       .wr_pl_axi_WLAST(wr_pl_axi_WLAST),
       .wr_pl_axi_WVALID(wr_pl_axi_WVALID),
       .wr_pl_axi_WREADY(wr_pl_axi_WREADY),
       .wr_pl_axi_BRESP(wr_pl_axi_BRESP),
       .wr_pl_axi_BVALID(wr_pl_axi_BVALID),

       .wr_ph_axi_AWADDR(wr_ph_axi_AWADDR),
       .wr_ph_axi_AWLEN(wr_ph_axi_AWLEN),
       .wr_ph_axi_AWVALID(wr_ph_axi_AWVALID),
       .wr_ph_axi_AWREADY(wr_ph_axi_AWREADY),
       .wr_ph_axi_WDATA(wr_ph_axi_WDATA),
       .wr_ph_axi_WLAST(wr_ph_axi_WLAST),
       .wr_ph_axi_WVALID(wr_ph_axi_WVALID),
       .wr_ph_axi_WREADY(wr_ph_axi_WREADY),
       .wr_ph_axi_BRESP(wr_ph_axi_BRESP),
       .wr_ph_axi_BVALID(wr_ph_axi_BVALID)
    );

endmodule
