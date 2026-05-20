#!/system/bin/sh
#
# Copyright (c) 2018 - 2025 Amazon.com, Inc. or its affiliates.  All rights reserved.
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

IPTABLES=/system/bin/iptables
DEBUG_RULES_HOOK=/system/bin/debug_firewall.sh
GREENGRASS_RULES_HOOK=/system/bin/greengrass_firewall.sh
OPENTHREAD_CONFIG=/system/bin/openthread_ip_config.sh
GETPROP=/system/bin/getprop
LOG=/system/bin/log
DNSMASQ=/system/bin/dnsmasq
TAG=Firewall
OOBEIP=$($GETPROP p2p.server.addr)
GET_DYN_CONF=/system/bin/get-dynconf-value
COMPANION_APP_TCPTUNNEL_PORT_CONF_NAME=url.companionapp.tcptunnel.port
COMPANION_APP_TCPTUNNEL_PORT=$($GETPROP persist.oobe.compapp.port)
WPA_CLI=/system/bin/wpa_cli
DNS1IP=$($GETPROP net.dns1)
DNS2IP=$($GETPROP net.dns2)
DNS4IP=$($GETPROP net.dns4)
DNS5IP=$($GETPROP net.dns5)
ETH_SUPPORT=$($GETPROP persist.ethernet.support)
TCPTUNNEL_LOCAL_LISTENING_PORT=$($GETPROP lab126.oobe.local.listening.prt)
# Read the P2P interface name
target=$($GETPROP ro.fireos.target.product)

IF_NAME='p2p-p2p0-'
P2PIF=$($WPA_CLI interface | grep $IF_NAME)

INTERFACE_LIST=("wlan0")

if [ "${ETH_SUPPORT}" == "1" ]; then
    INTERFACE_LIST+=("eth0")
fi

print() {
    $LOG -t $TAG $1
}

