#!/bin/sh

#
# xsdk won't start without the magic incantation to disable Cairo graphics.
#
xsdk -vmargs -Dorg.eclipse.swt.internal.gtk.cairoGraphics="false"
