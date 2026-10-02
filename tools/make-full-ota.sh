#!/bin/bash
# Builds a full A/B update package for the Kompakt from the images we flash by
# hand, for adb sideload from our LineageOS recovery.
#
#   tools/make-full-ota.sh <lineage-tree> <signing key, no extension> <out.zip> \
#       boot.img dtbo.img vbmeta.img system.img vendor.img product.img
#
# Needs m otatools. The key is the release key our recovery trusts.
set -euo pipefail
L=${1:?lineage tree}; KEY=${2:?key}; OUT=${3:?out.zip}
BOOT=${4:?boot}; DTBO=${5:?dtbo}; VBMETA=${6:?vbmeta}; SYSTEM=${7:?system}; VENDOR=${8:?vendor}
PRODUCT=${9:?product}
H=$L/out/host/linux-x86
W=$(mktemp -d); T=$W/tf
trap 'rm -rf "$W"' EXIT
mkdir -p $T/IMAGES $T/META $T/SYSTEM $T/VENDOR $T/PRODUCT/etc

cp "$BOOT" $T/IMAGES/boot.img
cp "$DTBO" $T/IMAGES/dtbo.img
cp "$VBMETA" $T/IMAGES/vbmeta.img
cp "$SYSTEM" $T/IMAGES/system.img
cp "$VENDOR" $T/IMAGES/vendor.img
cp "$PRODUCT" $T/IMAGES/product.img
printf '%s\n' boot dtbo product system vbmeta vendor > $T/META/ab_partitions.txt

# Mudita's super layout: one group, plain virtual A/B. No compression: with an
# Android 12 vendor, a compressed update needs early boot to mount it through
# snapuserd in legacy mode, and slot B never booted that way. Plain snapshots
# are the kernel's own dm-snapshot.
DYN='use_dynamic_partitions=true
dynamic_partition_list=system vendor product
super_partition_groups=mudita_dynamic_partitions
super_mudita_dynamic_partitions_group_size=5366611968
super_mudita_dynamic_partitions_partition_list=system vendor product
virtual_ab=true'
echo "$DYN" > $T/META/dynamic_partitions_info.txt
cat > $T/META/misc_info.txt <<EOF
recovery_api_version=3
fstab_version=2
ab_update=true
avb_enable=false
super_block_devices=super
super_super_device_size=5368709120
$DYN
EOF
: > $T/META/postinstall_config.txt
cp $L/system/update_engine/update_engine.conf $T/META/update_engine_config.txt

debugfs -R "dump /system/build.prop $T/SYSTEM/build.prop" "$SYSTEM" 2>/dev/null
debugfs -R "dump /build.prop $T/VENDOR/build.prop" "$VENDOR" 2>/dev/null
debugfs -R "dump /etc/build.prop $T/PRODUCT/etc/build.prop" "$PRODUCT" 2>/dev/null
for f in $T/SYSTEM/build.prop $T/VENDOR/build.prop $T/PRODUCT/etc/build.prop; do
  test -s $f || { echo "no build.prop at $f" >&2; exit 1; }
done
FP=$(grep "^ro.build.fingerprint=" $T/SYSTEM/build.prop | cut -d= -f2-)
INC=$(grep "^ro.build.version.incremental=" $T/SYSTEM/build.prop | cut -d= -f2-)
NOW=$(date +%s)
# recovery checks the device name; the date must not read as a downgrade;
# treble off skips a VINTF check this hand-made set cannot pass
cat >> $T/SYSTEM/build.prop <<EOF
ro.treble.enabled=false
ro.product.device=Kompakt
ro.product.name=Kompakt
ro.build.date.utc=$NOW
ro.system.build.date.utc=$NOW
ro.system.build.fingerprint=$FP
ro.system.build.version.incremental=$INC
EOF
# Every partition gets the package date, or the installer rejects it as older.
echo "ro.vendor.build.date.utc=$NOW" >> $T/VENDOR/build.prop
echo "ro.product.build.date.utc=$NOW" >> $T/PRODUCT/etc/build.prop

(cd $T && zip -q -0 -r $W/target_files.zip .)
PATH=$H/bin:$PATH ota_from_target_files -p $H -k "$KEY" --skip_postinstall \
  $W/target_files.zip "$OUT"
unzip -p "$OUT" META-INF/com/android/metadata
echo "OTA_MD5=$(md5sum "$OUT" | cut -d' ' -f1)"
echo OTA_OK
