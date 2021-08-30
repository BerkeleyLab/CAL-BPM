// Accumulator part of synchronous demodulation multiply-accumulate.
// Inputs and outputs consist of 8 separate values, an I
// and a Q value for each of 4 ADC channels.
// For circular BPMs loadEnable and latchEnable are asserted
// simultaneously once per acquisition interval.
// For single-pass BPMs loadEnable is be asserted at the beginning of the
// acquisition interval and latchEnable just past the end of acquisition.
//
// If 'useRMS' is asserted the scaled square root of the sum is returned.
//
// The SAMPLES_PER_TURN and TURNS_PER_SUM parameters are used only to set
// the size of the accumulators.  The actual number of samples per acquisition
// is controlled by the loadEnable and latchEnable inputs.

module sdAccumulate #(
    parameter PRODUCT_WIDTH    = -1,
    parameter SUM_WIDTH        = -1,
    parameter SAMPLES_PER_TURN = -1,
    parameter TURNS_PER_SUM    = -1,
    parameter DEBUG            = "false"
    ) (
    input                            clk,
    input                            useRMS,

    input    [(8*PRODUCT_WIDTH)-1:0] products,
    (*mark_debug=DEBUG*) input       loadEnable,
    
    (*mark_debug=DEBUG*) input       latchEnable,
    (*mark_debug=DEBUG*) input [3:0] sumShift,
    (*mark_debug=DEBUG*) output reg  sumsToggle,
    output reg   [(8*SUM_WIDTH)-1:0] sums,
    (*mark_debug=DEBUG*) output reg  overflowFlag = 0);

parameter RAW_ACC_W = PRODUCT_WIDTH + $clog2(SAMPLES_PER_TURN * TURNS_PER_SUM);
parameter SQRT_WIDTH = SUM_WIDTH - 1;
parameter SQR_WIDTH = 2 * SQRT_WIDTH;
// Add an extra bit to allow overflow detection
parameter ACC_WIDTH = (RAW_ACC_W > SQR_WIDTH ? RAW_ACC_W : SQR_WIDTH) + 1;
parameter WIDEN = ACC_WIDTH - PRODUCT_WIDTH;

reg [7:0] ovFlags = 0;
reg usingRMS = 0, sumEnable = 0;

// Per-channel firmware
genvar i;
generate
for (i = 0 ; i < 8 ; i = i + 1) begin : acc
    wire [PRODUCT_WIDTH-1:0] p=products[i*PRODUCT_WIDTH+:PRODUCT_WIDTH];
    wire s = p[PRODUCT_WIDTH-1];
    // Explicit sign extend
    wire [ACC_WIDTH-1:0] wideScaledProduct =
                                    (sumShift==0) ? { {WIDEN-0{s}}, p       } :
                                    (sumShift==1) ? { {WIDEN-1{s}}, p, 1'b0 } :
                                    (sumShift==2) ? { {WIDEN-2{s}}, p, 2'b0 } :
                                    (sumShift==3) ? { {WIDEN-3{s}}, p, 3'b0 } :
                                    (sumShift==4) ? { {WIDEN-4{s}}, p, 4'b0 } :
                                    (sumShift==5) ? { {WIDEN-5{s}}, p, 5'b0 } :
                                    (sumShift==6) ? { {WIDEN-6{s}}, p, 6'b0 } :
                                    (sumShift==7) ? { {WIDEN-7{s}}, p, 7'b0 } :
                                    (sumShift==8) ? { {WIDEN-8{s}}, p, 8'b0 } :
                                    (sumShift==9) ? { {WIDEN-9{s}}, p, 9'b0 } :
                                    (sumShift==10)? {{WIDEN-10{s}}, p,10'b0 } :
                                    (sumShift==11)? {{WIDEN-11{s}}, p,11'b0 } :
                                    (sumShift==12)? {{WIDEN-12{s}}, p,12'b0 } :
                                    (sumShift==13)? {{WIDEN-13{s}}, p,13'b0 } :
                                    (sumShift==14)? {{WIDEN-14{s}}, p,14'b0 } :
                                                    {{WIDEN-15{s}}, p,15'b0 };
    (*mark_debug=DEBUG*) reg [ACC_WIDTH-1:0] accumulator = 0;
    wire [SQRT_WIDTH-1:0] sqrt;
    wire sqrtDone;

    isqrt #(.X_WIDTH(SQR_WIDTH)) isqrt(
            .clk(clk),
            .x(accumulator[ACC_WIDTH-2:ACC_WIDTH-1-SQR_WIDTH]),
            .en(latchEnable),
            .y(sqrt),
            .dav(sqrtDone));

    always @(posedge clk) begin
        if (accumulator[ACC_WIDTH-1]==(usingRMS?1'b0:accumulator[ACC_WIDTH-2]))
            ovFlags[i] <= 0;
        else
            ovFlags[i] <= 1;
        if (loadEnable)     accumulator <= wideScaledProduct;
        else if (sumEnable) accumulator <= accumulator + wideScaledProduct;
        if (usingRMS) begin
            if (sqrtDone) begin
                sums[i*SUM_WIDTH+:SUM_WIDTH] <= { 1'b0, sqrt };
            end
        end
        else begin
            if (latchEnable) begin
                sums[i*SUM_WIDTH+:SUM_WIDTH] <=
                                 accumulator[ACC_WIDTH-2:ACC_WIDTH-1-SUM_WIDTH];
            end
        end
    end
end
endgenerate

// Common firmware
always @(posedge clk) begin
    overflowFlag <= |ovFlags;
    if (loadEnable) begin
        usingRMS <= useRMS;
        sumEnable <= 1;
    end
    else if (latchEnable) begin
        sumEnable <= 0;
    end
    if (usingRMS) begin
        if (acc[0].sqrtDone) sumsToggle <= !sumsToggle;
    end
    else begin
        if (latchEnable) sumsToggle <= !sumsToggle;
    end
end

endmodule
