#!/system/bin/sh
#
# Copyright (c) 2018  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

ARGS="bind-interfaces"
P2PIPADDRESS=$(getprop p2p.server.addr)
DHCPRANGE=$(getprop p2p.server.dhcpRange)
REG_ENDPOINT_FILE_NAME=/system/etc/registration_endpoint_host_names.csv
DNSMASQ_FILE_NAME=/data/csm_oobe/dnsmasq.conf

log -p i -t csm_dnsmasq.sh "starting dnsmasq"

read_hosts () {
     local IFS=,
     read KEY HOST_NAME
}

if [ -n "$P2PIPADDRESS" ]
then
     ARGS=" ${ARGS} \nlisten-address=${P2PIPADDRESS}"
fi

while read_hosts;
do
     if [ -n "$HOST_NAME" ]
     then
         ARGS="${ARGS} \naddress=/$HOST_NAME/$P2PIPADDRESS"
     fi
done < $REG_ENDPOINT_FILE_NAME

if [ -n "$DHCPRANGE" ]
then
     ARGS="${ARGS} \ndhcp-range=${DHCPRANGE}"
fi

ARGS=$(echo ${ARGS} | busybox sort -u )

echo $* $ARGS | tr " " "\n" > $DNSMASQ_FILE_NAME

log -p i -t csm_dnsmasq.sh "$?"
