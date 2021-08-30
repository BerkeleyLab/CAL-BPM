//
// Read ADC data and clock
// Overflow values are ignored.  In fact the overflow lines from
// ADC 3 are not even brought across from the AFE board.
//
// Values starting with adc or ADC are in ADC clock domain.
// Value starting with evr is in event receiver clock domain.
// Values starting with anything else are in system clock domain.
//
module adcReadout #(parameter ADC_WIDTH  = 16,
                    parameter NADC       = 4,
                    parameter DATA_WIDTH = 32,
                    parameter QUANTIZE   = "false"
          ) (
          input                            adcClk,
          input                            ADC0_CLK_P,  ADC0_CLK_N,
          input            [ADC_WIDTH-1:0] ADC0_DATA_P, ADC0_DATA_N,
          input                            ADC1_CLK_P,  ADC1_CLK_N,
          input            [ADC_WIDTH-1:0] ADC1_DATA_P, ADC1_DATA_N,
          input                            ADC2_CLK_P,  ADC2_CLK_N,
          input            [ADC_WIDTH-1:0] ADC2_DATA_P, ADC2_DATA_N,
          input                            ADC3_CLK_P,  ADC3_CLK_N,
          input            [ADC_WIDTH-1:0] ADC3_DATA_P, ADC3_DATA_N,
          output wire           [NADC-1:0] clkStates,
          output wire [NADC*ADC_WIDTH-1:0] adcRawData,
          output wire      [ADC_WIDTH-1:0] adc0, adc1, adc2, adc3,
          output reg                       adcUseThisSample,
          output reg                       adcExceedsThreshold,
          input                            sysClk,
          output reg            [NADC-1:0] clippedAdc,
          output wire      [ADC_WIDTH-1:0] peak0, peak1, peak2, peak3,
          input                            gpioStrobe,
          input           [DATA_WIDTH-1:0] gpioData,
          output wire     [DATA_WIDTH-1:0] gpioCSR,
          input                            evrHeartbeatMarker);

wire                 adcClk0i, adcClk1i, adcClk2i, adcClk3i;
wire [ADC_WIDTH-1:0] adc0i, adc1i, adc2i, adc3i;
reg  [ADC_WIDTH-1:0] threshold = 0, quantize = 0;

(* IOB = "FORCE" *) reg      [NADC-1:0] adcClks;

//
// Input buffers for data lines and per-ADC clocks.
//
genvar i;
generate
for (i = 0 ; i < ADC_WIDTH ; i = i + 1) begin : adcBuf
    IBUFDS adcBuf0 (.O(adc0i[i]), .I(ADC0_DATA_P[i]), .IB(ADC0_DATA_N[i]));
    IBUFDS adcBuf1 (.O(adc1i[i]), .I(ADC1_DATA_P[i]), .IB(ADC1_DATA_N[i]));
    IBUFDS adcBuf2 (.O(adc2i[i]), .I(ADC2_DATA_P[i]), .IB(ADC2_DATA_N[i]));
    IBUFDS adcBuf3 (.O(adc3i[i]), .I(ADC3_DATA_P[i]), .IB(ADC3_DATA_N[i]));
end
endgenerate
IBUFDS adcClk0Buf (.O(adcClk0i), .I(ADC0_CLK_P), .IB(ADC0_CLK_N));
IBUFDS adcClk1Buf (.O(adcClk1i), .I(ADC1_CLK_P), .IB(ADC1_CLK_N));
IBUFDS adcClk2Buf (.O(adcClk2i), .I(ADC2_CLK_P), .IB(ADC2_CLK_N));
IBUFDS adcClk3Buf (.O(adcClk3i), .I(ADC3_CLK_P), .IB(ADC3_CLK_N));

//
// Latch data.
// Also latch individual ADC clocks for use in ADC clock delay adjustment.
//
(* IOB = "FORCE" *) reg [NADC*ADC_WIDTH-1:0] adcLatchedData;
always @(posedge adcClk) begin
    adcClks <= { adcClk3i, adcClk2i, adcClk1i, adcClk0i };
    adcLatchedData <= { adc3i, adc2i, adc1i, adc0i }; 
