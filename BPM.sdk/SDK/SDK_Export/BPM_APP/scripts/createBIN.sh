#!/bin/sh

sh mergeBoot.sh
cd ../../Impact
promgen -w -p bin -c FF -o BPM.bin -s 131072 -u 00000000 ../system_hw_platform/download.bit -bpi_dc parallel -data_width 16 
