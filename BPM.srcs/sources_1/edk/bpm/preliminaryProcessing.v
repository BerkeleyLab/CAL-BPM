// Preliminary signal processing
// Convert ADC values to synchronously-demodulated or RMS magnitudes
//
module preliminaryProcessing #(
    parameter SYSCLK_RATE             = 100000000,
    parameter MAG_WIDTH               = 26,
    parameter SAMPLES_PER_TURN        = 77,
    parameter NADC                    = 4,
    parameter ADC_WIDTH               = 16,
    parameter DATA_WIDTH              = 32,
    parameter TURNS_PER_PT            = 152000,
    parameter CIC_STAGES              = 3,
    parameter CIC_FA_DECIMATE         = 76,
    parameter CIC_SA_DECIMATE         = 1000,
    parameter GPIO_LO_RF_ROW_CAPACITY = -1,
    parameter GPIO_LO_PT_ROW_CAPACITY = -1) (
    input                        clk,
    input       [DATA_WIDTH-1:0] gpioData,
    input                        localOscillatorAddressStrobe,
    input                        localOscillatorCsrStrobe,
    output wire [DATA_WIDTH-1:0] localOscillatorCsr,
    input                        sumShiftCsrStrobe,
    output wire [DATA_WIDTH-1:0] sumShiftCsr,
    input  wire                  autotrimCsrStrobe,
    input  wire                  autotrimThresholdStrobe,
    input             [NADC-1:0] autotrimGainStrobes,
    output wire [DATA_WIDTH-1:0] autotrimCsr, autotrimThreshold,
    output wire [DATA_WIDTH-1:0] gainRBK0, gainRBK1, gainRBK2, gainRBK3,
    input                 [63:0] sysTimestamp,
    input                        adcClk,
    input        [ADC_WIDTH-1:0] adc0, adc1, adc2, adc3,
    input                        adcExceedsThreshold, adcUseThisSample,
    output wire                  adcLoSynced,
    input                        evrClk,
    input                        evrFaMarker, evrSaMarker,
    input                 [63:0] evrTimestamp,
    input                        evrPtTrigger,evrSinglePassTrigger,evrHbMarker,
    output wire                  PT_P, PT_N,
    output reg                   sysSingleTrig,
    output wire                  tbtToggle,
    output wire  [MAG_WIDTH-1:0] rfTbtMag0, rfTbtMag1, rfTbtMag2, rfTbtMag3,
    output wire                  faToggle,
    output wire  [MAG_WIDTH-1:0] rfFaMag0, rfFaMag1, rfFaMag2, rfFaMag3,
    output wire                  adcTbtLoadAccumulator,
    output wire                  adcTbtLatchAccumulator,
    output wire                  adcMtLoadAndLatch,
    output reg                   saToggle,
    output reg            [63:0] sysSaTimestamp,
    output reg   [MAG_WIDTH-1:0] rfMag0, rfMag1, rfMag2, rfMag3,
    output reg   [MAG_WIDTH-1:0] plMag0, plMag1, plMag2, plMag3,
    output reg   [MAG_WIDTH-1:0] phMag0, phMag1, phMag2, phMag3,
    output reg                   ptToggle,
    output reg                   overflowFlag);

parameter LO_WIDTH   = 18;
parameter GAIN_WIDTH = MAG_WIDTH + 1;

wire sysUseRMS           = localOscillatorCsr[2];
wire sysIsSinglePassMode = localOscillatorCsr[1];
wire sysPtTimeMuxMode    = autotrimCsr[2];
wire sysUsePulsePt       = autotrimCsr[3];
wire sysPtSimulateBeam   = autotrimCsr[31];

//////////////////////////////////////////////////////////////////////////////
//                              EVR CLOCK DOMAIN                            //
//                                                                          //

// Get values to EVR clock domain
// Latch in EVR clock domain to ensure that all BPMs
// have exactly the same SA timestamp.
reg  adcMtLoadAndLatchToggle = 0;
(* ASYNC_REG="TRUE" *) reg evrMtLoadAndLatchToggle_m, evrUsePulsePt_m;
reg evrMtLoadAndLatchToggle, evrMtLoadAndLatchToggle_d, evrUsePulsePt;
reg [63:0] evrSaTimestamp;
reg evrSaMarker_d;
always @(posedge evrClk) begin
    evrMtLoadAndLatchToggle_m <= adcMtLoadAndLatchToggle;
    evrMtLoadAndLatchToggle   <= evrMtLoadAndLatchToggle_m;
    evrMtLoadAndLatchToggle_d <= evrMtLoadAndLatchToggle;
    evrUsePulsePt_m <= sysUsePulsePt;
    evrUsePulsePt   <= evrUsePulsePt_m;

    evrSaMarker_d <= evrSaMarker;
    if (evrSaMarker && !evrSaMarker_d) evrSaTimestamp <= evrTimestamp;
