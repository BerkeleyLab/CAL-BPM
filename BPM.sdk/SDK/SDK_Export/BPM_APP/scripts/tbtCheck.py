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
parser.add_argument('-p', '--prefix', default='SR01C:BPM1:', help='PV name prefix')
parser.add_argument('-n', '--npass', default=10, type=int, help='Number of passes')
args = parser.parse_args()

done = False
def wfHandler(pvname=None, count=None, value = None, **kw):
    global adcWfPV, done
    for i in range(0,4):
        if ((adcWfPV[i] == None) \
         or (adcWfPV[i].timestamp != adcWfPV[0].timestamp)):
            return

    for i in range(0,4):
        rms=np.std(adcWfPV[i].value)
        print rms,
    print ''
    done = True

armPV = epics.PV(args.prefix+"wfr:TBT:arm")
if (not armPV.wait_for_connection(1.0)):
    sys.exit(1)
adcWfPV = [None] * 4
for i in range(0,4):
    adcWfPV[i] = epics.PV(args.prefix+"wfr:TBT:c%d"%(i),auto_monitor=True, \
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
