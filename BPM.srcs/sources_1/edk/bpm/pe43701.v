//
// Write to Peregrine Semiconductor PE43701 digital attenuators
// Use serial address 0 only.
//

module pe43701(clk, data, enable, writeStrobe, busy, SCL, SDA, LE);

parameter CLOCK_RATE    = 100000000;
parameter BIT_RATE      =   5000000;
parameter ENABLE_COUNT  = 4;
parameter DATA_WIDTH    = 7;

input                     clk;
input  [DATA_WIDTH-1:0]   data;
input  [ENABLE_COUNT-1:0] enable;
input                     writeStrobe;
output                    busy;
output                    SCL;
output                    SDA;
output [ENABLE_COUNT-1:0] LE;

reg                    busy = 0;
reg [ENABLE_COUNT-1:0] enableLatch, LE;
reg [15:0]             shiftReg;
reg                    SCL;
wire                   SDA;
assign SDA = shiftReg[0];

parameter TICK_COUNTER_RELOAD = ((CLOCK_RATE+(BIT_RATE*2)-1)/(BIT_RATE*2))-1;
parameter TICK_COUNTER_WIDTH  = $clog2(TICK_COUNTER_RELOAD);
reg [TICK_COUNTER_WIDTH-1:0] tickCounter;
reg                          tick;
reg [4:0]                    bitsLeft;
reg [1:0]                    LEstate;

always @(posedge clk) begin
    if (!busy) begin
        SCL <= 0;
        LE <= 0;
        tickCounter <= TICK_COUNTER_RELOAD;
        tick <= 0;
        bitsLeft <= 16;
        LEstate <= 0;
        if (writeStrobe) begin
            shiftReg <= { 8'h00, 1'b0, data };
            enableLatch <= enable;
            busy <= 1;
        end
    end
    else begin
        if (tickCounter == 0) begin
            tickCounter <= TICK_COUNTER_RELOAD;
            tick <= 1;
        end
        else begin
            tickCounter <= tickCounter - 1;
            tick <= 0;
        end
        if (tick) begin
            if (bitsLeft) begin
                if (SCL) begin
                    bitsLeft <= bitsLeft - 1;
                    shiftReg <= { 1'b0, shiftReg[15:1] };
                    SCL <= 0;
                end
                else begin
                    SCL <= 1;
                end
            end
            else begin
                LEstate <= LEstate + 1;
                case (LEstate)
                0: LE <= enableLatch;
                1: LE <= 0;
                2: busy <= 0;
                default: ;
                endcase
            end
        end
    end
end

endmodule



