TEST_SOURCE = rmsCalc_tb.v ../../bpm/rmsCalc.v  \
                           ../../bpm/isqrt.v    \
                           ../../bpm/lowpass.v  \
                           ../../bpm/saturateMath.v  \
                           ../../bpm/washout.v
	
all: rmsCalc_tb.vvp

rmsCalc_tb.vvp: $(TEST_SOURCE) rmsBandSelect.hex
	iverilog -o rmsCalc_tb.vvp $(TEST_SOURCE)

test: rmsCalc_tb.vvp
	vvp rmsCalc_tb.vvp -lxt2 >test.dat

rmsCalc_tb.lxt:  rmsCalc_tb.vvp
	vvp  rmsCalc_tb.vvp -lxt2 >test.dat

view:  rmsCalc_tb.lxt force
	open /Applications/gtkwave.app rmsCalc_tb.gtkw 

force:

rmsBandSelect.hex: ../../bpm/rmsBandSelect.coe fixCoef.awk
	awk -f fixCoef.awk <../../bpm/rmsBandSelect.coe >rmsBandSelect.hex

clean:
	rm -f *.vvp *.lxt *.dat rmsBandSelect.hex
