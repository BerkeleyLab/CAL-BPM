//
// LTC2945 readout
// Very basic -- reads current and voltage channels only
//            -- no clock stretching (SCL is push/pull, not open-drain)
//            -- no ACK check
//            -- fixed device addresses (DC, D6, D4)
//

module ltc2945(clk, SCL, SDA,
               voltage0, current0,
               voltage1, current1,
               voltage2, current2);

input         clk;
inout         SCL, SDA;
output [15:0] voltage0, current0;
output [15:0] voltage1, current1;
output [15:0] voltage2, current2;

/* Hardware configuration */
parameter LTC_ADDRESS = 8'hD6;

/* Timing */
parameter CLOCK_RATE         = 100000000;
parameter BIT_RATE           = 100000;
parameter IDLE_DECISECONDS   = 5;
parameter IDLE_SPEEDUP       = 1;

parameter TICK_COUNTER_RELOAD = ((CLOCK_RATE+(BIT_RATE*4)-1)/(BIT_RATE*4))-1;
parameter TICK_COUNTER_WIDTH  = $clog2(TICK_COUNTER_RELOAD);
parameter IDLE_COUNTER_RELOAD = ((IDLE_DECISECONDS*BIT_RATE)/10/IDLE_SPEEDUP)-1;
parameter IDLE_COUNTER_WIDTH  = $clog2(IDLE_COUNTER_RELOAD);

/* Readings */
parameter REG_CURRENT_MSB = 8'h14;
parameter REG_VOLTAGE_MSB = 8'h1E;
reg [15:0] result = 0;
reg [15:0] voltage0 = 0, current0 = 0;
reg [15:0] voltage1 = 0, current1 = 0;
reg [15:0] voltage2 = 0, current2 = 0;

/* States */
parameter S_WAIT       = 0,
          S_START      = 1,
          S_WRITE_BYTE = 2,
          S_READ_BYTE  = 3,
          S_STOP       = 4;
reg [2:0] state = S_WAIT;

reg [TICK_COUNTER_WIDTH-1:0] tickCounter = TICK_COUNTER_RELOAD;
reg [IDLE_COUNTER_WIDTH-1:0] idleCounter = 0;

reg       tick = 0;
reg [1:0] phase = 0;
reg [3:0] bitsLeft = 0;
reg [1:0] byteIndex = 0;
reg [2:0] adcChanIndex = 0;
reg [6:0] ltcAddress = 0;
reg [8:0] shiftReg = 9'h1FF; // MSB drives SDA pin
reg       scl_high = 1, sdaLatch;

assign SCL = scl_high;
assign SDA = shiftReg[8] ? 1'bz : 1'b0;

always @(posedge clk) begin
    if (tickCounter) begin
        tickCounter <= tickCounter - 1;
        tick <= 1'b0;
    end
    else begin
        tickCounter <= TICK_COUNTER_RELOAD;
        tick <= 1'b1;
    end
end

always @(posedge clk) if (tick) begin
    phase <= phase + 1;
    if (phase == 2'b01) sdaLatch <= SDA;

    case (adcChanIndex[2:1])
    2'b00:   ltcAddress <= (8'hDC >> 1);
    2'b01:   ltcAddress <= (8'hD6 >> 1);
    default: ltcAddress <= (8'hD4 >> 1);
    endcase

    case (state)
    S_WAIT: begin
            scl_high <= 1'b1;
            shiftReg <= 9'h1FF;
            if (phase == 2'b11) begin
                if (idleCounter == 0) begin
                    state <= S_START;
                    byteIndex <= 0;
                end
                else begin
                    idleCounter <= idleCounter - 1;
                end
            end
        end

    S_START:
        case (phase)
        2'b00: scl_high <= 1'b1;
        2'b01: shiftReg <= 9'h0FF;
        2'b10: scl_high <= 1'b0;
        2'b11: begin
                shiftReg <= {ltcAddress, (byteIndex==0) ? 1'b0 : 1'b1, 1'b1};
                bitsLeft <= 8;
                state <= S_WRITE_BYTE;
            end
        default: ;
        endcase

    S_WRITE_BYTE:
        case (phase)
        2'b00: scl_high <= 1'b1;
        2'b10: scl_high <= 1'b0;
        2'b11: begin
                if (bitsLeft) begin
                    shiftReg <= { shiftReg[7:0], 1'b1 };
                     bitsLeft <= bitsLeft - 1;
                end
                else begin
                    case (byteIndex)
                    2'd0: begin
                            shiftReg <= {adcChanIndex[0] ? REG_VOLTAGE_MSB :
                                                           REG_CURRENT_MSB, 1'b1};
                            bitsLeft <= 8;
                            byteIndex <= 1;
                        end
                    2'd1: begin
                            byteIndex <= 2;
                            state <= S_START;
                        end
                    2'd2: begin
                            shiftReg <= 9'h1FE;
                            bitsLeft <= 8;
                            byteIndex <= 0;
                            state <= S_READ_BYTE;
                        end
                    default: ;
                    endcase
                end
            end
        default: ;
        endcase

    S_READ_BYTE:
        case (phase)
        2'b00: scl_high <= 1'b1;
        2'b10: scl_high <= 1'b0;
        2'b11: begin
                if (bitsLeft) begin
                    shiftReg <= {shiftReg[7:0], sdaLatch};
                    bitsLeft <= bitsLeft - 1;
                end
                else begin
                    shiftReg <= 9'h1FF;
                    if (byteIndex == 0) begin
                        result[15:8] <= shiftReg[7:0];
                        bitsLeft <= 8;
                        byteIndex <= 1;
                    end
                    else begin
                        result[7:0] <= shiftReg[7:0];
                        state <= S_STOP;
                    end
                end
            end
        default: ;
        endcase

    S_STOP:
        case (phase)
        2'b00: shiftReg <= 9'h0FF;
        2'b01: scl_high <= 1'b1;
        2'b10: shiftReg <= 9'h1FF;
        2'b11: begin
                case (adcChanIndex)
                0: current0 <= result;
                1: voltage0 <= result;
                2: current1 <= result;
                3: voltage1 <= result;
                4: current2 <= result;
                5: voltage2 <= result;
                default: ;
                endcase
                if (adcChanIndex < 5) begin
                    adcChanIndex <= adcChanIndex + 1;
                    byteIndex <= 0;
                    state <= S_START;
                end
                else begin
                    adcChanIndex <= 0;
                    idleCounter <= IDLE_COUNTER_RELOAD;
                    state <= S_WAIT;
                end
            end
        default: ;
        endcase
    endcase
end

endmodule
