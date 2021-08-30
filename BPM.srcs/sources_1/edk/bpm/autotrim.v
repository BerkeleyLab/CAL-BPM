// Compute gain trim values from pilot tone amplitudes
// The gains output is always choherent -- all four gains update at once.

module autotrim #(
    parameter GPIO_WIDTH = 32,
    parameter NADC       = 4,
    parameter MAG_WIDTH  = 24,
    parameter GAIN_WIDTH = 25,
    parameter DEBUG      = "false"
    ) (
    input  wire         clk,

    // Values to/from processing block
    input  wire [GPIO_WIDTH-1:0] gpioData,
    input  wire                  csrStrobe,
    input  wire                  thresholdStrobe,
    input  wire       [NADC-1:0] gainStrobes,
    (*mark_debug=DEBUG*)
    output wire [GPIO_WIDTH-1:0] statusReg,
    (*mark_debug=DEBUG*)
    output reg  [GPIO_WIDTH-1:0] thresholdReg = 100000,

    // FA values
    (*mark_debug=DEBUG*) input  wire                        ptToggle,
    (*mark_debug=DEBUG*) input  wire [(NADC*MAG_WIDTH)-1:0] plMags,
    (*mark_debug=DEBUG*) input  wire [(NADC*MAG_WIDTH)-1:0] phMags,

    // Gain trim factors
    // Always consistent set whether updated from processor or autotrim logic.
    output reg                          gainToggle = 0,
    output reg  [(NADC*GAIN_WIDTH)-1:0] gains =
                                           {NADC{1'b1,{(GAIN_WIDTH-1){1'b0}}}});

localparam MINIMUM_THRESHOLD = 100000;
localparam DIVIDER_WIDTH = GAIN_WIDTH + 1;

// Operating mode
localparam TRIM_CONTROL_OFF  = 3'd0,
           TRIM_CONTROL_LOW  = 3'd1,
           TRIM_CONTROL_HIGH = 3'd2,
           TRIM_CONTROL_DUAL = 3'd3,
           TRIM_CONTROL_MUX  = 3'd4;
reg [2:0] trimControl = TRIM_CONTROL_OFF, trimControlPending = TRIM_CONTROL_OFF;
reg timeMuxPilotPulses = 0;
reg timeMuxSimulateBeam = 0;

// Filtering of the gain factors.  A filter shift of 0 results in no filtering.
// First order low pass with pole at z = 1 - (1 / (1 << filterShift)).
reg [2:0] filterShift = 0, filterShiftPending = 0;

// Operating status
localparam TRIMSTATUS_OFF         = 3'd0,
           TRIMSTATUS_NO_TONE     = 3'd1,
           TRIMSTATUS_EXCESS_DIFF = 3'd2,
           TRIMSTATUS_ACTIVE      = 3'd3;
reg [1:0] trimStatus;

assign statusReg = { timeMuxSimulateBeam, 19'b0,
                     1'b0, filterShift,
                     2'b0, trimStatus,
                     timeMuxPilotPulses, trimControl} ;

// Computation state machine
reg ptMatch = 0;
localparam TS_IDLE          = 3'd0,
           TS_MINMAX_1      = 3'd1,
           TS_MINMAX_2      = 3'd2,
           TS_CHECK         = 3'd3,
           TS_START_DIVIDE  = 3'd4,
           TS_FINISH_DIVIDE = 3'd5,
           TS_FILTER        = 3'd6,
           TS_FINISH        = 3'd7;
(*mark_debug=DEBUG*) reg [2:0] trimState = TS_IDLE;

// Pilot tone checks
wire [MAG_WIDTH-1:0] plMag0 = plMags[0*MAG_WIDTH+:MAG_WIDTH];
wire [MAG_WIDTH-1:0] plMag1 = plMags[1*MAG_WIDTH+:MAG_WIDTH];
wire [MAG_WIDTH-1:0] plMag2 = plMags[2*MAG_WIDTH+:MAG_WIDTH];
wire [MAG_WIDTH-1:0] plMag3 = plMags[3*MAG_WIDTH+:MAG_WIDTH];
wire [MAG_WIDTH-1:0] phMag0 = phMags[0*MAG_WIDTH+:MAG_WIDTH];
wire [MAG_WIDTH-1:0] phMag1 = phMags[1*MAG_WIDTH+:MAG_WIDTH];
wire [MAG_WIDTH-1:0] phMag2 = phMags[2*MAG_WIDTH+:MAG_WIDTH];
wire [MAG_WIDTH-1:0] phMag3 = phMags[3*MAG_WIDTH+:MAG_WIDTH];
reg [MAG_WIDTH-1:0] plMin01, plMin23, plMin, phMin01, phMin23, phMin;
reg [MAG_WIDTH-1:0] plMax01, plMax23, plMax, phMax01, phMax23, phMax;
reg plLow, plVar, phLow, phVar;
reg [3:0] trimActiveDelay = ~0;
reg       trimActive = 0;

// Gain factors from processor
reg [((NADC-1)*GAIN_WIDTH)-1:0] psGbuf;

