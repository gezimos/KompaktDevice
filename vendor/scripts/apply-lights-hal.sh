#!/bin/bash
# The notification LED through LineageOS's own lights HAL.
# MediaTek's closed HAL lights one channel at a time and never breathes. Its
# binary is replaced by android.hardware.light-service.kompakt (KompaktOS
# patch hardware_lineage_interfaces/0001: LineageOS's service with libbase,
# libc++ and the light-V2 NDK linked in, since this vendor's VNDK is v31).
# The path stays, so the stock init rc (vendor.light-default, user system),
# the VINTF fragment (ILights/default) and the file label (mtk_hal_light_exec,
# in hal_light_server, which the platform policy lets write sysfs_leds) all
# carry over unchanged.
# The kernel side is kernel patch 0027: brightness levels and the timed nodes
# blink, start_idx, duty_pcts, pause_lo, pause_hi, ramp_step_ms. The kernel
# creates them 0664 root; the HAL runs as system, so they are chowned at boot.
# Usage: apply-lights-hal.sh <vendor-stage-dir> <android.hardware.light-service.kompakt>
# (idempotent). Edits in place so the files keep their SELinux labels.
set -euo pipefail
V="${1:?usage: apply-lights-hal.sh <vendor-stage-dir> <hal binary>}"
HAL="${2:?usage: apply-lights-hal.sh <vendor-stage-dir> <hal binary>}"
BIN="$V/bin/hw/android.hardware.lights-service.mediatek"
RC="$V/etc/init/hw/init.project.rc"

test -f "$HAL" || { echo "no HAL binary at $HAL"; exit 1; }
test -f "$BIN" || { echo "no MediaTek lights HAL under $V"; exit 1; }
test -f "$RC" || { echo "no init.project.rc under $V"; exit 1; }

# gate: the stock wiring the binary inherits
grep -qx "service vendor.light-default /vendor/bin/hw/android.hardware.lights-service.mediatek" \
  "$V/etc/init/lights-mtk-default.rc" || { echo "GATE_LIGHTS_RC"; exit 1; }
grep -q "<fqname>ILights/default</fqname>" "$V/etc/vintf/manifest/lights-mtk-default.xml" \
  || { echo "GATE_LIGHTS_VINTF"; exit 1; }
grep -F '/bin/hw/android\.hardware\.lights-service\.mediatek ' "$V/etc/selinux/vendor_file_contexts" \
  | grep -q ' u:object_r:mtk_hal_light_exec:s0$' || { echo "GATE_LIGHTS_FILE_CONTEXT"; exit 1; }
grep -qF "(typeattributeset hal_light_server (hal_light_default merged_hal_service mtk_hal_light))" \
  "$V/etc/selinux/vendor_sepolicy.cil" || { echo "GATE_LIGHTS_DOMAIN"; exit 1; }

# gate: the Kompakt build of the service, needing nothing this vendor lacks
grep -qa "android.hardware.light-service.lineage" "$HAL" || { echo "GATE_HAL_NOT_LINEAGE"; exit 1; }
for lib in libc++.so libbase.so android.hardware.light-V2-ndk.so; do
  if grep -qa "$lib" "$HAL"; then echo "GATE_HAL_NEEDS_$lib"; exit 1; fi
done

if cmp -s "$HAL" "$BIN"; then
  echo "lights HAL already the LineageOS one"
else
  cat "$HAL" > "$BIN"
  echo "lights HAL replaced ($(stat -c %s "$BIN") bytes)"
fi
python3 - "$BIN" <<'EOF'
import os, sys
label = os.getxattr(sys.argv[1], 'security.selinux')
print('LABEL', sys.argv[1], label)
if label.rstrip(b'\0') != b'u:object_r:mtk_hal_light_exec:s0':
    sys.exit('GATE_HAL_LABEL_LOST')
EOF

python3 - "$RC" <<'EOF'
import sys
rc = sys.argv[1]
MARK = '    # Kompakt: the notification LED nodes the lights HAL writes (apply-lights-hal.sh).\n'
NODES = ['brightness', 'blink', 'start_idx', 'duty_pcts', 'pause_lo', 'pause_hi', 'ramp_step_ms']
s = open(rc).read()
if MARK in s:
    print('LED nodes already handed to system')
    sys.exit(0)
block = '\non boot\n' + MARK
for c in ('red', 'green', 'blue'):
    for n in NODES:
        block += '    chown system system /sys/class/leds/%s/%s\n' % (c, n)
        block += '    chmod 0664 /sys/class/leds/%s/%s\n' % (c, n)
if not s.endswith('\n'):
    s += '\n'
with open(rc, 'r+') as f:
    f.write(s + block)
    f.truncate()
print('LED nodes handed to system')
EOF

N=$(grep -cE "^    chown system system /sys/class/leds/(red|green|blue)/(brightness|blink|start_idx|duty_pcts|pause_lo|pause_hi|ramp_step_ms)$" "$RC")
echo "led_chowns=$N/21"
test "$N" = 21
cmp -s "$HAL" "$BIN"
echo LIGHTS_HAL_OK