end

//
// Time-multiplexed pilot tone and simulated beam
//
wire evrPtWarning, evrPtStable;
pilotTone pilotTone(
    .evrClk(evrClk),
    .aEnable(sysPtTimeMuxMode),
    .aSimulate(sysPtSimulateBeam),
    .usePulsePt(evrUsePulsePt),
    .trigger(evrPtTrigger),
    .pulseStrobe(evrMtLoadAndLatchToggle != evrMtLoadAndLatchToggle_d),
    .ptWarning(evrPtWarning),
    .ptStable(evrPtStable),
    .PT_P(PT_P),
    .PT_N(PT_N));

//////////////////////////////////////////////////////////////////////////////
//                              ADC CLOCK DOMAIN                            //
//                                                                          //

//
// Get assorted timing values into ADC clock domain.
//
(* ASYNC_REG="TRUE" *) reg adcUseRMS_m = 0, adcUsePulsePt_m = 0;
(* ASYNC_REG="TRUE" *) reg adcIsSinglePassMode_m = 0, adcPtWarning_m = 0;
(* ASYNC_REG="TRUE" *) reg adcFaEvent_m = 0, adcSaEvent_m = 0;
(* ASYNC_REG="TRUE" *) reg adcHbEvent_m = 0, adcSpEvent_m = 0;
reg adcUseRMS = 0, adcUsePulsePt = 0;
reg adcIsSinglePassMode = 0, adcPtWarning = 0;
reg adcFaEvent = 0, adcFaEvent_d1 = 0, adcFaSync = 0;
reg adcSaEvent = 0, adcSaEvent_d1 = 0, adcSaSync = 0;
reg adcHbEvent = 0, adcHbEvent_d1 = 0;
reg adcSpEvent = 0;
reg adcFaDecimateFlag = 0, adcSaDecimateFlag = 0;
reg adcUsingEvrTrigger = 0;
reg [1:0] adcHbDivider = 2; reg adcSyncMarker = 0;
always @(posedge adcClk) begin
    adcUseRMS_m           <= sysUseRMS;
    adcUseRMS             <= adcUseRMS_m;
    adcIsSinglePassMode_m <= sysIsSinglePassMode;
    adcIsSinglePassMode   <= adcIsSinglePassMode_m;
    adcUsePulsePt_m       <= sysUsePulsePt;
    adcUsePulsePt         <= adcUsePulsePt_m;
    adcPtWarning_m        <= evrPtWarning;
    adcPtWarning          <= adcPtWarning_m;

    adcFaEvent_m  <= evrFaMarker;
    adcFaEvent    <= adcFaEvent_m;
    adcFaEvent_d1 <= adcFaEvent;
    if (adcFaEvent && !adcFaEvent_d1 && !adcFaSync) adcFaSync <= 1;

    adcSaEvent_m  <= evrSaMarker;
    adcSaEvent    <= adcSaEvent_m;
    adcSaEvent_d1 <= adcSaEvent;
    if (adcSaEvent && !adcSaEvent_d1 && !adcSaSync) adcSaSync <= 1;

    adcHbEvent_m  <= evrHbMarker;
    adcHbEvent    <= adcHbEvent_m;
    adcHbEvent_d1 <= adcHbEvent;

    adcSpEvent_m  <= evrSinglePassTrigger;
    adcSpEvent    <= adcSpEvent_m;
    if (adcSpEvent) adcUsingEvrTrigger <= 1;

    // Generate decimation requests
    if (adcMtLoadAndLatch) begin
        adcMtLoadAndLatchToggle <= !adcMtLoadAndLatchToggle;
        if (adcFaSync) begin
            adcFaSync <= 0;
            adcFaDecimateFlag <= 1;
        end
        else begin
            adcFaDecimateFlag <= 0;
        end
        if (adcSaSync) begin
            adcSaSync <= 0;
            adcSaDecimateFlag <= 1;
        end
        else begin
            adcSaDecimateFlag <= 0;
        end
    end

    if (adcHbEvent && !adcHbEvent_d1) begin
        // Use only every third hearbeat event to allow for RF accumulation
        // over multiples of three turns.  We assume that the ADC ticks per
        // heartbeat is already a multiple of two and five.
        if (adcHbDivider == 0) begin
            adcHbDivider <= 2;
            adcSyncMarker <= 1;
        end
        else begin
            adcHbDivider <= adcHbDivider - 1;
        end
    end
    else begin
        adcSyncMarker <= 0;
    end
