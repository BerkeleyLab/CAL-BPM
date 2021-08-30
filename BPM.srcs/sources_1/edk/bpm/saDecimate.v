//
// Decimate to SA rate
//

module saDecimate #(
    parameter DATA_WIDTH        = -1,
    parameter DECIMATION_FACTOR = -1,
    parameter STAGES            = -1,
    parameter CHANNEL_COUNT     = -1,
    parameter DEBUG             = "false"
    ) (
    input                     clk,

    input [(CHANNEL_COUNT*DATA_WIDTH)-1:0] inputData,
    input                                  inputToggle,
    input                                  decimateFlag,
    
    output reg                                  outputToggle = 0,
    output reg [(CHANNEL_COUNT*DATA_WIDTH)-1:0] outputData);

reg inputMatch = 0, decimateMatch = 0;
reg inputVALID = 0;
reg downsample = 0;
wire [3:0] cicValids;
always @(posedge clk) begin
    if (inputToggle == inputMatch) begin
        inputVALID <= 0;
    end
    else begin
        inputVALID <= 1;
        downsample <= decimateFlag;
        inputMatch <= inputToggle;
    end
    if (cicValids[0]) outputToggle <= !outputToggle;
end

genvar i;
generate
for (i = 0 ; i < CHANNEL_COUNT ; i = i + 1) begin : cic
wire                  cicValid;
wire [DATA_WIDTH-1:0] cicData;
assign cicValids[i] = cicValid;

always @(posedge clk) begin
    if (cicValid) begin
        outputData[i*DATA_WIDTH+:DATA_WIDTH] <= cicData;
    end
end
        
decimateCIC #(.INPUT_WIDTH(DATA_WIDTH),
              .OUTPUT_WIDTH(DATA_WIDTH),
              .DECIMATION_FACTOR(DECIMATION_FACTOR),
              .STAGES(STAGES))
  decimateCIC (
    .clk(clk),
    .S_downsample(downsample),

    .S_TDATA(inputData[i*DATA_WIDTH+:DATA_WIDTH]),
    .S_TVALID(inputVALID),

    .M_TDATA(cicData),
    .M_TVALID(cicValid));
end /* for */
endgenerate

endmodule
