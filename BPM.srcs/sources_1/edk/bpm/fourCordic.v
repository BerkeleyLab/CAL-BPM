// Multichannel rectangular to polar coordinate conversion.
// Input consists of 8 values -- a signed I and Q value for each of 4 ADCs.
// Output consists four sequential unsigned magnitude values.
// Input has back pressure.
// Output does not accept back pressure.
// The CORDIC block must be one bit wider than the input I and Q values
// since, "the Cartesian operands and results are represented using
// fixed-point twos complement numbers with an integer width of 2 bits"
// and the operands must be within the range +/-1.
// The output can have the same width as the I and Q inputs since the latter
// are signed and the former unsigned and the quadrature sum of the inputs
// is always less than 1 thus even with the CORDIC gain the output fits.

module fourCordic #(
    parameter IO_WIDTH        = 26,
    parameter S_TUSER_WIDTH   = 4,
    parameter DEBUG           = "false"
    ) (
    input                             clk,

    input          [(8*IO_WIDTH)-1:0] S_TDATA,
    input         [S_TUSER_WIDTH-1:0] S_TUSER,
    input                             S_TVALID,
    output reg                        S_TREADY = 1,
    
    (*mark_debug=DEBUG*) output wire        [IO_WIDTH-1:0] M_TDATA,
    (*mark_debug=DEBUG*) output wire [S_TUSER_WIDTH+2-1:0] M_TUSER,
    (*mark_debug=DEBUG*) output wire                       M_TVALID,
    (*mark_debug=DEBUG*) output wire                       overflowFlag);

// The following value must match the wizard-generated CORDIC block.
// The CORDIC inputs have an integer part of two bits [-2,2) but an
// acceptable input range of only [1,1) and so must be one bit wider
// than the I/Q sums.
parameter CORDIC_IO_WIDTH = IO_WIDTH + 1;

(*mark_debug=DEBUG*) reg [S_TUSER_WIDTH-1:0] userData;
                     reg  [(8*IO_WIDTH)-1:0] muxInputs;
(*mark_debug=DEBUG*) reg               [1:0] muxChan = 0;
(*mark_debug=DEBUG*) reg                     muxTVALID;
wire [IO_WIDTH-1:0] muxI = muxInputs[(2*muxChan+0)*IO_WIDTH+:IO_WIDTH];
wire [IO_WIDTH-1:0] muxQ = muxInputs[(2*muxChan+1)*IO_WIDTH+:IO_WIDTH];

// CORDIC block uses true AXI stream TDATA ports -- a multiple
// of 8 bits for each of the I/Q inputs and R/theta outputs.
localparam CORDIC_PORT_HALFWIDTH = 8*((CORDIC_IO_WIDTH+7)/8);
localparam IQ_WIDEN = CORDIC_PORT_HALFWIDTH - IO_WIDTH;

// Explicitly sign extend CORDIC inputs.
(*mark_debug=DEBUG*) wire [CORDIC_PORT_HALFWIDTH-1:0] cordicQ, cordicI;
assign cordicQ = {{IQ_WIDEN{muxQ[IO_WIDTH-1]}}, muxQ};
assign cordicI = {{IQ_WIDEN{muxI[IO_WIDTH-1]}}, muxI};
wire [CORDIC_PORT_HALFWIDTH-1:0] cordicR, cordicTheta;
assign M_TDATA = cordicR[IO_WIDTH-1:0];
assign overflowFlag = M_TVALID && (cordicR[IO_WIDTH] != 0);

always @(posedge clk) begin
    if (S_TVALID && S_TREADY) begin
        S_TREADY <= 0;
        muxInputs <= S_TDATA;
        userData <= S_TUSER;
        muxTVALID <= 1;
    end
    else if (muxTVALID) begin
        muxChan <= muxChan + 1;
        if (muxChan == 2'b11) begin
            muxTVALID <= 0;
            S_TREADY <= 1;
        end
    end
end

adcCordic adcCordic (.aclk(clk),
                     .s_axis_cartesian_tvalid(muxTVALID),
                     .s_axis_cartesian_tuser({userData, muxChan}),
                     .s_axis_cartesian_tdata({cordicQ, cordicI}),
                     .m_axis_dout_tvalid(M_TVALID),
                     .m_axis_dout_tuser(M_TUSER),
                     .m_axis_dout_tdata({cordicTheta, cordicR}));

endmodule
