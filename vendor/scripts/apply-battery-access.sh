#!/bin/bash
# Lets adb shell read /sys/kernel/battery_monitor. See docs/Battery.md.
# Usage: apply-battery-access.sh <vendor-stage-dir>   (idempotent)
set -euo pipefail
V="${1:?usage: apply-battery-access.sh <vendor-stage-dir>}"
CIL="$V/etc/selinux/vendor_sepolicy.cil"
RC="$V/etc/init/hw/init.project.rc"
test -f "$CIL" || { echo "no vendor_sepolicy.cil under $V"; exit 1; }
test -f "$RC"  || { echo "no init.project.rc under $V"; exit 1; }

NODES="cycle_counter first_use_date first_use_predicted_date first_use_trigger
       hwks_on_boot charge_limit hysteresis_enable"
TYPES="sysfs_battery_cycle sysfs_battery_date sysfs_battery_predicted_date
       sysfs_battery_trigger sysfs_battery_hwks sysfs_charge_limit
       sysfs_hysteresis_enable"

# The types and labels already exist; add grants only.
for t in $TYPES; do
  grep -q "^(type $t)$" "$CIL" || { echo "type not declared by vendor: $t"; exit 1; }
  if ! grep -q "allow shell_31_0 $t " "$CIL"; then
    printf '(allow shell_31_0 %s (file (read getattr open)))\n' "$t" >> "$CIL"
  fi
done

# 0644: read for all, writes stay with system.
for n in $NODES; do
  grep -q "chmod 0644 /sys/kernel/battery_monitor/$n" "$RC" || \
    sed -i "/restorecon_recursive \/mnt\/vendor\/persist/i\\    chmod 0644 /sys/kernel/battery_monitor/$n" "$RC"
done

for t in $TYPES; do grep -c "allow shell_31_0 $t " "$CIL" | tr '\n' ' '; done; echo "<- grants"
grep -c 'chmod 0644 /sys/kernel/battery_monitor/' "$RC"
echo BATTERY_ACCESS_OK
