#!/system/bin/sh
#
# Copyright (c) 2022 Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.

# Get the eMMC block device node
# At this time, we're assuming that there's only one eMMC device.
# In the case that there are multiple, we'll just report lifetime metrics on
# the first one.
# Tablet devices may have SD cards attached, which will also be a sysfs block
# device node. Make sure to choose the eMMC device node. The scr node only
# exists for SD cards.
WAIT_WRITE_FOR_HYNIX_SCRIPT="/system/bin/wait_write_for_hynix.sh"

for i in 0 1 2 3 4
do
  if [ -e "/sys/block/mmcblk$i" ] && [ ! -e "/sys/block/mmcblk$i/device/scr" ]; then
    emmc_device="mmcblk$i"
    break
  fi
done

# Exit with error if no valid sysfs eMMC node is found
if [ "$emmc_device" = "" ]; then
  echo "read_lifetime.sh failed, no valid sysfs eMMC node"
  exit 1
fi

manfid_file_name="/sys/block/$emmc_device/device/manfid";
if [ -e $manfid_file_name ]; then
  manfid=$(<$manfid_file_name)
  setprop sys.amzn_bsp_diag.emmc_manfid "$manfid"
fi

lifetime_ready=1
# Workaround for Hynix eMMC
if [ -f $WAIT_WRITE_FOR_HYNIX_SCRIPT ] && [ -x $WAIT_WRITE_FOR_HYNIX_SCRIPT ]; then
  $WAIT_WRITE_FOR_HYNIX_SCRIPT $manfid
  lifetime_ready=$?
fi
# Older devices export eMMC lifetime metrics using 2 files below
# 1. dev_lifetime_est_typ_a
# 2. dev_lifetime_est_typ_b
# Newer devices export eMMC lifetime metrics using 1 unified file
# 1. life_time

new_lifetime_file_name="/sys/block/$emmc_device/device/life_time";
lifetime_a_file_name="/sys/block/$emmc_device/device/dev_lifetime_est_typ_a";
lifetime_b_file_name="/sys/block/$emmc_device/device/dev_lifetime_est_typ_b";
pre_eol_info_file_name="/sys/block/$emmc_device/device/pre_eol_info";

# If sysfs nodes are empty or doesn't exist, use NA as a value
# lifetime contains 2 values, so use "NA NA"
if [ ! -e $new_lifetime_file_name ]; then
  if [ -e $lifetime_a_file_name ] || [ -e $lifetime_b_file_name ]; then
    lifetime_a=$(<$lifetime_a_file_name)
    lifetime_b=$(<$lifetime_b_file_name)
    lifetime="${lifetime_a} ${lifetime_b}"
  else
    lifetime=""
  fi
else
  lifetime=$(<$new_lifetime_file_name)
fi
if [ ! "$lifetime" = "" ] && [ "$lifetime_ready" == 1 ]; then
  setprop sys.amzn_bsp_diag.emmc_lifetime "$lifetime"
fi

if [ -e $pre_eol_info_file_name ]; then
  pre_eol_info=$(<$pre_eol_info_file_name)
  setprop sys.amzn_bsp_diag.emmc_pre_eol "$pre_eol_info"
fi
