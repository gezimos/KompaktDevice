# The device tree

Two things go by this name:

1. **The hardware device tree**: the DTB and DTBO the bootloader hands the
   kernel (section 1).
2. **The LineageOS device tree**: `device/mudita/kompakt`, the Android build
   configuration. It builds the boot image, which carries LineageOS recovery
   (section 2).

---

## 1. The hardware device tree

### 1.1 Two parts

```
boot.img  dtb section, 103,786 bytes: Android DT table (d7b7ab1e) around one
          FDT of 103,722 bytes, the generic MT6761 base tree
dtbo.img  45,056 bytes: Android DT table around one FDT of 40,473 bytes,
          67 fragments of device-specific overlay
```

Everything specific to the Kompakt is in the overlay: e-ink panel, accdet, NFC,
touch, SIM pins. The charger settings (`battery_cv`, the JEITA table) are in
the base tree. Both halves build from Mudita's published kernel source,
byte-identical to what ships: see [dtbo/README.md](../dtbo/README.md).

### 1.2 The source

`arch/arm64/boot/dts/mediatek/Kompakt.dts` line 597 includes
`<Kompakt/cust.dtsi>`, which is not in the release. That is normal: MediaTek's
DrvGen generates `cust.dtsi` at build time from
`drivers/misc/mediatek/dws/mt6761/Kompakt.dws`, which Mudita did publish.
Kernel patch 0021 adds the file (made by `dtbo/gencust.py`) and the Makefile
line.

- `Kompakt.dws` is byte-identical to `k61v1_64_bsp.dws`, MediaTek's reference
  board. Those defaults are genuinely what this phone ships.
- **`Compact.dws` and `Compact.dts` are stale twins.** `Compact.dws` differs on
  pins 5, 177 and 178 and lacks `MD1_SIM1_HOT_PLUG_EINT`. Use `Kompakt.*`.

### 1.3 The decompiled trees

`dtc -I dtb -O dts` on the shipping images gives the resolved trees:

```
dts/kompakt-base.dts       4,366 lines   from boot.img
dts/kompakt-overlay.dts    1,833 lines   from dtbo.img
```

Macro names are lost, every value is kept, and the overlay recompiles to the
same bytes. The `.dws` agrees with it section by section:

| generated section | dws module | overlay fragment | result |
|---|---|---|---|
| `gpio_init_default` | `gpio` | `@42` | 157/157 pins exact |
| EINT table | `eint` | `@43`-`@50` | 8/8 exact |
| MD1 SIM hotplug | `md1_eint` | `@51` | present |
| I²C device table | `i2c` | `@34`-`@37` | 16/16 exact |
| PMIC regulators | `pmic` | `@52`-`@57` | 6/6 exact |
| ADC channels | `adc` | `@28` | 3/3 exact |
| Clock buffer | `clk` | `@30` | 7/7 exact |
| Keypad | `kpd` | `@60` | exact |

Key pins: GPIO163 e-ink reset (active low), 164 e-ink 3v3, 165 e-ink busy,
174 touch reset, 0 touch EINT.

### 1.4 The e-ink node

`fragment@19`: `eink_spi@0`, `compatible = "eink,wd043wc5"`,
`spi-max-frequency` 18 MHz, reset/busy/3v3 on pio 163/165/164, `vio-supply`.
The SPI frequency here is not used: the driver sets its own clock at probe, so
changing it is a kernel change ([E-inkdriver.md](E-inkdriver.md)).

### 1.5 Signatures and the boot image layout

```
image       size         signature
boot        33,554,432   AVB: vbmeta struct at 24,055,808, AVBf footer in the last 64 bytes
dtbo            45,056   MediaTek cert1 at 40,552
lk             892,928   AVB0 at 627,452 and cert1 at 643,525
md1img      55,484,416   cert1 at 23,031,288
tee          2,134,016   cert1 at 133,128
scp            638,976   cert1 at 1,608
vbmeta           4,096   AVB0 at 0
```

Neither kind is checked on an unlocked bootloader, but our images keep the same
shape. The boot image:

