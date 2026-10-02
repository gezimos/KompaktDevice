#!/bin/bash
# Puts our boot logo, default sleep screen and power-off screen into meink.ko
# in the vendor stage. See docs/Images.md.
# Usage: apply-boot-logo.sh <vendor-stage-dir> <stock meink.ko> [logo] [sleep] [power-off]
# Always starts from the stock module, so it is idempotent.
set -euo pipefail
U="usage: apply-boot-logo.sh <vendor-stage-dir> <stock meink.ko> [logo image] [sleep image] [power-off image]"
V="${1:?$U}"
STOCK="${2:?$U}"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
IMG="${3:-$HERE/assets/boot-logo.jpg}"
SLEEP="${4:-$HERE/assets/sleep-default.jpg}"
OFF="${5:-$HERE/assets/power-off.png}"
OUT="$V/lib/modules/meink.ko"
test -f "$STOCK" || { echo "no stock meink.ko at $STOCK"; exit 1; }
test "$(stat -c %s "$STOCK" 2>/dev/null || stat -f %z "$STOCK")" = "7463280" || { echo "not the 1.6.0 meink.ko"; exit 1; }

python3 "$HERE/tools/sleepimg.py" patch "$STOCK" --logo "$IMG" --lock "$SLEEP" --poweroff "$OFF" --no-dither -o "$OUT"
chown root:root "$OUT" 2>/dev/null || true
chmod 644 "$OUT"
python3 - "$OUT" <<'EOF'
import os, sys
try:
    os.setxattr(sys.argv[1], 'security.selinux', b'u:object_r:vendor_file:s0\0')
except OSError as e:
    sys.exit('cannot label %s: %s' % (sys.argv[1], e))
EOF
echo BOOT_LOGO_OK
