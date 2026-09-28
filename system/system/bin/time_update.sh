#!/system/bin/sh
#
# Copyright (c) 2018-2020  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#
LOG=/system/bin/log
TAG=TimeService.update

print() {
    $LOG -t $TAG $1
}

# If rtc_device is set, only use "saved time" feature on cold boot
rtc_device=`getprop ro.sys.rtc.device`
if ! [ -z "$rtc_device" ] ; then
    # Don't allow this to run more than once per device boot
    rtc_checked=`getprop sys.rtc.checked`
    if [ "$rtc_checked" -a "$rtc_checked" != 0 ] ; then
        setprop sys.time.setonboot 0
        print "RTC already checked; not setting time"
        return
    else
        setprop sys.rtc.checked 1
        if grep /proc/life_cycle_reason -qie cold || grep /proc/life_cycle_reason -qie LCR_abnormal && ! grep /proc/life_cycle_reason -qie kernel ; then
            # Don't use the RTC on cold boot - it was reset!
            print "Cold boot; not setting time from RTC"
        else
            # System time = RTC time + RTC offset
            rtc_offset=`getprop persist.sys.rtc.offset`
            if ! [ "$rtc_offset" -a "$rtc_offset" != 0 ] ; then
                print "No RTC offset found!"
            else
                rtc_time=`cat $rtc_device/since_epoch`
                print "Setting time from RTC + offset: $rtc_time + $rtc_offset"
                date -u @$((rtc_time + rtc_offset))
                setprop sys.time.setonboot 1
                setprop sys.rtc.offset.used 1
                print "Time set from RTC + offset"
                return
            fi
        fi
    fi
fi

store_time=`getprop persist.sys.saved_time`
store_time=${store_time%???}  #convert milliseconds to seconds
system_time="`date +%s`"
if (("$store_time" > "$system_time"))
then
    date -u @$store_time
    setprop sys.time.setonboot 1
    print "Successfully set time on boot"
else
    setprop sys.time.setonboot 0
    print "Did not set time on boot"
fi
