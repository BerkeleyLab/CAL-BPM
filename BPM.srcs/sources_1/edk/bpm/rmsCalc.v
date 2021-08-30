//
// Compute RMS component of X and Y position measurements
//
module rmsCalc #(
    parameter GPIO_WIDTH    = 32
    ) (
    input                       clk,
    input                       faToggle,
    input      [GPIO_WIDTH-1:0] faX,
    input      [GPIO_WIDTH-1:0] faY,
    output reg [GPIO_WIDTH-1:0] wideXrms = 0,
    output reg [GPIO_WIDTH-1:0] wideYrms = 0,
    output reg [GPIO_WIDTH-1:0] narrowXrms = 0,
    output reg [GPIO_WIDTH-1:0] narrowYrms = 0);

localparam INPUT_WIDTH  = 26; // Number of meaninful bits in faX/Y
// Limit the width of operands to reduce DSP block usage
localparam DATA_WIDTH           = 25;
// Xiinix FIR widens data
localparam FILTER_OUTPUT_WIDTH = DATA_WIDTH;
localparam FILTER_INPUT_WIDTH  = FILTER_OUTPUT_WIDTH - 1;
localparam SQUARE_WIDTH = 2 * DATA_WIDTH;

//
// Remove DC component
// Filter time constant about 2^11 FA intervals (0.2048 seconds).
// Filter cutoff frequency ~0.78 Hz.
//
reg  faToggle_d = 0, washEnable = 0, washValid = 0;
wire [INPUT_WIDTH-1:0] xWash, yWash;
washout #(.WIDTH(INPUT_WIDTH), .L2_ALPHA(11))
  washX (.clk(clk),
         .enable(washEnable),
         .x(faX[INPUT_WIDTH-1:0]),
         .y(xWash));
washout #(.WIDTH(INPUT_WIDTH), .L2_ALPHA(11))
  washY (.clk(clk),
         .enable(washEnable),
         .x(faY[INPUT_WIDTH-1:0]),
         .y(yWash));
always @(posedge clk) begin
    faToggle_d <= faToggle;
    washEnable <= (faToggle != faToggle_d);
    washValid <= washEnable;
end

//
// Clip to internal range
//
reg  widebandValid = 0;
wire       [DATA_WIDTH-1:0] xWashClippedData, yWashClippedData;
reg signed [DATA_WIDTH-1:0] xWideband, yWideband;
reduceWidth #(.IWIDTH(INPUT_WIDTH), .OWIDTH(DATA_WIDTH))
                                    reducewXd (.I(xWash), .O(xWashClippedData));
reduceWidth #(.IWIDTH(INPUT_WIDTH), .OWIDTH(DATA_WIDTH))
                                    reducewYd (.I(yWash), .O(yWashClippedData));

wire [FILTER_INPUT_WIDTH-1:0] xWashClippedFilter, yWashClippedFilter;
reg signed [FILTER_INPUT_WIDTH-1:0] xFilterIn, yFilterIn;
reduceWidth #(.IWIDTH(INPUT_WIDTH), .OWIDTH(FILTER_INPUT_WIDTH))
                                  reducewXf (.I(xWash), .O(xWashClippedFilter));
reduceWidth #(.IWIDTH(INPUT_WIDTH), .OWIDTH(FILTER_INPUT_WIDTH))
                                  reducewYf (.I(yWash), .O(yWashClippedFilter));
always @(posedge clk) begin
    xWideband <= xWashClippedData;
    yWideband <= yWashClippedData;
    xFilterIn <= xWashClippedFilter;
    yFilterIn <= yWashClippedFilter;
    widebandValid <= washValid;
end

//
// The FIR low-pass filters that select the narrow band region of interest.
// Used to be a single FIR with two channels, but that caused weird results.
//
localparam AXI_INPUT_WIDTH = (((FILTER_INPUT_WIDTH + 7) / 8) * 8);
localparam AXI_OUTPUT_WIDTH = (((FILTER_OUTPUT_WIDTH + 7) / 8) * 8);
wire signed  [AXI_INPUT_WIDTH-1:0] firXdata = xFilterIn;
wire signed  [AXI_INPUT_WIDTH-1:0] firYdata = yFilterIn;
reg                          [1:0] firInTvalid = 0;
wire                         [1:0] firInTready;
wire                         [1:0] firOutTvalid;
wire      [2*AXI_OUTPUT_WIDTH-1:0] firOutTdata;
reg signed        [DATA_WIDTH-1:0] xNarrowband, yNarrowband;
reg                                narrowbandValid = 0;
rmsBandSelect rmsBandSelect_x (
    .aclk(clk),
    .s_axis_data_tvalid(firInTvalid[0]),
    .s_axis_data_tready(firInTready[0]),
    .s_axis_data_tdata(firXdata),
    .m_axis_data_tvalid(firOutTvalid[0]),
    .m_axis_data_tdata(firOutTdata[0+:AXI_OUTPUT_WIDTH]));
rmsBandSelect rmsBandSelect_y (
    .aclk(clk),
    .s_axis_data_tvalid(firInTvalid[1]),
    .s_axis_data_tready(firInTready[1]),
    .s_axis_data_tdata(firYdata),
    .m_axis_data_tvalid(firOutTvalid[1]),
    .m_axis_data_tdata(firOutTdata[AXI_OUTPUT_WIDTH+:AXI_OUTPUT_WIDTH]));
