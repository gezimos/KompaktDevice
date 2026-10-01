#!/bin/bash
# Installs the patched fingerprint HAL and its ini, for scrolling by swiping
# the sensor. Key codes stay 0: the Kompakt app does the scrolling.
# Usage: apply-fp-navigator.sh <vendor-stage-dir> <stock fpsensor_fingerprint.default.so>
# Always patches the stock library, so it is idempotent.
set -euo pipefail
V="${1:?usage: apply-fp-navigator.sh <vendor-stage-dir> <stock fpsensor_fingerprint.default.so>}"
STOCK="${2:?usage: apply-fp-navigator.sh <vendor-stage-dir> <stock fpsensor_fingerprint.default.so>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SO="$V/lib64/hw/fpsensor_fingerprint.default.so"
INI="$V/etc/fpsensor_nav.ini"

label() {
    python3 - "$1" "$2" <<'EOF'
import os, sys
try:
    os.setxattr(sys.argv[1], 'security.selinux', sys.argv[2].encode() + b'\0')
except OSError as e:
    sys.exit('cannot label %s: %s' % (sys.argv[1], e))
EOF
}

python3 "$HERE/tools/patch-fp-navigator.py" "$STOCK" "$SO"
chown root:root "$SO" 2>/dev/null || true
chmod 644 "$SO"
label "$SO" u:object_r:vendor_file:s0

cat > "$INI" <<'EOF'
[fpsensor_config]
navigator=1
left_key_code=0
right_key_code=0
up_key_code=0
down_key_code=0
click_key_code=0
longpress_key_code=0
dclick_key_code=0
EOF
chown root:root "$INI" 2>/dev/null || true
chmod 644 "$INI"
label "$INI" u:object_r:vendor_configs_file:s0
echo FP_NAVIGATOR_OK
