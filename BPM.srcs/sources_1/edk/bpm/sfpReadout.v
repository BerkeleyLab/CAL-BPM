//
// Read values from SFP ROMs.
// Very basic -- no clock stretching (SCL is push/pull, not open-drain)
//            -- fixed device addresses (A0, A2)
//            -- No ACK check
// Primary use is reading receiver power so always read two bytes.
//

module sfpReadout(clk, writeStrobe, address, busy, readout, SCL, SDA);

/* Timing */
parameter CLOCK_RATE         = 100000000;
parameter BIT_RATE           = 100000;

/* Tuneable parameter */
parameter SFP_COUNT     = 6;

/* Fixed parameters */
parameter ADDRESS_WIDTH = 9;  // MSB selects address A0 or A2
parameter RBK_COUNT     = 16;

input                              clk;
input                              writeStrobe;
input [8:0]                        address;
output                             busy;
output [(SFP_COUNT*RBK_COUNT)-1:0] readout;
output [SFP_COUNT-1:0]             SCL;
inout  [SFP_COUNT-1:0]             SDA;

parameter TICK_COUNTER_RELOAD = ((CLOCK_RATE+(BIT_RATE*4)-1)/(BIT_RATE*4))-1;
parameter TICK_COUNTER_WIDTH  = $clog2(TICK_COUNTER_RELOAD);
parameter SHIFT_TOP = 26;

/* States */
parameter S_START    = 0,
          S_TRANSFER = 1,
          S_STOP     = 2;
reg [1:0] state = S_START;

reg [TICK_COUNTER_WIDTH-1:0] tickCounter = TICK_COUNTER_RELOAD;

reg               busy = 0;
reg               tick = 0;
reg [1:0]         phase = 0;
reg               writing;
reg               sample = 0;
reg [4:0]         bitsLeft = 0;
reg [8:0]         addrLatch;
reg [SHIFT_TOP:0] txShift; // MSB drives SDA pins low when 0
reg               scl = 1; // Drives SCL pins

//
// Readings
//
genvar i;
generate
for (i = 0 ; i < SFP_COUNT ; i = i + 1) begin : sfp_assign
    reg [RBK_COUNT-1:0] rxi;
    assign SCL[i] = scl;
    assign SDA[i] = txShift[SHIFT_TOP] ? 1'bz : 1'b0;
    always @(posedge clk) begin
        if (tick && sample)
            rxi <= { rxi[RBK_COUNT-2:0], SDA[i] };
    end
    assign readout[((i*RBK_COUNT)+(RBK_COUNT-1)):i*RBK_COUNT] = rxi;
end
endgenerate

//
// Main state machine
//
always @(posedge clk) begin
    if (!busy) begin
        tickCounter <= TICK_COUNTER_RELOAD;
        phase <= 0;
        writing <= 1;
        scl <= 1'b1;
        txShift[SHIFT_TOP] <= 1'b1;
        if (writeStrobe) begin
            busy <= 1;
            addrLatch = address;
            tick <= 1;
            state <= S_START;
        end
        else begin
            tick <= 0;
        end
    end
    else begin
        if (tickCounter) begin
            tickCounter <= tickCounter - 1;
            tick <= 1'b0;
        end
        else begin
            tickCounter <= TICK_COUNTER_RELOAD;
            tick <= 1'b1;
            phase <= phase + 1;
        end
    end
    if (tick) begin
        case (state)
        S_START:
            case (phase)
            2'b00: scl <= 1'b1;
            2'b01: txShift[SHIFT_TOP] <= 1'b0;
            2'b10: scl <= 1'b0;
            2'b11: begin
                    if (writing) begin
                        bitsLeft <= 17;
                        txShift <= { 6'b101000, addrLatch[8], 1'b0, 1'b1,
                                     addrLatch[7:0],                1'b1,
                                     9'h1FF };
                    end
                    else begin
                        bitsLeft <= 26;
                        txShift <= { 6'b101000, addrLatch[8], 1'b1, 1'b1,
                                     8'hFF,                         1'b0,
                                     8'hFF,                         1'b1 };
                    end
                    state <= S_TRANSFER;
                end
            default: ;
            endcase

        S_TRANSFER:
            case (phase)
            2'b00: scl <= 1'b1;
            2'b01: if ((bitsLeft != 9) && (bitsLeft != 0))
                    sample <= 1;
            2'b10: begin
                    sample <= 0;
                    scl <= 1'b0;
                end
            2'b11: begin
                    if (bitsLeft) begin
                        txShift <= { txShift[SHIFT_TOP-1:0], 1'b1 };
                        bitsLeft <= bitsLeft - 1;
                    end
                    else begin
                        writing <= 0;
                        if (writing)
                            state <= S_START;
                        else
                            state <= S_STOP;
                    end
                end
            default: ;
            endcase

        S_STOP:
            case (phase)
            2'b00: txShift[SHIFT_TOP] <= 1'b0;
            2'b01: scl <= 1'b1;
            2'b10: txShift[SHIFT_TOP] <= 1'b1;
            2'b11: busy <= 0;
            default: ;
            endcase

        default: ;
        endcase
    end
end

endmodule
