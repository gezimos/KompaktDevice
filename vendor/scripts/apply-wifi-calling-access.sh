#!/bin/bash
# Lets ipsec_mon read the interface details it needs for the Wi-Fi calling
# tunnel. Android 16 asks for nlmsg_readpriv on those reads; without it the
# tunnel comes up but nothing is sent through it, and IMS never registers.
# Usage: apply-wifi-calling-access.sh <vendor-stage-dir>   (idempotent)
set -euo pipefail
V="${1:?usage: apply-wifi-calling-access.sh <vendor-stage-dir>}"
CIL="$V/etc/selinux/vendor_sepolicy.cil"
test -f "$CIL" || { echo "no vendor_sepolicy.cil under $V"; exit 1; }

grep -q "^(type ipsec_mon)$" "$CIL" || { echo "type not declared by vendor: ipsec_mon"; exit 1; }
RULE='(allow ipsec_mon self (netlink_route_socket (nlmsg_readpriv)))'
grep -qxF "$RULE" "$CIL" || printf '%s\n' "$RULE" >> "$CIL"

grep -cxF "$RULE" "$CIL" | tr '\n' ' '; echo "<- ipsec_mon readpriv"
echo WIFI_CALLING_ACCESS_OK
