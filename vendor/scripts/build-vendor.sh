#!/bin/bash
# Builds vendor.img from a labelled stage. See docs/Vendor.md.
#
#   WORK=<dir> LINEAGE=<tree> SYSTEM_IMG=<system.img> \
#       vendor/scripts/build-vendor.sh <build number>
#
# WORK holds the inputs and receives vendor-<build number>.img and its log:
#   vstage2/                    the labelled stage (STAGE= to use another)
#   vendorx/                    the stock vendor, extracted, for comparison
#   meink_loader-poweroff.ko    our meink_loader build
#   meink_hal-217.ko            the meink_hal the stage must carry
#   meink-kompakt-pictures.ko   meink.ko with our pictures (apply-boot-logo.sh)
# SYSTEM_IMG is the system image this vendor ships with; its policy is compiled
# together with the vendor's.
BN=${1:?usage: build-vendor.sh <build number>}
W=${WORK:?set WORK to the folder with the stage and inputs}
L=${LINEAGE:?set LINEAGE to a built LineageOS tree}
SYS=${SYSTEM_IMG:?set SYSTEM_IMG to the system image this vendor ships with}
V=${STAGE:-$W/vstage2}
HERE=$(cd "$(dirname "$0")/../.." && pwd)
exec > $W/vendor$BN.log 2>&1
set -euxo pipefail
export V
AVB=$L/out/host/linux-x86/bin/avbtool
KO=$W/meink_loader-poweroff.ko
IMG=$W/vendor-$BN.img

# gate: loader build and vermagic
grep -qa "kompakt-sleepimg" $KO || { echo GATE_LOADER_NOT_SLEEPIMG; exit 1; }
grep -qa "hook wrapped after EinkInit" $KO || { echo GATE_LOADER_NO_HOLD; exit 1; }
grep -qa "kompakt-poweroff" $KO || { echo GATE_LOADER_NO_POWEROFF_HOOK; exit 1; }
grep -qa "vermagic=4.19.191-00095-g83b1ab1a9a4b-dirty" $KO || { echo GATE_VERMAGIC; exit 1; }
# gate: meink_hal.ko unchanged
test "$(md5sum < $V/lib/modules/meink_hal.ko)" = "$(md5sum < $W/meink_hal-217.ko)" || { echo GATE_HAL_NOT_217; exit 1; }
# gate: meink.ko from apply-boot-logo.sh, only picture bytes changed
KL=$W/meink-kompakt-pictures.ko
test "$(md5sum < $KL | cut -d' ' -f1)" = "e6e0eb22b4ac73fd1d38555e9ed5fb84" || { echo GATE_LOGO_KO_MD5; exit 1; }
test "$(stat -c %s $KL)" = "7463280" || { echo GATE_LOGO_KO_SIZE; exit 1; }
(cmp -l $W/vendorx/lib/modules/meink.ko $KL || true) | awk '{ p=$1-1; if (!((p >= 1267592 && p < 1267592+1536000) || (p >= 2803592 && p < 2803592+1536000) || (p >= 5877512 && p < 5877512+1536000))) bad++ } END { print "LOGO_KO_BYTES_OUTSIDE_ARRAY=" bad+0; exit (bad>0) }' || { echo GATE_LOGO_KO_TOUCHES_CODE; exit 1; }
cp $KL $V/lib/modules/meink.ko
chown root:root $V/lib/modules/meink.ko; chmod 644 $V/lib/modules/meink.ko
python3 -c "import os;os.setxattr('$V/lib/modules/meink.ko', b'security.selinux', b'u:object_r:vendor_file:s0\0')"

bash $HERE/vendor/scripts/apply-eink-access.sh $V

cp $KO $V/lib/modules/meink_loader.ko
chown root:root $V/lib/modules/meink_loader.ko; chmod 644 $V/lib/modules/meink_loader.ko
python3 -c "import os;os.setxattr('$V/lib/modules/meink_loader.ko', b'security.selinux', b'u:object_r:vendor_file:s0\0')"
python3 - <<'PY'
import os, sys
V = os.environ['V']
for p in ('lib/modules/meink_loader.ko', 'etc/selinux/vendor_sepolicy.cil', 'etc/init/hw/init.project.rc'):
    label = os.getxattr(os.path.join(V, p), 'security.selinux')
    print('LABEL', p, label)
    if not label.startswith(b'u:object_r:vendor_'):
        sys.exit('GATE_LABEL_LOST ' + p)
PY

# gate: policy compiles as init compiles it
bash $HERE/vendor/scripts/check-vendor-policy.sh $V $SYS $L || { echo GATE_POLICY_DOES_NOT_COMPILE; exit 1; }

