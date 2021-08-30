// Decimation CIC filter.
// I/O values can be signed or unsigned.
module decimateCIC #(
    parameter INPUT_WIDTH       = -1,
    parameter OUTPUT_WIDTH      = -1,
    parameter DECIMATION_FACTOR = -1,
    parameter STAGES            = -1,
    parameter IS_SIGNED         = 0
    ) (
    input                   clk,

    input [INPUT_WIDTH-1:0] S_TDATA,
    input                   S_TVALID,
    input                   S_downsample,

    output wire [OUTPUT_WIDTH-1:0] M_TDATA,
    output wire                    M_TVALID);

// Hack this in since Vivado 2017.3 refuses to accept pow here.
// Not only does it refuse to accept it, its presence causes weird
// errors in the modules which instantiate this module!
parameter WIDEN = $clog2(
          (STAGES==1)?(DECIMATION_FACTOR) :
          (STAGES==2)?(DECIMATION_FACTOR*DECIMATION_FACTOR) :
          (STAGES==3)?(DECIMATION_FACTOR*DECIMATION_FACTOR*DECIMATION_FACTOR) :
                      (DECIMATION_FACTOR*DECIMATION_FACTOR*
                      DECIMATION_FACTOR*DECIMATION_FACTOR));
localparam WIDTH = INPUT_WIDTH + WIDEN;
localparam OSHIFT = WIDEN - (OUTPUT_WIDTH - INPUT_WIDTH);

genvar i;

// Integrators
// Supply dummy '[id]iShift' and '[ic]Enables' bits for low stage counts
// to avoid negative subscripts or zero-width port select values.
localparam iShiftWidth = STAGES > 2 ? STAGES - 1 : 2;
localparam iEnableWidth = iShiftWidth + 1;
reg   [iShiftWidth-1:0] iShift = 0, dShift = 0;
wire [iEnableWidth-1:0] iEnables = {iShift, S_TVALID};
wire [iEnableWidth-1:0] dEnables = {dShift, S_TVALID && S_downsample};
always @(posedge clk) begin
    iShift <= {iShift[0+:iShiftWidth-1], S_TVALID};
    dShift <= {dShift[0+:iShiftWidth-1], S_TVALID && S_downsample};
end
reg [(STAGES*WIDTH)-1:0] sum = 0;
generate
for (i = 0 ; i < STAGES ; i = i + 1) begin : integrate
    always @(posedge clk) begin
        if (iEnables[i]) begin
            if (i == 0) begin
                sum[0*WIDTH+:WIDTH] <= sum[0*WIDTH+:WIDTH] + 
                 { {WIDEN{IS_SIGNED ? S_TDATA[INPUT_WIDTH-1]: 1'b0}}, S_TDATA };
            end
            else begin
                sum[i*WIDTH+:WIDTH] <= sum[i*WIDTH+:WIDTH] +
                                                        sum[(i-1)*WIDTH+:WIDTH];
            end
        end
    end
end
endgenerate

// Combs
reg  [iEnableWidth:0] cEnables = 0;
always @(posedge clk) begin
    cEnables <= {cEnables[0+:iEnableWidth], dEnables[STAGES-1]};
end
reg [(STAGES*WIDTH)-1:0] save = 0, result = 0;
generate
for (i = 0 ; i < STAGES ; i = i + 1) begin : combs
    always @(posedge clk) begin
        if (cEnables[i]) begin
            if (i == 0) begin
                result[0*WIDTH+:WIDTH] <= sum[(STAGES-1)*WIDTH+:WIDTH] -
                                                           save[0*WIDTH+:WIDTH];
                save[0*WIDTH+:WIDTH] <= sum[(STAGES-1)*WIDTH+:WIDTH];
            end
            else begin
                result[i*WIDTH+:WIDTH] <= result[(i-1)*WIDTH+:WIDTH] -
                                                           save[i*WIDTH+:WIDTH];
                save[i*WIDTH+:WIDTH] <= result[(i-1)*WIDTH+:WIDTH];
            end
        end
    end
end
endgenerate

wire [WIDTH-1:0] lastC = result[(STAGES-1)*WIDTH+:WIDTH];
assign M_TDATA = lastC[OSHIFT+:OUTPUT_WIDTH];
assign M_TVALID = cEnables[STAGES];

endmodule
