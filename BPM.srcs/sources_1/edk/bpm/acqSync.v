//
// Produce acquisition triggers based on EVR heartbeat event.
//
module acqSync #(
    parameter BUS_WIDTH = 32
    ) (
    input                       sysClk,
    input       [BUS_WIDTH-1:0] sysGPIO_OUT,
    input                       sysFAstrobe,
    input                       sysSAstrobe,
    output wire [BUS_WIDTH-1:0] sysFAstatus,
    output wire [BUS_WIDTH-1:0] sysSAstatus,

    input       evrClk,
    input       evrHeartbeat,
    output wire evrFaMarker,
    output wire evrSaMarker);

// Watch for rising edge of event trigger line
reg evrHeartbeat_d;
always @(posedge evrClk) begin
    evrHeartbeat_d <= evrHeartbeat;
end
wire evrHeartbeatStrobe = evrHeartbeat && !evrHeartbeat_d;

//
// Instantiate synchronization blocks
//
eventSync #(.BUS_WIDTH(BUS_WIDTH),
            .MAX_RELOAD(30000))
  eventFaSync(.sysClk(sysClk),
              .sysGPIO_OUT(sysGPIO_OUT),
              .sysCSRstrobe(sysFAstrobe),
              .sysStatus(sysFAstatus),
              .evrClk(evrClk),
              .syncStrobe(evrHeartbeatStrobe),
              .marker(evrFaMarker));

eventSync #(.BUS_WIDTH(BUS_WIDTH),
            .MAX_RELOAD(30000000))
  eventSaSync(.sysClk(sysClk),
              .sysGPIO_OUT(sysGPIO_OUT),
              .sysCSRstrobe(sysSAstrobe),
              .sysStatus(sysSAstatus),
              .evrClk(evrClk),
              .syncStrobe(evrHeartbeatStrobe),
              .marker(evrSaMarker));

endmodule

///////////////////////////////////////////////////////////////////////////////
//
// Synchronization block
//
module eventSync #(
    parameter MAX_RELOAD = -1,
    parameter BUS_WIDTH = -1
    ) (
    input                       sysClk,
    input      [BUS_WIDTH-1:0]  sysGPIO_OUT,
    input                       sysCSRstrobe,
    output wire [BUS_WIDTH-1:0] sysStatus,

    input      evrClk,
    input      syncStrobe,
    output reg marker = 0);

parameter COUNTER_WIDTH = $clog2(MAX_RELOAD);
parameter STRETCH_WIDTH = 3;

reg [COUNTER_WIDTH-1:0] sysReload = ~0;
reg   [COUNTER_WIDTH:0] counter = ~0;
wire counterDone = counter[COUNTER_WIDTH];
reg [STRETCH_WIDTH-1:0] stretch = 0;
reg                     synced = 0;
reg                     lostSync = 0;

//
// System clock domain
//
always @(posedge sysClk) begin
    if (sysCSRstrobe) sysReload <= sysGPIO_OUT[COUNTER_WIDTH-1:0];
end
assign sysStatus = { synced, lostSync,
                     {BUS_WIDTH-2-COUNTER_WIDTH{1'b0}},
                     sysReload };

//
// EVR clock domain
// Don't worry about reload values crossing boundaries since
// a momentary loss of sync is no big deal.
//
always @(posedge evrClk, posedge sysCSRstrobe) begin
    if (sysCSRstrobe) begin
        lostSync <= 0;
    end
    else begin
        if (synced && counterDone) begin
            stretch <= ~0;
            marker <= 1;
        end
        else if (stretch) begin
            stretch <= stretch - 1;
        end
        else begin
            marker <= 0;
        end

        if (syncStrobe) begin
            if (counterDone) begin
                synced <= 1;
            end
            else begin
                synced <= 0;
                if (synced) begin
                    lostSync <= 1;
                end
            end
            counter <= { 1'b0, sysReload };
        end
        else if (counterDone) begin
            counter <= { 1'b0, sysReload };
        end
        else begin
            counter <= counter - 1;
        end
    end
end

endmodule