end

//
// Local oscillator
//
reg adcHoldoff = 0;
wire adcSinglePassStart = adcIsSinglePassMode && !adcPtWarning && !adcHoldoff &&
                   ((adcExceedsThreshold && !adcUsingEvrTrigger) || adcSpEvent);
wire [LO_WIDTH-1:0] adcRfCos, adcRfSin, adcPlCos, adcPlSin, adcPhCos, adcPhSin;
(*mark_debug="false"*)
localOscillator #(.OUTPUT_WIDTH(LO_WIDTH),
                  .GPIO_LO_RF_ROW_CAPACITY(GPIO_LO_RF_ROW_CAPACITY),
                  .GPIO_LO_PT_ROW_CAPACITY(GPIO_LO_PT_ROW_CAPACITY))
  localOscillator(.clk(adcClk),
                  .adcSyncMarker(adcSyncMarker),
                  .singleStart(adcSinglePassStart),
                  .sysClk(clk),
                  .sysAddressStrobe(localOscillatorAddressStrobe),
                  .sysGpioStrobe(localOscillatorCsrStrobe),
                  .sysGpioData(gpioData),
                  .sysGpioCsr(localOscillatorCsr),
                  .tbtLoadAccumulator(adcTbtLoadAccumulator),
                  .tbtLatchAccumulator(adcTbtLatchAccumulator),
                  .mtLoadAndLatch(adcMtLoadAndLatch),
                  .loSynced(adcLoSynced),
                  .rfCos(adcRfCos),
                  .rfSin(adcRfSin),
                  .plCos(adcPlCos),
                  .plSin(adcPlSin),
                  .phCos(adcPhCos),
                  .phSin(adcPhSin));

// Syncronous demodulator multipliers
// Product can be one bit narrower since the local oscillator value, or
// the scaled ADC value taking the place of the local oscillator can
// never take on negative full scale value.
localparam PRODUCT_WIDTH = ADC_WIDTH + LO_WIDTH - 1;
wire [4*ADC_WIDTH-1:0] adcs = { adc3, adc2, adc1, adc0 };
wire [8*PRODUCT_WIDTH-1:0] rfProducts, plProducts, phProducts;

genvar i; generate
for (i = 0 ; i < NADC ; i = i + 1) begin : adcDemod

