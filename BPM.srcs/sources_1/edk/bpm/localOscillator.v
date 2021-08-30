//
// Local oscillators for synchronous demodulators
//
// Output quadrature clocks for demodulating ADC signals
//    RF (rfCos, rfSin)
//    Pilot tones (plCos, plSin, phCos, phSin)
// Also generate turn-by-turn and multi-turn aquisition markers.
//
//
// Identifiers beginning with 'sys' are in the system clock domain.
// All others are in the ADC clock domain.
//
module localOscillator #(parameter OUTPUT_WIDTH            = 18,
                         parameter GPIO_LO_RF_ROW_CAPACITY = -1,
                         parameter GPIO_LO_PT_ROW_CAPACITY = -1,
                         parameter DEBUG                   = "false") (
                         input                          clk,
                         input                          adcSyncMarker,
                         input                          singleStart,
                         input                          sysClk,
                         input                          sysAddressStrobe,
                         input                          sysGpioStrobe,
                         input                   [31:0] sysGpioData,
                         output wire             [31:0] sysGpioCsr,
                         output reg                     tbtLoadAccumulator,
                         output reg                     tbtLatchAccumulator,
                         output reg                     mtLoadAndLatch,
                         output reg                     loSynced = 0,
                         output wire [OUTPUT_WIDTH-1:0] rfCos,
                         output wire [OUTPUT_WIDTH-1:0] rfSin,
                         output wire [OUTPUT_WIDTH-1:0] plCos,
                         output wire [OUTPUT_WIDTH-1:0] plSin,
                         output wire [OUTPUT_WIDTH-1:0] phCos,
                         output wire [OUTPUT_WIDTH-1:0] phSin);

parameter RF_RD_ADDRESS_WIDTH = $clog2(GPIO_LO_RF_ROW_CAPACITY);
parameter PT_RD_ADDRESS_WIDTH = $clog2(GPIO_LO_PT_ROW_CAPACITY);
parameter RF_WR_ADDRESS_WIDTH = RF_RD_ADDRESS_WIDTH + 1;
parameter PT_WR_ADDRESS_WIDTH = PT_RD_ADDRESS_WIDTH + 1;

//
// Bits in GPIO write data
//
wire              [1:0] sysMemWrBankSelect = sysGpioData[31:30];
wire [OUTPUT_WIDTH-1:0] sysMemWrData = sysGpioData[OUTPUT_WIDTH-1:0];

//
// Generate RAM write-enable signals
//
wire sysRfMemWrStrobe, sysPlMemWrStrobe, sysPhMemWrStrobe;
assign sysRfMemWrStrobe = sysGpioStrobe && (sysMemWrBankSelect == 2'b00);
assign sysPlMemWrStrobe = sysGpioStrobe && (sysMemWrBankSelect == 2'b01);
assign sysPhMemWrStrobe = sysGpioStrobe && (sysMemWrBankSelect == 2'b10);

// Address to be written
// Assume that PT_WR_ADDRESS_WIDTH equals or exceeds RF_WR_ADDRESS_WIDTH.
reg [PT_WR_ADDRESS_WIDTH-1:0] sysMemWrAddress;

//
// Instantiate the three lookup tables
//
reg [RF_RD_ADDRESS_WIDTH-1:0] rfIndex = 0;
reg [PT_RD_ADDRESS_WIDTH-1:0] ptIndex = 0;
localOscillatorDPRAM #(.WRITE_ADDRESS_WIDTH(RF_WR_ADDRESS_WIDTH),
                       .WRITE_DATA_WIDTH(OUTPUT_WIDTH))
  rfTable (.wClk(sysClk),
           .wEnable(sysRfMemWrStrobe),
           .wAddr(sysMemWrAddress[RF_WR_ADDRESS_WIDTH-1:0]),
           .wData(sysMemWrData),
           .rClk(clk),
           .rAddr(rfIndex),
           .rData({rfSin, rfCos}));
localOscillatorDPRAM #(.WRITE_ADDRESS_WIDTH(PT_WR_ADDRESS_WIDTH),
                       .WRITE_DATA_WIDTH(OUTPUT_WIDTH))
  plTable (.wClk(sysClk),
           .wEnable(sysPlMemWrStrobe),
           .wAddr(sysMemWrAddress),
           .wData(sysMemWrData),
           .rClk(clk),
           .rAddr(ptIndex),
           .rData({plSin, plCos}));
localOscillatorDPRAM #(.WRITE_ADDRESS_WIDTH(PT_WR_ADDRESS_WIDTH),
                       .WRITE_DATA_WIDTH(OUTPUT_WIDTH))
  phTable (.wClk(sysClk),
           .wEnable(sysPhMemWrStrobe),
           .wAddr(sysMemWrAddress),
           .wData(sysMemWrData),
           .rClk(clk),
           .rAddr(ptIndex),
           .rData({phSin, phCos}));

