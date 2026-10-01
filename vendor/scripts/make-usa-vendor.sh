#!/bin/bash
# The USA edition of our vendor: the same stage with the files Mudita builds per
# modem region taken from the stock USA vendor. The VoLTE stack, modem apps and
# Wi-Fi calling tunnel must match the modem (USA V236.P6, Global V236.P8), or
# IMS never registers on a North American phone.
#
# Usage: make-usa-vendor.sh <global stage> <stock USA vendor root> <stock Global vendor root> <out stage>
# The global stage must already carry our changes (build-vendor.sh). Only files
# that differ between the two stock vendors are swapped, and only if ours still
# equals Mudita's Global copy, so none of our edits can be overwritten.
set -euo pipefail
STAGE=${1:?global stage}; USA=${2:?stock USA vendor}; GLO=${3:?stock Global vendor}; OUT=${4:?out stage}

rm -rf "$OUT"
cp -a --preserve=all "$STAGE" "$OUT"

list=$(mktemp)
(cd "$USA" && find . -type f | sort) | while read -r f; do
  [ -f "$GLO/$f" ] || continue
  cmp -s "$USA/$f" "$GLO/$f" && continue
  # build.prop only differs by fingerprint and property_contexts by a comment.
  case "$f" in *build.prop|*vendor_property_contexts) continue ;; esac
  echo "$f"
done > "$list"

n=0
while read -r f; do
  cmp -s "$STAGE/$f" "$GLO/$f" || { echo "ours changed $f, refusing to replace it"; exit 1; }
  label=$(getfattr -n security.selinux --only-values "$OUT/$f")
  cp "$USA/$f" "$OUT/$f"
  chown root:root "$OUT/$f"
  chmod --reference="$STAGE/$f" "$OUT/$f"
  setfattr -n security.selinux -v "$label" "$OUT/$f"
  n=$((n + 1))
done < "$list"
rm -f "$list"

grep -q "V236.P6" "$OUT/etc/init/init.md_apps.rc" || { echo "modem apps are not the USA ones"; exit 1; }
echo "USA_FILES=$n"
