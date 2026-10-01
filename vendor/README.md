# vendor

Builds `vendor.img`: Mudita's vendor partition with our files added. The
repack is byte-exact, so only the files we change differ from stock.

```
scripts/build-vendor.sh    builds vendor.img from the stage
scripts/make-usa-vendor.sh the USA edition of that stage
scripts/check-vendor-policy.sh  compiles the vendor policy with a system image's
scripts/*.sh               one change each to a stage directory (see below)
tools/patch-fp-navigator.py  turns on navigation in the fingerprint HAL
mudita/                    Mudita's vendor files; the blobs are not committed
scripts/withdrawn/, tools/withdrawn/   old experiments that never shipped
```

## Build

```sh
WORK=<dir> LINEAGE=<tree> SYSTEM_IMG=<system.img> \
    vendor/scripts/build-vendor.sh <build number>
```

It runs on a Linux build host, from a stage: an extracted and labelled copy of
the stock vendor partition. The other scripts each take the stage directory as
their first argument; `build-vendor.sh` runs the ones
that change every build. [docs/Vendor.md](../docs/Vendor.md) describes the
setup.

Every build has two editions. The stage is Global; `scripts/make-usa-vendor.sh`
makes the USA one for North American phones, whose VoLTE stack must match their
modem (see Vendor.md, "Two editions").

## What ours changes

```
lib/modules/meink_hal.ko, meink_loader.ko   ours, GPL, built from kernel/patches/0020
lib/modules/meink.ko                        Mudita's, with our pictures (apply-boot-logo.sh)
lib64/hw/fpsensor_fingerprint.default.so    navigation on (tools/patch-fp-navigator.py)
etc/fpsensor_nav.ini                        its settings (apply-fp-navigator.sh)
etc/selinux/vendor_sepolicy.cil             e-ink and battery nodes reachable (apply-eink-access.sh, apply-battery-access.sh)
etc/selinux/plat_pub_versioned.cil          Mudita's orphaned vendor types bound (fix-orphaned-vendor-types.sh)
etc/init/hw/init.project.rc                 the matching permissions
etc/init/hw/init.mt6761.usb.rc              no mass storage with adb + serial (apply-usb-no-mass-storage.sh)
build.prop                                  ro.vendor.mtk_aod_support=1 and the build number (stamp-build-number.sh)
```

## Constraints

- **`modules.load` is ignored.** Modules load from explicit `modprobe` lines in
  `etc/init/hw/init.project.rc`, in order: `meink_hal.ko`, `meink.ko`, then
  `meink_loader.ko`. A new module needs its own line there.
- **Use the system `mke2fs`, not AOSP's.** AOSP's drops the SELinux labels and
  the image will not boot. Check with `os.getxattr(path, b"security.selinux")`.
- **`avbtool add_hashtree_footer` needs `fec` on PATH** (`out/host/linux-x86/bin`).
- Extract as root from a loop mount with `tar --xattrs --selinux`; a copy made
  on macOS loses the labels and the symlinks.
- The partition is full. Strip any module you add.

## Verify before flashing

```
labelled files    2081, unlabelled 1    same as stock
symlinks          189                   same as stock
size              419,803,136           same as stock
files differing   only the ones you changed
```

Vendor is a logical partition, so it flashes from fastbootd:

```sh
adb reboot fastboot
fastboot flash vendor vendor.img
```

To go back, flash the `vendor.img` from a stock Mudita release the same way.
