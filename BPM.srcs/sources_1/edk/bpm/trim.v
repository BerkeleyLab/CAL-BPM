//
// Apply gain compensation factors
//
module trim #(
    parameter MAG_WIDTH  = 26,
    parameter GAIN_WIDTH = 27
    ) (
    input                          clk,
    input                          strobe,
    input     [(MAG_WIDTH*4)-1:0]  magnitudes,
    input     [(GAIN_WIDTH*4)-1:0] gains,
    output reg                     trimmedToggle,
    output reg [(MAG_WIDTH*4)-1:0] trimmed);

localparam PRODUCT_WIDTH = MAG_WIDTH + GAIN_WIDTH;
localparam MULTIPLIER_LATENCY = 6;
reg [MULTIPLIER_LATENCY-1:0] strobes;
wire productReady = strobes[MULTIPLIER_LATENCY-1];

always @(posedge clk) begin
    strobes <= { strobes[MULTIPLIER_LATENCY-2:0], strobe };
    if (productReady) trimmedToggle <= !trimmedToggle;
end

genvar i;
generate
for (i = 0 ; i < 4 ; i = i + 1) begin : trim
    wire [MAG_WIDTH-1:0] mag = magnitudes[i*MAG_WIDTH+:MAG_WIDTH];
    wire [GAIN_WIDTH-1:0] gain = gains[i*GAIN_WIDTH+:GAIN_WIDTH];
    wire [PRODUCT_WIDTH-1:0] product;

    trimMultiplier trimMultiplier (.clk(clk),
                                   .a(mag),
                                   .b(gain),
                                   .p(product));

    // Round result
    always @(posedge clk) begin
        if (productReady) begin
            trimmed[i*MAG_WIDTH+:MAG_WIDTH] <=
                                   product[GAIN_WIDTH-1+:MAG_WIDTH] + 
                                   {{MAG_WIDTH-1{1'b0}}, product[GAIN_WIDTH-2]};
            
        end
    end
end
endgenerate

endmodule
