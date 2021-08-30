//
// Drive RJ-45 traffic indicator LED (LED2)
// Alternate between orange and green if both transmitting and receiving
// else orange if transmitting
// else green if receiving
// else off.
//
module ethernetTrafficIndicator(sysClk, PHY_LED_RX_N, PHY_LED_TX_N,
                                        RJ45_LED2P, RJ45_LED2N);

parameter SYSCLK_RATE = 100000000;

input  sysClk;
input  PHY_LED_RX_N, PHY_LED_TX_N;
output RJ45_LED2P, RJ45_LED2N;
reg    RJ45_LED2P, RJ45_LED2N;

parameter COUNTER_RELOAD = (SYSCLK_RATE / 16) - 1;
parameter COUNTER_WIDTH  = $clog2(COUNTER_RELOAD);

reg receiving, transmitting;
reg previousWasTransmit;
reg [COUNTER_WIDTH-1:0] counter;

always @(posedge sysClk) begin
    if (counter == 0) begin
        counter <= COUNTER_RELOAD;
        receiving <= 0;
        transmitting <= 0;
        if (receiving && transmitting) begin
            if (previousWasTransmit) begin
                previousWasTransmit <= 0;
                RJ45_LED2N <= 0; RJ45_LED2P <= 1;
            end
            else begin
                previousWasTransmit <= 1;
                RJ45_LED2N <= 1; RJ45_LED2P <= 0;
            end
        end
        else if (transmitting) begin
            previousWasTransmit <= 1;
            RJ45_LED2N <= 1; RJ45_LED2P <= 0;
        end
        else if (receiving) begin
            previousWasTransmit <= 0;
            RJ45_LED2N <= 0; RJ45_LED2P <= 1;
        end
        else begin
            RJ45_LED2P <= 0;
            RJ45_LED2N <= 0;
        end
    end
    else begin
        counter <= counter - 1;
        if (PHY_LED_RX_N == 0) receiving <= 1;
        if (PHY_LED_TX_N == 0) transmitting <= 1;
    end
end

endmodule
