//
// Washout (first-order high-pass filter)
//
// Difference is one bit wider than input since, for example:
//       Input sits near negative full scale for a while.
//       High-pass operation drives output back to zero.
//       Input immediately transitions to near positive full scale.
//       Output transitions from 0 to (input +full scale - input -full scale).
// Output is same width as input and is clipped if necessary.
// One clock latency
//
// Eric Norum
// LBNL
//

module washout(clk, enable, x, y);

parameter WIDTH    = 14;
parameter L2_ALPHA = 10;

parameter SUM_WIDTH  = WIDTH+L2_ALPHA;
parameter DIFF_WIDTH = SUM_WIDTH+1;

input              clk, enable;
input  [WIDTH-1:0] x;
output [WIDTH-1:0] y;
reg    [WIDTH-1:0] y = 0;

reg  [SUM_WIDTH-1:0]  sum = 0;
wire [DIFF_WIDTH-1:0] diff;
wire [WIDTH:0]        yRaw;
 
assign diff = {x[WIDTH-1], x, {DIFF_WIDTH-WIDTH-1{1'b0}}} -
              {sum[SUM_WIDTH-1], sum};
assign yRaw = diff[DIFF_WIDTH-1:DIFF_WIDTH-WIDTH-1];

always @(posedge clk)
begin
    if (enable) begin
        sum <= sum +
              { {L2_ALPHA-1{diff[DIFF_WIDTH-1]}}, diff[DIFF_WIDTH-1:L2_ALPHA] };
        case(yRaw[WIDTH:WIDTH-1])
          2'b01:   y <= { 1'b0, {(WIDTH-1){1'b1}} };
          2'b10:   y <= { 1'b1, {(WIDTH-1){1'b0}} };
          default: y <= yRaw[WIDTH-1:0];
        endcase
    end
end

endmodule
