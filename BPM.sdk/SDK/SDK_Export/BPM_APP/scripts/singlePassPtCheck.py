#
# Check single-pass pilot tones
#
import numpy as np
import epics
import sys
import datetime
import time
import argparse

parser = argparse.ArgumentParser(description='Monitor single-pass pilot tones.', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-b', '--bad', action='store_true', help='Print only bad tones')
parser.add_argument('-d', '--deltatime', action='store_true', help='Show time delta')
parser.add_argument('-p', '--prefix', default='SR01C:BPM1:', help='PV name prefix')
args = parser.parse_args()

then = None

def ptHandler(pvname=None, count=None, value = None, **kw):
    global adcPtPV, then
    for i in range(0,8):
        if ((adcPtPV[i] == None) \
         or (adcPtPV[i].timestamp != adcPtPV[0].timestamp)):
            return
    fail = False
    for i in range(0,4):
        if (adcPtPV[2*i].value != adcPtPV[2*i+1].value):
            fail = True
            break
    if (not fail):
        for i in range(1,8):
            r = float(adcPtPV[i].value) / float(adcPtPV[0].value)
            if (r < 0.9) or (r > 1.1):
                fail = True
                break
    if not args.bad or fail:
        if args.deltatime:
            if then:
                d = adcPtPV[0].timestamp - then
            else:
                d = 0
            print '%.6f' % d,
        else:
            print datetime.datetime.fromtimestamp(adcPtPV[0].timestamp).isoformat(' '),
        for i in range(0,8):
            print adcPtPV[i].value,
        if fail:
            print ' FAIL'
        else:
            print ''
    then = adcPtPV[0].timestamp
        
def connect(name):
    pv = epics.PV(name, form='time')
    if (not pv or not pv.wait_for_connection(1.0)):
        print >>sys.stderr, "Can't connect to " + name
        sys.exit(1)
    return pv

adcPtPV = [None] * 8
i = 0
for a in range(0,4):
    for t in ['Lo', 'Hi']:
        name = args.prefix+'ADC%d:pt%sMag'%(a,t)
        adcPtPV[i] = connect(name)
        i += 1
for i in range(0,8):
    adcPtPV[i].add_callback(ptHandler)

while (True):
    time.sleep(0.1)
