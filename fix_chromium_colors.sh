#!/bin/bash

#remove all color profiles from your devices in settings -> color

SRGB_PATH=$(colormgr get-standard-space srgb | grep "Object Path:" | cut -d: -f2);
for DISPLAY_PATH in $(colormgr get-devices display | grep "Object Path:" | cut -d: -f2)
do
  colormgr device-add-profile $DISPLAY_PATH $SRGB_PATH;
  colormgr device-make-profile-default $DISPLAY_PATH $SRGB_PATH;
done

exit 0