end
if (QUANTIZE == "true") begin
  reg [NADC*ADC_WIDTH-1:0] adcQuantized;
  always @(posedge adcClk) begin
    adcQuantized <= adcLatchedData & {~quantize,~quantize,~quantize,~quantize};
  end
  assign adcRawData = adcQuantized;
end
else begin
    assign adcRawData = adcLatchedData;
end

//
// Process latched ADC values
//
wire      [ADC_WIDTH-1:0] adcThreshold;
wire [NADC*ADC_WIDTH-1:0] adcsWashed;
wire [NADC*ADC_WIDTH-1:0] adcsPeak;
wire           [NADC-1:0] adcsAboveThreshold;

generate
for (i = 0 ; i < NADC ; i = i + 1) begin : adcIn
    wire [ADC_WIDTH-1:0] adcRaw = adcRawData[i*ADC_WIDTH+:ADC_WIDTH];
    wire [ADC_WIDTH-1:0] adcWashed;
    reg  [ADC_WIDTH-1:0] adcAbsWashed;
    wire adcAboveThreshold = (adcAbsWashed > adcThreshold);

    //
    // Check for clipping
    // Stretch ADC clock domain flag to ensure that
    // it's seen in the system clock domain.
    //
    reg                  adcClipFlag;
    reg            [1:0] adcClipStretch;
    always @(posedge(adcClk)) begin
        if ((adcRaw == {1'b0, {ADC_WIDTH-1{1'b1}}})
         || (adcRaw == {1'b1, {ADC_WIDTH-1{1'b0}}})) begin
            adcClipFlag <= 1'b1;
            adcClipStretch <= ~0;
        end
        else if (adcClipStretch != 0) begin
            adcClipStretch <= adcClipStretch - 1;
        end
        else begin
            adcClipFlag <= 1'b0;
        end
    end
    reg [4:0] clipTimer;
    always @(posedge sysClk) begin
        if (adcClipFlag) begin
            clipTimer <= 5'h1F;
            clippedAdc[i] <= 1'b1;
        end
        else if (tick) begin 
            if (clipTimer != 0) begin
                clipTimer <= clipTimer - 1;
            end
            else begin
                clippedAdc[i] <= 1'b0;
            end
        end
    end

    //
    // Remember peak ADC excursion
    //
    reg  [ADC_WIDTH-1:0] adcAbsRaw, adcPeak, adcPeakHold, peak;
    assign adcsPeak[i*ADC_WIDTH+:ADC_WIDTH] = adcPeakHold;
    always @(posedge(adcClk)) begin
        adcAbsRaw <= (adcRaw[ADC_WIDTH-1]) ? -adcRaw : adcRaw;
        if (adcHeartbeatMarker) begin
            adcPeakHold <= adcPeak;
            adcPeak <= adcAbsRaw;
        end
        else begin
            if (adcAbsRaw > adcPeak) adcPeak <= adcAbsRaw;
        end
    end
    always @(posedge sysClk) begin
        if (sysLatchPeak) peak <= adcPeakHold;
    end

    //
    // Remove DC
    //
    washout #(.WIDTH(ADC_WIDTH), .L2_ALPHA(20)) dcBlock (.clk(adcClk),
                                                         .enable(1'b1),
                                                         .x(adcRaw),
                                                         .y(adcWashed));
    assign adcsWashed[i*ADC_WIDTH+:ADC_WIDTH] = adcWashed;

    //
    // Watch for signals above threshold.
    //
    always @(posedge(adcClk)) begin
        adcAbsWashed <= (adcWashed[ADC_WIDTH-1]) ? -adcWashed : adcWashed;
    end
    assign adcsAboveThreshold[i] = adcAboveThreshold;
end
endgenerate

//
// Forward peak values
//
assign peak0 = adcsPeak[0*ADC_WIDTH+:ADC_WIDTH];
assign peak1 = adcsPeak[1*ADC_WIDTH+:ADC_WIDTH];
assign peak2 = adcsPeak[2*ADC_WIDTH+:ADC_WIDTH];
assign peak3 = adcsPeak[3*ADC_WIDTH+:ADC_WIDTH];

