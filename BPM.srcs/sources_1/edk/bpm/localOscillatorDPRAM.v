//
// Dual-port RAM for local oscillator tables
// Write side in system clock domain
// Read side in ADC clock domain
// Read width is twice write width
//
module localOscillatorDPRAM #(
    parameter WRITE_ADDRESS_WIDTH = -1,
    parameter WRITE_DATA_WIDTH    = -1
    ) (
    input                           wClk,
    input                           wEnable,
    input [WRITE_ADDRESS_WIDTH-1:0] wAddr,
    input    [WRITE_DATA_WIDTH-1:0] wData,

    input                                 rClk,
    input       [WRITE_ADDRESS_WIDTH-2:0] rAddr,
    output reg [(2*WRITE_DATA_WIDTH)-1:0] rData);

localparam READ_CAPACITY = 1 << (WRITE_ADDRESS_WIDTH - 1);

reg [WRITE_DATA_WIDTH-1:0] dpramA [0:READ_CAPACITY-1];
reg [WRITE_DATA_WIDTH-1:0] dpramB [0:READ_CAPACITY-1];

wire [WRITE_ADDRESS_WIDTH-2:0] dpramWaddr = wAddr[WRITE_ADDRESS_WIDTH-1:1];

always @(posedge wClk) begin
    if (wEnable && (wAddr[0] == 0)) dpramA[dpramWaddr] <= wData;
    if (wEnable && (wAddr[0] == 1)) dpramB[dpramWaddr] <= wData;
end

always @(posedge rClk) begin
    rData <= {dpramB[rAddr], dpramA[rAddr]};
end

endmodule
