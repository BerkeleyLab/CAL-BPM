//
// ADC Waveform Recorder
//
module adcWaveformRecorder #(
    parameter ADC_WIDTH       = 64,
    parameter TIMESTAMP_WIDTH = 64,
    parameter BUS_WIDTH       = 32,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter AXI_DATA_WIDTH  = 128,
    parameter ACQ_COUNT       = 1 << 24
    ) (
    input                             adcClk,
    input             [ADC_WIDTH-1:0] adcRawData, adcTestData,
    input                             clk,
    input                       [7:0] triggers,
    input       [TIMESTAMP_WIDTH-1:0] timestamp,
    input             [BUS_WIDTH-1:0] writeData,
    input                       [3:0] regStrobes,
    output wire       [BUS_WIDTH-1:0] csr, pretrigCount, acqCount, acqAddress,
    output reg  [TIMESTAMP_WIDTH-1:0] whenTriggered,
    input             [BUS_WIDTH-1:0] sysTicks,

    output wire [AXI_ADDR_WIDTH-1:0] axi_AWADDR,
    output wire                [7:0] axi_AWLEN,
    output reg                       axi_AWVALID = 0,
    input                            axi_AWREADY,
    output wire [AXI_DATA_WIDTH-1:0] axi_WDATA,
    output wire                      axi_WLAST,
    output reg                       axi_WVALID = 0,
    input                            axi_WREADY,
    input                      [1:0] axi_BRESP,
    input                            axi_BVALID);

parameter BURST_BEATS       = 64;
parameter PRETRIG_COUNT     = 3080;
parameter ACQ_BURSTS        = ACQ_COUNT / BURST_BEATS / 2;
parameter BEATCOUNT_WIDTH  = $clog2(BURST_BEATS);
parameter BURSTCOUNT_WIDTH = $clog2(ACQ_BURSTS);

reg [7:0] triggerReg, triggerReg_d;

//
// Recorder diagnostics
//
reg [31:0] diag, diag_d1, diag_d2;

////////////////////////////////////////////////////////////////////////////
// ADC clock domain
// Handle reset requests and normal/diagnostic mode requests.
wire [ADC_WIDTH-1:0] adcData = csrTestMode ? adcTestData : adcRawData;
reg [ADC_WIDTH-1:0] adcHold;
reg                 adcPhase = 0;
reg                 fifoOverflow = 0;
reg csrResetB = 0;
(* ASYNC_REG="TRUE" *) reg adcResetB_m = 0, adcResetB = 0;
always @(posedge adcClk) begin
    adcResetB_m <= csrResetB;
    adcResetB   <= adcResetB_m;
    adcPhase <= !adcPhase;
    adcHold <= adcData;
    if (fifoFull)
        fifoOverflow <= 1;
    if (adcPhase) begin
        diag <= diag + 1;
        diag_d1 <= diag;
        diag_d2 <= diag_d1;
    end
end

////////////////////////////////////////////////////////////////////////////
// ADC to system  clock domain transition
// The 'programmable empty' FIFO capability provides pretrigger buffering.
wire [AXI_DATA_WIDTH-1:0] fifoIn = csrDiagMode ? {diag, diag_d1, diag_d2, diag}
                                               : { adcData, adcHold };
wire [AXI_DATA_WIDTH-1:0] fifoOut;
wire fifoRead, fifoEmpty, fifoFull;
adcFifo adcFifo (.rst(!csrResetB),
                 .wr_clk(adcClk),
                 .full(fifoFull),
                 .rd_clk(clk),
                 .din(fifoIn),
                 .wr_en(adcPhase && adcResetB),
                 .rd_en(fifoRead),
                 .dout(fifoOut),
                 .prog_empty(fifoEmpty));

////////////////////////////////////////////////////////////////////////////
// Everything else is in system clock domain

//
// AXI state machine
//
parameter S_IDLE = 3'd0;
parameter S_WAIT = 3'd1;
parameter S_ADDR = 3'd2;
parameter S_DATA = 3'd3;
parameter S_ACK  = 3'd4;
reg                  [2:0] state = S_IDLE;
reg  [BEATCOUNT_WIDTH-1:0] beatCount = 0;
reg [BURSTCOUNT_WIDTH-1:0] burstCount = 0;

