#!/bin/sh

scp ../../Impact/BPM.bin ../Release/BPM_APP.srec enorum@access.als.lbl.gov:
ssh enorum@access.als.lbl.gov "scp BPM.bin BPM_APP.srec bpm01:///usr/local/epics/R3.15.4/modules/instrument/ALS_BPM/head/FPGA ; rm BPM.bin BPM_APP.srec"
