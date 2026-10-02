#!/bin/bash
# Takes mass storage out of the adb + serial (adb_acm) USB configuration.
# Its unused file-storage thread can panic the kernel at plug-in.
# adb moves into the freed f1: Android's init.usb.configfs.rc links adb as f1
# for the same trigger, and a second adb link breaks adb in a reset loop.
# Usage: apply-usb-no-mass-storage.sh <vendor-stage-dir>   (idempotent)
# Edits in place so the file keeps its SELinux label.
set -euo pipefail
V="${1:?usage: apply-usb-no-mass-storage.sh <vendor-stage-dir>}"
RC="$V/etc/init/hw/init.mt6761.usb.rc"

python3 - "$RC" <<'EOF'
import sys
p = sys.argv[1]
HEAD = ('on property:sys.usb.ffs.ready=1 && property:sys.usb.config=adb && \\\n'
        'property:vendor.usb.acm_enable=1 && property:sys.usb.configfs=1\n')
LINK = ('    symlink /config/usb_gadget/g1/functions/mass_storage.usb0 '
        '/config/usb_gadget/g1/configs/b.1/f1\n')
NOTE = ('    # Kompakt: no mass storage here; its thread panicked the kernel at\n'
        '    # plug-in (KompaktDevice vendor/scripts/apply-usb-no-mass-storage.sh).\n')
ADB2 = '    symlink /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f2\n'
ADB1 = '    symlink /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f1\n'

with open(p, 'r+') as f:
    s = f.read()
    if s.count(HEAD) != 1:
        sys.exit('expected one adb_acm block, found %d' % s.count(HEAD))
    start = s.index(HEAD) + len(HEAD)
    end = s.index('\n\n', start)
    block = s[start:end + 1]
    if 'Kompakt: no mass storage here' not in block:
        if block.count(LINK) != 1:
            sys.exit('mass storage link not found in the adb_acm block')
        block = block.replace(LINK, NOTE)
    if ADB1 in block:
        print('USB_ADB_ACM already without mass storage, adb as f1')
        sys.exit(0)
    if block.count(ADB2) != 1:
        sys.exit('adb link not found in the adb_acm block')
    block = block.replace(ADB2, ADB1)
    s = s[:start] + block + s[end + 1:]
    f.seek(0)
    f.write(s)
    f.truncate()
print('USB_ADB_ACM mass storage removed, adb as f1')
EOF
