# The vendor partition

What is in the Kompakt's `vendor.img`, what ours changes, and how it is built.
Companion to [Kernel.md](Kernel.md) and [E-inkdriver.md](E-inkdriver.md);
[vendor/README.md](../vendor/README.md) has the short version.

```
stock vendor.img   419,803,136 bytes   ext4   1892 files
ro.vendor.build.fingerprint = Mudita/Kompakt/Kompakt:12/SP1A.210812.016/20260731:user/dev-keys
ro.vendor.build.version.release = 12        ro.vendor.build.version.sdk = 31
ro.board.platform = mt6761                  ro.vendor.build.security_patch = 2026-07-31
ro.product.first_api_level = 31             ro.board.first_api_level = 30
```

Vendor is Android 12 under an Android 16 system. That works, and it sets the
ceiling on every HAL we inherit. All partitions are plain ext4; nothing is
compressed or EROFS.

Our vendor is Mudita's, repacked with these changes:

| file | change |
|---|---|
| `lib/modules/meink_hal.ko`, `meink_loader.ko` | ours, GPL, from kernel patch 0020 |
| `lib/modules/meink.ko` | Mudita's, with our pictures ([Images.md](Images.md)) |
| `lib64/hw/fpsensor_fingerprint.default.so`, `etc/fpsensor_nav.ini` | fingerprint navigation on (section 6) |
| `etc/selinux/*.cil` | e-ink and battery nodes reachable, orphaned vendor types bound (section 2, [Battery.md](Battery.md)) |
| `etc/init/hw/init.project.rc` | the matching `chmod`s |
| `etc/init/hw/init.mt6761.usb.rc` | no mass storage in the adb + serial configuration |
| `build.prop` | `ro.vendor.mtk_aod_support=1`; the build number in `ro.vendor.build.version.incremental` |

It is flashed and shipped with every release.

## 1. Kernel modules

`vendor/lib/modules/` holds the e-ink trio (`meink_hal.ko`, `meink.ko`,
`meink_loader.ko`), `mt6357-accdet.ko` (headset detect), connectivity (`wmt_drv`,
`bt_drv_connac1x`, `wlan_drv_gen4m`, `wmt_chrdev_wifi`, `connfem`, `gps_drv`,
`fmradio_drv_mt6631`), `fpsgo`, `met` and `trace_mmstat`.

**`modules.load` is not used.** Modules load from explicit `exec` lines in
`etc/init/hw/init.project.rc`, e-ink in the order `meink_hal`, `meink`,
`meink_loader`. A new module needs its own line there.

Headset detection is a vendor module, not part of the kernel image.
`vendor/firmware/` has Wi-Fi, BT, GPU (`rgx.fw`), FM and touch firmware, and no
e-ink firmware: the controller image is compiled into `meink.ko`.

`lib/modules/kompakt_eink.ko` is an old shim still in the stage; nothing loads it.

## 2. SELinux: the e-ink nodes

`etc/selinux/vendor_sepolicy.cil` is plain text. Mudita label fourteen
`/sys/einkinfo` nodes one by one, each with its own type (`sysfs_eink_waveform`,
`sysfs_eink_contrast`, ...; the full list is in [E-inkdriver.md](E-inkdriver.md)).
Stock leaves `refresh_mode`, `manual_mode`, `temperature_offset` and
`log_level` as generic `sysfs`, which `system_app` can never be granted
(`neverallow`). Labels come from `genfscon`, which lives in vendor policy, so
only a vendor change can fix that.

Ours adds:

| path | type | granted to |
|---|---|---|
| `/einkinfo/refresh_mode`, `manual_mode`, `temperature_offset`, `log_level` | `sysfs_eink_misc` | `system_app`, `shell` |
| `/einkinfo/sleep_image` (prefix, so `sleep_image_stock` too) | `sysfs_eink_misc` | `system_app`, `shell` |
| `/module/meink_hal/parameters` (prefix, every parameter) | `sysfs_eink_param` | `system_app`, `shell` |

