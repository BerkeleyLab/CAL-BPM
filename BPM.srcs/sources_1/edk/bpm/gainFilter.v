//
// First-order low-pass (unsigned values)
// Pole at z = 1 - (1 / (1 << filterShift))
//
module gainFilter #(
    parameter DATA_WIDTH  = 30,
    parameter SHIFT_WIDTH = 3
    ) (
    input                        clk,
    input      [SHIFT_WIDTH-1:0] filterShift,
    input                        S_TVALID,
    input       [DATA_WIDTH-1:0] S_TDATA,
    output reg                   M_TVALID,
    output wire [DATA_WIDTH-1:0] M_TDATA);

localparam WIDEN = (1 << SHIFT_WIDTH) - 1;
localparam SUM_WIDTH = DATA_WIDTH + WIDEN;

reg [SUM_WIDTH-1:0] sum = 0;
assign M_TDATA = sum[WIDEN+:DATA_WIDTH];
always @(posedge clk)
begin
    M_TVALID <= S_TVALID;
    if (S_TVALID) begin
        sum <= (S_TDATA << (WIDEN - filterShift)) + (sum - (sum >> filterShift));
    end
end

endmodule