# If '.' in the address, then it's IPv4.
# The input comes from properties, should be valid V4 or V6 address
function valid_ipv4() {
    local  ip=$1
    local  stat=1

    OIFS=$IFS
    IFS='.'
    tokens=($ip)
    IFS=$OIFS

    [[ ${#tokens[@]} -gt 1 ]]
    stat=$?
    return $stat
}

get_companion_app_tcptunnel_port() {

    # set the local variable port to ""
    local port=""
    if [ -e ${GET_DYN_CONF} ]; then
        port=$(${GET_DYN_CONF} ${COMPANION_APP_TCPTUNNEL_PORT_CONF_NAME})
    fi

    if [ "${port}" == "" ]; then
        port=${COMPANION_APP_TCPTUNNEL_PORT}
    fi

    print "Companion App TCPTunnel Port:${port}"
    echo -n "${port}"
}

if [ ! -x $IPTABLES ]; then
    print "$IPTABLES... not found"
    exit 1
fi

# Clean up all settings before processing
default_firewall_cleanup() {
    print "Cleaning up iptables before processing default firewall settings"
    $IPTABLES --flush

    # Default policy for all chains: DROP
    $IPTABLES -P INPUT DROP
    $IPTABLES -P OUTPUT DROP
    $IPTABLES -P FORWARD DROP
}

# Add default firewall settings for target interface
default_firewall_interface() {
    local interface=$1
    print "Setting up default firewall settings for interface $interface"

    # Accept RELATED,ESTABLISHED connections on target interface (device initiated)
    $IPTABLES -A INPUT -i "$interface" -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p udp -m state --state ESTABLISHED -j ACCEPT

    # Spotify Connect login server.
    $IPTABLES -A INPUT -i "$interface" -p tcp -m tcp --dport 4070 -j ACCEPT

    # Whatify Spotify Connect login server.
    $IPTABLES -A INPUT -i "$interface" -p tcp -m tcp --dport 4071 -j ACCEPT

    # SIP Calling support
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 16384:32767 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p tcp --dport 16384:32767 -j ACCEPT


    # TPH traffic on target interface. TPH/phd listens on port 40317
    $IPTABLES -A INPUT -i "$interface" -p tcp -m tcp --dport 40317 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 40317 --sport 40317 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 40317 --sport 49317 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 40317 --sport 33434 -j ACCEPT

    # Whole Home Audio traffic on target interface.  The whad listens on:
    # udp port 55442 for audio distribution
    # tcp port 55442 for audio distribution
    # tcp port 55443 for control plane behavior,
    # udp port 55444 for timestamp exchange
    # udp port 55445 for Quantum UDP WHASP
    # tcp port 55445 for TCP WHASP
    # udp port 55446 for multi-tier timestamp exchange
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 55442 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p tcp -m tcp --dport 55442:55443 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 55444:55446 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p tcp -m tcp --dport 55445 -j ACCEPT

    # CMB. Allow packets on port 5000
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 5000 -j ACCEPT

    # Matter use
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 5540 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface" -p udp --dport 5541 -j ACCEPT
    $IPTABLES -A FORWARD -i "$interface" -p udp --dport 5540 -j ACCEPT
    $IPTABLES -A FORWARD -i "$interface" -p udp --dport 5541 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 5540 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 5541 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p tcp --dport 5540 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p tcp --dport 5541 -j ACCEPT

    # UPnP:
    # allow traffic on Dst Port 1900 which are UPnP advertisements and Bye Bye
    # Allow traffic on Dst Port 50000; these pkts are SSDP search results
    # SSDP search queries are sent with Src Port 50000
    $IPTABLES -A INPUT -i "$interface"  -p udp --dport 1900 -j ACCEPT
    $IPTABLES -A INPUT -i "$interface"  -p udp --dport 50000 -j ACCEPT

    # mDNS: Avahi Publish of Spotify Connect service.
    $IPTABLES -A INPUT -i "$interface"  -p udp --dport 5353 -j ACCEPT

    # Allow all outgoing traffic on target interface
    $IPTABLES -A OUTPUT -o "$interface" -j ACCEPT

    # Allow LocalAdapterPlatform to listen to UDP Broadcasts from Tuya
    $IPTABLES -A INPUT -i $interface -p udp --dport 6667 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Allows LocalAdapterPlatform to perform UDP/SSDP Broadcast discovery for LifX, TPLink, Yeelight
    # Allows traffic only from RFC 1918 IP Addresses, ie IP-endoints on local network
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Allow ADB over Wifi traffic on target interface (if enabled)
    $IPTABLES -A INPUT  -i "$interface" -p tcp --dport 5555 -j ACCEPT
    $IPTABLES -A OUTPUT -o "$interface" -p tcp --sport 5555 -j ACCEPT

    # Octave remote player traffic
    $IPTABLES -A INPUT  -i "$interface" -p tcp --dport 1030 -j ACCEPT
    $IPTABLES -A OUTPUT -o "$interface" -p tcp --sport 1030 -j ACCEPT

}

# Add common default firewall settings (non-interface specific)
default_firewall_common() {
    print "Setting up common default firewall"
    # ICMP. Allow only responses to local connections
    $IPTABLES -A INPUT -p icmp -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Add rules for internal debugging use
    if [ -f $DEBUG_RULES_HOOK ]; then
        /system/bin/sh $DEBUG_RULES_HOOK
    else
        print "$DEBUG_RULES_HOOK does not exist"
    fi

    if [ -f $GREENGRASS_RULES_HOOK ]; then
        /system/bin/sh $GREENGRASS_RULES_HOOK
    fi

    # Accept all on the loopback interface
    $IPTABLES -A INPUT -i lo -j ACCEPT
    # Filter OUTPUT through oem_out
    $IPTABLES -A OUTPUT -j oem_out
    $IPTABLES -A OUTPUT -o lo -j ACCEPT
}

# Add default firewall settings here
default_firewall_setup () {
    default_firewall_cleanup
    for interface in "${INTERFACE_LIST[@]}"
    do
        default_firewall_interface ${interface}
    done
    default_firewall_common
}

# Add Alexa hybrid firewall settings for target interface
alexa_hybrid_firewall_interface() {
    local interface=$1
    local AHE_SECURE_PORT=$2
    print "Setting up alexa hybrid firewall settings for interface $interface and port $AHE_PORT"

    if [ -z $interface ] || [ -z $AHE_SECURE_PORT ]; then
        print "Invalid parameters. interface=$interface port=$AHE_PORT"
        exit 1
    fi

    # Allow extensions device connecting to AHE on given interface
    $IPTABLES -A INPUT -i "$interface" -p tcp --dport $AHE_SECURE_PORT -j ACCEPT
}

alexa_hybrid_firewall_common() {
    AHE_CLIENT_UID=$1
    AHE_SERVICE_UID=$2
    AHE_PORT=$3

    if [ -z $AHE_CLIENT_UID ] || [ -z $AHE_SERVICE_UID ] || [ -z $AHE_PORT ]; then
        print "Invalid parameters. client=$AHE_CLIENT_UID, service=$AHE_SERVICE_UID, port=$AHE_PORT"
        exit 1
    fi

    # Remove any existing rules on the oem_out chain
    $IPTABLES --flush oem_out
    # Drop traffic from a non alexa hybrid client user to AHE port/prevent impersonating SIM process.
    # Accept packets for an ESTABLISHED connection. This is required to allow FIN packets.
    $IPTABLES -A oem_out -o lo -p tcp --dport $AHE_PORT -d 127.0.0.1 -m state --state ESTABLISHED -j ACCEPT
    $IPTABLES -A oem_out -o lo -p tcp --dport $AHE_PORT -d 127.0.0.1 -m owner ! --uid-owner $AHE_CLIENT_UID -j DROP
    # Drop traffic from a non alexa hybrid service user from AHE port/prevent impersonating AHE process.
    # Don't accept for ESTABLISHED connection. When client initiates connection the SYN_ACK packet is
    # considered as part of ESTABLISHED connection. We don't want that.
    # We want to include SYC_ACK packets in owner uid filter.
    $IPTABLES -A oem_out -o lo -p tcp --sport $AHE_PORT -s 127.0.0.1 -m owner ! --uid-owner $AHE_SERVICE_UID -j DROP
}

# Add alexa hybrid firewall settings here
alexa_hybrid_firewall_setup () {
    print "alexa_hybrid_firewall_setup"
    local AHE_CLIENT_UID=$($GETPROP alexa.hybrid.client.uid)
    local AHE_SERVICE_UID=$($GETPROP alexa.hybrid.service.uid)
    local AHE_PORT=$($GETPROP alexa.hybrid.service.port)
    local AHE_SECURE_PORT=$($GETPROP alexa.hybrid.secure.port)
    for interface in "${INTERFACE_LIST[@]}"
    do
        alexa_hybrid_firewall_interface ${interface} ${AHE_SECURE_PORT}
    done
    alexa_hybrid_firewall_common ${AHE_CLIENT_UID} ${AHE_SERVICE_UID} ${AHE_PORT}
}

aicf_messenger_firewall_interface() {
    local INTERFACE=$1
    local AICF_MESSENGER_SECURE_PORT=$2
    local AICF_MESSENGER_RESERVE_START=$3
    local AICF_MESSENGER_RESERVE_END=$4

    print "Setting up AICF messenger firewall settings for $INTERFACE and port $AICF_MESSENGER_SECURE_PORT"

    if [ -z $AICF_MESSENGER_SECURE_PORT ]; then
        print "Invalid parameters. port=$AICF_MESSENGER_SECURE_PORT"
        exit 1
    fi

    # Allow remote AicfMessenger to connect to AicfMessenger on the device on given interface
    $IPTABLES -A INPUT -i $INTERFACE -p tcp --dport $AICF_MESSENGER_SECURE_PORT -j ACCEPT

    # Reserve ports for future control plane use.  Block all traffic for now
    if [ ! -z $AICF_MESSENGER_RESERVE_START -a ! -z $AICF_MESSENGER_RESERVE_END ]; then
        $IPTABLES -A INPUT -i $INTERFACE -p tcp --dport $AICF_MESSENGER_RESERVE_START:$AICF_MESSENGER_RESERVE_END -j DROP
        $IPTABLES -A OUTPUT -o $INTERFACE -p tcp --dport $AICF_MESSENGER_RESERVE_START:$AICF_MESSENGER_RESERVE_END -j DROP
    fi
}

aicf_messenger_firewall_common() {
    AICF_MESSENGER_CLIENT_UID=$1
    AICF_MESSENGER_SERVICE_UID=$2
    AICF_MESSENGER_PORT=$3

    if [ -z "$AICF_MESSENGER_CLIENT_UID" ] || [ -z "$AICF_MESSENGER_SERVICE_UID" ] || [ -z "$AICF_MESSENGER_PORT" ]; then
        print "Invalid parameters. client=$AICF_MESSENGER_CLIENT_UID, service=$AICF_MESSENGER_SERVICE_UID, port=$AICF_MESSENGER_PORT"
        exit 1
    fi

    # Create new chain aicfmessenger_out if not exist
    $IPTABLES -N aicfmessenger_out >> /dev/null 2>&1
    # Filter OUTPUT through aicfmessenger_out
    $IPTABLES -I OUTPUT 1 -j aicfmessenger_out
    # Remove any existing rules on the aicfmessenger_out chain
    $IPTABLES --flush aicfmessenger_out
    # Drop traffic from a non aicf messenger client user to AICF messenger port/prevent impersonating PuffinApp process.
    # Accept packets for an ESTABLISHED connection. This is required to allow FIN packets.
    $IPTABLES -A aicfmessenger_out -o lo -p tcp --dport $AICF_MESSENGER_PORT -d 127.0.0.1 -m state --state ESTABLISHED -j ACCEPT
    $IPTABLES -A aicfmessenger_out -o lo -p tcp --dport $AICF_MESSENGER_PORT -d 127.0.0.1 -m owner ! --uid-owner $AICF_MESSENGER_CLIENT_UID -j DROP
    # Drop traffic from a non aicf messenger user from AICF messenger port/prevent impersonating AicfMessenger.
    # Don't accept for ESTABLISHED connection. When client initiates connection the SYN_ACK packet is
    # considered as part of ESTABLISHED connection. We don't want that.
    # We want to include SYN_ACK packets in owner uid filter.
    $IPTABLES -A aicfmessenger_out -o lo -p tcp --sport $AICF_MESSENGER_PORT -s 127.0.0.1 -m owner ! --uid-owner $AICF_MESSENGER_SERVICE_UID -j DROP
}

aicf_messenger_firewall_start() {
    local AICF_RUNNING=`$GETPROP aicfmessenger_enable`
    if [ $AICF_RUNNING -eq "1" ]; then
        print "aicf_messenger_firewall_setup"
        local AICF_MESSENGER_CLIENT_UID='aicf'
        local AICF_MESSENGER_SERVICE_UID='aicf'
        local AICF_MESSENGER_SECURE_PORT=10001
        local AICF_MESSENGER_RESERVE_START=10002
        local AICF_MESSENGER_RESERVE_END=10006

        aicf_messenger_firewall_interface wlan0 ${AICF_MESSENGER_SECURE_PORT} ${AICF_MESSENGER_RESERVE_START} ${AICF_MESSENGER_RESERVE_END}
        aicf_messenger_firewall_interface br0 ${AICF_MESSENGER_SECURE_PORT} ${AICF_MESSENGER_RESERVE_START} ${AICF_MESSENGER_RESERVE_END}
        aicf_messenger_firewall_common ${AICF_MESSENGER_CLIENT_UID} ${AICF_MESSENGER_SERVICE_UID} ${AICF_MESSENGER_SECURE_PORT}
    fi
}

# Firewall settings for P2P interface
p2p_firewall_start () {
    print "Setting up P2P firewall settings on $P2PIF"

    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # Setup ip tables to reject all non-essential traffic
    # Redirect all DNS traffic to ourselves. This is necessary when the client device
    # has a static DNS address configured
    $IPTABLES -t nat -A PREROUTING -i "$P2PIF" -p udp --dport 53 -j DNAT --to ${OOBEIP}
    # ACCEPT all DNS traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p udp --dport 53 -j ACCEPT
    # ACCEPT all DHCP traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
    # ACCEPT all incoming OOBE webserver traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p tcp --dport 8080 -j ACCEPT
    $IPTABLES -A INPUT -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -j ACCEPT

    # Allow all outgoing traffic
    $IPTABLES -A OUTPUT -o "$P2PIF" -j ACCEPT
}

# Firewall settings for P2P interface
p2p_firewall_stop () {
    print "Disabling P2P firewall settings on $P2PIF"

    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # Delete all rules setup by p2p_firewall_start
    # Delete DNS redirection
    $IPTABLES -t nat -D PREROUTING -i "$P2PIF" -p udp --dport 53 -j DNAT --to ${OOBEIP}
    # Delete ACCEPT all DNS traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p udp --dport 53 -j ACCEPT
    # Delete ACCEPT all DHCP traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
    # Delete ACCEPT all incoming OOBE webserver traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p tcp --dport 8080 -j ACCEPT
    $IPTABLES -D INPUT -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -j ACCEPT

    # Delete Allow all outgoing traffic
    $IPTABLES -D OUTPUT -o "$P2PIF" -j ACCEPT

    # below is a temporary change.
    print "killing dnsmasq..."
    kill -9 `cat /data/csm_oobe/dnsmasq.pid`
}

nat_firewall_start () {
    PROP_COMPANION_IP="lab126.p2p.companion.app.ip"
    IP=`getprop $PROP_COMPANION_IP`
    if [ "x$IP" == "x" ]; then
        print "$PROP_COMPANION_IP is empty, failed to enable NAT"
        return
    fi
    print "enabling ip_forward"
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Add rules for forwarding and NAT-ing traffic for the companion
    # app IP if necessary.
    for interface in "${INTERFACE_LIST[@]}"
    do
        $IPTABLES -C FORWARD -p tcp -s ${IP} -i ${P2PIF} -o ${interface} -j ACCEPT
    done

    if [ $? -ne 0 ]; then
        print "enabling NAT for $IP only"

        for interface in "${INTERFACE_LIST[@]}"
        do
            # Accept tcp forwarding traffic
            iptables -A FORWARD -p tcp -s $IP -i ${P2PIF} -o ${interface} -j ACCEPT
            # Masquerade all NAT traffic
            iptables -t nat -I natctrl_nat_POSTROUTING -o ${interface} -j MASQUERADE
        done

        iptables -A FORWARD -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi

    print "detecting nameserver"
    # Save nameserver to a file
    if valid_ipv4 ${DNS1IP}; then echo "nameserver ${DNS1IP}" > /data/csm_oobe/resolv.dnsmasq;
    elif valid_ipv4 ${DNS2IP}; then echo "nameserver ${DNS2IP}" > /data/csm_oobe/resolv.dnsmasq;
    elif valid_ipv4 ${DNS4IP}; then echo "nameserver ${DNS4IP}" > /data/csm_oobe/resolv.dnsmasq;
    elif valid_ipv4 ${DNS5IP}; then echo "nameserver ${DNS5IP}" > /data/csm_oobe/resolv.dnsmasq;
    fi
    echo "nameserver 8.8.8.8" >> /data/csm_oobe/resolv.dnsmasq;
    chmod 644 /data/csm_oobe/resolv.dnsmasq

    print "applying nameserver"
    # Reload dnsmasq to use upstream nameserver from the file
    kill -9 `cat /data/csm_oobe/dnsmasq.pid`
    $DNSMASQ --group=dhcp --leasefile-ro
}

nat_firewall_stop () {
    PROP_COMPANION_IP="lab126.p2p.companion.app.ip"
    IP=`getprop $PROP_COMPANION_IP`
    if [ "x$IP" == "x" ]; then
        print "$PROP_COMPANION_IP is empty, NAT wasn't enabled"
        return
    fi
    # cleanup
    if [ -f $OPENTHREAD_CONFIG ]; then
        print "keeping ip_foward for Openthread"
        # Delete tcp forwarding rule from NAT setup
        for interface in "${INTERFACE_LIST[@]}"
        do
            iptables -D FORWARD -p tcp -s $IP -i ${P2PIF} -o ${interface} -j ACCEPT
        done
        iptables -D FORWARD -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    else
        print "disabling ip_forward"
        echo 0 > /proc/sys/net/ipv4/ip_forward

        # Stop accepting forward traffic
        iptables -F FORWARD
    fi

    for interface in "${INTERFACE_LIST[@]}"
    do
        # Delete NAT masquerade rule.
        iptables -t nat -D POSTROUTING -o ${interface} -j MASQUERADE
    done

    print "clearing nameserver"
    echo "" > /data/csm_oobe/resolv.dnsmasq
    chmod 644 /data/csm_oobe/resolv.dnsmasq

    print "applying nameserver"
    kill -s HUP `cat /data/csm_oobe/dnsmasq.pid`
}

tcp_tunnel_start () {
    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # The companion app make authorize link code call on port number 443. OOBE apk is a prebuilt. So it cannot bind to port numbers less than 1024.
    # So, any traffic that is sent over the p2p interface to the server ip, should be redirected to a port that the OOBE apk can bind to. This port
    # on which the OOBE apk is listening is written in the system property lab126.oobe.local.listening.prt, by the OOBE apk.
    print "Enabling TCPTunnel port forwarding from ${TCPTUNNEL_LOCAL_LISTENING_PORT} to ${COMPANION_APP_TCPTUNNEL_PORT} on $P2PIF"

    iptables -A INPUT -i "$P2PIF" -p tcp --dport ${TCPTUNNEL_LOCAL_LISTENING_PORT} -j ACCEPT
    iptables -t nat -A PREROUTING -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -d ${OOBEIP} -j DNAT --to-destination ${OOBEIP}:${TCPTUNNEL_LOCAL_LISTENING_PORT}
}

tcp_tunnel_stop () {
    # cleanup
    print "Disabling TCPTunnel port forwarding"

    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    iptables -D INPUT -i "$P2PIF" -p tcp --dport ${TCPTUNNEL_LOCAL_LISTENING_PORT} -j ACCEPT
    iptables -t nat -D PREROUTING -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -d ${OOBEIP} -j DNAT --to-destination ${OOBEIP}:${TCPTUNNEL_LOCAL_LISTENING_PORT}
}

start_setup_firewall () {

    case "$1" in
        default)
            default_firewall_setup
            aicf_messenger_firewall_start
            ;;
        p2p)
            shift
            p2p_firewall_start
            ;;
        nat)
            shift
            nat_firewall_start
            ;;
        port_forwarding)
            shift
            tcp_tunnel_start
            ;;
        alexa_hybrid_firewall)
            alexa_hybrid_firewall_setup
            ;;
        *)
            exit 1
            ;;
    esac
}

stop_setup_firewall () {

    case "$1" in
        p2p)
            shift
            p2p_firewall_stop
            nat_firewall_stop
            ;;
        nat)
            shift
            nat_firewall_stop
            ;;
        port_forwarding)
            shift
            tcp_tunnel_stop
            ;;
        *)
            exit 1
            ;;
    esac
}

case "$1" in
    start)
        if [ "$2" ]
        then
            shift
            # Setup any specific settings
            start_setup_firewall "$@"
            exit 0
        fi
        ;;
    stop)
        if [ "$2" ]
        then
            shift
            # Stop any specific settings
            stop_setup_firewall "$@"
            exit 0
        fi
        ;;
    *)
        exit 1
        ;;
esac

exit 1
