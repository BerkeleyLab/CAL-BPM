//
// Support for Aurora communication module
// One per Aurora block
//
module cellCommAuroraSupport(input  wire       sysAuroraReset,
                             input  wire       userClk,
                             output wire       auroraReset,
                             input  wire       channelUp,
                             input  wire       channelRx,
                             output wire [1:0] sfpLEDs);

(* ASYNC_REG="TRUE" *) reg auroraReset_m, auroraReset_r;
assign auroraReset = auroraReset_r;
reg rxGood = 0;
reg [21:0] rxGoodStretch;
always @(posedge userClk) begin
    auroraReset_m <= sysAuroraReset;
    auroraReset_r <= auroraReset_m;
    if (channelUp && channelRx) begin
        rxGood <= 1;
        rxGoodStretch <= ~0;
    end
    else begin
        if (rxGoodStretch == 0) begin
            rxGood <= 0;
        end
        else begin
            rxGoodStretch <= rxGoodStretch - 1;
        end
    end
end
assign sfpLEDs = { rxGood, channelUp };

endmodule
