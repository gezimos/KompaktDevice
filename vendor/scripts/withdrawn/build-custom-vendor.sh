#!/bin/bash
# Withdrawn: built a vendor with the old kompakt_eink shim. Never shipped.
#   WORK=<dir> LINEAGE=<tree> build-custom-vendor.sh
# WORK holds vendor.img (stock) and kompakt_eink-stripped.ko.
W=${WORK:?set WORK}
L=${LINEAGE:?set LINEAGE}
exec > $W/mkvendor.log 2>&1
set -x
AVB=$L/out/host/linux-x86/bin/avbtool
SALT=65aced7271cad1e1a596ceafde6e37ea8fd3dae2bb8f0e5151723d900462d45f
MOD=$W/kompakt_eink-stripped.ko

mountpoint -q /mnt/v || mount -o loop,ro $W/vendor.img /mnt/v
rm -rf $W/vstage2; mkdir -p $W/vstage2
( cd /mnt/v && tar --xattrs --xattrs-include='*' --selinux --acls -cf - . ) | \
  ( cd $W/vstage2 && tar --xattrs --xattrs-include='*' --selinux --acls -xpf - )
echo "TAR_EXIT=$?"

V=$W/vstage2

# 1. our e-ink shim module, labelled like every other module there
cp $MOD $V/lib/modules/kompakt_eink.ko
chown root:root $V/lib/modules/kompakt_eink.ko
chmod 644 $V/lib/modules/kompakt_eink.ko
setfattr -n security.selinux -v "u:object_r:vendor_file:s0" $V/lib/modules/kompakt_eink.ko
ls -lZ $V/lib/modules/kompakt_eink.ko

# 2. load it after meink.ko, before meink_loader.ko drives the panel
python3 - <<PY
p="$W/vstage2/lib/modules/modules.load"
lines=open(p).read().splitlines()
assert "kompakt_eink.ko" not in lines
i=lines.index("meink.ko")
lines.insert(i+1,"kompakt_eink.ko")
open(p,"w").write("\n".join(lines)+"\n")
print("modules.load:"); print("\n".join(lines[:6]))
PY

# 3. dependency line so modprobe pulls meink_hal first
python3 - <<PY
p="$W/vstage2/lib/modules/modules.dep"
s=open(p).read()
line="/vendor/lib/modules/kompakt_eink.ko: /vendor/lib/modules/meink_hal.ko\n"
if line not in s: s += line
open(p,"w").write(s)
print([l for l in s.splitlines() if "kompakt_eink" in l])
PY

# 4. the AOD property, here instead of in the ROM so it survives any system.img
python3 - <<PY
p="$W/vstage2/build.prop"
s=open(p).read()
if "mtk_aod_support" not in s:
    s = s.rstrip("\n") + "\n\n# Kompakt: MediaTek HWC supports doze on mt6761; Mudita never enabled it.\nro.vendor.mtk_aod_support=1\n"
open(p,"w").write(s)
print(s.splitlines()[-2:])
PY

# 5. repack, same geometry as stock
rm -f $W/vendor-kompakt.img
mke2fs -q -t ext4 -b 4096 -O ^has_journal,^metadata_csum,^64bit,^resize_inode -m 0 \
  -N 2200 -d $V $W/vendor-kompakt.img 100852
echo "MKFS_EXIT=$?"
$AVB add_hashtree_footer --image $W/vendor-kompakt.img --partition_name vendor \
  --partition_size 419803136 --salt $SALT --hash_algorithm sha256 --fec_num_roots 2
echo "AVB_EXIT=$?"

# 6. verify by mounting the result
mkdir -p /mnt/v3; umount /mnt/v3 2>/dev/null
mount -o loop,ro $W/vendor-kompakt.img /mnt/v3
echo "MOUNT_EXIT=$?"
ls -lZ /mnt/v3/lib/modules/kompakt_eink.ko
grep -n "kompakt_eink" /mnt/v3/lib/modules/modules.load /mnt/v3/lib/modules/modules.dep
grep -n "mtk_aod_support" /mnt/v3/build.prop
echo "=== everything else unchanged? ==="
cd /mnt/v  && find . -type f -exec md5sum {} + 2>/dev/null | sort -k2 > $W/m-old.txt
cd /mnt/v3 && find . -type f -exec md5sum {} + 2>/dev/null | sort -k2 > $W/m-new.txt
echo "files differing (expect exactly 4: our module, modules.load, modules.dep, build.prop):"
diff $W/m-old.txt $W/m-new.txt | grep "^[<>]" | awk '{print $3}' | sort -u
umount /mnt/v3
ls -l $W/vendor-kompakt.img; md5sum $W/vendor-kompakt.img
echo MKVENDOR_DONE
