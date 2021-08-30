#!/bin/sh

set -ex
(
cd ../Release
make clean all
)
sh mergeBoot.sh
sh createBIN.sh
