#
# Waveform recorder timing test
#
import epics
import argparse
import sys
import time

parser = argparse.ArgumentParser(description='Read large ADC waveform.', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-n', '--nsamples', type=int, default=0, help='Number of samples to acquire (0 means maximum allowable)')
parser.add_argument('-p', '--prefix', default='SR01C:BPM1:', help='PV name prefix')
parser.add_argument('-r', '--recorder', default='ADC', choices=('ADC', 'TBT', 'FA', 'PL', 'PH'), help='Recorder selection')
parser.add_argument('-v', '--verbose', action='store_true', help='Print extra information')
parser.add_argument('-w', '--waveform', action='store_true', help='Print waveform too')
args = parser.parse_args()

doneCount = 0
def wfHandler(pvname=None, count=None, value = None, **kw):
    global doneCount
    doneCount += 1

def rateHandler(pvname=None, count=None, value = None, **kw):
    global doneCount
    doneCount += 1


wfr = []
for i in range(0,4):
    wfr.append(epics.PV(args.prefix+"wfr:%s:c%d"%(args.recorder, i), callback=wfHandler, auto_monitor=True))
pretrigCount = epics.PV(args.prefix+"wfr:%s:pretrigCount" % (args.recorder))
acqCount     = epics.PV(args.prefix+"wfr:%s:acqCount" % (args.recorder))
rate         = epics.PV(args.prefix+"wfr:%s:rate" % (args.recorder), callback=rateHandler)
arm          = epics.PV(args.prefix+"wfr:%s:arm" % (args.recorder))
triggerMask  = epics.PV(args.prefix+"wfr:%s:triggerMask" % (args.recorder))
trigger      = epics.PV(args.prefix+"wfr:softTrigger")

if (args.nsamples > 0):
    sampleCount = args.nsamples
else:
    sampleCount = wfr[0].nelm

arm.put(0)
triggerMask.put(0x1)
if (args.recorder == 'ADC'):
    pretrigCount.put(3080)
elif (args.recorder == 'TBT') or (args.recorder == 'FA'):
    pretrigCount.put(100)
else:
    pretrigCount.put(5)
acqCount.put(sampleCount)
arm.put(1)
time.sleep(1)
doneCount = 0
trigger.put(1)

then = time.time()
passCount = 0
while (doneCount < 5):
    passCount += 1
    if (passCount > 60):
        print "NO WAVEFORM!"
        sys.exit(1)
    time.sleep(1)
now = time.time()
if (args.verbose):
    if (wfr[0].count != wfr[0].nelm):
        print "# Got %d samples.  Limit is %d." % (wfr[0].count, wfr[0].nelm)
    print "# %d samples at %g kB/sec (%.2f seconds)" %  (wfr[0].count, rate.value, now - then)
if (args.waveform):
    i = 0
    while (i < wfr[0].count):
        print "%d" % (i),
        for w in range(0,4):
            print " %d" % (wfr[w].value[i]),
        print
        i += 1