assign axi_WDATA = csrDiagMode ? {fifoOut[127:32], sysTicks} : fifoOut;
assign axi_AWADDR = { acqBase[31:BURSTCOUNT_WIDTH + BEATCOUNT_WIDTH + 4],
                                    burstCount, {BEATCOUNT_WIDTH{1'b0}}, 4'b0 };
assign axi_AWLEN = BURST_BEATS - 1;
assign axi_WLAST = (state == S_DATA) && (beatCount == 0);
assign fifoRead = (((state == S_IDLE) && !fifoEmpty)
                || ((state == S_ADDR) && axi_AWREADY) 
                || ((state == S_DATA) && axi_WREADY && (beatCount != 0)));

//
// Microblaze interface
//
wire csrStrobe = regStrobes[0];
reg [7:0] csrTriggerEnables = 0;
reg       csrArmed = 0, full = 0, csrTestMode = 0, csrDiagMode = 0;
reg [1:0] csrBRESP = 0;
assign csr = { csrTriggerEnables, 8'b0,
               5'b0, csrResetB, csrTestMode, csrDiagMode,
               full, csrBRESP, fifoOverflow, state, csrArmed };
assign pretrigCount  = PRETRIG_COUNT; // 2 * FIFO 'programmable empy'
assign acqCount = ACQ_BURSTS * BURST_BEATS * 2;
wire addrStrobe = regStrobes[3];
reg [BUS_WIDTH-1:0] acqBase;
assign acqAddress = axi_AWADDR;

//
// The recorder
//
always @(posedge clk) begin
    triggerReg <= triggers;
    triggerReg_d <= triggerReg;

    if (addrStrobe) begin
        acqBase <= writeData;
    end
    if (csrStrobe) begin
        csrTriggerEnables <= writeData[31:24];
        csrResetB   <= writeData[10];
        csrTestMode <= writeData[9];
        csrDiagMode <= writeData[8];
        csrArmed <= writeData[0];
        full <= 0;
    end
    case (state)
    S_IDLE: begin
        if (csrArmed
         && ((csrTriggerEnables & triggerReg & ~triggerReg_d) != 0)) begin
            whenTriggered <= timestamp;
            burstCount <= 0;
            state <= S_WAIT;
        end
    end

    //
    // Wait for fifo to fill above threshold
    //
    S_WAIT: begin
        if (csrArmed) begin
            if (!fifoEmpty) begin
                state <= S_ADDR;
                axi_AWVALID <= 1;
            end
        end
        else begin
            state <= S_IDLE;
        end
    end

    //
    // Set up a transfer
    //
    S_ADDR: begin
        if (axi_AWREADY) begin
            axi_AWVALID <= 0;
            axi_WVALID <= 1;
            beatCount <= BURST_BEATS - 1;
            state <= S_DATA;
        end
    end

    //
    // Transfer a burst
    // No need to check FIFO validity since the 'programmable empty'
    // FIFO capability ensures that there is (way) more than one
    // burst's worth of data available.
    //
    S_DATA: begin
        if (axi_WREADY) begin
            if (beatCount == 0) begin
                axi_WVALID <= 0;
                state <= S_ACK;
            end
            else begin
                beatCount <= beatCount - 1;
            end
        end
    end

    //
    // Wait for AXI acknowledgement
    //
    S_ACK: begin
        if (axi_BVALID) begin
            csrBRESP <= axi_BRESP;
            burstCount <= burstCount + 1;
            if (burstCount == {BURSTCOUNT_WIDTH{1'b1}}) begin
                csrArmed <= 0;
                if (csrArmed)
                    full <= 1;
                state <= S_IDLE;
            end
            else if (axi_BRESP != 0) begin
                csrArmed <= 0;
                state <= S_IDLE;
            end
            else begin
                state <= S_WAIT;
            end
        end
    end

    default: ;
    endcase
end

endmodule
