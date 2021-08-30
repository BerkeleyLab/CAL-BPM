#!/bin/sh

set -ex

cd ../../Impact
data2mem -bm ../hw/bpmTop_bd.bmm            \
         -bt ../hw/bpmTop.bit               \
         -bd ../BOOT_APP/Debug/BOOT_APP.elf \
         tag system_i_microblaze_0 -o b ../system_hw_platform/download.bit
