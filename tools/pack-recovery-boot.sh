#!/bin/bash
# Packs a boot.img with LineageOS recovery for the Kompakt.
#
#   tools/pack-recovery-boot.sh <lineage-tree> <kernel Image.gz> <dtb> <out.img>
#
# Build the device target first (lunch lineage_kompakt-bp4a-userdebug; m bootimage).
set -euo pipefail
L=${1:?lineage tree}; KERNEL=${2:?kernel Image.gz}; DTB=${3:?dtb}; OUT=${4:?output boot.img}
O=$L/out/target/product/kompakt
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in system/bin/recovery system/bin/fastbootd system/bin/update_engine_sideload system/bin/adbd \
         system/bin/hw/android.hardware.boot-service.default_recovery; do
  test -e "$O/recovery/root/$f" || fail "recovery root has no $f; build the device target first"
done
cp -a "$O/recovery/root" "$W/root"

# not needed on an all-ext4 phone
for f in system/bin/nano system/lib64/libncurses_recovery.so system/bin/sload_f2fs \
         system/bin/make_f2fs system/bin/mkfs.erofs system/bin/fsck.erofs system/bin/dump.erofs; do
  rm -f "$W/root/$f"
done

# The ramdisk's own meink.ko gets the same pictures as the vendor copy.
HERE=$(cd "$(dirname "$0")/.." && pwd)
MK=$W/root/lib/modules/meink.ko
python3 "$HERE/tools/sleepimg.py" patch "$MK" --logo "$HERE/assets/boot-logo.jpg" \
  --lock "$HERE/assets/sleep-default.jpg" --poweroff "$HERE/assets/power-off.png" \
  --no-dither -o "$W/meink.ko" > /dev/null || fail "meink pictures"
test "$(stat -c %s "$W/meink.ko")" = "$(stat -c %s "$MK")" || fail "meink.ko changed size"
cp "$W/meink.ko" "$MK"

"$L/out/host/linux-x86/bin/mkbootfs" -d "$O/system" "$W/root" > "$W/rd.cpio"
if command -v pigz > /dev/null; then pigz -11 -n -c "$W/rd.cpio" > "$W/ramdisk"
else gzip -9 -n -c "$W/rd.cpio" > "$W/ramdisk"; fi
gzip -dc "$W/ramdisk" | cmp - "$W/rd.cpio" || fail "ramdisk round trip"

# The header, offsets and command line of Mudita's boot image.
python3 "$L/system/tools/mkbootimg/mkbootimg.py" \
  --kernel "$KERNEL" --ramdisk "$W/ramdisk" --dtb "$DTB" \
  --header_version 2 --base 0x40000000 --pagesize 2048 \
  --kernel_offset 0x00080000 --ramdisk_offset 0x11b00000 \
  --tags_offset 0x07880000 --dtb_offset 0x07880000 \
  --os_version 12.0.0 --os_patch_level 2026-07 \
  --cmdline "bootopt=64S3,32N2,64N2 buildvariant=user" \
  -o "$OUT"
"$L/out/host/linux-x86/bin/avbtool" add_hash_footer --image "$OUT" \
  --partition_name boot --partition_size 33554432 --algorithm NONE

python3 "$L/system/tools/mkbootimg/unpack_bootimg.py" --boot_img "$OUT" --out "$W/check" > /dev/null
cmp -s "$W/check/kernel" "$KERNEL" || fail "kernel differs after packing"
cmp -s "$W/check/dtb" "$DTB" || fail "dtb differs after packing"
echo "RAMDISK_SIZE=$(stat -c %s "$W/ramdisk")"
echo "BOOT_MD5=$(md5sum "$OUT" | cut -d' ' -f1)"
echo PACK_OK
