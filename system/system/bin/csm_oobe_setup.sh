#!/system/bin/sh
#
# Copyright (c) 2018  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

# Android system properties that are required by OOBE are set here.
setprop p2p.server.addr 10.201.126.241
setprop p2p.server.prefixLength 28
setprop p2p.server.dhcpRange 10.201.126.242,10.201.126.254,20m
setprop lab126.p2p.companion.app.ip 10.201.126.242/24
setprop com.lab126.dnsmasq_script /system/bin/csm_dnsmasq.sh
# Android property that list supported locales
setprop lab126.headless.locales en-US,en-GB,de-DE,en-IN,ja-JP,en-CA,en-AU,fr-FR,it-IT,es-ES,es-MX,fr-CA,pt-BR,hi-IN,es-US

