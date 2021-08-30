#
# Produce local oscillator lookup tables
#
import math
import argparse

parser = argparse.ArgumentParser(description='Create local oscillator lookup tables.', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-i', '--integerOutput', action='store_true', help='Show values as integaers, not scaled back to [-1,1].')
parser.add_argument('-s', '--scaleFactor', default=0x1FFFF, type=int, help='Double to Integer scale factor (full scale value).')
args = parser.parse_args()

def quantize(x):
    if (x < 0): return -quantize(-x)
    xi = math.floor((x * args.scaleFactor) + 0.5)
    if (not args.integerOutput): xi /= args.scaleFactor
    return xi

def rfTable(name, Frf, refDivider, refMultiplier, sampleCount):
    Frf = float(Frf)
    Fadc = Frf / refDivider * refMultiplier
    Feff = Frf - math.floor(Frf / Fadc) * Fadc
    if (Feff > Fadc / 2): Feff = Fadc - Feff
    fftIndex = Feff / (Fadc / sampleCount)
    print "Frf:%.3f  Fadc:%.3f  Feff:%.3f  FFT index:%d" % (Frf, Fadc, Feff, fftIndex)
    f = open(name, 'w')
    w = 2 * math.pi * Frf
    Tsamp = 1.0 / Fadc
    for i in xrange(sampleCount):
        s = quantize(math.sin(w*Tsamp*i))
        c = quantize(math.cos(w*Tsamp*i))
        print>>f, "%9.6f,%9.6f" % (c, s)

def ptTable(name, Foffset, Frf, refDivider, refMultiplier, sampleCount):
    Frf = float(Frf)
    Fadc = Frf / refDivider * refMultiplier
    Flo = Frf - Foffset
    Fhi = Frf + Foffset
    print "Frf:%.3f  Fadc:%.3f  Flo:%.3f  Fhi:%.3f" % (Frf, Fadc, Flo, Fhi)
    f = open(name, 'w')
    wl = 2 * math.pi * Flo
    wh = 2 * math.pi * Fhi
    Tsamp = 1.0 / Fadc
    for i in xrange(sampleCount):
        sl = quantize(math.sin(wl*Tsamp*i))
        cl = quantize(math.cos(wl*Tsamp*i))
        sh = quantize(math.sin(wh*Tsamp*i))
        ch = quantize(math.cos(wh*Tsamp*i))
        print>>f, "%9.6f,%9.6f,%9.6f,%9.6f" % (cl, sl, ch, sh)

rfTable('rfTableSR.csv', 500, 328,  77, 77)
rfTable('rfTableTL.csv', 500, 328,  77, 77)
rfTable('rfTableBR.csv', 500, 500, 116, 29)

ptTable('ptTableSR_1_2.csv', (500.0/328.0)*(1.0/2.0), 500, 328, 77, 77*2)
ptTable('ptTableSR_11_19.csv', (500.0/328.0)*(11.0/19.0), 500, 328, 77, 77*19)
ptTable('ptTableTL.csv', 0, 500, 328,  77,  77)
ptTable('ptTableBR_1_2.csv', (500.0/125.0)*(1.0/2.0), 500, 500, 116,  29*2)