// Gain factors from autotrim division
reg  [(NADC*GAIN_WIDTH)-1:0] trimsLo, trimsHi;
wire [(NADC*GAIN_WIDTH)-1:0] trimsAvg;
reg                          filterEnable = 0;
reg  [(NADC*GAIN_WIDTH)-1:0] filterIn;
wire              [NADC-1:0] filterDone;
wire [(NADC*GAIN_WIDTH)-1:0] filterOut;
genvar adc; generate
for (adc = 0 ; adc < NADC ; adc = adc + 1) begin : tAvg
    wire [GAIN_WIDTH:0] tSum = trimsLo[adc*GAIN_WIDTH+:GAIN_WIDTH] +
                               trimsHi[adc*GAIN_WIDTH+:GAIN_WIDTH] + 1;
    assign trimsAvg[adc*GAIN_WIDTH+:GAIN_WIDTH] = tSum[GAIN_WIDTH:1];

    // Optional low-pass
    gainFilter #(.DATA_WIDTH(GAIN_WIDTH), .SHIFT_WIDTH(3))
      gainFilter (
        .clk(clk),
        .filterShift(filterShift),
        .S_TVALID(filterEnable),
        .S_TDATA(filterIn[adc*GAIN_WIDTH+:GAIN_WIDTH]),
        .M_TVALID(filterDone[adc]),
        .M_TDATA(filterOut[adc*GAIN_WIDTH+:GAIN_WIDTH]));

end
endgenerate

// Dividers
reg divStartStrobe = 0;
wire divBusyLo, divBusyHi;
reg [1:0] divChannel;
wire [DIVIDER_WIDTH-MAG_WIDTH-1:0] dPad = 0;
wire [DIVIDER_WIDTH-1:0] quotientL, quotientH;
scaleGain #(.OPERAND_WIDTH(DIVIDER_WIDTH))
  scaleGainLo(
      .clk(clk),
      .startStrobe(divStartStrobe),
      .dividend({dPad, plMin}),
      .divisor({dPad, plMags[divChannel*MAG_WIDTH+:MAG_WIDTH]}),
      .busy(divBusyLo),
      .quotient(quotientL));
scaleGain #(.OPERAND_WIDTH(DIVIDER_WIDTH))
  scaleGainHi(
      .clk(clk),
      .startStrobe(divStartStrobe),
      .dividend({dPad, phMin}),
      .divisor({dPad, phMags[divChannel*MAG_WIDTH+:MAG_WIDTH]}),
      .busy(divBusyHi),
      .quotient(quotientH));

