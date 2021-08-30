//
// Derive AFE PLL reference from EVR recovered clock
//
module afeRefClkGenerator(sysClk, writeData, csrStrobe, csr,
                          evrClk, evrFiducial, evrAfeRef);

parameter BUS_WIDTH     = 32;
parameter COUNTER_WIDTH = 8;

input                  sysClk, csrStrobe;
input  [BUS_WIDTH-1:0] writeData;
output [BUS_WIDTH-1:0] csr;
wire   [BUS_WIDTH-1:0] csr;
input                  evrClk, evrFiducial;
output                 evrAfeRef;
reg                    evrAfeRef = 0;

reg                     evrFiducial_d = 0;
reg [COUNTER_WIDTH-1:0] reloadHi = ~0, reloadLo = ~0;
reg [COUNTER_WIDTH-1:0] evrCounter = 0, evrCountAtSync;
reg                     evrSynced = 0;
reg                     evrAfeRefAtSync;

//
// Microblaze interface
//
assign csr = { evrCountAtSync, {BUS_WIDTH-(3*COUNTER_WIDTH)-2{1'b0}},
               evrAfeRefAtSync, evrSynced,
               reloadHi, reloadLo };
always @(posedge sysClk) begin
    if (csrStrobe) begin
        reloadLo <= writeData[COUNTER_WIDTH-1:0];
        reloadHi <= writeData[(2*COUNTER_WIDTH)-1:COUNTER_WIDTH];
    end
end
        
//
// EVR clock domain
// The CSR is written only once during startup and status shouldn't change
// very often so don't bother with explicit clock-crossing firmware.
//
always @(posedge evrClk) begin
    evrFiducial_d <= evrFiducial;
    if (evrFiducial && !evrFiducial_d) begin
        if ((evrAfeRef == 0) && (evrCounter == 0))
            evrSynced <= 1;
        else
            evrSynced <= 0;
        evrCounter <= reloadHi;
        evrAfeRef <= 1;
        evrCountAtSync <= evrCounter;
        evrAfeRefAtSync <= evrAfeRef;
    end
    else begin
        if (evrCounter == 0) begin
            if (evrAfeRef) begin
                evrCounter <= reloadLo;
                evrAfeRef <= 0;
            end
            else begin
                evrCounter <= reloadHi;
                evrAfeRef <= 1;
            end
        end
        else begin
            evrCounter <= evrCounter - 1;
        end
    end
end

endmodule
