# Convert CORDIC 26-bit arguments and show magnitude

from __future__ import print_function
import math
import sys

def b26(ival):
    print "%X" % (ival)
    if (ival & (1 << 25)): ival -= 1 << 26
    return ival

for i in range(1,len(sys.argv)):
    w = int(sys.argv[i], 16)
    print("%d %x" % (w, w)
    qVal = b26(w & ((1 << 26) - 1))
    iVal = b26(w >> 26)
    mag = math.floor(math.hypot(iVal, qVal))
    cmag = math.floor(mag * 1.646760258)
    print("%12g %12g %12g %9.0f %12g" % (iVal, qVal, cmag, mag, mag),end='')
    if (cmag >= (1 << 26)): print "!!!!",
    print()


