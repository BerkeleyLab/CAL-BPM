set style data lines
plot 'test.dat' using 4 title "X Wide",   \
     'test.dat' using 3 title "Y Wide",   \
     'test.dat' using 2 title "X Narrow", \
     'test.dat' using 1 title "Y Narrow"
pause -1

