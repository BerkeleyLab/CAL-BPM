#
# Compare single-pass FPGA computation with client-provided values.
#
from scipy.fftpack import fft
import matplotlib.pyplot as plt
import numpy as np
import epics
import sys
import time
import argparse

parser = argparse.ArgumentParser(description='Check single-pass FPGA operation.', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-d', '--dB',  action="store_true", help='FFT plot as dBm')
parser.add_argument('-f', '--fft',  action="store_true", help='Plot FFT')
parser.add_argument('-i', '--index', default=20, type=int, help='FFT index)')
parser.add_argument('-l', '--log', default=None, help='Log data file)')
parser.add_argument('-n', '--npass', default=10, type=int, help='Number of passes')
parser.add_argument('-p', '--prefix', default='SR01C:BPM1:', help='PV name prefix')
parser.add_argument('-r', '--rms',  action="store_true", help='Show RMS-derived values too')
parser.add_argument('-s', '--samples', default=77, type=int, help='Sample count')
args = parser.parse_args()
if (args.log):
    logFile = open(args.log, 'w');
else:
    logFile = None

done = False
def wfHandler(pvname=None, count=None, value = None, **kw):
    global adcWfPV, done
    button = [0, 0, 0, 0]
    for i in range(0,4):
        if ((adcWfPV[i] == None) \
         or (adcWfPV[i].timestamp != adcWfPV[0].timestamp)):
            return
    if (logFile):
        for i in range(0,args.samples):
            for a in range(0,4):
                print >>logFile, adcWfPV[a].value[i],
            print >>logFile, ""
    for p in range(2 if (args.rms) else 1):
        sum = 0
        for i in range(0,4):
            x=np.array(adcWfPV[i].value[range(0,args.samples)])
            if (p == 0):
                y=np.abs(fft(x))
                button[i] = y[args.index]
                if (args.fft and args.dB): y = 20*np.log10(y)
                if (args.fft): plt.plot(range(0,args.samples/2),y[0:args.samples/2])
            else:
                button[i] = np.std(x)
            sum += button[i]
        buttonA = button[3]
        buttonB = button[1]
        buttonC = button[2]
        buttonD = button[0]
        x = 16.0 * 2.0 * (buttonD - buttonB) / sum
        y = 16.0 * 2.0 * (buttonA - buttonC) / sum
        print "  %8.3f %8.3f %8.0f" % (x, y, sum),
    print ""
    if (args.fft and (args.index > 0)): plt.show()
    done = True

armPV = epics.PV(args.prefix+"wfr:ADC:arm")
if (not armPV.wait_for_connection(1.0)):
    sys.exit(1)
adcWfPV = [None] * 4
for i in range(0,4):
    adcWfPV[i] = epics.PV(args.prefix+"wfr:ADC:c%d"%(i),auto_monitor=True, \
                                                            form='time')
    if (not adcWfPV[i].wait_for_connection(1.0)):
        sys.exit(1)
for i in range(0,4):
    adcWfPV[i].add_callback(wfHandler)
while(args.npass):
    armPV.put(1)
    while (not done):
        time.sleep(0.1)
    done = False
    args.npass -= 1
