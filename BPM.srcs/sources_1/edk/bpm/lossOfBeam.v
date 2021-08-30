//
// Generate loss-of-beam trigger
//
module lossOfBeam #(
    parameter   DATA_WIDTH = 32,
    parameter HISTORY_SIZE = 64,
    parameter   DATA_SHIFT = 3) (
    input                       clk, thresholdStrobe, turnByTurnToggle,
    input      [DATA_WIDTH-1:0] gpioData, buttonSum,
    output reg [DATA_WIDTH-1:0] threshold,
    output reg                  lossOfBeamTrigger);

parameter   ADDR_WIDTH = $clog2(HISTORY_SIZE);

wire[DATA_WIDTH-1:0] smoothedSum;
reg [DATA_WIDTH-1:0] diff1, diff2;
reg [DATA_WIDTH-1:0] limitHistory[0:HISTORY_SIZE-1], limit;
reg [ADDR_WIDTH-1:0] addr = 0;
reg                  turnByTurnMatch = 0;
reg            [1:0] state = 0;

//
// Apply low-pass filter to reduce the effect of a single-turn glitch
//
lowpass #(.WIDTH(DATA_WIDTH),
         .L2_ALPHA(3)) smooth (.clk(clk),
                               .en(turnByTurnToggle != turnByTurnMatch),
                               .u(buttonSum),
                               .y(smoothedSum));

always @(posedge clk) begin
    limit <= limitHistory[addr];
    if (thresholdStrobe) threshold <= gpioData;

    case(state)
    0: begin
        if (turnByTurnToggle != turnByTurnMatch) begin
            turnByTurnMatch <= !turnByTurnMatch;
            state <= 1;
        end
       end
    1: begin
        if (smoothedSum < limit) begin
            lossOfBeamTrigger <= 1;
        end
        else begin
            lossOfBeamTrigger <= 0;
        end
        diff1 <= smoothedSum - {{DATA_SHIFT{1'b0}},
                                          smoothedSum[DATA_WIDTH-1:DATA_SHIFT]};
        state <= 2;
       end
    2: begin
        diff2 <= diff1 - threshold;
        state <= 3;
       end
    3: begin
        limitHistory[addr] <= (diff2[DATA_WIDTH-1] == 0) ? diff2 : 0;
        addr <= addr + 1;
        state <= 0;
       end
    default: ;
    endcase
end

endmodule
