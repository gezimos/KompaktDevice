# tools

```
sleepimg.py            the pictures inside meink.ko
logoimg.py             the bootloader's logo partition
cpioedit.py            replace one file in the boot ramdisk
pack-recovery-boot.sh  boot.img with LineageOS recovery
make-full-ota.sh       the full update package
make-ota-json.py       the Updater's list for one package
```

The picture tools need Python 3 and Pillow, take any image format, and never
change a file's size. [docs/Images.md](../docs/Images.md) maps every picture on
the phone.

## sleepimg.py: the pictures inside meink.ko

meink paints four pictures itself: the sleep screen, the power-off screen, the
boot logo while the kernel comes up, and the flat-battery screen. They are byte
arrays in the module, and the tool rewrites them in place: size, symbols, CRCs
and vermagic stay the same.

```sh
python3 tools/sleepimg.py extract meink.ko -o pictures/
python3 tools/sleepimg.py patch meink.ko --logo assets/boot-logo.jpg --no-dither -o meink-new.ko --preview preview/
```

`--lock`, `--poweroff`, `--logo` and `--battery` each take a picture. Use
`--no-dither` for line art; photos get 16-level Floyd-Steinberg by default.
Always check `--preview`: it is exactly what the panel will show. Format:
480 × 800, 4 bytes a pixel (R = G = B, then 0xff), stored rotated 180°; the tool
rotates both ways.

The result ships in the vendor image as `/vendor/lib/modules/meink.ko`;
`vendor/scripts/apply-boot-logo.sh` runs this with the pictures in `assets/`.
A user's own sleep picture is written at runtime by the Kompakt app through
`/sys/einkinfo/sleep_image` ([docs/E-inkdriver.md](../docs/E-inkdriver.md)); the
picture in the module is what the app's Default restores.

## logoimg.py: the bootloader's logo partition

The `logo` partition holds 60 pictures; the boot screen is slot 0, repeated at
slot 38. The tool repacks it byte-identically (`verify` proves this) and keeps
the signing certificates that follow the pictures.

```sh
python3 tools/logoimg.py verify logo.bin
python3 tools/logoimg.py extract logo.bin -o pictures/
python3 tools/logoimg.py patch logo.bin --slot 0 assets/boot-logo.jpg --slot 38 assets/boot-logo.jpg -o logo-new.bin --preview preview/
```

Pictures here are upright, 8-bit grey. Flash from the **bootloader**
(`adb reboot bootloader`), not fastbootd:

```sh
fastboot flash logo logo-new.bin
```

Keep the original partition: it is the only way back to Mudita's boot screen,
and Mudita's updates do not carry it.

## cpioedit.py: one file in the boot ramdisk

Replaces one entry in a newc cpio (the boot ramdisk format) without unpacking
it; every other entry keeps its bytes, order, modes and inodes. With no entry
name it only checks that it can rebuild the archive byte for byte and prints
`ROUNDTRIP_IDENTICAL=True`. Run that first.

```sh
python3 tools/cpioedit.py ramdisk.cpio unused.cpio
python3 tools/cpioedit.py ramdisk.cpio new.cpio system/etc/init/hw/init.rc my-init.rc
```

It works on the decompressed cpio; unpack it from the boot image and repack it
around this.

## pack-recovery-boot.sh: boot.img with LineageOS recovery

Packs our kernel and dtb with the LineageOS recovery the device target builds
(`lunch lineage_kompakt-bp4a-userdebug; m bootimage`, with
[patches/](../patches/README.md) applied), using the header, offsets and
command line of Mudita's boot image. It leaves out tools the phone does not
need and puts our pictures into the recovery's `meink.ko`.

```sh
tools/pack-recovery-boot.sh <lineage tree> <Image.gz> <dtb> kompakt_boot_lineage_recovery.img
```

## make-full-ota.sh: the full update package

A full A/B update package from the images we flash by hand (boot with LineageOS
recovery, dtbo, vbmeta, system, vendor and Mudita's product), built with
LineageOS's OTA tool and signed with the release key the recovery trusts. Every
partition carries the package's date, or the installer refuses it as a
downgrade.

```sh
tools/make-full-ota.sh <lineage tree> vendor/lineage-priv/keys/releasekey out.zip \
    boot.img dtbo.img vbmeta.img system.img vendor.img product.img
```

The GSI build makes no target-files, so the script assembles one from the
system image's `build.prop`, with the device set to `Kompakt` (the recovery
checks it), the date set to now, and `ro.treble.enabled=false` to skip a VINTF
check this set cannot pass. `product` is Mudita's because the stock fstab
mounts it at first stage.

## make-ota-json.py: the Updater's list for one package

The LineageOS Updater on the phone reads
`releases/latest/download/<type>-<region>.json` from the KompaktOS repo, where
type is `gapps` or `vanilla` and region is `global` or `usa`. Each release
therefore carries four lists beside its four packages, one per package:

```sh
tools/make-ota-json.py KompaktOS-1.1-USA-GApps.zip system-gapps.img \
    https://github.com/gezimos/KompaktOS/releases/download/v1.1/KompaktOS-1.1-USA-GApps.zip \
    > gapps-usa.json
```

The date in the list comes from the system image, not the package: the package
is stamped with the time it was made, which would offer a phone its own build
again.
