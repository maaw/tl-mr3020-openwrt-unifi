#!/bin/sh
# Overlay the OpenWrt 19.07.10 hostapd generator, preserving stock BSS behavior.
set -eu
source_script=$1
target_script=$2
awk '
    /config_add_string macfilter / {
        print
        print "\tconfig_add_array mr3020_client_vlans"
        schema++
        next
    }
    /\[ -n "\$vlan_possible" -a -n "\$dynamic_vlan" \] &&/ {
        print "\tlocal client_vlans record mac vid port rest"
        print "\tjson_get_values client_vlans mr3020_client_vlans"
        print "\t[ -n \"$client_vlans\" ] && {"
        print "\t\tlocal clients=/var/run/mr3020-$ifname.clients vlans=/var/run/mr3020-$ifname.vlans"
        print "\t\t(umask 077; : > \"$clients\"; : > \"$vlans\") || return 1"
        print "\t\tfor record in $client_vlans; do"
        print "\t\t\tmac=${record%%,*}; rest=${record#*,}"
        print "\t\t\tvid=${rest%%,*}; port=${rest#*,}"
        print "\t\t\tprintf \"%s %s\\n\" \"$mac\" \"$vid\" >> \"$clients\" || return 1"
        print "\t\t\tprintf \"%s %s\\n\" \"$vid\" \"$port\" >> \"$vlans\" || return 1"
        print "\t\tdone"
        print "\t\tsort -u -o \"$vlans\" \"$vlans\" || return 1"
        print "\t\tappend bss_conf \"macaddr_acl=0\" \"$N\""
        print "\t\tappend bss_conf \"accept_mac_file=$clients\" \"$N\""
        print "\t\tappend bss_conf \"dynamic_vlan=1\" \"$N\""
        print "\t\tappend bss_conf \"vlan_file=$vlans\" \"$N\""
        print "\t}"
        generator++
    }
    { print }
    END { if (schema != 1 || generator != 1) exit 1 }
' "$source_script" > "$target_script"