always @(posedge clk) begin
    if (firInTvalid[0]) begin
        if (firInTready[0]) begin
            firInTvalid[0] <= 0;
        end
    end
    else if (widebandValid) begin
        firInTvalid[0] <= 1;
    end
    if (firInTvalid[1]) begin
        if (firInTready[1]) begin
            firInTvalid[1] <= 0;
        end
    end
    else if (widebandValid) begin
        firInTvalid[1] <= 1;
    end
    if (firOutTvalid[0]) begin
        narrowbandValid <= 1;
        xNarrowband <= firOutTdata[0+:DATA_WIDTH];
    end
    else begin
        narrowbandValid <= 0;
    end
    if (firOutTvalid[1]) begin
        yNarrowband <= firOutTdata[AXI_OUTPUT_WIDTH+:DATA_WIDTH];
    end
end

//
// Square x/y, wideband/narrowband values
// Multipliers can free run since the values are stable between updates.
//
reg signed [SQUARE_WIDTH-1:0] xwSquared, ywSquared, xnSquared, ynSquared;
reg squaresValid = 0;
always @(posedge clk) begin
    xwSquared <= xWideband * xWideband;
    ywSquared <= yWideband * yWideband;
    xnSquared <= xNarrowband * xNarrowband;
    ynSquared <= yNarrowband * yNarrowband;
end
always @(posedge clk) begin
    squaresValid <= narrowbandValid;
end

//
// The low-pass filters that simulate the 'mean' part of the RMS computation.
// Filter time constant about 2^12 FA intervals (0.4096 seconds).
// Filter cutoff frequency ~0.39 Hz.
//
wire [SQUARE_WIDTH-1:0] xwMean, ywMean, xnMean, ynMean;
lowpass #(.WIDTH(SQUARE_WIDTH), .L2_ALPHA(12))
               meanXw (.clk(clk), .en(squaresValid), .u(xwSquared), .y(xwMean));
lowpass #(.WIDTH(SQUARE_WIDTH), .L2_ALPHA(12))
               meanYw (.clk(clk), .en(squaresValid), .u(ywSquared), .y(ywMean));
lowpass #(.WIDTH(SQUARE_WIDTH), .L2_ALPHA(12))
               meanXn (.clk(clk), .en(squaresValid), .u(xnSquared), .y(xnMean));
lowpass #(.WIDTH(SQUARE_WIDTH), .L2_ALPHA(12))
               meanYn (.clk(clk), .en(squaresValid), .u(ynSquared), .y(ynMean));
reg filterDone = 0;
always @(posedge clk) begin
    filterDone <= squaresValid;
end

//
// Multiplex filtered values through square root block
//
localparam SQRT_IDLE    = 3'd0,
           SQRT_XW_WAIT = 3'd1,
           SQRT_YW_WAIT = 3'd2,
           SQRT_XN_WAIT = 3'd3,
           SQRT_YN_WAIT = 3'd4;
reg              [2:0] sqrtState = SQRT_IDLE;
reg [SQUARE_WIDTH-1:0] sqrtOperand;
reg                    sqrtEnable;
wire  [DATA_WIDTH-1:0] squareRoot;
wire                   sqrtDav;
isqrt #(.X_WIDTH(SQUARE_WIDTH)) rmsIsqrt(.clk(clk),
                                         .x(sqrtOperand),
                                         .en(sqrtEnable),
                                         .y(squareRoot),
                                         .dav(sqrtDav));
always @(posedge clk) begin
    case (sqrtState)
    SQRT_IDLE: begin
        sqrtOperand <= xwMean;
        if (filterDone) begin
            sqrtEnable <= 1;
            sqrtState <= SQRT_XW_WAIT;
        end
    end
    SQRT_XW_WAIT: begin
        if (sqrtDav) begin
            wideXrms <= { {GPIO_WIDTH-DATA_WIDTH{1'b0}}, squareRoot };
            sqrtEnable <= 1;
            sqrtOperand <= ywMean;
            sqrtState <= SQRT_YW_WAIT;
        end
        else begin
            sqrtEnable <= 0;
        end
    end
    SQRT_YW_WAIT: begin
        if (sqrtDav) begin
            wideYrms <= { {GPIO_WIDTH-DATA_WIDTH{1'b0}}, squareRoot };
            sqrtEnable <= 1;
            sqrtOperand <= xnMean;
            sqrtState <= SQRT_XN_WAIT;
        end
        else begin
            sqrtEnable <= 0;
        end
    end
    SQRT_XN_WAIT: begin
        if (sqrtDav) begin
            narrowXrms <= { {GPIO_WIDTH-DATA_WIDTH{1'b0}}, squareRoot };
            sqrtEnable <= 1;
            sqrtOperand <= ynMean;
            sqrtState <= SQRT_YN_WAIT;
        end
        else begin
            sqrtEnable <= 0;
        end
    end
    SQRT_YN_WAIT: begin
        if (sqrtDav) begin
            narrowYrms <= { {GPIO_WIDTH-DATA_WIDTH{1'b0}}, squareRoot };
            sqrtState <= SQRT_IDLE;
        end
        else begin
            sqrtEnable <= 0;
        end
    end
    default: sqrtState <= SQRT_IDLE;
    endcase
end
endmodule