//
// Delay values to give single pass self triggering time to process
//
wire [NADC*ADC_WIDTH-1:0] adcsDelayed;
adcReadoutDelay adcReadoutDelay (.clk(adcClk),
                                 .d(adcsWashed),
                                 .q({adc3, adc2, adc1, adc0}));

//
// Watch for data excursions beyond threshold
//
assign gpioCSR = { quantize, threshold };
always @(posedge sysClk) begin
    if (gpioStrobe) begin
        threshold <= gpioData[0+:ADC_WIDTH];
        if (QUANTIZE == "true") begin
            quantize <= gpioData[ADC_WIDTH+:ADC_WIDTH];
        end
        else begin
            quantize <= {ADC_WIDTH{1'b0}};
        end
    end
end
forwardData #(.DATA_WIDTH(ADC_WIDTH)) fwThreshold(.inClk(sysClk),
                                                  .inData(threshold),
                                                  .outClk(adcClk),
                                                  .outData(adcThreshold));
// Use about equal number of samples pre and post trigger for RMS.
// The delay block provides 12 samples delay of which 4 are taken up
// by the trigger computation before the RMS summation blocks.
reg [4:0] adcUseSampleCounter = 0;
always @(posedge adcClk) begin
    if (|adcsAboveThreshold) begin
        adcExceedsThreshold <= 1;
        adcUseThisSample <= 1;
        adcUseSampleCounter <= 18;
    end
    else begin
        adcExceedsThreshold <= 0;
        if (adcUseSampleCounter != 0) begin
            adcUseSampleCounter <= adcUseSampleCounter - 1;
        end
        else begin
            adcUseThisSample <= 0;
        end
    end
end

//
// Forward ADC clock values to system clock domain
// No need for fancy clock domain crossing logic since
// we don't care if the values are metastable because
// of how they're used in the ADC clock delay adjust code.
//
assign clkStates = adcClks;

//
// Copy strobes between clock domains
//
(* ASYNC_REG="TRUE" *) reg adcHb_m = 0, adcHb = 0;
reg adcHb_d = 0, adcHeartbeatMarker = 0, adcToggle = 0;
always @(posedge adcClk) begin
    adcHb_m <= evrHeartbeatMarker;
    adcHb <= adcHb_m;
    adcHb_d <= adcHb;
    adcHeartbeatMarker <= (adcHb && !adcHb_d);
    if (adcHeartbeatMarker) adcToggle <= !adcToggle;
end
(* ASYNC_REG="TRUE" *) reg sysAdctoggle_m = 0, sysAdctoggle = 0;
reg sysAdcMatch = 0, sysLatchPeak = 0;
always @(posedge sysClk) begin
    sysAdctoggle_m <= adcToggle;
    sysAdctoggle <= sysAdctoggle_m;
    if (sysAdcMatch != sysAdctoggle) begin
        sysAdcMatch <= sysAdctoggle;
        sysLatchPeak <= 1;
    end
    else begin
        sysLatchPeak <= 0;
    end
end

//
// Produce slow clock for clip signal stretching
//
parameter SYSCLK_RATE = 100000000;
parameter SYSCLK_TICKS_PER_CENTISECOND = SYSCLK_RATE / 100;
parameter SYSCLK_TICK_DIVISOR_WIDTH = $clog2(SYSCLK_TICKS_PER_CENTISECOND);
reg  [SYSCLK_TICK_DIVISOR_WIDTH-1:0] sysClkTickDivisor = 0;
reg                                  tick;
always @(posedge sysClk) begin
    if (sysClkTickDivisor == 0) begin
        sysClkTickDivisor <= SYSCLK_TICKS_PER_CENTISECOND - 1;
        tick <= 1'b1;
    end
    else begin
        sysClkTickDivisor <= sysClkTickDivisor - 1;
        tick <= 1'b0;
    end
end

endmodule
