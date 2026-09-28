#!/system/bin/sh
#
# Copyright (c) 2018  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

echo "Entering power save mode" > /dev/kmsg

# Disable wifi/bt/zigbee
for dir in $(ls /sys/class/rfkill)
do
    echo 0 > /sys/class/rfkill/$dir/state
done

# Retry to ensure suspend request works
retryTimes=0;

while [ $retryTimes -lt 5 ]
do
    if [ $retryTimes -gt 0 ]
    then
        echo "Retry entering power save mode #$retryTimes" > /dev/kmsg
    fi

    echo mem > /sys/power/state

    # Enter into suspend mode successfully
    if [ $? -eq 0 ]
    then
        echo "Enter into suspend mode successfully" > /dev/kmsg
        break
    fi

    retryTimes=$((retryTimes + 1))
done

echo "Start detecting button press" > /dev/kmsg
/system/bin/start ps_button_detect

if [ $retryTimes -eq 5 ]
then
    echo "Unable to enter power save mode after $retryTimes retries" > /dev/kmsg
fi
