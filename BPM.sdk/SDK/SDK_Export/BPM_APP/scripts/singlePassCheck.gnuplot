#
# Plot data with embedded status lines
#
set style data lines
set xrange [0:100]
plot "jnk.dat" using 1 title "ADC 0", \
     "jnk.dat" using 2 title "ADC 1", \
     "jnk.dat" using 3 title "ADC 2", \
     "jnk.dat" using 4 title "ADC 2", \
     "jnk.dat" using ((int($4) & 1) * 1000 - 500) title "Use",  \
     "jnk.dat" using ((int($3) & 1) * 1000 - 500) title "Load",  \
     "jnk.dat" using ((int($2) & 1) * 1000 - 500)title "Latch", \
     -400, 400

pause -1
