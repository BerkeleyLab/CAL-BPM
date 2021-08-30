//
// ADC input clock
// Provide delay adjust
//
module adcClkin(ADC_CLK_P, ADC_CLK_N, adcClk,
                sysClk, gpioStrobe, gpioData, delayTap, 
                delayCtrlRefClk200, delayCtrlLocked);

input        ADC_CLK_P, ADC_CLK_N;
output       adcClk;
input        sysClk, gpioStrobe;
input [31:0] gpioData;
output [4:0] delayTap;
wire   [4:0] delayTap;
input        delayCtrlRefClk200;
output       delayCtrlLocked;
wire         delayCtrlLocked;

//
// System interface
//
reg  delayCtrlResetBar = 0;
wire delayCtrlReset;
assign delayCtrlReset = !delayCtrlResetBar;
wire [4:0] delaySetting;
assign delaySetting = gpioData[12:8];
wire delayStrobe;
assign delayStrobe = gpioStrobe;
always @(posedge sysClk) begin
    if (gpioStrobe) begin
        delayCtrlResetBar <= !gpioData[15];
    end
end

//
// Convert differential ADC clock input
//
wire adcClki;
IBUFDS adcClkBufi (.O(adcClki), .I(ADC_CLK_P), .IB(ADC_CLK_N));

//
// Programmable delay
//
wire adcClkd;
(* IODELAY_GROUP = "adc_input_clock_group" *)
IODELAYE1 #(
         .CINVCTRL_SEL          ("FALSE"),
         .DELAY_SRC             ("I"),   
         .HIGH_PERFORMANCE_MODE ("TRUE"),
         .IDELAY_TYPE           ("VAR_LOADABLE"),
         .IDELAY_VALUE          (0),
         .ODELAY_TYPE           ("FIXED"),
         .ODELAY_VALUE          (0),
         .REFCLK_FREQUENCY      (200.0),
         .SIGNAL_PATTERN        ("CLOCK"))
       iodelaye1 (
         .DATAOUT               (adcClkd),
         .DATAIN                (1'b0),
         .C                     (sysClk),
         .CE                    (1'b0),
         .INC                   (1'b0), 
         .IDATAIN               (adcClki),
         .ODATAIN               (1'b0),
         .RST                   (delayStrobe),
         .T                     (1'b1),
         .CNTVALUEIN            (delaySetting),
         .CNTVALUEOUT           (delayTap),
         .CLKIN                 (1'b0),
         .CINVCTRL              (1'b0));

//
// Clock to logic running at ADC rate
//
BUFG adcClkBuf (.O(adcClk), .I(adcClkd));

//
// Delay control
//
(* IODELAY_GROUP = "adc_input_clock_group" *)
IDELAYCTRL delayctrl (.RDY(delayCtrlLocked),
                      .REFCLK(delayCtrlRefClk200),
                      .RST(delayCtrlReset));

endmodule
