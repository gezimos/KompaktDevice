#!/bin/bash
# Opens the e-ink sysfs nodes and meink_hal module parameters to adb shell and
# KompaktService. See docs/Vendor.md.
# Usage: apply-eink-access.sh <vendor-stage-dir>   (idempotent)
# Edits in place so the files keep their SELinux labels.
# A new module_param needs a name in PARAMS.
set -euo pipefail
V="${1:?usage: apply-eink-access.sh <vendor-stage-dir>}"
RC="$V/etc/init/hw/init.project.rc"
CIL="$V/etc/selinux/vendor_sepolicy.cil"
test -f "$RC" || { echo "no init.project.rc under $V"; exit 1; }
test -f "$CIL" || { echo "no vendor_sepolicy.cil under $V"; exit 1; }

GENFS='(genfscon sysfs /einkinfo/sleep_image (u object_r sysfs_eink_misc ((s0) (s0))))'
if ! grep -qxF "$GENFS" "$CIL"; then
  python3 - "$CIL" "$GENFS" <<'EOF'
import sys
cil, line = sys.argv[1], sys.argv[2]
s = open(cil).read()
anchor = '(genfscon sysfs /einkinfo/log_level (u object_r sysfs_eink_misc ((s0) (s0))))\n'
assert s.count(anchor) == 1, 'anchor: the einkinfo/log_level genfscon not found'
s = s.replace(anchor, anchor + line + '\n')
with open(cil, 'r+') as f:
    f.write(s)
    f.truncate()
EOF
fi

NODES="dither_type dither_param dither_colors eink_temperature temperature_offset
       refresh_time refresh_mode manual_mode sleep_image"
PARAMS="trace measure deghost_every partial partial_max_pct partial_full_every
        semi_partial semi_window auto_busy_pct auto_busy_frames auto_idle_ms"

python3 - "$RC" "$NODES" "$PARAMS" <<'EOF'
import sys
rc, nodes, params = sys.argv[1], sys.argv[2].split(), sys.argv[3].split()
s = open(rc).read()
NODE = '    chmod 0666 /sys/einkinfo/'
PARAM = '    chmod 0666 /sys/module/meink_hal/parameters/'
ANCHOR = NODE + 'power\n'
assert s.count(ANCHOR) == 1, 'anchor: Mudita einkinfo/power chmod not found'

def insert_after(s, prefix, names, fallback, header):
    missing = [n for n in names if prefix + n + '\n' not in s]
    if not missing:
        return s, 0
    lines = ''.join(prefix + n + '\n' for n in missing)
    present = [s.index(prefix + n + '\n') + len(prefix + n + '\n')
               for n in names if n not in missing]
    if present:
        at = max(present)
    else:
        at = s.index(fallback) + len(fallback)
        lines = header + lines
    return s[:at] + lines + s[at:], len(missing)

s, a = insert_after(s, NODE, nodes, ANCHOR,
    '    # Kompakt: the four chmods above name nodes that do not exist. The driver\n'
    '    # calls them dither_type, dither_param and dither_colors, not dithering_*,\n'
    '    # so those three were left 0664 and only the owner could write them.\n'
    '    # eink_temperature was never listed at all.\n')
node_end = NODE + nodes[-1] + '\n'
s, b = insert_after(s, PARAM, params, node_end,
    '\n'
    '    # Kompakt: the e-ink tunables, so a threshold can be tested over adb instead\n'
    '    # of costing a build. SELinux still gates these to shell and system_app via\n'
    '    # sysfs_eink_param; module_param cannot declare them world writable itself,\n'
    '    # because VERIFY_OCTAL_PERMISSIONS rejects the write bit at compile time.\n'
    '    # A new module_param needs a line here.\n')
if a or b:
    with open(rc, 'r+') as f:
        f.write(s)
        f.truncate()
print(f'nodes_added={a} params_added={b}')
EOF

N=$(for n in $NODES;  do grep -c "chmod 0666 /sys/einkinfo/$n\$" "$RC"; done | grep -c '^1$')
P=$(for p in $PARAMS; do grep -c "chmod 0666 /sys/module/meink_hal/parameters/$p\$" "$RC"; done | grep -c '^1$')
echo "nodes=$N/$(echo $NODES | wc -w) params=$P/$(echo $PARAMS | wc -w)"
test "$N" = "$(echo $NODES | wc -w)" && test "$P" = "$(echo $PARAMS | wc -w)"
G=$(grep -cxF "$GENFS" "$CIL")
echo "sleep_image genfscon=$G"
test "$G" = "1"
echo EINK_ACCESS_OK
