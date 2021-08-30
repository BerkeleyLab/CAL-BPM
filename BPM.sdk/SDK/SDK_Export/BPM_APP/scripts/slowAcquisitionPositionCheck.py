#
# Check single-pass pilot tones
#
import numpy as np
import epics
import math
import sys
import datetime
import time
import argparse

parser = argparse.ArgumentParser(description='Monitor single-pass positions -- show mean and RMS.', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-d', '--deltatime', action='store_true', help='Show time delta')
parser.add_argument('-p', '--prefix', default='SR01C:BPM1:', help='PV name prefix')
parser.add_argument('-v', '--verbose', action='store_true', help='Show positions too')
args = parser.parse_args()

then = None
stats = [[0.0, 0, 0.0, 0.0], [0.0, 0, 0.0, 0.0]]


def pvHandler(pvname=None, count=None, value=None, statIndex=None, **kw):
    global pvs, then, stats
    stats[statIndex][0] = value
    for i in range(0,2):
        if ((pvs[i] == None) \
         or (pvs[i].timestamp != pvs[0].timestamp)):
            return
    if args.deltatime:
        if then:
            d = pvs[0].timestamp - then
        else:
            d = 0
        print '%9.6f' % d,
        then = pvs[0].timestamp
    else:
        print datetime.datetime.fromtimestamp(pvs[0].timestamp).isoformat(' '),
    for i in range(0,2):
        value = stats[i][0]
        stats[i][1] += 1
        stats[i][2] += value
        stats[i][3] += value * value
        n = stats[i][1]
        mean = stats[i][2]/n
        if (n == 1):
            rms = 0
        else:
            rms = math.sqrt((stats[i][3]/n) - mean*mean)
        if (args.verbose):
            print "%10.4f" % (value),
        print "%10.4f %9.4f" % (mean * 1000, rms * 1000),
    print ''
        
def connect(name):
    pv = epics.PV(name, form='time')
    if (not pv or not pv.wait_for_connection(1.0)):
        print >>sys.stderr, "Can't connect to " + name
        sys.exit(1)
    return pv

pvs = [None] * 2
i = 0
for p in ['X', 'Y']:
    name = args.prefix+'SA:%s'%(p)
    pvs[i] = connect(name)
    i += 1
for i in range(0,2):
    pvs[i].add_callback(pvHandler, statIndex=i)

while (True):
    time.sleep(0.1)