```
content          0 .. 24,055,808
vbmeta (AVB0)    at 24,055,808, 1600 bytes  (v1.0, auth 320, aux 1024)
AVBf footer      last 64 bytes: original_image_size 24,055,808,
                 vbmeta_offset 24,059,904, vbmeta_size 1,600
```

`mkbootimg` produces neither the vbmeta struct nor the footer. Add them (as
`tools/pack-recovery-boot.sh` does):

```sh
avbtool add_hash_footer --image boot-new.img --partition_name boot \
    --partition_size 33554432 --algorithm NONE
```

`NONE` leaves it unsigned. The bootloader has no slot for a custom key, so a
signature of ours would never be checked ([Kernel.md](Kernel.md)).

### 1.6 Extracting the trees

`boot.img` is header v2, 2048-byte pages, sections page-aligned in the order
header, kernel, ramdisk, second, recovery_dtbo, dtb. The dtb size is the
little-endian word at offset 1648 (recovery_dtbo size at 1632).
`unpack_bootimg.py` does the same. Both the dtb section and `dtbo.img` are
Android DT tables: a big-endian header, then `(size, offset)` entries. Take the
FDT out and run `dtc -I dtb -O dts`.

### 1.7 What binds on a running phone

The overlay is MediaTek's reference board, so it declares some devices this
board does not use. From `/sys/bus/*/devices/*/driver`:

```
bus      node                   driver bound
i2c-0    focaltech@38           mtk-tpd              touch
i2c-3    pn544@28               nxp,pn544            NFC
i2c-5    subpmic_pmu@34         mt6370_pmu           the health HAL reads its charger
i2c-5    usb_type_c@4e          usb_type_c
i2c-4/6  camera nodes           kd_camera_hw, CAM_CAL_*, *AF
spi0     fingerprint            fpsensor
spi1     eink_spi@0             eink_spi
spi3     p61                    p61                  NFC secure element
unbound: nfc@08, speaker_amp@34, slave_charger@4b, ext_buck_lp4x@50,
         ext_buck_lp4@57 (i2c-3); ext_buck_vgpu@55 (i2c-6); mtk-usb@60 (i2c-2)
```

**Leave the NFC and camera nodes alone.** The phone has NFC and a rear camera,
and the rear camera is also exposed as a front one so face-verification apps
work. Unbound nodes cost nothing at runtime.

---

## 2. The LineageOS device tree

`device/mudita/kompakt`. Every value was read off the shipping firmware.
`BoardConfig.mk` and `device.mk` carry the settings below; `rootdir/` the stock
fstab and `init.recovery.mt6761.rc`; `sepolicy/vendor/` the recovery policy;
`vintf/` the stock manifests; `prebuilt/` the kernel, dtb, dtbo and recovery
modules (not committed); `proprietary-files.txt` and `extract-files.sh` the blob
list, generated from an unpacked `vendor.img`.

| partition | built by |
|---|---|
| `boot` (with recovery) | this device target (`m bootimage`), then `tools/pack-recovery-boot.sh` |
| `dtbo` | `dtbo/mkdtbo.py` |
| `vendor` | `vendor/scripts/build-vendor.sh` from a labelled stage ([Vendor.md](Vendor.md)) |
| `system` | the KompaktOS GSI build |
| `product` | Mudita's stock image |
| bootloader, preloader, modem | stock, never replaced |

The vendor partition's SELinux policy is Mudita's CIL edited by
`vendor/scripts`, not compiled from here; `sepolicy/vendor` reaches the
recovery's policy.

### 2.1 Boot image

```
BOARD_KERNEL_BASE         0x40000000      (kernel_addr 0x40080000)
BOARD_KERNEL_OFFSET       0x00080000      pass explicitly; mkbootimg defaults to 0x8000
BOARD_KERNEL_PAGESIZE     2048
BOARD_RAMDISK_OFFSET      0x11b00000      (0x51b00000 - base)
BOARD_KERNEL_TAGS_OFFSET  0x07880000      (0x47880000 - base)
BOARD_DTB_OFFSET          0x07880000
BOARD_BOOT_HEADER_VERSION 2
BOARD_KERNEL_CMDLINE      bootopt=64S3,32N2,64N2 buildvariant=user
os_version                12.0.0, patch level 2026-07
```