always @(posedge clk) begin
    // Handle writes from processor
    if (thresholdStrobe) begin
        thresholdReg <= (gpioData > MINIMUM_THRESHOLD) ? gpioData :
                                                         MINIMUM_THRESHOLD;
    end
    if (csrStrobe) begin
        trimControlPending <= gpioData[2:0];
        timeMuxPilotPulses <= gpioData[3];
        timeMuxSimulateBeam <= gpioData[31];
        filterShiftPending <= gpioData[10:8];
    end
    if(gainStrobes[0])psGbuf[0*GAIN_WIDTH+:GAIN_WIDTH]<=gpioData[0+:GAIN_WIDTH];
    if(gainStrobes[1])psGbuf[1*GAIN_WIDTH+:GAIN_WIDTH]<=gpioData[0+:GAIN_WIDTH];
    if(gainStrobes[2])psGbuf[2*GAIN_WIDTH+:GAIN_WIDTH]<=gpioData[0+:GAIN_WIDTH];
    if (gainStrobes[3]) begin
        if (trimControl == TRIM_CONTROL_OFF) begin
            gains <= {gpioData[GAIN_WIDTH-1:0], psGbuf};
        end
    end

    // Find minimum and maximum of each pilot tone
    plMin01 <= (plMag0  < plMag1)  ? plMag0  : plMag1;
    plMin23 <= (plMag2  < plMag3)  ? plMag2  : plMag3;
    plMin   <= (plMin01 < plMin23) ? plMin01 : plMin23;
    phMin01 <= (phMag0  < phMag1)  ? phMag0  : phMag1;
    phMin23 <= (phMag2  < phMag3)  ? phMag2  : phMag3;
    phMin   <= (phMin01 < phMin23) ? phMin01 : phMin23;
    plMax01 <= (plMag0  > plMag1)  ? plMag0  : plMag1;
    plMax23 <= (plMag2  > plMag3)  ? plMag2  : plMag3;
    plMax   <= (plMax01 > plMax23) ? plMax01 : plMax23;
    phMax01 <= (phMag0  > phMag1)  ? phMag0  : phMag1;
    phMax23 <= (phMag2  > phMag3)  ? phMag2  : phMag3;
    phMax   <= (phMax01 > phMax23) ? phMax01 : phMax23;

    // Check for tones below threshold or with too much variation
    plLow <= (plMin < thresholdReg);
    plVar <= (plMin < {1'b0, plMax[MAG_WIDTH-1:1]});
    phLow <= (phMin < thresholdReg);
    phVar <= (phMin < {1'b0, phMax[MAG_WIDTH-1:1]});

    // Crank state machine
    ptMatch <= ptToggle;
    case (trimState)
    TS_IDLE: begin
        trimControl <= trimControlPending;
        filterShift <= filterShiftPending;
        if (ptMatch != ptToggle) trimState <= TS_MINMAX_1;
    end
    // Allow a couple of cycles for min and max computation to complete
    TS_MINMAX_1: trimState <= TS_MINMAX_2;
    TS_MINMAX_2: trimState <= TS_CHECK;
    TS_CHECK: begin
        if (trimControl == TRIM_CONTROL_LOW) begin
            if (plLow)      trimStatus <= TRIMSTATUS_NO_TONE;
            else if (plVar) trimStatus <= TRIMSTATUS_EXCESS_DIFF;
            else            trimStatus <= TRIMSTATUS_ACTIVE;
        end
        else if (trimControl == TRIM_CONTROL_HIGH) begin
            if (phLow)      trimStatus <= TRIMSTATUS_NO_TONE;
            else if (phVar) trimStatus <= TRIMSTATUS_EXCESS_DIFF;
            else            trimStatus <= TRIMSTATUS_ACTIVE;
        end
        else if ((trimControl == TRIM_CONTROL_DUAL)
              || (trimControl == TRIM_CONTROL_MUX)) begin
            if (plLow || phLow)      trimStatus <= TRIMSTATUS_NO_TONE;
            else if (plVar || phVar) trimStatus <= TRIMSTATUS_EXCESS_DIFF;
            else                     trimStatus <= TRIMSTATUS_ACTIVE;
        end
        else begin
            trimStatus <= TRIMSTATUS_OFF;
        end
        divChannel <= 0;
        divStartStrobe <= 1;
        trimState <= TS_START_DIVIDE;
    end
    TS_START_DIVIDE: begin
        if (trimStatus == TRIMSTATUS_ACTIVE) begin
            if (trimActiveDelay == 0) begin
                trimActive <= 1;
            end
            else begin
                trimActiveDelay <= trimActiveDelay - 1;
            end
        end
        else begin
            trimActiveDelay <= ~0;
            trimActive <= 0;
        end
        divStartStrobe <= 0;
        trimState <= TS_FINISH_DIVIDE;
    end
    TS_FINISH_DIVIDE: begin
        if (!divBusyLo && !divBusyHi) begin
            // Round result
            trimsLo[divChannel*GAIN_WIDTH+:GAIN_WIDTH] <=
                                        quotientL[1+:GAIN_WIDTH] + quotientL[0];
            trimsHi[divChannel*GAIN_WIDTH+:GAIN_WIDTH] <=
                                        quotientH[1+:GAIN_WIDTH] + quotientH[0];
            divChannel <= divChannel + 1;
            if (divChannel == (NADC - 1)) begin
                trimState <= TS_FILTER;
            end
            else begin
                divStartStrobe <= 1;
                trimState <= TS_START_DIVIDE;
            end
        end
    end
    TS_FILTER: begin
        if (trimControl == TRIM_CONTROL_LOW)        filterIn <= trimsLo;
        else if (trimControl == TRIM_CONTROL_HIGH)  filterIn <= trimsHi;
        else if ((trimControl == TRIM_CONTROL_DUAL)
              || (trimControl == TRIM_CONTROL_MUX)) filterIn <= trimsAvg;
        if (trimActive) filterEnable <= 1;
        trimState <= TS_FINISH;
    end
    TS_FINISH: begin
        filterEnable <= 0;
        if (filterDone[0] || !trimActive) begin
            if (trimActive) gains <= filterOut;
            // Show completion to allow preliminary processing to proceed
            gainToggle <= !gainToggle;
            trimState <= TS_IDLE;
        end
    end
    default: ;
    endcase
end

endmodule

//
// Compute gain trims
// Simple long division
//
module scaleGain #(parameter OPERAND_WIDTH = 26) (
    input  wire                     clk,
    input  wire                     startStrobe,
    input  wire [OPERAND_WIDTH-1:0] dividend,
    input  wire [OPERAND_WIDTH-1:0] divisor,
    output reg                      busy = 0,
    output reg  [OPERAND_WIDTH-1:0] quotient);

parameter COUNTER_WIDTH = $clog2(OPERAND_WIDTH);

reg [OPERAND_WIDTH-1:0] dividendReg, divisorReg;
reg [$clog2(OPERAND_WIDTH)-1:0] counter;

always @(posedge clk) begin
    if (busy) begin
        counter <= counter - 1;
        if (counter == 0) begin
            busy <= 0;
        end
        if (dividendReg >= divisorReg) begin
            dividendReg <= (dividendReg - divisorReg) << 1;
            quotient <= (quotient << 1) | 1;
        end
        else begin
            dividendReg <= dividendReg << 1;
            quotient <= (quotient << 1);
        end
    end
    else if (startStrobe) begin
        if (dividend == divisor) begin
            quotient <= {1'b1, {OPERAND_WIDTH-1{1'b0}}};
        end
        else begin
            dividendReg <= dividend;
            divisorReg <= divisor;
            quotient <= 0;
            busy <= 1;
            counter <= OPERAND_WIDTH - 1;
        end
    end
end

endmodule
