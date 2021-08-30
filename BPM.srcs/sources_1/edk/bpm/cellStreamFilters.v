//
// Filter FA data before sending to neighbours
// All in system clock domain
//
module cellStreamFilters (
    input  wire        clk,

    input  wire        csrStrobe,
    input  wire        dataStrobe,
    input  wire [31:0] gpioData,
    output wire [31:0] status,

    input  wire        faToggle,
    input  wire [31:0] inputFA_X,
    input  wire [31:0] inputFA_Y,

    output reg         filteredFaToggle = 0,
    output wire [31:0] filteredFA_X,
    output wire [31:0] filteredFA_Y);

//
// Coefficient reloads
// Tricky since each write gives only 32 bits and coefficients are 36 bits
//
reg [31:0] dLatch = 0;
reg  [3:0] dState = 0;
reg        xEnable = 0, yEnable = 0;

wire xCoefLD, yCoefLD;
assign xCoefLD = csrStrobe && gpioData[8] && gpioData[0];
assign yCoefLD = csrStrobe && gpioData[8] && gpioData[1];

wire xCoefWE, yCoefWE;
assign xCoefWE = dataStrobe && xEnable && (dState != 0);
assign yCoefWE = dataStrobe && yEnable && (dState != 0);

wire [35:0] coefficient;
assign coefficient = (dState == 1) ? { gpioData[ 3: 0], dLatch[31: 0] } :
                     (dState == 2) ? { gpioData[ 7: 0], dLatch[31: 4] } :
                     (dState == 3) ? { gpioData[11: 0], dLatch[31: 8] } :
                     (dState == 4) ? { gpioData[15: 0], dLatch[31:12] } :
                     (dState == 5) ? { gpioData[19: 0], dLatch[31:16] } :
                     (dState == 6) ? { gpioData[23: 0], dLatch[31:20] } :
                     (dState == 7) ? { gpioData[27: 0], dLatch[31:24] } :
                     (dState == 8) ? { gpioData[31: 0], dLatch[31:28] } : 36'hx;

always @(posedge clk) begin
    if (csrStrobe && gpioData[8]) begin
        dState <= 0;
        xEnable <= gpioData[0];
        yEnable <= gpioData[1];
    end
    if (dataStrobe) begin
        dLatch <= gpioData;
        if (dState == 8) begin
            dState <= 0;
        end
        else begin
            dState <= dState + 1;
        end
    end
end

//
// Filters
//
wire xRDY, yRDY;
reg  xDone = 0, yDone = 0;
reg  faMatch = 0;
wire newData;
assign newData = (faMatch != faToggle) ? 1 : 0;
always @(posedge clk) begin
    if (faMatch != faToggle) begin
        faMatch <= !faMatch;
        xDone <= 0;
        yDone <= 0;
    end
    else begin
        if ((xRDY && yRDY) || (xDone && yDone)) begin
            filteredFaToggle <= !filteredFaToggle;
            xDone <= 0;
            yDone <= 0;
        end
        else begin
            if (xRDY) xDone <= 1;
            if (yRDY) yDone <= 1;
        end
    end
end

//
// Diagnostic modes
//
reg        recordAlternateFAchannels = 0, showImpulseResponse = 0;
reg  [9:0] impulseCounter = 0;
reg [31:0] impulseData = 0;
always @(posedge clk) begin
    if (csrStrobe && gpioData[31]) recordAlternateFAchannels <= gpioData[30];
    if (csrStrobe && gpioData[29]) showImpulseResponse <= gpioData[28];

    if (newData) begin
        impulseCounter <= impulseCounter + 1;
        if (impulseCounter == 0) begin
            impulseData <= 32'h7FFFFFFF;
        end
        else begin
            impulseData <= 32'h0;
        end
    end
end

assign status = { 1'b0, recordAlternateFAchannels, 1'b0, showImpulseResponse,
                  28'h0 };

//
// Extract appropriate bits from FIR ouputs
// The FIR wizard assumes that all tap values can be full scale (2^35).
// To keep 1 nm/count scaling we require that the sum of all tap values
// be 2^35 and thus throw away the top 10 bits.
//
wire [41:0] doutX, doutY;
assign filteredFA_X = doutX[31:0];
assign filteredFA_Y = doutY[31:0];

CellStreamFilter xFilter (.clk(clk),
                          .nd(newData),
                          .coef_ld(xCoefLD),
                          .coef_we(xCoefWE),
                          .coef_din(coefficient),
                          .rdy(xRDY),
                          .din(showImpulseResponse ? impulseData : inputFA_X),
                          .dout(doutX));

CellStreamFilter yFilter (.clk(clk),
                          .nd(newData),
                          .coef_ld(yCoefLD),
                          .coef_we(yCoefWE),
                          .coef_din(coefficient),
                          .rdy(yRDY),
                          .din(showImpulseResponse ? impulseData : inputFA_Y),
                          .dout(doutY));

endmodule