plus `setattr` for `init` on both types, so the `chmod`s in `init.project.rc`
work. Access is decided by SELinux domain, not uid, so `adb root` would not
help.

The module parameters also need `chmod 0666` in `init.project.rc`:
`module_param` cannot declare the write bit for others. That makes every
`meink_hal` tunable readable and writable over adb with no root and no rebuild.

`update_mode` is labelled but does not exist on our kernel. The offline switch
is labelled too: `/bus/platform/drivers/pmic-codec-accdet/irqkey_state` is
`sysfs_irqkey`.

## 3. Runtime overlays

`vendor/overlay/` ships eight small RROs (`FrameworkResOverlay`,
`FrameworkResOverlayExt`, `SystemUIResOverlay`, `MtkSettingsResOverlay`,
`SettingsProviderResOverlay`, `CellbroadcastUIResOverlay`, `WifiResOverlay`,
`WifiResMainlineOverlay`). The framework ones set, among others:
`config_showNavigationBar`, `config_dozeAfterScreenOff` and both
`config_powerDecouple*FromDisplay` true; `config_num_physical_slots` 2;
`config_screenBrightnessDoze` 5; `config_dozeComponent`
`com.android.dreams.alwaysondisplay/.AlwaysOnDisplay`;
`config_biometric_sensors` `["0:2:15"]`; an 18-step auto-brightness curve;
default and peak refresh rate 61 (the panel's `fps_limit` is 62). Its
`power_profile` is an unedited MediaTek template.

RROs are ordered by partition, later wins: system, vendor, odm, oem, product,
system_ext. Overlays in `/system/product/overlay` outrank these; a vendor RRO
beats a static value built into `framework-res`.

## 4. Audio

The audio policy in `vendor/etc/` declares the wired devices
(`OUT_WIRED_HEADSET`, `OUT_WIRED_HEADPHONE`, `IN_WIRED_HEADSET`,
`OUT_USB_HEADSET`, `OUT_USB_DEVICE`) with Speaker as default output, so wired
routing is configured. Detection is the `mt6357-accdet` module; the HAL is
`android.hardware.audio.service.mediatek`.

## 5. Other contents

`vendor/bin/hw/` is MediaTek's usual HAL set: camera, RIL (`mtkfusionrild`),
lights (the notification LED), sensors, thermal, usb, vibrator, composer 2.1,
allocator 4.0, media c2, GNSS, Wi-Fi, Bluetooth, NFC, secure element, keymaster
(`beanpod`) and Microtrust TEE (`thh/`).

The vendor build number is in `ro.vendor.build.version.incremental`
(`kompakt-<N>`, set by `stamp-build-number.sh`), because apps may read that
property; a new `ro.vendor.*` property would be denied to them. The Kompakt app
shows it under Installed images.

## 6. Fingerprint navigation

Chipone's fingerprint HAL (`lib64/hw/fpsensor_fingerprint.default.so`) has a
navigation engine that ships switched off: `customer_get_ini_file_full_name()`
returns NULL, so its ini is never found. `vendor/tools/patch-fp-navigator.py`
replaces that function's `mov x0, #0` with `adr x0, PATH` (same eight bytes),
with PATH written over a log string only the uncalled `interrupt_test` uses. It
checks the stock bytes first and never changes the size.

The ini sets `navigator=1` and every key code to 0. With the navigator on, the
HAL polls the TA while a finger is on the sensor, and the TA logs which of the
sensor's 12 zones are covered; the Kompakt app reads those lines and scrolls.
The HAL's own keys stay off: the sensor is one row of zones (dx is always 0),
the TA's dy changes sign within one swipe, and the uinput device is created
before the ini is read, so it declares no keys. Leave `fp_config_feature_disable_nav_if_screen_off` at 0: set, it calls an
ioctl the driver rejects every 10 ms.

## 7. Building vendor.img

### The stage

The image is built from a **labelled stage**: the stock image extracted as root,
on Linux, from a loop mount, with every `security.selinux` xattr:

```sh
mount -o loop,ro vendor.img /mnt/v
( cd /mnt/v && tar --xattrs --xattrs-include='*' --selinux --acls -cf - . ) | \
  ( cd <stage> && tar --xattrs --xattrs-include='*' --selinux --acls -xpf - )
```

`vendor/mudita/kompakt/proprietary/` is not a source: it has no labels, and a
macOS extraction drops all 189 symlinks. Keep the stage outside the source
tree, where a sync cannot touch it; the scripts in `vendor/scripts/` are the
record of every edit. They edit files in place so the files keep their labels
(Python's `os.getxattr` / `os.setxattr` work where `setfattr` is missing).

### The scripts

On a new stage, once (all idempotent, stage directory as `$1`):

```sh
bash vendor/scripts/fix-orphaned-vendor-types.sh <stage>   # ORPHANED_TYPES_OK
bash vendor/scripts/apply-battery-access.sh      <stage>   # BATTERY_ACCESS_OK
bash vendor/scripts/apply-eink-access.sh         <stage>   # nodes=9/9 params=11/11, EINK_ACCESS_OK
```

Then every build:

```sh
WORK=<dir> LINEAGE=<tree> SYSTEM_IMG=<system.img> \
    vendor/scripts/build-vendor.sh <build number>
```

It installs our `meink.ko` pictures (checking that only picture bytes differ
from stock), `meink_loader.ko`, the e-ink access, the fingerprint HAL and ini,
`apply-usb-no-mass-storage.sh` (`USB_ADB_ACM ...`) and
`stamp-build-number.sh` (`STAMPED ...`). It checks labels after each edit,
compiles the policy together with `SYSTEM_IMG`'s the way init does
(`check-vendor-policy.sh`) and stops if it fails, makes the image, and reads
back from the image what it carries. `WORK` holds the stage and the module
builds; the script's header lists them.

The USB change matters: mass storage's `file-storage` thread in the adb + serial
configuration panicked the kernel at plug-in (NULL dereference in
`musb_gadget_enable`). adb moves into the freed `f1`: Android's own
`init.usb.configfs.rc` links adb as `f1` on the same trigger, and a second adb
link in the configuration puts adbd in a reset loop, with no adb until the USB
mode is changed.

### Two editions: Global and USA

Mudita builds the vendor per modem region, and the two differ in 29 files, all
of them paired with the modem firmware:

| | Global | USA (North America) |
|---|---|---|
| modem (`gsm.version.baseband`) | `MOLY.LR12A.R3.MP.V236.P8` | `MOLY.LR12A.R3.MP.V236.P6` |
| `etc/init/init.md_apps.rc` | `load_verno ... V236.P8` | `load_verno ... V236.P6` |

The files are the VoLTE stack (`volte_stack`, `volte_ua`, `volte_imcb`,
`libvolte_core_shr.so`), the modem app libraries (`libutinterface_md`,
`libcurl-md`, `libcurl_xcap_md`, `libssl-mdapp`, `libcrypto-mdapp`, `libverno`,
`libwo`), the Wi-Fi calling tunnel (`charon`, `epdg_wod`, `starter`, `stroke`,
`libstrongswan`, `libcharon-ss`, `libhydra`, `libsimaka`) and `init.md_apps.rc`.
A vendor from the other region still boots and gets data, but IMS never
registers, so calls fail on carriers that need 4G calling (every US carrier).

Our stage is the Global one. The USA edition is the same stage with those files
taken from a stock USA vendor:

```sh
bash vendor/scripts/make-usa-vendor.sh <global stage> <stock USA vendor> <stock Global vendor> <usa stage>
```

It swaps only files that differ between the two stock vendors, refuses any file
we have changed, keeps each file's label, and checks the result names the P6
modem. Build the image from the USA stage the same way, and ship its own full
update packages: a phone must get the edition that matches its modem.

### Checks

A miss looks exactly like a success, so check the stage:

| check | expect |
|---|---|
| `grep -c 'typeattributeset proc_battery_cmd_31_0 ' etc/selinux/plat_pub_versioned.cil` | 1 |
| `grep -c 'chmod 0644 /sys/kernel/battery_monitor' etc/init/hw/init.project.rc` | 7 |
| `grep '^(typeattributeset ' etc/selinux/plat_pub_versioned.cil \| sort \| uniq -d \| wc -l` | 0 |

(The e-ink grants are `allow` rules in `vendor_sepolicy.cil`, so they are not
in `plat_pub_versioned.cil`.) And the image:

```
labelled files      all but 1   (same as stock)
symlinks            189         (same as stock)
files differing     only the ones changed
size                419,803,136 (same as stock)
```

### Making the image

```sh
/usr/sbin/mke2fs -q -t ext4 -b 4096 -O ^has_journal,^metadata_csum,^64bit,^resize_inode \
  -m 0 -N 2245 -d <stage> vendor-new.img 100852
PATH=<lineage>/out/host/linux-x86/bin:$PATH avbtool add_hashtree_footer \
  --image vendor-new.img --partition_name vendor --partition_size 419803136 \
  --hash_algorithm sha256 --fec_num_roots 2 \
  --salt 65aced7271cad1e1a596ceafde6e37ea8fd3dae2bb8f0e5151723d900462d45f
```

- **Use the system `mke2fs`, never AOSP's.** AOSP's silently drops SELinux
  labels (it expects `e2fsdroid` to add them); the image will not boot.
  `mke2fs -d` copies the xattrs by itself.
- **`fec` must be on PATH** (`out/host/linux-x86/bin`), or `add_hashtree_footer`
  fails with `FileNotFoundError: 'fec'`.
- The filesystem is 100852 blocks of 4 KB; hashtree and FEC follow, and the
  whole image is 419,803,136 bytes, the same as stock. The salt is stock's,
  kept so the images stay comparable. Vendor is full, so every file added must
  be small.
- A repack of the unchanged stage reproduces stock exactly: every file,
  label, symlink, owner and mode. Only symlink permission bits differ (`0777`
  against `0755`), which the kernel ignores.

- Verity: the stock footer is `Algorithm: NONE`, chained from `vbmeta_vendor`,
  and our top-level vbmeta has flags 2 (hashtree disabled), which covers
  chained partitions too. Vendor is not verified; the footer is kept for shape.

`vendor` is logical, inside `super`: flash it from fastbootd
(`adb reboot fastboot`, `fastboot flash vendor vendor.img`). Flashing the stock
`vendor.img` the same way reverts it.

### Adding a label

The stock policy declares a type in three places plus the grant, so a new
`genfscon` takes four lines and an `allow`:

```
(type sysfs_eink_misc)
(typeattributeset fs_type    (... sysfs_eink_misc))
(typeattributeset sysfs_type (... sysfs_eink_misc))
(genfscon sysfs /einkinfo/refresh_mode (u object_r sysfs_eink_misc ((s0) (s0))))
(allow system_app_31_0 sysfs_eink_misc (file (ioctl read write getattr lock append map open watch watch_reads)))
```

`genfscon` on sysfs matches by path prefix. `system_app_31_0` is the domain
KompaktService runs in; `platform_app_31_0` and `kpoc_charger_31_0` are granted
the stock nodes too. If `init` has to `chmod` the node, grant it `setattr`.

A rule against a versioned attribute that nothing binds compiles and grants
nothing; see [Battery.md](Battery.md).

`precompiled_sepolicy` on vendor is ignored under our system image: init checks
it against the system's plat policy hash, which never matches, and compiles the
`.cil` at boot. Editing the CIL is enough. Verify on the device: `ls -Z` the
node, and `logcat -b all | grep 'avc:  denied'`.

## 8. Reading a vendor image

```sh
7zz x -y -o<dir> vendor.img          # ext4, 7-Zip reads it (no labels, no symlinks)
grep -a einkinfo <dir>/etc/selinux/vendor_sepolicy.cil
grep modprobe <dir>/etc/init/hw/init.project.rc
aapt2 dump resources <overlay>.apk   # aapt2 is in the lineage tree, prebuilts/sdk/tools
debugfs -R "cat /build.prop" vendor.img | grep incremental
```