# fingerprint navigation: patched HAL from the stock one, plus its ini
bash $HERE/vendor/scripts/apply-fp-navigator.sh $V $W/vendorx/lib64/hw/fpsensor_fingerprint.default.so
bash $HERE/vendor/scripts/apply-usb-no-mass-storage.sh $V
bash $HERE/vendor/scripts/stamp-build-number.sh $V $BN
python3 - <<'PY'
import os, sys
V = os.environ['V']
for p in ('lib64/hw/fpsensor_fingerprint.default.so', 'etc/fpsensor_nav.ini', 'etc/init/hw/init.mt6761.usb.rc', 'build.prop'):
    label = os.getxattr(os.path.join(V, p), 'security.selinux')
    print('LABEL', p, label)
    if not label.startswith(b'u:object_r:vendor_'):
        sys.exit('GATE_LABEL_LOST ' + p)
PY
rm -f $IMG
# the system mke2fs: AOSP's drops the SELinux labels
/usr/sbin/mke2fs -q -t ext4 -b 4096 -O ^has_journal,^metadata_csum,^64bit,^resize_inode -m 0 \
  -N 2245 -d $V $IMG 100852
PATH=$L/out/host/linux-x86/bin:$PATH $AVB add_hashtree_footer \
  --image $IMG --partition_name vendor --partition_size 419803136 \
  --salt 65aced7271cad1e1a596ceafde6e37ea8fd3dae2bb8f0e5151723d900462d45f \
  --hash_algorithm sha256 --fec_num_roots 2

# read back what the image carries
IMG_KO=$(debugfs -R "cat /lib/modules/meink_loader.ko" $IMG 2>/dev/null | md5sum | cut -d' ' -f1)
IMG_MEINK=$(debugfs -R "cat /lib/modules/meink.ko" $IMG 2>/dev/null | md5sum | cut -d' ' -f1)
echo "IMAGE_MEINK_MATCH=$([ "$IMG_MEINK" = "$(md5sum < $KL | cut -d' ' -f1)" ] && echo yes || echo NO)"
echo "IMAGE_LOADER_MATCH=$([ "$IMG_KO" = "$(md5sum < $KO | cut -d' ' -f1)" ] && echo yes || echo NO)"
echo "IMAGE_GENFSCON=$(debugfs -R "cat /etc/selinux/vendor_sepolicy.cil" $IMG 2>/dev/null | grep -c 'genfscon sysfs /einkinfo/sleep_image ')"
echo "IMAGE_CHMOD=$(debugfs -R "cat /etc/init/hw/init.project.rc" $IMG 2>/dev/null | grep -c 'chmod 0666 /sys/einkinfo/sleep_image$')"
echo "IMAGE_LOADER_LABEL=$(debugfs -R "ea_get /lib/modules/meink_loader.ko security.selinux" $IMG 2>/dev/null | tr -d '\0\n')"
echo "IMAGE_FP_MATCH=$([ "$(debugfs -R "cat /lib64/hw/fpsensor_fingerprint.default.so" $IMG 2>/dev/null | md5sum | cut -d' ' -f1)" = "$(md5sum < $V/lib64/hw/fpsensor_fingerprint.default.so | cut -d' ' -f1)" ] && echo yes || echo NO)"
echo "IMAGE_INI=$(debugfs -R "cat /etc/fpsensor_nav.ini" $IMG 2>/dev/null | grep -c navigator=1) IMAGE_INI_ZERO_KEYS=$(debugfs -R "cat /etc/fpsensor_nav.ini" $IMG 2>/dev/null | grep -c "_key_code=0")"
echo "IMAGE_INI_LABEL=$(debugfs -R "ea_get /etc/fpsensor_nav.ini security.selinux" $IMG 2>/dev/null | tr -d '\0\n')"
echo "IMAGE_USB_MASS_STORAGE_LINKS=$(debugfs -R "cat /etc/init/hw/init.mt6761.usb.rc" $IMG 2>/dev/null | grep -c "mass_storage.usb0 /config/usb_gadget/g1/configs/b.1/f1")"
echo "IMAGE_USB_NOTE=$(debugfs -R "cat /etc/init/hw/init.mt6761.usb.rc" $IMG 2>/dev/null | grep -c "Kompakt: no mass storage here")"
echo "IMAGE_BUILD_NUMBER=$(debugfs -R "cat /build.prop" $IMG 2>/dev/null | grep "^ro.vendor.build.version.incremental=")"
echo "IMAGE_BUILDPROP_LABEL=$(debugfs -R "ea_get /build.prop security.selinux" $IMG 2>/dev/null | tr -d '\0\n')"
echo "VENDOR_MD5=$(md5sum $IMG | cut -d' ' -f1)"
echo VENDOR_DONE
