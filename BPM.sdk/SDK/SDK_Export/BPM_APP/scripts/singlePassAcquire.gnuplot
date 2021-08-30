set style data lines

lsb(x,y)=(floor(x)&1)*y

plot 'j' using 1 title "ADC 0", \
    'j' using (lsb($1,500)) title "Load and Latch", \
    'j' using (lsb($2,1000)) title "TBT Load", \
    'j' using (lsb($3,-500)) title "TBT Latch", \
    'j' using (lsb($4,-1000)) title "Use Sample"
pause -1

set xrange[3650:3800]
replot
pause -1
