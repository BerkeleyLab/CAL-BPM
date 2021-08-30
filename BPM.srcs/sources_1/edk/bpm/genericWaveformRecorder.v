//
// Generic Waveform Recorder
//
module genericWaveformRecorder #(
    parameter DATA_WIDTH      = 128,
    parameter TIMESTAMP_WIDTH = 64,
    parameter BUS_WIDTH       = 32,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter AXI_DATA_WIDTH  = 128,
    parameter ACQ_CAPACITY    = 1 << 23 // Max samples (4 32-bit values/sample)
    ) (
    input                        clk,
    input       [DATA_WIDTH-1:0] data,
    input                        dataToggle,
    input                  [7:0] triggers,
    input  [TIMESTAMP_WIDTH-1:0] timestamp,
    input        [BUS_WIDTH-1:0] writeData,
    input                  [3:0] regStrobes,
    output wire       [BUS_WIDTH-1:0] csr, pretrigCount, acqCount, acqAddress,
    output reg  [TIMESTAMP_WIDTH-1:0] whenTriggered,

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

parameter WRITE_ADDR_WIDTH  = $clog2(ACQ_CAPACITY);
parameter WRITE_COUNT_WIDTH = $clog2(ACQ_CAPACITY+1);
parameter BEATCOUNT_WIDTH   = 3;
parameter MULTI_BEAT_LENGTH = (1 << BEATCOUNT_WIDTH);

reg [7:0] triggerReg, triggerReg_d;

//
// Data transfer
//
reg                 dataMatch;
reg [BUS_WIDTH-1:0] diagCount;

//
// AXI state machine
//
parameter S_WAIT  = 3'd0;
parameter S_ADDR  = 3'd1;
parameter S_DATA  = 3'd2;
parameter S_ACK   = 3'd3;
parameter S_PAUSE = 3'd4;
reg                   [2:0] state = S_WAIT;
reg                   [5:0] pauseCount = 0;
reg                         triggerFlag = 0, triggered = 0;
reg [WRITE_COUNT_WIDTH-1:0] pretrigLeft = 0, acqLeft = 0;
reg  [WRITE_ADDR_WIDTH-1:0] writeAddr = 0;
assign axi_AWADDR = { acqBase[31:WRITE_ADDR_WIDTH + 4], writeAddr, 4'b0 };
reg [BEATCOUNT_WIDTH-1:0] beatCount;
assign axi_AWLEN = { {(8-BEATCOUNT_WIDTH){1'b0}}, beatCount };
assign axi_WLAST = (state == S_DATA) && (beatCount == 0);
assign axi_WDATA = csrDiagMode ? { fifoOut[DATA_WIDTH-1:2*BUS_WIDTH],
                            {(BUS_WIDTH-BEATCOUNT_WIDTH){1'b0}}, beatCount,
                            fifoOut[BUS_WIDTH-1:0] } : fifoOut;

//
// Microblaze interface
//
wire csrStrobe = regStrobes[0];
wire pretrigStrobe = regStrobes[1];
wire acqCountStrobe = regStrobes[2];
wire addrStrobe = regStrobes[3];
reg [WRITE_COUNT_WIDTH-1:0] pretrigCount_r, acqCount_r;
assign pretrigCount = { {BUS_WIDTH-WRITE_COUNT_WIDTH{1'b0}}, pretrigCount_r };
assign acqCount     = { {BUS_WIDTH-WRITE_COUNT_WIDTH{1'b0}}, acqCount_r };
assign acqAddress   = axi_AWADDR;
reg       overrun = 0;
reg [7:0] csrTriggerEnables = 0;
reg       csrArmed = 0, full = 0, csrDiagMode = 0;
reg [1:0] csrBRESP = 0;
assign csr = { csrTriggerEnables,
               8'b0,
               7'b0, csrDiagMode,
              full, csrBRESP, overrun, state, csrArmed };
reg [BUS_WIDTH-1:0] acqBase;

//
// Provide some elasticity between incoming data and AXI
//
wire                       fifo_wr_en, fifo_rd_en;
wire                       fifoOverflow, fifoEmpty, fifoProgEmpty;
wire      [DATA_WIDTH-1:0] fifoIn, fifoOut;
assign fifoIn = csrDiagMode ? {data[DATA_WIDTH-1:BUS_WIDTH], diagCount} : data;
assign fifo_wr_en = (csrArmed && (dataMatch != dataToggle)
                  && (!triggerFlag || (acqLeft != 0)));
assign fifo_rd_en = (((state == S_ADDR) && axi_AWREADY)
                  || ((state == S_DATA) && (beatCount != 0) && axi_WREADY));
generic_wfr_fifo fifo (.clk(clk),                 // input clk
                       .din(fifoIn),              // input [127 : 0] din
                       .wr_en(fifo_wr_en),        // input wr_en
                       .rd_en(fifo_rd_en),        // input rd_en
                       .dout(fifoOut),            // output [127 : 0] dout
                       .overflow(fifoOverflow),   // output overflow
                       .empty(fifoEmpty),         // output empty
                       .prog_empty(fifoProgEmpty)); // output prog_empty

//
// The recorder
//
always @(posedge clk) begin
    dataMatch <= dataToggle;
    if (dataMatch != dataToggle) diagCount <= diagCount + 1;
    if (fifoOverflow) overrun <= 1;
    if (pretrigStrobe)  pretrigCount_r <= writeData;
    if (acqCountStrobe) acqCount_r     <= writeData;
    if (addrStrobe)     acqBase        <= writeData;
    if (csrStrobe) begin
        csrTriggerEnables <= writeData[31:24];
        csrDiagMode <= writeData[8];
        full <= 0;
        if (writeData[0]) begin
            if (!csrArmed) begin
                writeAddr <= 0;
                pretrigLeft <= pretrigCount_r;
                acqLeft <= acqCount_r;
                csrArmed <= 1;
            end
        end
        else begin
            csrArmed <= 0;
        end
    end

    //
    // Watch for trigger
    //
    triggerReg <= triggers;
    triggerReg_d <= triggerReg;
    if (csrArmed) begin
        if ((pretrigLeft == 0)
         && ((csrTriggerEnables & triggerReg & ~triggerReg_d) != 0)) begin
            triggerFlag <= 1;
        end
        if (dataMatch != dataToggle) begin
            if (triggerFlag) begin
                triggered <= 1;
                if (!triggered) whenTriggered <= timestamp;
                if (acqLeft) begin
                    acqLeft <= acqLeft - 1;
                end
                else begin
                    if (!csrStrobe) begin
                        csrArmed <= 0;
                        full <= 1;
                    end
                end
            end
            else begin
                if (pretrigLeft) begin
                    pretrigLeft <= pretrigLeft - 1;
                    if (acqLeft) acqLeft <= acqLeft - 1;
                end
            end
        end
    end
    else begin
        triggerFlag <= 0;
        triggered <= 0;
    end

    //
    // Acquisition AXI master state machine
    //
    case (state)
    //
    // Wait for data
    // Use a multi-word transfer if FIFO contains enough values
    // and the write address is not going to wrap around.
    // The FIFO prog_empty threshold is equal to MULTI_BEAT_LENGTH-1.
    //
    S_WAIT: begin
        if (!fifoProgEmpty
         && (writeAddr <= (ACQ_CAPACITY-MULTI_BEAT_LENGTH))) begin
            beatCount <= MULTI_BEAT_LENGTH-1;
            axi_AWVALID <= 1;
            state <= S_ADDR;
        end
        else if (!fifoEmpty) begin
            beatCount <= 0;
            axi_AWVALID <= 1;
            state <= S_ADDR;
        end
    end

    //
    // Set up a transfer
    //
    S_ADDR: begin
        if (axi_AWREADY) begin
            axi_AWVALID <= 0;
            axi_WVALID <= 1;
            state <= S_DATA;
        end
    end

    //
    // Transfer word(s)
    //
    S_DATA: begin
        if (axi_WREADY) begin
            writeAddr <= writeAddr + 1;
            if (beatCount) begin
                beatCount <= beatCount - 1;
            end
            else begin
                axi_WVALID <= 0;
                state <= S_ACK;
            end
        end
    end

    //
    // Wait for AXI acknowledgement
    //
    S_ACK: begin
        if (axi_BVALID) begin
            csrBRESP <= axi_BRESP;
            if ((axi_BRESP != 0) && !csrStrobe) begin
                csrArmed <= 0;
                acqLeft <= 0;
            end
            pauseCount <= ~0;
            state <= S_PAUSE;
        end
    end

    //
    // Give some time for other masters to run
    //
    S_PAUSE: begin
        if (pauseCount) pauseCount <= pauseCount - 1;
        else            state <= S_WAIT;
    end

    default: state <= S_WAIT;
    endcase
end

endmodule
