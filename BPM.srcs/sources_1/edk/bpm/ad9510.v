//
// Simple 24-bit SPI transfers
//
module ad9510 #(
    parameter WRITE_WIDTH = 24,
    parameter READ_WIDTH = 8)(
    input                        clk, writeStrobe,
    input      [WRITE_WIDTH-1:0] writeData,
    output reg                   busy = 0,
    output wire [READ_WIDTH-1:0] readData,
    output wire                  SPI_CLK, SPI_SSEL, SPI_MOSI,
    input                        SPI_MISO);

parameter COUNTER_WIDTH = $clog2(WRITE_WIDTH+1);
parameter DIVISOR_WIDTH = 3;

reg   [WRITE_WIDTH-1:0] shiftRegister;
reg [COUNTER_WIDTH-1:0] bitCounter;
reg [DIVISOR_WIDTH-1:0] clkDivider;

assign readData = shiftRegister[READ_WIDTH-1:0];
assign SPI_SSEL = !busy;
assign SPI_CLK = clkDivider[DIVISOR_WIDTH-1];
assign SPI_MOSI = shiftRegister[WRITE_WIDTH-1];

always @(posedge clk) begin
    if (!busy) begin
        bitCounter <= WRITE_WIDTH;
        clkDivider <= 0;
        if (writeStrobe) begin
            shiftRegister <= writeData;
            busy <= 1;
        end
    end
    else begin
        clkDivider <= clkDivider + 1;
        if (clkDivider == 0) begin
            if (bitCounter == 0) begin
                busy <= 0;
            end
        end
        else if (clkDivider == {DIVISOR_WIDTH{1'b1}}) begin
            shiftRegister <= {shiftRegister[WRITE_WIDTH-2:0], SPI_MISO};
            bitCounter <= bitCounter - 1;
        end
    end
end

endmodule
