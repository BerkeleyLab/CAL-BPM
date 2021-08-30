//
// Produce pilot tone or pulse synchronized to event clock.
// All signals except aEnable and aSimulate, are in EVR clock domain.
//

module pilotTone #(
    parameter EVR_CLOCK_RATE           = 125000000,
    parameter PILOT_TONE_MILLISECONDS = 3,
    parameter SIMULATION_MILLISECONDS = 500
    ) (
    input       evrClk,
    input       aEnable,
    input       aSimulate,
    input       usePulsePt,
    input       trigger,
    input       pulseStrobe,
    output reg  ptWarning,
    output reg  ptStable,
    output wire PT_P, PT_N);

// Delay values:
//  5 us 'warn' to tone on
//  5 us tone on to 'tone stable'
//  PILOT_TONE_MILLISECONDS to 'tone not stable'
//  300 us from 'tone not stable' to tone off
//  5 us tone off to 'no warn'
//  Then, if simulated beam signal generation is enabled:
//     PILOT_TONE_MILLISECONDS to beginning of simulated beam
//     SIMULATION_MILLISECONDS to end of simulated beam
// The time from 'tone not stable' to tone off must be greater than the
// pilot tone acquisition interval (FA interval) in preliminaryProcessing.v.
localparam SHORT_DELAY_TICKS = 5 * (EVR_CLOCK_RATE / 1000000);
localparam STABLE_TICKS = PILOT_TONE_MILLISECONDS * (EVR_CLOCK_RATE / 1000);
localparam HOLD_TICKS = 300 * (EVR_CLOCK_RATE / 1000000);
localparam SIMULATION_TICKS = SIMULATION_MILLISECONDS * (EVR_CLOCK_RATE / 1000);

parameter SHORT_DELAY_TICKS_WIDTH = $clog2(SHORT_DELAY_TICKS);
parameter STABLE_TICKS_WIDTH = $clog2(STABLE_TICKS);
parameter HOLD_TICKS_WIDTH = $clog2(HOLD_TICKS);
parameter SIMULATION_TICKS_WIDTH = $clog2(SIMULATION_TICKS);

reg [SIMULATION_TICKS_WIDTH-1:0] delay;

// Signal patterns
// The single-pass pattern has two pulses since that gives a little bigger
// ringing signal through the filters and splits the difference between
// single and four bunch linac operation.
localparam PATTERN_OFF        = 8'h00;
localparam PATTERN_CONTINUOUS = 8'h55;
localparam PATTERN_SINGLE     = 8'h88;

// State machine
localparam S_IDLE       = 3'd0,
           S_START      = 3'd1,
           S_STABILIZE  = 3'd2,
           S_STABLE     = 3'd3,
           S_HOLD       = 3'd4,
           S_SHUTDOWN   = 3'd5,
           S_AWAIT_BEAM = 3'd6,
           S_BEAM_ON    = 3'd7;
reg [2:0] state = S_IDLE;
reg       trigger_d = 0;

// ptByteClk is at same rate and phase as evrClk so no domain-crossing
// logic required for enable and trigger.
reg [7:0] pattern = 0;
(* ASYNC_REG="TRUE" *) reg       simulate_m, simulate;

// Generate MMCM reset and SERDES reset
(* ASYNC_REG="TRUE" *) reg enable_m, enable;
wire ptByteClk, ptFastClk, mmcmLocked;
reg [4:0] mmcmResetCount = 0;
wire mmcmReset = !mmcmResetCount[4];
always @(posedge evrClk) begin
    enable_m <= aEnable;
    enable   <= enable_m;
    if (!enable) mmcmResetCount <= 0;
    else if (mmcmReset) mmcmResetCount <= mmcmResetCount + 1;
end

// SERDES support
pilotToneMMCM pilotToneMMCM (
    .evrClk(evrClk),
    .RESET(mmcmReset),
    .LOCKED(mmcmLocked),
    .ptByteClk(ptByteClk),
    .ptFastClk(ptFastClk));

pilotToneSERDES pilotToneSERDES (
    .CLK_IN(ptFastClk),
    .CLK_DIV_IN(ptByteClk),
    .IO_RESET(!mmcmLocked),
    .DATA_OUT_FROM_DEVICE(pattern),
    .DATA_OUT_TO_PINS_P(PT_P),
    .DATA_OUT_TO_PINS_N(PT_N));

// Generate front-panel signals
always @(posedge ptByteClk) begin
    simulate_m <= aSimulate;
    trigger_d <= trigger;
    case (state)
    S_IDLE: begin
        simulate <= simulate_m;
        pattern <= PATTERN_OFF;
        delay <= SHORT_DELAY_TICKS - 1;
        if (enable && trigger && !trigger_d) begin
            ptWarning <= 1;
            state <= S_START;
        end
    end
    S_START: begin
        if (delay[SHORT_DELAY_TICKS_WIDTH-1:0] == 0) begin
            delay <= SHORT_DELAY_TICKS - 1;
            if (!usePulsePt) pattern <= PATTERN_CONTINUOUS;
            state <= S_STABILIZE;
        end
        else begin
            delay <= delay - 1;
        end
    end
    S_STABILIZE: begin
        if (delay[SHORT_DELAY_TICKS_WIDTH-1:0] == 0) begin
            delay <= STABLE_TICKS - 1;
            ptStable <= 1;
            state <= S_STABLE;
        end
        else begin
            delay <= delay - 1;
        end
        if (usePulsePt) pattern <= pulseStrobe ? PATTERN_SINGLE : PATTERN_OFF;
    end
    S_STABLE: begin
        if (delay[STABLE_TICKS_WIDTH-1:0] == 0) begin
            delay <= HOLD_TICKS -1;
            ptStable <= 0;
            state <= S_HOLD;
        end
        else begin
            delay <= delay - 1;
        end
        if (usePulsePt) pattern <= pulseStrobe ? PATTERN_SINGLE : PATTERN_OFF;
    end
    S_HOLD: begin
        if (delay[HOLD_TICKS_WIDTH-1:0] == 0) begin
            delay <= SHORT_DELAY_TICKS - 1;
            state <= S_SHUTDOWN;
        end
        else begin
            delay <= delay - 1;
        end
        if (usePulsePt) pattern <= pulseStrobe ? PATTERN_SINGLE : PATTERN_OFF;
    end
    S_SHUTDOWN: begin
        pattern <= PATTERN_OFF;
        if (delay[SHORT_DELAY_TICKS_WIDTH-1:0] == 0) begin
            delay <= STABLE_TICKS - 1;
            ptWarning <= 0;
            state <= simulate ? S_AWAIT_BEAM : S_IDLE;
        end
        else begin
            delay <= delay - 1;
        end
    end
    S_AWAIT_BEAM: begin
        if (delay[STABLE_TICKS_WIDTH-1:0] == 0) begin
            delay <= SIMULATION_TICKS - 1;
            if (!usePulsePt) pattern <= PATTERN_CONTINUOUS;
            state <= S_BEAM_ON;;
       end
        else begin
            delay <= delay - 1;
        end
    end
    S_BEAM_ON: begin
        if (delay[SIMULATION_TICKS_WIDTH-1:0] == 0) begin
            state <= S_IDLE;
        end
        else begin
            delay <= delay - 1;
        end
        if (usePulsePt) pattern <= pulseStrobe ? PATTERN_SINGLE : PATTERN_OFF;
    end
    default: ;
    endcase
end

endmodule
