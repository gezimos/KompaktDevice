#!/bin/bash
# Lets the Kompakt app write the kernel's camera flag (cameragpio_state), labelled like irqkey_state.
# Usage: apply-camera-switch-access.sh <vendor-stage-dir>   (idempotent)
set -euo pipefail
V="${1:?usage: apply-camera-switch-access.sh <vendor-stage-dir>}"
CIL="$V/etc/selinux/vendor_sepolicy.cil"
RC="$V/etc/init/hw/init.project.rc"
test -f "$CIL" || { echo "no vendor_sepolicy.cil under $V"; exit 1; }
test -f "$RC"  || { echo "no init.project.rc under $V"; exit 1; }

# sysfs_irqkey already lets system_app write; the node only needs the same label.
grep -q "^(type sysfs_irqkey)$" "$CIL" || { echo "type not declared by vendor: sysfs_irqkey"; exit 1; }
GENFS='(genfscon sysfs /bus/platform/drivers/pmic-codec-accdet/cameragpio_state (u object_r sysfs_irqkey ((s0) (s0))))'
ANCHOR='(genfscon sysfs /bus/platform/drivers/pmic-codec-accdet/irqkey_state (u object_r sysfs_irqkey ((s0) (s0))))'
test "$(grep -cF "$ANCHOR" "$CIL")" = 1 || { echo "anchor: the irqkey_state genfscon not found"; exit 1; }
if ! grep -qF "$GENFS" "$CIL"; then
  python3 - "$CIL" "$ANCHOR" "$GENFS" <<'PY'
import sys
p, anchor, add = sys.argv[1:4]
s = open(p).read()
assert s.count(anchor) == 1
open(p, "w").write(s.replace(anchor, anchor + "\n" + add, 1))
PY
fi
grep -q "chmod 0666 /sys/bus/platform/drivers/pmic-codec-accdet/cameragpio_state" "$RC" || { echo "init.project.rc no longer opens cameragpio_state"; exit 1; }

echo "cameragpio genfscon=$(grep -cF "$GENFS" "$CIL")"
echo CAMERA_SWITCH_ACCESS_OK
