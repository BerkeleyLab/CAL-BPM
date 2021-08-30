#!/bin/sh

set -ex

cd ../../Impact

for i
do
    case $i in
    [0-9]|[0-9][0-9]|[0-9][0-9][0-9]) ;;
    *) echo "Usage: $0 ### [### ...]" >&2 ; exit 1 ;;
    esac
done

for i
do
    tftp -v -m octet 192.168.1.$i -c put BPM.bin &
done
wait
cd ../BPM_APP/Release
for i
do
    tftp -v -m octet 192.168.1.$i -c put BPM_APP.srec &
done
wait
