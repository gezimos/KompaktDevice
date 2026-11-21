#!/bin/bash
# The modem is not started while Offline+ is engaged.
# Booted with the switch on, the modem fails its radio self-check inside its own
# start-up (mml1_rf_error_check.c, before the mux has sent it anything),
# ccci_mdinit resets it every 14 s, the RIL daemon never starts and the phone
# process dies at its start-up timeout again and again, until the switch is
# released. MuditaOS has nothing for this either. So ccci_mdinit becomes a
# disabled service that init starts on vendor.kompakt.modem=1:
# kompakt-modem-gate.sh sets the property from the switch at boot, and
# KompaktService (OfflineWatcherService) sets it on every flip, so the modem
# starts the moment the switch is released. A flip with the modem running only
# turns the radio off, as before. See docs/Vendor.md.
# Usage: apply-offline-modem-gate.sh <vendor-stage-dir>   (idempotent)
# Edits in place so the files keep their SELinux labels; the two files it adds
# under etc/ are labelled vendor_configs_file like the rest of etc/.
set -euo pipefail
V="${1:?usage: apply-offline-modem-gate.sh <vendor-stage-dir>}"
RC="$V/etc/init/init.cccimdinit.rc"
CIL="$V/etc/selinux/vendor_sepolicy.cil"
PC="$V/etc/selinux/vendor_property_contexts"
for f in "$RC" "$CIL" "$PC"; do
  test -f "$f" || { echo "no $(basename "$f") under $V"; exit 1; }
done

# 1. ccci_mdinit is started by the property, not by its class
python3 - "$RC" <<'EOF'
import sys
rc = sys.argv[1]
s = open(rc).read()
OLD = ('service ccci_mdinit /vendor/bin/ccci_mdinit 0\n'
       '    user system\n'
       '    group radio system\n'
       '    class core\n'
       '    priority -20\n'
       '    ioprio rt 4\n'
       '    oneshot\n')
NEW = OLD + ('    # Kompakt: started by kompakt-modem.rc once Offline+ is off.\n'
             '    disabled\n')
if NEW in s:
    print('ccci_mdinit already gated')
    sys.exit(0)
assert s.count(OLD) == 1, 'anchor: the stock ccci_mdinit service not found'
s = s.replace(OLD, NEW)
with open(rc, 'r+') as f:
    f.write(s)
    f.truncate()
print('ccci_mdinit gated')
EOF

# 2. the probe at boot and the trigger
write_etc() {  # <path> <mode>, content on stdin
  cat > "$1"
  chown root:root "$1"
  chmod "$2" "$1"
  python3 -c "import os, sys; os.setxattr(sys.argv[1], 'security.selinux', b'u:object_r:vendor_configs_file:s0\0')" "$1"
}
write_etc "$V/etc/init/kompakt-modem.rc" 0644 <<'EOF'
# Kompakt: booted with Offline+ engaged, the modem fails its radio self-check
# and resets forever, so it is only started once the switch is off.
# kompakt-modem-gate.sh sets vendor.kompakt.modem from the switch at boot and
# KompaktService sets it on every flip (vendor/scripts/apply-offline-modem-gate.sh).
on boot
    exec u:r:kompakt_modem_gate:s0 root root -- /vendor/bin/sh /vendor/etc/kompakt-modem-gate.sh

on property:vendor.kompakt.modem=1
    start ccci_mdinit
EOF
write_etc "$V/etc/kompakt-modem-gate.sh" 0644 <<'EOF'
#!/vendor/bin/sh
# Kompakt: vendor.kompakt.modem is 1 while Offline+ is off; init starts the modem on it (kompakt-modem.rc).
# A switch that cannot be read counts as off: a phone must not lose its modem to a missing node.
s=0
read s < /sys/bus/platform/drivers/pmic-codec-accdet/irqkey_state
if [ "$s" = "1" ]; then m=0; else m=1; fi
exec /vendor/bin/toybox_vendor setprop vendor.kompakt.modem "$m"
EOF

# 3. the property and the probe's domain
if ! grep -qE '^vendor\.kompakt\. ' "$PC"; then
  printf '\n# Kompakt: the modem gate (apply-offline-modem-gate.sh)\nvendor.kompakt.    u:object_r:vendor_kompakt_prop:s0\n' >> "$PC"
fi
MARK=';; Kompakt: the modem gate (apply-offline-modem-gate.sh)'
if ! grep -qxF "$MARK" "$CIL"; then
cat >> "$CIL" <<'EOF'

;; Kompakt: the modem gate (apply-offline-modem-gate.sh)
;; vendor.kompakt.modem: a public vendor property, so KompaktService (system_app) may set it.
(type vendor_kompakt_prop)
(roletype object_r vendor_kompakt_prop)
(typeattributeset property_type (vendor_kompakt_prop))
(typeattributeset vendor_property_type (vendor_kompakt_prop))
(typeattributeset vendor_public_property_type (vendor_kompakt_prop))
(allow system_app_31_0 vendor_kompakt_prop (property_service (set)))
(allow system_app_31_0 vendor_kompakt_prop (file (read getattr map open)))
;; kompakt_modem_gate: /vendor/bin/sh running kompakt-modem-gate.sh from init at boot.
(type kompakt_modem_gate)
(roletype object_r kompakt_modem_gate)
(typeattributeset domain (kompakt_modem_gate))
(allow init_31_0 vendor_shell_exec_31_0 (file (read getattr map execute open)))
(allow init_31_0 kompakt_modem_gate (process (transition siginh rlimitinh)))
(dontaudit init_31_0 kompakt_modem_gate (process (noatsecure)))
(allow kompakt_modem_gate vendor_shell_exec_31_0 (file (read getattr map execute open entrypoint)))
(allow kompakt_modem_gate vendor_toolbox_exec_31_0 (file (read getattr map execute open execute_no_trans)))
(allow kompakt_modem_gate sysfs_irqkey (file (read getattr open)))
(allow kompakt_modem_gate property_socket_31_0 (sock_file (write)))
(allow kompakt_modem_gate init_31_0 (unix_stream_socket (connectto)))
(allow kompakt_modem_gate vendor_kompakt_prop (property_service (set)))
(allow kompakt_modem_gate vendor_kompakt_prop (file (read getattr map open)))
EOF
fi

# what the stage carries now
echo "ccci_mdinit_disabled=$(grep -c '^    # Kompakt: started by kompakt-modem.rc' "$RC")"
echo "modem_rc_start=$(grep -c '^    start ccci_mdinit$' "$V/etc/init/kompakt-modem.rc")"
echo "modem_gate_domain=$(grep -cx '(type kompakt_modem_gate)' "$CIL")"
echo "modem_prop_context=$(grep -cE '^vendor\.kompakt\. ' "$PC")"
test "$(grep -c '^    # Kompakt: started by kompakt-modem.rc' "$RC")" = 1
test "$(grep -c '^    start ccci_mdinit$' "$V/etc/init/kompakt-modem.rc")" = 1
test "$(grep -cx '(type kompakt_modem_gate)' "$CIL")" = 1
test "$(grep -cE '^vendor\.kompakt\. ' "$PC")" = 1
for p in "$V/etc/init/kompakt-modem.rc" "$V/etc/kompakt-modem-gate.sh"; do
  python3 -c "import os, sys; l = os.getxattr(sys.argv[1], 'security.selinux'); print('LABEL', sys.argv[1], l); sys.exit(l.rstrip(b'\0') != b'u:object_r:vendor_configs_file:s0')" "$p"
done
echo OFFLINE_MODEM_GATE_OK
