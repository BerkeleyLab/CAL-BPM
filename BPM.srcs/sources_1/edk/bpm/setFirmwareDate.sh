#!/bin/bash

set -ex

SECONDS=` date '+%s'`
TZINFO=` date '+%z'`
SIGN=`echo $TZINFO | sed -n -e 's/\(.\).*/\1/p'`
HHMM=`echo $TZINFO | sed -n -e 's/.\(.*\)/\1/p'`
((SECONDS=$SECONDS $SIGN ((((10#$HHMM/100)*60)+(10#$HHMM%100)) * 60)))
(
echo "// MACHINE GENERATED -- DO NOT EDIT"
echo "parameter FIRMWARE_DATE = $SECONDS;"
) >firmwareDate.v

