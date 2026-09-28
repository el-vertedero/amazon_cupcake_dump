#!/system/bin/sh
#
# Copyright (c) 2018  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

BUTTONS="volumeup volumedown action mute gpio-privacy"
PM_WAKEUP_IRQ=$(cat /sys/power/pm_wakeup_irq)

for BUTTON in $BUTTONS
do
    IRQ=$(cat /proc/interrupts | grep $BUTTON$ | busybox awk -F ':' "{print \$1}")
    if [ "$PM_WAKEUP_IRQ" = $IRQ ]
    then
        echo "Button $BUTTON pressed."
        /system/bin/reboot
    fi
done

echo "Spurious wakeup by interrupt=$PM_WAKEUP_IRQ"
# Go back to suspend mode if system resumed without button
/system/bin/start echo_power_save
