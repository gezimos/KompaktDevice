#!/bin/bash
# Binds Mudita's orphaned vendor types to their versioned attributes
# (the missing typeattributeset lines). See docs/Battery.md.
# Usage: fix-orphaned-vendor-types.sh <vendor-stage-dir>   (idempotent)
set -euo pipefail
V="${1:?usage: fix-orphaned-vendor-types.sh <vendor-stage-dir>}"
P="$V/etc/selinux/plat_pub_versioned.cil"
test -f "$P" || { echo "no plat_pub_versioned.cil under $V"; exit 1; }
VER="$(cat "$V/etc/selinux/plat_sepolicy_vers.txt" 2>/dev/null || echo 31.0)"
SUF="${VER//./_}"

TYPES="aee_core_forwarder capability_app cmddumper connsyslogger em_app
       emdlogger em_svr mdlogger mobile_log_d mtd_device mtk_advcamserver
       mtkbootanimation mudita_service netdiag proc_battery_cmd
       proc_battery_current_cmd sysfs_headset sysfs_pmu sysfs_vbus
       system_mtk_ctl_emdlogger1_prop system_mtk_ctl_emdlogger2_prop
       system_mtk_ctl_emdlogger3_prop system_mtk_ctl_mdlogger_prop
       system_mtk_heavy_loading_prop system_mtk_init_svc_aee_aedv_prop
       system_mtk_init_svc_emdlogger1_prop system_mtk_init_svc_md_monitor_prop
       system_mtk_persist_mtk_aee_prop system_mtk_pkm_init_prop
       teeregistryd_app vtservice"

added=0
for t in $TYPES; do
  grep -q "^(type $t)$" "$P" || { echo "not declared, skipping: $t"; continue; }
  if ! grep -q "^(typeattributeset ${t}_${SUF} ($t))$" "$P"; then
    printf '(typeattributeset %s_%s (%s))\n' "$t" "$SUF" "$t" >> "$P"
    added=$((added+1))
  fi
done
echo "associations_added=$added"

# Lets init chmod the e-ink nodes in init.project.rc.
C="$V/etc/selinux/vendor_sepolicy.cil"
for rule in \
  "(allow init_${SUF} sysfs_eink_misc (file (setattr)))" \
  "(allow init_${SUF} sysfs_eink_param (file (setattr)))" \
  "(allow init_${SUF} sysfs_eink_param (dir (search)))" ; do
  grep -qF "$rule" "$C" || printf '%s\n' "$rule" >> "$C"
done

echo "Verify by compiling the full policy the way init does, then on device:"
echo "  logcat -b all | grep 'avc:  denied' | grep mtk_battery_cmd   # must be empty"
echo ORPHANED_TYPES_OK
