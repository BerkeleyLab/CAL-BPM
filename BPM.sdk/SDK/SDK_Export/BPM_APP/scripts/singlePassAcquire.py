#
# Acquire single-pass data
#
from __future__ import print_function
import numpy as np
import epics
import sys
import time
import argparse

parser = argparse.ArgumentParser(description='Acquire single-pass test-mode data.', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-l', '--log', default=None, help='Write to file rather than stdout')
parser.add_argument('-p', '--prefix', default='SR01C:BPM1:', help='PV name prefix')
parser.add_argument('-s', '--samples', default=100000, type=int, help='Sample count')
parser.add_argument('-t', '--triggerLevel', default=1000, type=int, help='Trigger level (ADC counts)')
args = parser.parse_args()
if (args.samples < 4000) or (args.samples > 10000000):
    print("Number of samples out of range [4000,10e6]", file=sys.stderr)
    sys.exit(1)
if (args.log):
    logFile = open(args.log, 'w');
else:
    logFile = sys.stdout

done = False
def wfHandler(pvname=None, count=None, value = None, **kw):
    global adcWfPV, done
    button = [0, 0, 0, 0]
    for i in range(0,4):
        if ((adcWfPV[i] == None) \
         or (adcWfPV[i].timestamp != adcWfPV[0].timestamp)):
            return
    for i in range(0,args.samples):
        for a in range(0,4):
            print(adcWfPV[a].value[i], file=logFile, end='')
        print('', file=logFile)
    done = True

triggerLevel = epics.PV(args.prefix+"selfTrigger:level")
triggerMask = epics.PV(args.prefix+"wfr:ADC:triggerMask")
saveTriggerLevel = triggerLevel.get()
pretrigCount = epics.PV(args.prefix+"wfr:ADC:pretrigCount")
acqCount = epics.PV(args.prefix+"wfr:ADC:acqCount")
dataMode = epics.PV(args.prefix+"wfr:ADC:DataMode")
armPV = epics.PV(args.prefix+"wfr:ADC:arm")
if (not armPV.wait_for_connection(1.0)):
    sys.exit(1)

armPV.put(0, wait=True)
if (args.triggerLevel > 0):
    triggerLevel.put(args.triggerLevel, wait=True)
    triggerMask.put(0x5, wait=True)
else:
    triggerMask.put(0x81, wait=True)
pretrigCount.put(3080, wait=True)
acqCount.put(args.samples, wait=True)
dataMode.put(1, wait=True)

adcWfPV = [None] * 4
for i in range(0,4):
    adcWfPV[i] = epics.PV(args.prefix+"wfr:ADC:c%d"%(i),auto_monitor=True, \
                                                            form='time')
    if (not adcWfPV[i].wait_for_connection(1.0)):
        sys.exit(1)
for i in range(0,4):
    adcWfPV[i].add_callback(wfHandler)

armPV.put(1)
while (not done):
    time.sleep(0.1)
dataMode.put(0)
triggerLevel.put(saveTriggerLevel)
