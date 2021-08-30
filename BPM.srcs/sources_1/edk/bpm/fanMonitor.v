//
// PARAMETERS
//  CLOCK     Clock rate (Hz)
//  FAN_PPR   Fan pulses per revolution (1, 2, 4, 8)
//
// Output is fan speed in RPM and updates about twice per second
//
module fanMonitor(clk, reset, tach, rpm);

parameter CLOCK     = 100000000;
parameter FAN_PPR   = 2;

//
// Derived parameters
// Sample tachometer only once every 25 us to provide a little debouncing.
//
parameter SAMPLE_RATE    = 40000;                  // 25 us/sample
parameter UPDATE_DIVISOR = 60 * SAMPLE_RATE / 128; // 60/128 seconds per update
parameter SAMPLE_DIVISOR = (CLOCK + (SAMPLE_RATE/2)) / SAMPLE_RATE;

parameter TACH_WIDTH     = OUTPUT_WIDTH-3;  // Filter multiplies by 8;
parameter OUTPUT_WIDTH   = 16;

input                     clk;
input                     reset;
input                     tach;
output [OUTPUT_WIDTH-1:0] rpm;
 
reg  [15:0]             sampleDivisor;
reg  [14:0]             updateDivisor;
reg                     updateFlag;
wire                    tachPulse;
reg                     tach0, tach1;
reg  [TACH_WIDTH-1:0]   tachCount;
wire [OUTPUT_WIDTH-1:0] tachFiltered;
reg  [OUTPUT_WIDTH-1:0] rpm;

firstOrderLowPass #(.UWIDTH(TACH_WIDTH), .YWIDTH(OUTPUT_WIDTH))
                  Filter (.clk(clk),
                          .reset(reset),
                          .enable(updateFlag),
                          .u(tachCount),
                          .y(tachFiltered));

assign tachPulse = (tach0 != tach1);

always @(posedge clk)
begin
    if (reset) begin
        sampleDivisor <= SAMPLE_DIVISOR-1;
        updateDivisor <= UPDATE_DIVISOR-1;
        updateFlag    <= 0;
        tachCount     <= 0;
        tach0         <= 0;
        tach1         <= 0;
    end
    else begin
        //
        // Divide down
        //
        if (sampleDivisor == 0) begin
            sampleDivisor <= SAMPLE_DIVISOR-1;
            tach0 <= tach;
            tach1 <= tach0;
            if (tachPulse)
                tachCount <= tachCount + 1;
            if (updateDivisor == 0) begin
                updateDivisor <= UPDATE_DIVISOR-1;
                updateFlag <= 1;
            end
            else begin
                updateDivisor <= updateDivisor - 1;
            end
        end
        else begin
            if (updateFlag)
                tachCount <= 0;
            updateFlag <= 0;
            sampleDivisor <= sampleDivisor - 1;
        end
    end
end

always @(tachFiltered)
begin
    //
    // Effect of filter widening:
    //                    tachFiltered = tach_count * 8
    //
    // We calculate the speed once every 128th of a
    // minute and count both edges of the tach signal:
    //                    RPM = tach_count * 128 / (2 * pulses_per_rev)
    //
    // Substituting for tach_count:
    //                    RPM = (tachFiltered / 8) * 128 / (2 * pulses_per_rev)
    //                    RPM = tachFiltered * 8 / pulses_per_rev
    //
    case (FAN_PPR)
    1:  rpm = { tachFiltered[OUTPUT_WIDTH-3:0], 3'b0 };
    2:  rpm = { tachFiltered[OUTPUT_WIDTH-3:0], 2'b0 };
    4:  rpm = { tachFiltered[OUTPUT_WIDTH-2:0], 1'b0 };
    8:  rpm = { tachFiltered[OUTPUT_WIDTH-1:0]       };
    default: rpm = ~0;
    endcase
end

endmodule

module firstOrderLowPass(clk, reset, enable, u, y);

parameter UWIDTH = 12;
parameter YWIDTH = 16;

input                clk;
input                reset;
input                enable;
input  [UWIDTH-1:0]  u;
output [YWIDTH-1:0]  y;
reg    [YWIDTH-1:0]  y;
reg                  running = 0;
 
wire   [YWIDTH-UWIDTH-1:0]  z;
assign z = 0;

always @(posedge clk)
begin
    if (reset) begin
        y <= 0;
        running <= 0;
    end
    else begin
        if (enable) begin
            if (!running) begin
                running <= 1;
                y <= {u, z[YWIDTH-UWIDTH-1:0] };
            end
            else begin
                y <= {z[YWIDTH-UWIDTH-1:0], u[UWIDTH-1:0]} + y -
                                                {z, y[YWIDTH-1:YWIDTH-UWIDTH]}; 
            end
        end
    end
end

endmodule
