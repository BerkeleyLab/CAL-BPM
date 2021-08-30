`timescale 1 ns /  1ns

module rmsCalc_tb;

parameter GPIO_WIDTH = 32;
parameter DATA_WIDTH = 26;

reg clk=1;
reg [GPIO_WIDTH-1:0] faX = {GPIO_WIDTH{1'bx}}, faY = {GPIO_WIDTH{1'bx}};
reg faToggle = 0;
wire [GPIO_WIDTH-1:0] wideXrms, wideYrms, narrowXrms, narrowYrms;

//
// Instantiate device under test
//
rmsCalc #(.GPIO_WIDTH(GPIO_WIDTH))
  rmsCalc (
    .clk(clk),
    .faToggle(faToggle),
    .faX(faX),
    .faY(faY),
    .wideXrms(wideXrms),
    .wideYrms(wideYrms),
    .narrowXrms(narrowXrms),
    .narrowYrms(narrowYrms));
//
// Create clock
//
parameter Fsys = 10.0e6;
always begin
    #50 clk = ~clk;
end

//
// Create data
//
parameter XL_AMPLITUDE = 50000.0;
parameter XH_AMPLITUDE = 30000.0;
parameter YL_AMPLITUDE = 28000.0;
parameter YH_AMPLITUDE = 17000.0;
parameter Fsamp = 10.0e3;
parameter Tsamp = 1.0 / Fsamp;
parameter M_2PI = 6.283185307179586;
integer limit = (Fsys / Fsamp) - 1;
integer ticks = 0;
real t = 0;
integer xVal, yVal;
real fLo = 200, fHi = 400;
always @(posedge clk) begin
    if (ticks >= limit) begin
        $display("%6d %6d %6d %6d", narrowYrms, narrowXrms, wideYrms, wideXrms);
        ticks <= 0;
        t = t + Tsamp;
        xVal = XL_AMPLITUDE * $sin(M_2PI * fLo * t) +
               XH_AMPLITUDE * $sin(M_2PI * fHi * t);
        yVal = YL_AMPLITUDE * $sin(M_2PI * fLo * t) +
               YH_AMPLITUDE * $sin(M_2PI * fHi * t);
        faX[DATA_WIDTH-1:0] <=  xVal;
        faY[DATA_WIDTH-1:0] <= yVal;
        faToggle <= !faToggle;
    end
    else begin
        if (ticks == 20) begin
            faX <= {GPIO_WIDTH{1'bx}};
            faY <= {GPIO_WIDTH{1'bx}};
        end
        ticks <= ticks + 1;
    end
end

//
// Test harness
//
real expectedXwide = $sqrt(0.5) * $sqrt(XL_AMPLITUDE * XL_AMPLITUDE +
                                        XH_AMPLITUDE * XH_AMPLITUDE);
real expectedYwide = $sqrt(0.5) * $sqrt(YL_AMPLITUDE * YL_AMPLITUDE +
                                        YH_AMPLITUDE * YH_AMPLITUDE);
real expectedXnarrow = $sqrt(0.5) * XL_AMPLITUDE;
real expectedYnarrow = $sqrt(0.5) * YL_AMPLITUDE;
real ratioXwide, ratioYwide, ratioXnarrow, ratioYnarrow;
initial
begin
    $dumpfile("rmsCalc_tb.lxt");
    $dumpvars(0, rmsCalc_tb);

    $display("     NY     NX     WY     WX");
    // Take 2 seconds worth of data
    #2000000001 ;
    // Show ideal values (assuming perfect band select filter)
    ratioXwide = wideXrms / expectedXwide;
    ratioYwide = wideYrms / expectedYwide;
    ratioXnarrow = narrowXrms / expectedXnarrow;
    ratioYnarrow = narrowYrms / expectedYnarrow;
    $display("%g %g %g %g", $sqrt(0.5) * YL_AMPLITUDE,
                            $sqrt(0.5) * XL_AMPLITUDE,
                            $sqrt(0.5) * $sqrt(YL_AMPLITUDE * YL_AMPLITUDE +
                                               YH_AMPLITUDE * YH_AMPLITUDE),
                            $sqrt(0.5) * $sqrt(XL_AMPLITUDE * XL_AMPLITUDE +
                                               XH_AMPLITUDE * XH_AMPLITUDE));
    $display("# %g %g %g %g", ratioYnarrow, ratioXnarrow, ratioYwide, ratioXwide);
    if ((ratioXwide > 0.996)
     && (ratioXwide < 1)
     && (ratioYwide > 0.996)
     && (ratioYwide < 1)
     && (ratioXnarrow > 0.985)
     && (ratioXnarrow < 1.00)
     && (ratioYnarrow > 0.985)
     && (ratioYnarrow < 1.00))
        $display("PASS");
    else
        $display("FAIL");
    $finish;
end

endmodule

// Dummy version of Xilinx filter
module rmsBandSelect #(
    parameter FILTER_INPUT_WIDTH = 24,
    parameter AXI_IN_WIDTH = (((FILTER_INPUT_WIDTH + 7) / 8) * 8),
    parameter FILTER_OUTPUT_WIDTH = FILTER_INPUT_WIDTH + 1,
    parameter AXI_OUT_WIDTH = (((FILTER_OUTPUT_WIDTH + 7) / 8) * 8)
    ) (
    input                          aclk,
    input                          s_axis_data_tvalid,
    output reg                     s_axis_data_tready = 0,
    input       [AXI_IN_WIDTH-1:0] s_axis_data_tdata,
    output reg                     m_axis_data_tvalid = 0,
    output reg [AXI_OUT_WIDTH-1:0] m_axis_data_tdata={AXI_OUT_WIDTH{1'bx}});

localparam COEFFICIENT_COUNT   = 115;
localparam COEFFICIENT_WIDTH   = 18;
localparam COEFFICIENT_SCALING = 4;

reg signed [COEFFICIENT_WIDTH-1:0] coefficients[0:COEFFICIENT_COUNT-1];
initial $readmemh("rmsBandSelect.hex", coefficients);


integer i = 0, j = 0;
reg running = 0, running_d = 0;

always @(posedge aclk) begin
    running_d <= running;
    m_axis_data_tvalid <= (!running && running_d);
    if (running) begin
        j <= j + 1;
        if (j == (COEFFICIENT_COUNT - 1)) begin
            running <= 0;
            i <= ((i - 1) + COEFFICIENT_COUNT) % COEFFICIENT_COUNT;
        end
    end
    else if (s_axis_data_tvalid && s_axis_data_tready) begin
        s_axis_data_tready <= 0;
        j <= 0;
        running <= 1;
    end
    else if (s_axis_data_tvalid) begin
        s_axis_data_tready <= 1;
    end
end

reg signed [FILTER_INPUT_WIDTH-1:0] x [0:COEFFICIENT_COUNT-1];
reg signed [FILTER_INPUT_WIDTH+COEFFICIENT_WIDTH+COEFFICIENT_SCALING-1:0] accumulator;
integer k;
initial begin for (k = 0 ; k < COEFFICIENT_COUNT ; k = k + 1) x[k] = 0; end
always @(posedge aclk) begin
    if (running) begin
        accumulator <= accumulator + (x[(j+i)%COEFFICIENT_COUNT] *
                                                               coefficients[j]);
    end
    else if (running_d) begin
        m_axis_data_tdata[0+:FILTER_OUTPUT_WIDTH] <=
                        accumulator[COEFFICIENT_WIDTH+
                                    COEFFICIENT_SCALING-1+:FILTER_OUTPUT_WIDTH];
        accumulator <= 0;
    end
    else begin
        m_axis_data_tdata[0+:FILTER_OUTPUT_WIDTH] <=
                                                    {FILTER_OUTPUT_WIDTH{1'bx}};
        accumulator <= 0;
        x[i] <= s_axis_data_tdata[0+:FILTER_INPUT_WIDTH];
    end
end
 
endmodule
