#
# Waveform recorder timing and stress test.
# First connect the timing system coincidence clock to the BPM button inputs.
#
from __future__ import print_function
import epics
import time
import argparse

parser = argparse.ArgumentParser(description='Continously trigger BPM waveform recorders.', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-n', '--nameprefix', default='SR01C:BPM1:', help='PV name prefix')
parser.add_argument('-t', '--turn', default='1', type=int, help='Turn number of peak')
args = parser.parse_args()

wfCount = 0
def wfHandler(pvname=None, count=None, value = None, **kw):
    global wfCount
    wfCount += 1
    if (pvname.find("TBT") >= 0):
        for i in xrange(0,15):
            if (((i == args.turn) and (value[i] < 300000)) \
             or ((i != args.turn) and (value[i] > 30000))):
                for i in xrange(0,15): print value[i],
                print
                break


softTrigger = epics.PV(args.nameprefix+"wfr:softTrigger")
arm = [ epics.PV(args.nameprefix+"wfr:ADC:arm"), \
        epics.PV(args.nameprefix+"wfr:TBT:arm"), \
        epics.PV(args.nameprefix+"wfr:FA:arm"),  \
        epics.PV(args.nameprefix+"wfr:PL:arm"),  \
        epics.PV(args.nameprefix+"wfr:PH:arm") ]
wf = [ epics.PV(args.nameprefix+"wfr:ADC:c3", auto_monitor=True, callback=wfHandler), \
       epics.PV(args.nameprefix+"wfr:TBT:c3", auto_monitor=True, callback=wfHandler), \
       epics.PV(args.nameprefix+"wfr:FA:c3", auto_monitor=True, callback=wfHandler), \
       epics.PV(args.nameprefix+"wfr:PL:c3", auto_monitor=True, callback=wfHandler), \
       epics.PV(args.nameprefix+"wfr:PH:c3", auto_monitor=True, callback=wfHandler) ]

print wf
for a in arm:
    a.put(0)
time.sleep(1)

retryCount = 0
timeoutCount = 0
while True:
    wfCount = 0
    for a in arm:
        a.put(1)
    time.sleep(0.5)
    softTrigger.put(1)
    i = 0
    while (wfCount < 3):
        time.sleep(0.2)
        i += 1
        if (i == 50*5):
            timeoutCount += 1
            print "Timeout ", timeoutCount
            break