**Prove the parameters before flashing any boot image.** A wrong ramdisk
offset builds clean and bootloops with no kernel output. Repack the stock
sections with the exact command you are about to use:

```sh
python3 system/tools/mkbootimg/mkbootimg.py --kernel <stock kernel> \
    --ramdisk <stock ramdisk> --dtb <stock dtb> ... -o /tmp/roundtrip.img
cmp -n 24053760 /tmp/roundtrip.img boot.img                        # identical
xxd -l 1664 /tmp/roundtrip.img | diff - <(xxd -l 1664 boot.img)    # identical header
```

The only allowed difference is one trailing page of padding.

### 2.2 Partitions

Dynamic partitions in `super`, all ext4 (the stock kernel has no EROFS or
F2FS), AVB 2.0, A/B. From `first_stage_ramdisk/fstab.mt6761`:

```
system   /system   ext4 ro  wait,avb=vbmeta_system,logical,first_stage_mount,slotselect,
                            avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey
vendor   /vendor   ext4 ro  wait,avb,logical,first_stage_mount,slotselect
product  /product  ext4 ro  wait,avb,logical,first_stage_mount,slotselect
/dev/block/by-name/md_udc  /metadata  ext4  noatime,nosuid,nodev,discard
                            wait,check,formattable,first_stage_mount
```

The GSI keys on the `system` line are why a GSI mounts at all; keep them.
`product` mounts at first stage, so every slot needs one. There is no recovery
partition: recovery is the boot ramdisk (`BOARD_USES_RECOVERY_AS_BOOT`).

`super`, from `lpdump`:

```
size 5,368,709,120 bytes (5 GiB), first sector 2048
group main_a    max 5,366,611,968 bytes: product_a, system_a, vendor_a
group cow       max 0
flags           virtual_ab_device
metadata        version 10.2, max 65536 bytes, 3 slots
```

`virtual_ab_device` is why the target inherits `virtual_ab_ota.mk` and why
`*-cow` partitions appear during an update.

AVB keys point at `external/avb/test/data` on purpose: nothing we sign is
verified, and the bootloader must never be relocked ([Kernel.md](Kernel.md)).
The top-level vbmeta sets flags 2 (hashtree disabled).

### 2.3 Identity

`ro.product.vendor.{device,model}` Kompakt, `ro.product.vendor.brand` Mudita,
`ro.board.platform` mt6761, `ro.product.board` Kompakt. Vendor is Android 12:
`ro.vendor.build.version.sdk` 31, `ro.product.first_api_level` 31,
`ro.board.first_api_level` 30. Defconfig `Kompakt_defconfig`, MediaTek board
name `k61v1_64_bsp`.

### 2.4 Full install from fastboot

1. Bootloader: set slot A, flash `vbmeta` to both slots by name, flash `boot`
   and `dtbo`.
2. fastbootd: cancel any snapshot update, flash `vendor` and `system`.
3. Bootloader: wipe.

Check `fastboot getvar is-userspace` before each phase. A system-only update
does not reflash boot or vendor.

### 2.5 Building LineageOS recovery

Apply `patches/` ([patches/README.md](../patches/README.md)), then:

```sh
lunch lineage_kompakt-bp4a-userdebug
m bootimage
tools/pack-recovery-boot.sh <lineage tree> <Image.gz> <dtb> boot.img
```

The pack script puts the recovery root into Mudita's header, offsets, command
line, os_version and patch level with our kernel and dtb, so the ramdisk is the
only difference. It drops nano and the f2fs and erofs tools, gives the
ramdisk's `meink.ko` our pictures ([Images.md](Images.md)), compresses with
gzip (the kernel unpacks gzip only) and adds the AVB footer.

Traps `BoardConfig.mk` and `device.mk` already handle:

