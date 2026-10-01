#!/bin/bash
# Stamps the build number into the vendor stage for the Kompakt app.
# Usage: stamp-build-number.sh <vendor-stage-dir> <build number>   (idempotent)
# Uses ro.vendor.build.version.incremental: apps can read it; a new
# ro.vendor.* property would be denied to them.
set -euo pipefail
V="${1:?usage: stamp-build-number.sh <vendor-stage-dir> <build number>}"
N="${2:?usage: stamp-build-number.sh <vendor-stage-dir> <build number>}"
[[ "$N" =~ ^[0-9]+$ ]] || { echo "build number must be digits: $N" >&2; exit 1; }
P="$V/build.prop"

# Edit in place, not sed -i: a new file would lose its SELinux label.
python3 - "$P" "$N" <<'EOF'
import re, sys
p, n = sys.argv[1], sys.argv[2]
with open(p, 'r+') as f:
    s = re.sub(r'(?m)^ro\.vendor\.build\.version\.incremental=.*$',
               'ro.vendor.build.version.incremental=kompakt-' + n, f.read())
    f.seek(0)
    f.write(s)
    f.truncate()
EOF
grep -qx "ro.vendor.build.version.incremental=kompakt-$N" "$P" || {
    echo "build.prop has no ro.vendor.build.version.incremental line to stamp" >&2
    exit 1
}
echo "STAMPED ro.vendor.build.version.incremental=kompakt-$N"
