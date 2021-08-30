//
// Read from a block of ADT7410 temperature sensors
// Very basic -- no clock stretching (SCL is push/pull, not open-drain)
//            -- full resolution (1/128 degrees C, 16 bit value)
//            -- no ACK check
//

module adt7410 #(
    parameter CLOCK_RATE     = 100000000,
    parameter BIT_RATE       = 100000,
    parameter DEVICE_COUNT   = 4,
    parameter RESULT_BITS    = 16,
    parameter RESULT_LENGTH  = (DEVICE_COUNT * RESULT_BITS)
    ) (
    input         clk,
    output        SCL,
    inout         SDA,
    output [RESULT_LENGTH-1:0] temperatures);

/* Timing */
parameter IDLE_DECISECONDS   = 5;
parameter IDLE_SPEEDUP       = 1;

parameter TICK_COUNTER_RELOAD = ((CLOCK_RATE+(BIT_RATE*4)-1)/(BIT_RATE*4))-1;
parameter TICK_COUNTER_WIDTH  = $clog2(TICK_COUNTER_RELOAD+1);
parameter IDLE_COUNTER_RELOAD = ((IDLE_DECISECONDS*BIT_RATE)/10/IDLE_SPEEDUP)-1;
parameter IDLE_COUNTER_WIDTH  = $clog2(IDLE_COUNTER_RELOAD+1);

parameter SHIFT_TOP = 26;

/* Readings */
reg [RESULT_LENGTH-1:0] temperatures, rxShift = 0;

/* States */
parameter S_IDLE       = 0,
          S_START      = 1,
          S_TRANSFER   = 2,
          S_STOP       = 3;
reg [1:0] state = S_IDLE;
reg setAddress  = 0;
reg reading     = 0;
reg configuring = 0;

reg [TICK_COUNTER_WIDTH-1:0] tickCounter = TICK_COUNTER_RELOAD;
reg [IDLE_COUNTER_WIDTH-1:0] idleCounter = 0;

reg        tick = 0;
reg [1:0]  phase = 0;
reg [1:0]  subAddress = 0;
 
reg [5:0]  bitsLeft = 0;
reg [SHIFT_TOP:0] txShift = 27'h7FFFFFF; // MSB drives SDA pin
reg        scl = 1;

assign SCL = scl;
assign SDA = txShift[SHIFT_TOP] ? 1'bz : 1'b0;

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
    case (state)
    S_IDLE: begin
            scl <= 1'b1;
            txShift[SHIFT_TOP] <= 1'b1;
            subAddress <= 2'b00;
            setAddress <= 1'b1;
            reading <= 1'b0;
            configuring <= 1'b0;
            if (phase == 2'b11) begin
                if (idleCounter == 0) begin
                    state <= S_START;
                    idleCounter <= IDLE_COUNTER_RELOAD;
                end
                else begin
                    idleCounter <= idleCounter - 1;
                end
            end
        end

    S_START:
        case (phase)
        2'b00: scl <= 1'b1;
        2'b01: txShift[SHIFT_TOP] <= 1'b0;
        2'b10: scl <= 1'b0;
        2'b11: begin
                if (setAddress) begin
                    bitsLeft <= 17;
                    txShift <= { 5'b10010, subAddress, 1'b0, 1'b1,
                                 8'h00,                      1'b1,
                                 9'h1FF };
                end
                else if (reading) begin 
                    bitsLeft <= 26;
                    txShift <= { 5'b10010, subAddress, 1'b1, 1'b1,
                                 8'hFF,                      1'b0,
                                 8'hFF,                      1'b1 };
                end
                else begin
                    bitsLeft <= 26;
                    txShift <= { 5'b10010, subAddress, 1'b0, 1'b1,
                                 // Configuration register:
                                 8'h03,                      1'b1,
                                 // 16 bit mode, single shot:
                                 8'hA0,                      1'b1 };
                end
                state <= S_TRANSFER;
            end
        default: ;
        endcase

    S_TRANSFER:
        case (phase)
        2'b00: scl <= 1'b1;
        2'b10: begin
                if (reading
                 && (bitsLeft <= 17)
                 && (bitsLeft != 9)
                 && (bitsLeft != 0))
                    rxShift <= { rxShift[RESULT_LENGTH-2:0], SDA };
                scl <= 1'b0;
            end
        2'b11: begin
                if (bitsLeft) begin
                    txShift <= { txShift[SHIFT_TOP-1:0], 1'b1 };
                    bitsLeft <= bitsLeft - 1;
                end
                else begin
                    if (setAddress) begin
                        setAddress <= 0;
                        reading <= 1'b1;
                        state <= S_START;
                    end
                    else begin
                        state <= S_STOP;
                    end
                end
            end
        default: ;
        endcase

    S_STOP:
        case (phase)
        2'b00: txShift[SHIFT_TOP] <= 1'b0;
        2'b01: scl <= 1'b1;
        2'b10: txShift[SHIFT_TOP] <= 1'b1;
        2'b11: begin
                reading <= 0;
                subAddress <= subAddress + 1;
                if (subAddress == 2'b11) begin
                    if (configuring) begin
                        state <= S_IDLE;
                    end
                    else begin
                        temperatures <= rxShift;
                        configuring <= 1;
                        state <= S_START;
                    end
                end
                else begin
                    if (!configuring) setAddress <= 1;
                    state <= S_START;
                end
            end
        default: ;
        endcase
    endcase
end

endmodule