- `BOARD_INCLUDE_RECOVERY_DTBO` is tested with `ifdef`; leave it unset.
- `compression_retrofit.mk` names `snapuserd.ramdisk`, which no longer exists;
  its settings are set by hand.
- `TARGET_KERNEL_SOURCE` must name a path that does not exist, or the build
  ignores the prebuilt kernel.

What recovery needs from this tree:

| need | where |
|---|---|
| USB gadget bound to `musb-hdrc` | `init.recovery.mt6761.rc` |
| `fastbootd`, `update_engine_sideload` | `device.mk`; nothing else pulls them in |
| Boot HAL `android.hardware.boot-service.default_recovery` | `device.mk`. Its class is `early_hal`, which recovery never starts, so `init.recovery.mt6761.rc` starts `vendor.boot-default` |
| Boot HAL may read `/etc/recovery.fstab` (rootfs) to find misc | `sepolicy/vendor/hal_bootctl_default.te` |
| Typed block devices for fastbootd and the installer | `sepolicy/vendor/file_contexts`: super, boot, dtbo, vbmeta, `md_udc`, userdata, frp, recovery, and `para` as misc |
| adb shell may read `/tmp/recovery.log` | `sepolicy/vendor/shell.te` |

`para` holds the A/B slot state in AOSP's `bootloader_control` layout at
offset 0x800, so AOSP's default boot HAL works unchanged.

### 2.6 Using LineageOS recovery

It draws black on white (the kernel inverts recovery frames, patch 0023;
recovery uses two inks and outlines the selected row), installs a full update
package by `adb sideload` or from the SD card with a progress bar, and has a
fastbootd (Advanced > Enter fastboot) that reads and writes `super`. Updates are
virtual A/B: install to the other slot, switch on success.

**Update packages.** `tools/make-full-ota.sh` builds a full A/B payload from
boot, dtbo, vbmeta, system, vendor and product, signed with the release key;
recovery's `otacerts.zip` carries that key beside LineageOS's. The stock Mudita
recovery accepts only Mudita-signed packages. The installer enforces:

- **Partition dates.** Every partition must carry a date no older than the
  recovery's own build, or it fails with `kPayloadTimestampError`. The script
  stamps every partition with the package's date.
- **No snapshots in recovery.** Without `/data` there is nowhere for
  copy-on-write files, so the installer writes the other slot directly, over
  space the current slot uses. An interrupted install leaves the current slot
  unusable, and `--set-active` back to it does not help. This is AOSP
  behaviour for any virtual A/B device sideloading in recovery. Repair from
  fastbootd: `fastboot create-logical-partition system_a 0` (likewise
  `vendor_a`, `product_a`), then flash them; `product` is Mudita's image.
- **The host counter stalls.** Sideload caches the package in memory after the
  verification pass, so `adb sideload` stops counting near 47% while the
  install runs. Watch the phone's bar.

**adb.** Release images keep `ro.adb.secure=1`. `adb sideload` needs no key;
`adb shell` answers `unauthorized` to a host whose key recovery does not carry,
and there is no screen to approve one on. The device makefiles cannot set
recovery's `/adb_keys`. adbd runs as `shell`, not root, and recovery waits at
most 5 s for USB (10 s for sideload) before drawing.

**Working with it.**

- The recovery log is in `/tmp` and is lost on reboot. adbd logs nowhere.
- Recovery marks the next boot as recovery. Leave with **Reboot system now**,
  or a warm reboot lands back in recovery.
- A long power press is a cold reset and wipes pstore. After a warm reboot,
  `adb bugreport` has the last kernel log (LAST KMSG).
- `fastboot reboot recovery` from the bootloader works.

**Do not retry:** `fastboot boot` crashes this bootloader (`lk_crash`); only
flashing tests a boot image.

A maintained MT6761 LineageOS 23.2 port to compare against:
`9cb14c1ec0/android_device_lenovo_clove_row_wifi` with
`android_kernel_lenovo_TB-8505F`, branch `lineage-23.2`.
