#!/bin/bash
# Installs the open e-ink driver (kernel patch 0035) into a vendor stage: the
# three modules, the modprobe line that picks its mode, the boot_ok write that
# ends a shadow or open boot, and the policy for both. See docs/E-inkdriver.md.
# Usage: apply-open-eink.sh <vendor-stage-dir> <dir with the 0035 modules> <meink|shadow|open|off>
#   the module dir holds kompakt_eink-0035.ko, meink_hal-0035.ko, meink_loader-0035.ko
#   off (the open driver parked): installs meink_hal and meink_loader only and removes
#   every trace an earlier shadow or open install left in the stage
# (idempotent; edits in place so the files keep their SELinux labels)
set -euo pipefail
V="${1:?usage: apply-open-eink.sh <vendor-stage-dir> <module dir> <meink|shadow|open|off>}"
K="${2:?usage: apply-open-eink.sh <vendor-stage-dir> <module dir> <meink|shadow|open|off>}"
MODE="${3:?usage: apply-open-eink.sh <vendor-stage-dir> <module dir> <meink|shadow|open|off>}"
case "$MODE" in meink|shadow|open|off) ;; *) echo "mode must be meink, shadow, open or off"; exit 1;; esac
RC="$V/etc/init/hw/init.project.rc"
CIL="$V/etc/selinux/vendor_sepolicy.cil"
DEP="$V/lib/modules/modules.dep"
PROP="$V/build.prop"
for f in "$RC" "$CIL" "$DEP" "$PROP"; do test -f "$f" || { echo "no $f"; exit 1; }; done

# The modules: the driver, and the HAL and loader that know about it.
MODS="kompakt_eink meink_hal meink_loader"
[ "$MODE" = off ] && MODS="meink_hal meink_loader"
for m in $MODS; do
  test -f "$K/$m-0035.ko" || { echo "no $K/$m-0035.ko"; exit 1; }
  grep -qa "vermagic=4.19.191-00095-g83b1ab1a9a4b-dirty" "$K/$m-0035.ko" || { echo "$m: wrong vermagic"; exit 1; }
  cp "$K/$m-0035.ko" "$V/lib/modules/$m.ko"
  chown root:root "$V/lib/modules/$m.ko"; chmod 644 "$V/lib/modules/$m.ko"
  python3 -c "import os;os.setxattr('$V/lib/modules/$m.ko', b'security.selinux', b'u:object_r:vendor_file:s0\0')"
done

[ "$MODE" = off ] && rm -f "$V/lib/modules/kompakt_eink.ko"
python3 - "$RC" "$CIL" "$DEP" "$PROP" "$MODE" <<'EOF'
import sys
rc, cil, dep, prop, mode = sys.argv[1:]

def edit(path, fn):
    s = open(path).read()
    t = fn(s)
    if t != s:
        with open(path, 'r+') as f:
            f.write(t)
            f.truncate()

# Loaded after meink, which it reads and falls back to, and before the loader, which probes the panel.
def rc_fn(s):
    meink = '    exec u:r:vendor_modprobe:s0 -- /vendor/bin/modprobe -d /vendor/lib/modules meink.ko\n'
    ours = '    exec u:r:vendor_modprobe:s0 -- /vendor/bin/modprobe -d /vendor/lib/modules kompakt_eink.ko driver=${ro.vendor.kompakt.eink:-meink}\n'
    ok = ('\n# Kompakt: the open e-ink driver: this boot completed, so the next one keeps its mode\n'
          'on property:sys.boot_completed=1\n'
          '    write /sys/module/kompakt_eink/parameters/boot_ok 1\n')
    if mode == 'off':
        return s.replace(ours, '').replace(ok, '\n')
    if ours not in s:
        assert s.count(meink) == 1, 'anchor: the meink.ko modprobe line'
        s = s.replace(meink, meink + ours)
    if ok not in s:
        s = s.rstrip('\n') + '\n' + ok
    return s

# boot_ok is written by vendor_init; the boot flag lives in /metadata and the kernel writes it.
CIL_LINES = [
    '(genfscon sysfs /module/kompakt_eink/parameters (u object_r sysfs_eink_param ((s0) (s0))))',
    '(allow vendor_init_31_0 sysfs_eink_param (file (write open getattr)))',
    '(allow kernel_31_0 metadata_file_31_0 (dir (search getattr open read write add_name remove_name)))',
    '(allow kernel_31_0 metadata_file_31_0 (file (create open read write getattr setattr append unlink)))',
]
# The kompakt_eink parameters and the fallback file in /metadata; sysfs_eink_param stays for meink_hal.
OFF_CIL = CIL_LINES[:1] + CIL_LINES[2:]

def cil_fn(s):
    if mode == 'off':
        return '\n'.join(l for l in s.split('\n') if l not in OFF_CIL)
    lines = s.split('\n')
    for l in CIL_LINES:
        if l not in lines:
            s = s.rstrip('\n') + '\n' + l + '\n'
            lines = s.split('\n')
    return s

def dep_fn(s):
    line = '/vendor/lib/modules/kompakt_eink.ko: /vendor/lib/modules/meink_hal.ko'
    if mode == 'off':
        return '\n'.join(l for l in s.split('\n') if l != line)
    if line not in s.split('\n'):
        s = s.rstrip('\n') + '\n' + line + '\n'
    return s

def prop_fn(s):
    lines = [l for l in s.rstrip('\n').split('\n') if not l.startswith('ro.vendor.kompakt.eink=')]
    if mode == 'off':
        return '\n'.join(lines) + '\n'
    return '\n'.join(lines) + '\nro.vendor.kompakt.eink=' + mode + '\n'

edit(rc, rc_fn)
edit(cil, cil_fn)
edit(dep, dep_fn)
edit(prop, prop_fn)
EOF

if [ "$MODE" = off ]; then
  grep -q "kompakt_eink" "$RC" "$DEP" "$PROP" && { echo "off: kompakt_eink still referenced"; exit 1; }
  test -e "$V/lib/modules/kompakt_eink.ko" && { echo "off: module still in stage"; exit 1; }
else
grep -c "kompakt_eink.ko driver=" "$RC" | grep -qx 1 || { echo "rc: modprobe line"; exit 1; }
grep -c "kompakt_eink/parameters/boot_ok" "$RC" | grep -qx 1 || { echo "rc: boot_ok"; exit 1; }
grep -qx "ro.vendor.kompakt.eink=$MODE" "$PROP" || { echo "build.prop: mode"; exit 1; }
fi
echo "APPLY_OPEN_EINK_OK mode=$MODE"