// If RMS values are being computed:
//  - the RF ADC value is replaced with 0 if adcUseThisSample is not asserted
//    or pilot tones may be on.
//  - the PT ADC value is replaced with 0 if adcUseThisSample is not asserted
//    and pulse pilot tones are enabled.
//  - the local oscillator sine term is replaced with 0.
//  - the local oscillator cosine term is replaced with the scaled ADC value.
//    Note that the ADC value is not shifted all the way up.  This is to
//    ensure that the 'local oscillator' value can never take on the full
//    scale negative value.
wire [ADC_WIDTH-1:0] adc = adcs[i*ADC_WIDTH+:ADC_WIDTH];
wire [LO_WIDTH-1:0] adcLO={adc[ADC_WIDTH-1], adc, {LO_WIDTH-ADC_WIDTH-1{1'b0}}};
wire [ADC_WIDTH-1:0] rfADC = adcPtWarning || (adcUseRMS && !adcUseThisSample) ?
                                                        {ADC_WIDTH{1'b0}} : adc;
wire [ADC_WIDTH-1:0] ptADC = adcUsePulsePt && adcUseRMS && !adcUseThisSample ?
                                                        {ADC_WIDTH{1'b0}} : adc;
// Set multiplier to ADC value for RMS computation or table entry for I-Q.
wire [LO_WIDTH-1:0] rfLOcos = adcUseRMS ? adcLO : adcRfCos;
wire [LO_WIDTH-1:0] rfLOsin = adcUseRMS ? {LO_WIDTH{1'b0}} : adcRfSin;
wire [LO_WIDTH-1:0] plLOcos = adcUseRMS ? adcLO : adcPlCos;
wire [LO_WIDTH-1:0] plLOsin = adcUseRMS ? {LO_WIDTH{1'b0}} : adcPlSin;
wire [LO_WIDTH-1:0] phLOcos = adcUseRMS ? adcLO : adcPhCos;
wire [LO_WIDTH-1:0] phLOsin = adcUseRMS ? {LO_WIDTH{1'b0}} : adcPhSin;
wire signed [PRODUCT_WIDTH-1:0] adcRfPrdI, adcRfPrdQ;
wire signed [PRODUCT_WIDTH-1:0] adcPlPrdI, adcPlPrdQ, adcPhPrdI, adcPhPrdQ;

demodMultiplier dmMulRfI(.clk(adcClk), .a(rfADC), .b(rfLOcos), .p(adcRfPrdI));
demodMultiplier dmMulRfQ(.clk(adcClk), .a(rfADC), .b(rfLOsin), .p(adcRfPrdQ));
demodMultiplier dmMulPlI(.clk(adcClk), .a(ptADC), .b(plLOcos), .p(adcPlPrdI));
demodMultiplier dmMulPlQ(.clk(adcClk), .a(ptADC), .b(plLOsin), .p(adcPlPrdQ));
demodMultiplier dmMulPhI(.clk(adcClk), .a(ptADC), .b(phLOcos), .p(adcPhPrdI));
demodMultiplier dmMulPhQ(.clk(adcClk), .a(ptADC), .b(phLOsin), .p(adcPhPrdQ));

assign rfProducts[i*2*PRODUCT_WIDTH+:2*PRODUCT_WIDTH] = {adcRfPrdQ, adcRfPrdI};
assign plProducts[i*2*PRODUCT_WIDTH+:2*PRODUCT_WIDTH] = {adcPlPrdQ, adcPlPrdI};
assign phProducts[i*2*PRODUCT_WIDTH+:2*PRODUCT_WIDTH] = {adcPhPrdQ, adcPhPrdI};

end // endfor
endgenerate

// Watch for accumulator overflows
// Stretch to allow detection in system clock domain.
reg adcOverflowFlag = 0;
wire tbtSumOverflow, rfSumOverflow, plSumOverflow, phSumOverflow;
reg [3:0] adcOverflowsStretched;
reg [9:0] adcOvTimer = ~0;
always @(posedge adcClk) begin
    if (tbtSumOverflow || rfSumOverflow || plSumOverflow || phSumOverflow) begin
        adcOvTimer <= ~0;
        adcOverflowsStretched <= adcOverflowsStretched |
                  {phSumOverflow, plSumOverflow, rfSumOverflow, tbtSumOverflow};
        adcOverflowFlag <= 1;
    end
    else begin
        adcOvTimer <= adcOvTimer - 1;
        if (adcOvTimer == 0) begin
            adcOverflowFlag <= 0;
            adcOverflowsStretched <= 0;
        end
    end
end

// Hold off single-pass triggers after single pass trigger.
reg [25:0] adcHoldoffCounter;
always @(posedge adcClk) begin
    if (adcSinglePassStart) begin
        adcHoldoff <= 1;
        adcHoldoffCounter <= ~0;
    end
    else if (adcHoldoffCounter != 0) begin
        adcHoldoffCounter <= adcHoldoffCounter - 1;
    end
    else begin
        adcHoldoff <= 0;
    end
end

//
// Synchronous demodulator accumulators
//
reg [3:0] adcTbtSumShift = 0, adcMtSumShift = 0;
wire adcTbtToggle, adcMtToggle;
wire [8*MAG_WIDTH-1:0] tbtSums, rfSums, plSums, phSums;

// Turn-by-turn
// Used for single-pass, too.
sdAccumulate #(.PRODUCT_WIDTH(PRODUCT_WIDTH),
               .SUM_WIDTH(MAG_WIDTH),
               .SAMPLES_PER_TURN(SAMPLES_PER_TURN),
               .TURNS_PER_SUM(1))
  sdTBTaccumulator(.clk(adcClk),
    .useRMS(adcUseRMS),
    .products(rfProducts),
    .loadEnable(adcTbtLoadAccumulator),
    .latchEnable(adcTbtLatchAccumulator),
    .sumShift(adcTbtSumShift),
    .sumsToggle(adcTbtToggle),
    .sums(tbtSums),
    .overflowFlag(tbtSumOverflow));

// Remainder of accumulators update over identical multi-turn interval.
// Assume typical case for TURNS_PER_SUM.
// Multi-turn sum shift will get things back into range if necessary.
sdAccumulate #(.PRODUCT_WIDTH(PRODUCT_WIDTH),
               .SUM_WIDTH(MAG_WIDTH),
               .SAMPLES_PER_TURN(SAMPLES_PER_TURN),
               .TURNS_PER_SUM(2))
  sdRFaccumulator(.clk(adcClk),
    .useRMS(adcUseRMS),
    .products(rfProducts),
    .loadEnable(adcMtLoadAndLatch),
    .latchEnable(adcMtLoadAndLatch),
    .sumShift(adcMtSumShift),
    .sumsToggle(adcMtToggle),
    .sums(rfSums),
    .overflowFlag(rfSumOverflow));

sdAccumulate #(.PRODUCT_WIDTH(PRODUCT_WIDTH),
               .SUM_WIDTH(MAG_WIDTH),
               .SAMPLES_PER_TURN(SAMPLES_PER_TURN),
               .TURNS_PER_SUM(2))
  sdPLaccumulator(.clk(adcClk),
    .useRMS(adcUseRMS),
    .products(plProducts),
    .loadEnable(adcMtLoadAndLatch),
    .latchEnable(adcMtLoadAndLatch),
    .sumShift(adcMtSumShift),
    .sums(plSums),
    .overflowFlag(plSumOverflow));

sdAccumulate #(.PRODUCT_WIDTH(PRODUCT_WIDTH),
               .SUM_WIDTH(MAG_WIDTH),
               .SAMPLES_PER_TURN(SAMPLES_PER_TURN),
               .TURNS_PER_SUM(2))
  sdPHaccumulator(.clk(adcClk),
    .useRMS(adcUseRMS),
    .products(phProducts),
    .loadEnable(adcMtLoadAndLatch),
    .latchEnable(adcMtLoadAndLatch),
    .sumShift(adcMtSumShift),
    .sums(phSums),
    .overflowFlag(phSumOverflow));

//                                                                          //
//                              ADC CLOCK DOMAIN                            //
//////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////
//                             SYSTEM CLOCK DOMAIN                          //
//                                                                          //

// Watch for overflows
// Widen for easy detection by IOC
(* ASYNC_REG="TRUE" *) reg sysAdcOverflowFlag_m = 0, sysAdcOverflowFlag = 0;
(* ASYNC_REG="TRUE" *) reg sysSingleTrig_m;
reg [$clog2(SYSCLK_RATE/2)-1:0] ovTimer;
always @(posedge clk) begin
    sysAdcOverflowFlag_m <= adcOverflowFlag;
    sysAdcOverflowFlag   <= sysAdcOverflowFlag_m;
    if (sysAdcOverflowFlag || cordicOverflowFlag) begin
        ovTimer <= ~0;
        overflowFlag <= 1;
    end
    else begin
        ovTimer <= ovTimer - 1;
        if (ovTimer == 0) overflowFlag <= 0;
    end
    sysSingleTrig_m <= adcHoldoff;
    sysSingleTrig   <= sysSingleTrig_m;
end

//
// Multiplex all channels through the single normalize/CORDIC block.
// Prioritize turn-by-turn, then low then high pilot tones, then rf.
//
localparam STREAM_SELECT_WIDTH = 2;
localparam STREAM_TBT = 2'd0,
           STREAM_RF  = 2'd1,
           STREAM_PL  = 2'd2,
           STREAM_PH  = 2'd3;

// Get ADC 'accumulator ready' toggles into system clock domain
(* ASYNC_REG="TRUE" *) reg sysTbtToggle_m, sysMtToggle_m;
reg sysTbtToggle, sysMtToggle_p, sysMtToggle;
reg sysTbtMatch, sysMtMatch_p, sysRfMatch, sysPlMatch, sysPhMatch;
reg sysFaDecimateFlag, sysSaDecimateFlag;

wire cordicREADY;

wire sumVALID = ((sysTbtMatch != sysTbtToggle)
              || (sysPlMatch  != sysMtToggle)
              || (sysPhMatch  != sysMtToggle)
              || (sysRfMatch  != sysMtToggle));

wire [STREAM_SELECT_WIDTH-1:0] sumSelect =
                       (sysTbtMatch != sysTbtToggle) ? STREAM_TBT :
                       (sysPlMatch  != sysMtToggle)  ? STREAM_PL  :
                       (sysPhMatch  != sysMtToggle)  ? STREAM_PH  : STREAM_RF;

wire [(8*MAG_WIDTH)-1:0] sums = (sumSelect == STREAM_TBT) ? tbtSums :
                                (sumSelect == STREAM_PL)  ? plSums  :
                                (sumSelect == STREAM_PH)  ? phSums  : rfSums;

// Don't bother with any fancy clock domain crossing logic for the sum
// shift values since changes to these are rare and will at worst cause
// one (TBT, RF or Pilot Tone) value to be computed improperly.
reg [3:0] faCICshift = 0;
wire [2:0] cicStageCount = CIC_STAGES;
wire [9:0] cicFaDecimate = CIC_FA_DECIMATE;
assign sumShiftCsr = { cicStageCount,
                       cicFaDecimate,
                       {DATA_WIDTH-3-10-4-3*4{1'b0}},
                       adcOverflowsStretched,
                       faCICshift, adcMtSumShift, adcTbtSumShift };
always @(posedge clk) begin
    if (sumShiftCsrStrobe) begin
        {faCICshift,adcMtSumShift,adcTbtSumShift} <= gpioData[0+:3*4];
    end
    sysTbtToggle_m <= adcTbtToggle;
    sysTbtToggle   <= sysTbtToggle_m;
    sysMtToggle_m <= adcMtToggle;
    sysMtToggle_p <= sysMtToggle_m;
    sysMtToggle   <= sysMtToggle_p;
    // Sample decimation flags one cycle early so they're
    // valid when sumVALID is asserted.
    if (sysMtMatch_p != sysMtToggle_p) begin
        sysMtMatch_p <= sysMtToggle_p;
        sysFaDecimateFlag <= adcFaDecimateFlag;
        sysSaDecimateFlag <= adcSaDecimateFlag;
    end
    if (cordicREADY) begin
        // Ensure that sumVALID and sumSelect ordering matches this.
        if (sysTbtMatch != sysTbtToggle) sysTbtMatch <= !sysTbtMatch;
        else if (sysPlMatch != sysMtToggle) sysPlMatch <= !sysPlMatch;
        else if (sysPhMatch != sysMtToggle) sysPhMatch <= !sysPhMatch;
        else if (sysRfMatch != sysMtToggle) sysRfMatch <= !sysRfMatch;
    end
end

// The CORDIC block
// Shared by all channels and all streams
// Extra bits are SA decimation flag, FA decimation flag and channel number.
localparam CORDIC_M_TUSER_WIDTH = STREAM_SELECT_WIDTH + 4;
wire [CORDIC_M_TUSER_WIDTH-1:0] cordicTUSER;
wire [1:0] cordicADC = cordicTUSER[0+:2];
wire [STREAM_SELECT_WIDTH-1:0] cordicStream=cordicTUSER[2+:STREAM_SELECT_WIDTH];
wire cordicFaDecimateFlag = cordicTUSER[2+STREAM_SELECT_WIDTH];
wire cordicSaDecimateFlag = cordicTUSER[3+STREAM_SELECT_WIDTH];
wire cordicTVALID;
wire cordicOverflowFlag;
wire  [MAG_WIDTH-1:0] cordicMagnitude;
fourCordic #(.IO_WIDTH(MAG_WIDTH),
             .S_TUSER_WIDTH(2+STREAM_SELECT_WIDTH))
  fourCordic (.clk(clk),
              .S_TDATA(sums),
              .S_TUSER({sysSaDecimateFlag, sysFaDecimateFlag, sumSelect}),
              .S_TVALID(sumVALID),
              .S_TREADY(cordicREADY),
              .M_TDATA(cordicMagnitude),
              .M_TUSER(cordicTUSER),
              .M_TVALID(cordicTVALID),
              .overflowFlag(cordicOverflowFlag));

// TBT values don't undergo any filtering
reg [(4*MAG_WIDTH)-1:0] tbtMags;
reg tbtTrimStrobe = 0;
always @(posedge clk) begin
    if (cordicTVALID && (cordicStream == STREAM_TBT)) begin
        tbtMags[cordicADC*MAG_WIDTH+: MAG_WIDTH] = cordicMagnitude;
        if (cordicADC == 2'd3) tbtTrimStrobe <= 1;
    end
    else begin
        tbtTrimStrobe <= 0;
    end
end

// CIC PILOT TONE FA DECIMATION
wire ptDecimatedToggle;
wire [(4*MAG_WIDTH)-1:0] decimatedPlMags, decimatedPhMags;
faDecimate #(.DATA_WIDTH(MAG_WIDTH),
             .DECIMATION_FACTOR(CIC_FA_DECIMATE),
             .STAGES(CIC_STAGES))
  plDecimate (
    .clk(clk),
    .inputData(cordicMagnitude),
    .inputChannel(cordicADC),
    .inputValid(cordicTVALID && (cordicStream == STREAM_PL)),
    .cicShift(faCICshift),
    .decimateFlag(cordicFaDecimateFlag),
    .outputData(decimatedPlMags));

faDecimate #(.DATA_WIDTH(MAG_WIDTH),
             .DECIMATION_FACTOR(CIC_FA_DECIMATE),
             .STAGES(CIC_STAGES))
  phDecimate (
    .clk(clk),
    .inputData(cordicMagnitude),
    .inputChannel(cordicADC),
    .inputValid(cordicTVALID && (cordicStream == STREAM_PH)),
    .cicShift(faCICshift),
    .decimateFlag(cordicFaDecimateFlag),
    // High pilot tone comes last so use it to flip ptDecimatedToggle.
    .outputToggle(ptDecimatedToggle),
    .outputData(decimatedPhMags));

// In time-multiplexed pilot tone mode use only the pilot tone
// magnitudes computed at the end of the pilot tone interval.
(* ASYNC_REG="TRUE" *) reg sysPtStable_m = 0;
reg sysPtStable = 0, sysPtStable_d = 0;
reg ptDecimatedMatch = 0;
reg [(4*MAG_WIDTH)-1:0] trimPlMags, trimPhMags;
always @(posedge clk) begin
    sysPtStable_m  <= evrPtStable;
    sysPtStable    <= sysPtStable_m;
    if (ptDecimatedMatch != ptDecimatedToggle) begin
        ptDecimatedMatch <= ptDecimatedToggle;
        sysPtStable_d <= sysPtStable;
        if (!sysPtTimeMuxMode || (!sysPtStable && sysPtStable_d)) begin
            {plMag3, plMag2, plMag1, plMag0} <= decimatedPlMags;
            {phMag3, phMag2, phMag1, phMag0} <= decimatedPhMags;
            ptToggle <= !ptToggle;
        end
    end
end

// CIC RF FA DECIMATION
wire rfDecimatedToggle;
wire [MAG_WIDTH-1:0] cicFaMag0, cicFaMag1, cicFaMag2, cicFaMag3;
reg saDecimateFlag;
always @(posedge clk) begin
    if (cordicTVALID && cordicFaDecimateFlag) begin
        saDecimateFlag <= cordicSaDecimateFlag;
    end
end
faDecimate #(.DATA_WIDTH(MAG_WIDTH),
             .DECIMATION_FACTOR(CIC_FA_DECIMATE),
             .STAGES(CIC_STAGES))
  rfDecimate (
    .clk(clk),
    .inputData(cordicMagnitude),
    .inputChannel(cordicADC),
    .inputValid(cordicTVALID && (cordicStream == STREAM_RF)),
    .cicShift(faCICshift),
    .decimateFlag(cordicFaDecimateFlag),

    .outputToggle(rfDecimatedToggle),
    .outputData({cicFaMag3, cicFaMag2, cicFaMag1, cicFaMag0}));

//
// Auto trim
//
wire [GAIN_WIDTH-1:0] gain0, gain1, gain2, gain3;
wire gainDoneToggle;
autotrim #(.GPIO_WIDTH(DATA_WIDTH),
           .NADC(NADC),
           .MAG_WIDTH(MAG_WIDTH),
           .GAIN_WIDTH(GAIN_WIDTH))
  autotrim (
      .clk(clk),
      .gpioData(gpioData),
      .csrStrobe(autotrimCsrStrobe),
      .thresholdStrobe(autotrimThresholdStrobe),
      .gainStrobes(autotrimGainStrobes),
      .statusReg(autotrimCsr),
      .thresholdReg(autotrimThreshold),
      .ptToggle(ptToggle),
      .plMags({plMag3, plMag2, plMag1, plMag0}),
      .phMags({phMag3, phMag2, phMag1, phMag0}),
      .gainToggle(gainDoneToggle),
      .gains({gain3, gain2, gain1, gain0}));

assign gainRBK0 = { {(DATA_WIDTH-GAIN_WIDTH){1'b0}}, gain0 };
assign gainRBK1 = { {(DATA_WIDTH-GAIN_WIDTH){1'b0}}, gain1 };
assign gainRBK2 = { {(DATA_WIDTH-GAIN_WIDTH){1'b0}}, gain2 };
assign gainRBK3 = { {(DATA_WIDTH-GAIN_WIDTH){1'b0}}, gain3 };

// Apply trim factors
// Hold off trimming FA until auto trim has completed
reg ptToggle_d = 0, awaitGainsAndRf = 0;
reg rfDecimatedMatch = 0, gainDoneMatch = 0;
reg faTrimStrobe = 0;
always @(posedge clk) begin
    if (ptToggle_d != ptToggle) begin
        ptToggle_d <= ptToggle;
        // Set up to watch for new gain and RF values
        gainDoneMatch <= gainDoneToggle;
        rfDecimatedMatch <= rfDecimatedToggle;
        awaitGainsAndRf <= 1;
        faTrimStrobe <= 0;
    end
    else if (awaitGainsAndRf && (gainDoneMatch != gainDoneToggle) &&
                                (rfDecimatedMatch != rfDecimatedToggle)) begin
        faTrimStrobe <= 1;
        awaitGainsAndRf <= 0;
    end
    else begin
        faTrimStrobe <= 0;
    end
end

trim #(.MAG_WIDTH(MAG_WIDTH),
       .GAIN_WIDTH(GAIN_WIDTH))
  faTrim (
    .clk(clk),
    .strobe(faTrimStrobe),
    .magnitudes({cicFaMag3, cicFaMag2, cicFaMag1, cicFaMag0}),
    .gains({gain3, gain2, gain1, gain0}),
    .trimmedToggle(faToggle),
    .trimmed({rfFaMag3, rfFaMag2, rfFaMag1, rfFaMag0}));

trim #(.MAG_WIDTH(MAG_WIDTH),
       .GAIN_WIDTH(GAIN_WIDTH))
  tbtTrim (
    .clk(clk),
    .strobe(tbtTrimStrobe),
    .magnitudes(tbtMags),
    .gains({gain3, gain2, gain1, gain0}),
    .trimmedToggle(tbtToggle),
    .trimmed({rfTbtMag3, rfTbtMag2, rfTbtMag1, rfTbtMag0}));

// CIC SA DECIMATION
wire [MAG_WIDTH-1:0] rfSaMag0, rfSaMag1, rfSaMag2, rfSaMag3;
wire saDecimatedToggle;
reg faMatch = 0;
saDecimate #(.DATA_WIDTH(MAG_WIDTH),
             .DECIMATION_FACTOR(CIC_SA_DECIMATE),
             .STAGES(CIC_STAGES),
             .CHANNEL_COUNT(4))
  saDecimate (.clk(clk),
              .inputData({rfFaMag3, rfFaMag2, rfFaMag1, rfFaMag0}),
              .inputToggle(faToggle),
              .decimateFlag(saDecimateFlag),
              .outputToggle(saDecimatedToggle),
              .outputData({rfSaMag3, rfSaMag2, rfSaMag1, rfSaMag0}));

// In single-pass mode set SA values from turn-by-turn results and generate
// SA update on every single pass trigger, or if no single pass trigger
// occurs, then the most recent pilot tone update, or if no pilot tone
// update has ocurrred then every third heartbeat.
reg tbtMatch = 0, ptMatch = 0;
reg saSend = 0;
(* ASYNC_REG="TRUE" *) reg sysHbEvent_m, sysHoldoff_m = 0;
reg sysHbEvent, sysHbEvent_d, sysHoldoff = 0, sysHoldoff_d = 0;
reg [$clog2(SYSCLK_RATE)-1:0] ptWatchdog = SYSCLK_RATE - 1;
reg [1:0] hbWatchdog;
reg [63:0] sysSinglePassTimestamp;
always @(posedge clk) begin
    sysHoldoff_m  <= adcHoldoff;
    sysHoldoff    <= sysHoldoff_m;
    sysHoldoff_d  <= sysHoldoff;
    sysHbEvent_m  <= evrHbMarker;
    sysHbEvent    <= sysHbEvent_m;
    sysHbEvent_d  <= sysHbEvent;

    if (sysIsSinglePassMode) begin
        /*
         * Note time at end of pilot tone acquisition and beginning
         * of single-pass button acquisition for use when we send
         * the SA values.
         */
        if ((!sysPtStable && sysPtStable_d)
         || (sysHoldoff && !sysHoldoff_d)) begin
            sysSinglePassTimestamp <= sysTimestamp;
        end
        if (saSend) begin
            rfMag0 <= rfTbtMag0;
            rfMag1 <= rfTbtMag1;
            rfMag2 <= rfTbtMag2;
            rfMag3 <= rfTbtMag3;
            saToggle <= !saToggle;
            saSend <= 0;
            ptWatchdog <= 0;
            hbWatchdog <= 3;
        end
        else begin
            if (sysHbEvent && !sysHbEvent_d && (hbWatchdog != 0)) begin
                hbWatchdog <= hbWatchdog - 1;
            end
            if (tbtMatch != tbtToggle) begin
                tbtMatch <= tbtToggle;
                sysSaTimestamp <= sysSinglePassTimestamp;
                saSend <= 1;
            end
            else if (ptMatch != ptToggle) begin
                ptMatch <= ptToggle;
                ptWatchdog <= SYSCLK_RATE - 1;
            end
            else begin
                if (ptWatchdog != 0) begin
                    ptWatchdog <= ptWatchdog - 1;
                end
                if (ptWatchdog == 1) begin
                    sysSaTimestamp <=sysSinglePassTimestamp;
                    saSend <= 1;
                end
                else if (hbWatchdog == 0) begin
                    sysSaTimestamp <= sysTimestamp;
                    saSend <= 1;
                end
            end
        end
    end
    else begin
        rfMag0 <= rfSaMag0;
        rfMag1 <= rfSaMag1;
        rfMag2 <= rfSaMag2;
        rfMag3 <= rfSaMag3;
        saToggle <= saDecimatedToggle;
        /*
         * No clock crossing worries here since evrSaTimestamp
         * will have been latched before the CORDIC/trim computations.
         */
        sysSaTimestamp <= evrSaTimestamp;
    end
end

endmodule
