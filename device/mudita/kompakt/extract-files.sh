#!/bin/bash
#
# Pull the proprietary blobs out of an unpacked stock vendor.img, not a device.
#
#   ./extract-files.sh /tmp/vendor
#
set -e

SRC="${1:?usage: extract-files.sh <unpacked vendor.img>}"
DEVICE=kompakt
VENDOR=mudita
OUT="$(cd "$(dirname "$0")"/../../../vendor/"$VENDOR"/"$DEVICE" 2>/dev/null && pwd \
      || echo "$(dirname "$0")/../../../vendor/$VENDOR/$DEVICE")"
LIST="$(dirname "$0")/proprietary-files.txt"

mkdir -p "$OUT/proprietary"
n=0
while read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    rel="${line#vendor/}"
    src="$SRC/$rel"
    if [ ! -f "$src" ]; then
        echo "missing: $rel" >&2
        continue
    fi
    mkdir -p "$OUT/proprietary/vendor/$(dirname "$rel")"
    cp -a "$src" "$OUT/proprietary/vendor/$rel"
    n=$((n + 1))
done < "$LIST"
echo "extracted $n files to $OUT/proprietary"
