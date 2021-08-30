//
// Monitor clock.
// Result is clock rate in Hz.
// Uses EVR pulse-per-second trigger as reference.
//
module clkMonitor #(
    parameter SYSCLK_RATE  = 100000000,
    parameter RESULT_WIDTH = 28
    ) (
    input                         sysClk,
    input                         monClk,
    input                         evrPPS,
    output reg [RESULT_WIDTH-1:0] Hz);

parameter WATCHDOG_RELOAD = SYSCLK_RATE + (SYSCLK_RATE / 10) - 1;
parameter WATCHDOG_WIDTH  = $clog2(WATCHDOG_RELOAD+1);

//
// Values in monitored clock domain
// Count monitor clocks between markers
//
(* ASYNC_REG="TRUE" *) reg monEvrPPS_m, monEvrPPS = 0;
reg                    monEvrPPS_d;
reg                    monToggle = 0;
reg [RESULT_WIDTH-1:0] monCounter = 0, monLatched = 0;
always @(posedge monClk) begin
    monEvrPPS_m <= evrPPS;
    monEvrPPS   <= monEvrPPS_m;
    monEvrPPS_d <= monEvrPPS;
    if (monEvrPPS && !monEvrPPS_d) begin
        monLatched <= monCounter;
        monCounter <= 1;
        monToggle <= !monToggle;
    end
    else if (monCounter != {RESULT_WIDTH{1'b1}}) begin
        monCounter <= monCounter + 1;
    end
end

//
// Values in system clock domain
// Transfer value to system when ready
//
(* ASYNC_REG="TRUE" *) reg sysToggle_m = 0, sysToggle = 0;
reg sysMatch = 0;
reg [WATCHDOG_WIDTH-1:0] sysWatchdog = 0;
always @(posedge sysClk) begin
    sysToggle_m <= monToggle;
    sysToggle <= sysToggle_m;
    if (sysMatch != sysToggle) begin
        sysMatch <= !sysMatch;
        Hz <= monLatched;
        sysWatchdog <= WATCHDOG_RELOAD;
    end
    else begin
        sysWatchdog <= sysWatchdog - 1;
        if (sysWatchdog == 0)
            Hz <= 0;
    end
end

endmodule
