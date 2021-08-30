#!/bin/bash

APP="xsdk"
VERS="${XILINX_VERSION=14.7}"
export XILINXD_LICENSE_FILE="27004@engvlic3.lbl.gov"

while [ $# -ne 0 ]
do
    case "$1" in
        [0-9][0-9].[0-9])          VERS="$1" ;;
        ise|xps|impact|xpa|bash)   APP="$1" ;;
        sdk|xsdk)                  APP="xsdk" ;;
        coregen|cg)                APP="coregen" ;;
        *lan*|*hea*|p*)            APP="planAhead" ;;
        *)    echo "Usage: $0 [#.#] [ise|xps|xsdk|impact|xpa|plan|bash]" >&2 ; exit 1 ;;
    esac
    shift
done

case `uname -m` in
    *_64)   b=64 ;;
    *)      b=32 ;;
esac
s="/eda/xilinx/$VERS/ISE_DS/settings$b.sh"
if [ -f "$s" ]
then
    echo "Getting settings from \"$s\"."
    . "$s"
else
    echo "Can't find $s" >&2
    exit 2
fi

case "$APP" in
    bash) "$APP" -l ;;
    xsdk)  mkdir -p "$HOME/xilinxPlaypen"
           cd "$HOME/xilinxPlaypen" # Leave logging dregs in one place
           xsdk -vmargs -Dorg.eclipse.swt.internal.gtk.cairoGraphics="false" &
           ;;
    *)     mkdir -p "$HOME/xilinxPlaypen"
           cd "$HOME/xilinxPlaypen" # Leave logging dregs in one place
           "$APP" & ;;
esac
