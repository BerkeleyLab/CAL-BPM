//
// Decimate to FA rate
//

module faDecimate #(
    parameter DATA_WIDTH        = 24,
    parameter DECIMATION_FACTOR = 152,
    parameter STAGES            = 3,
    parameter CHANNEL_WIDTH     = 2,
    parameter LAST_CHAN         = 3
    ) (
    input                     clk,

    input    [DATA_WIDTH-1:0] inputData,
    input [CHANNEL_WIDTH-1:0] inputChannel,
    input                     inputValid,
    input               [3:0] cicShift,
    input                     decimateFlag,

    output reg                outputToggle = 0,
    output reg[((LAST_CHAN+1)*DATA_WIDTH)-1:0]outputData);


reg    [DATA_WIDTH-1:0] inputData_d;
reg [CHANNEL_WIDTH-1:0] inputChannel_d;
reg                     inputValid_d;
reg                     downsample = 0;
always @(posedge clk) begin
    inputData_d    <= inputData;
    inputChannel_d <= inputChannel;
    inputValid_d   <= inputValid;
    if (inputValid && (inputChannel == 0)) downsample <= decimateFlag;
end

// Scale CIC output by 0 to 15 bits to account for change in decimation when
// number of turns per RF changes (CIC scaling is decimation**NSTAGES).
// For example, if there are four turns per RF sample in the demodulator the
// FA decimation will be a quarter of the value for which the CIC filter was
// instantiated. With a four stage filter this means that, without scaling,
// the output would be 4**4, or 256 times, too small!
// This requires that we pad the input data to ensure positive bit selection
// in the CIC output shift when a one or two stage CIC is chosen.
parameter P = 15 - (STAGES == 1 ? $clog2(DECIMATION_FACTOR) :
                    STAGES == 2 ? $clog2(DECIMATION_FACTOR *DECIMATION_FACTOR) :
                    15);
parameter PAD = P <= 0 ? 0 : P;

genvar i;
generate
for (i = 0 ; i <= LAST_CHAN ; i = i + 1) begin : cic


wire cicVALID;
wire [DATA_WIDTH+15-1:0] cicDATA;

decimateCIC #(.INPUT_WIDTH(DATA_WIDTH+PAD),
              .OUTPUT_WIDTH(DATA_WIDTH+15),
              .DECIMATION_FACTOR(DECIMATION_FACTOR),
              .STAGES(STAGES))
  decimateCIC (
    .clk(clk),
    .S_downsample(downsample),

    .S_TDATA({inputData_d, {PAD{1'b0}}}),
    .S_TVALID(inputValid_d && (inputChannel_d == i)),

    .M_TDATA(cicDATA),
    .M_TVALID(cicVALID));

always @(posedge clk) begin
    if (cicVALID) begin
       outputData[i*DATA_WIDTH+:DATA_WIDTH] <= cicDATA[15-cicShift+:DATA_WIDTH];
       if (i == LAST_CHAN) outputToggle <= !outputToggle;
    end
end

end /* for */
endgenerate

endmodule