//
// Hang on to values needed for operation
//
reg                      sysUseRMS = 0, sysIsSingle = 0, sysRun = 0;
reg                      rfSynced = 0, ptSynced = 0;
assign sysGpioCsr = { {32-2-4{1'b0}},
                      ptSynced, rfSynced,
                      1'b0, sysUseRMS, sysIsSingle, sysRun };
reg [RF_RD_ADDRESS_WIDTH-1:0] sysRfLastIdx;
reg [PT_RD_ADDRESS_WIDTH-1:0] sysPtLastIdx;
always @(posedge sysClk) begin
    if (sysAddressStrobe) begin
        sysMemWrAddress <= sysGpioData[PT_WR_ADDRESS_WIDTH-1:0];
    end
    if (sysGpioStrobe) begin
        case (sysMemWrBankSelect)
        2'b00: sysRfLastIdx <= sysMemWrAddress[1+:RF_RD_ADDRESS_WIDTH];
        2'b01: sysPtLastIdx <= sysMemWrAddress[1+:PT_RD_ADDRESS_WIDTH];
        2'b10: sysPtLastIdx <= sysMemWrAddress[1+:PT_RD_ADDRESS_WIDTH];
        2'b11: begin
            sysRun      <= sysGpioData[0];
            sysIsSingle <= sysGpioData[1];
            sysUseRMS   <= sysGpioData[2];
        end
        default: ;
        endcase
    end
end

//////////////////////////////////////////////////////////////////////////////
//                             ADC CLOCK DOMAIN                             //
//////////////////////////////////////////////////////////////////////////////

wire run, isSingle;
wire [RF_RD_ADDRESS_WIDTH-1:0] rfLastIdx;
wire [PT_RD_ADDRESS_WIDTH-1:0] ptLastIdx;

forwardData #(.DATA_WIDTH(2+PT_RD_ADDRESS_WIDTH+RF_RD_ADDRESS_WIDTH))
  loInfo (
    .inClk(sysClk),
    .inData({ sysRun, sysIsSingle, sysPtLastIdx, sysRfLastIdx }),
    .outClk(clk),
    .outData({ run, isSingle, ptLastIdx, rfLastIdx }));
reg [RF_RD_ADDRESS_WIDTH-1:0] singleMatch = 0;
reg                           singleActive = 0;
always @(posedge clk)
begin
    if (run) begin
        if (adcSyncMarker) begin
            if (isSingle) begin
                loSynced <= 1;
            end
            else begin
                if ((rfIndex == 0) && (ptIndex == 0)) begin
                    loSynced <= 1;
                    rfSynced <= 1;
                    ptSynced <= 1;
                end
                else begin
                    loSynced <= 0;
                    rfSynced <= (rfIndex == 0);
                    ptSynced <= (ptIndex == 0);
                end
                rfIndex <= 1;
                ptIndex <= 1;
            end
        end
        else begin
            rfIndex <= (rfIndex == rfLastIdx) ? 0 : rfIndex + 1;
            ptIndex <= (ptIndex == ptLastIdx) ? 0 : ptIndex + 1;
        end
        if (isSingle) begin
            if (singleStart) begin
                tbtLoadAccumulator  <= 1;
                tbtLatchAccumulator <= 0;
                singleMatch <= rfIndex;
                singleActive <= 1;
            end
            else if (singleActive && (rfIndex == singleMatch)) begin
                tbtLoadAccumulator  <= 0;
                tbtLatchAccumulator <= 1;
                singleActive <= 0;
            end
            else begin
                tbtLoadAccumulator  <= 0;
                tbtLatchAccumulator <= 0;
            end
        end
        else begin
            if (rfIndex == 0) begin
                tbtLoadAccumulator  <= 1;
                tbtLatchAccumulator <= 1;
            end
            else begin
                tbtLoadAccumulator  <= 0;
                tbtLatchAccumulator <= 0;
            end
        end
        mtLoadAndLatch <= (ptIndex == 0);
    end
end

endmodule
