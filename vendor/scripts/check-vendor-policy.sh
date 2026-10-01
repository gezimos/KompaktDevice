#!/bin/bash
# Compiles a stage's vendor policy together with a system image's policy, the
# way init does at boot. A vendor policy that does not compile leaves the phone
# unable to boot, so build-vendor.sh stops on a failure here.
# Usage: check-vendor-policy.sh <vendor-stage-dir> <system.img> <lineage tree>
set -uo pipefail
V=${1:?usage: check-vendor-policy.sh <vendor-stage-dir> <system.img> <lineage tree>}
IMG=${2:?usage: check-vendor-policy.sh <vendor-stage-dir> <system.img> <lineage tree>}
L=${3:?usage: check-vendor-policy.sh <vendor-stage-dir> <system.img> <lineage tree>}
SECILC=$L/out/host/linux-x86/bin/secilc
VER=$(cat "$V/etc/selinux/plat_sepolicy_vers.txt")
P=$(mktemp -d)
trap 'rm -rf "$P"' EXIT

for f in system/etc/selinux/plat_sepolicy.cil \
         system/etc/selinux/mapping/$VER.cil \
         system/etc/selinux/mapping/$VER.compat.cil \
         system/system_ext/etc/selinux/system_ext_sepolicy.cil \
         system/product/etc/selinux/product_sepolicy.cil; do
    debugfs -R "dump /$f $P/$(basename "$f")" "$IMG" 2>/dev/null
    test -s "$P/$(basename "$f")" || { echo "MISSING $f"; echo "SECILC_EXIT=1"; exit 1; }
done

"$SECILC" -m -M true -G -N -c 30 \
    "$P/plat_sepolicy.cil" "$P/$VER.cil" "$P/$VER.compat.cil" \
    "$P/system_ext_sepolicy.cil" "$P/product_sepolicy.cil" \
    "$V/etc/selinux/plat_pub_versioned.cil" \
    "$V/etc/selinux/vendor_sepolicy.cil" \
    -o "$P/policy" -f /dev/null
rc=$?
echo "SECILC_EXIT=$rc"
exit $rc
