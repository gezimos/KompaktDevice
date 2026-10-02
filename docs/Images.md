# Every picture on the phone

Where each picture the Kompakt shows outside Android lives, what paints it,
and how to change it. [tools/README.md](../tools/README.md) has the tools.

| Picture | Lives in | Painted by, when | Change it |
|---|---|---|---|
| Boot logo | `logo` partition, slot 0 | the bootloader, at power-on | `logoimg.py`, flash `logo` from the bootloader |
| Boot logo, second copy | `logo` partition, slot 38 | nothing on this phone (MediaTek's `boot_logo_updater`, which would, is not in this vendor) | same |
| Boot logo, kernel | `meink.ko`, `cImageMuditaLogo_map` | `meink_ed043wc5_init`, when vendor loads meink at early-init; stays on the panel until the lock screen, so a bootloop sits on this one | `sleepimg.py --logo`, vendor image (`apply-boot-logo.sh`) |
| Boot logo, recovery | the boot ramdisk's own `meink.ko` (`lib/modules`), `cImageMuditaLogo_map` | meink, when recovery loads it at first stage, before the recovery menu | `sleepimg.py --logo`, boot image (`tools/pack-recovery-boot.sh` patches it) |
| Sleep screen | `meink.ko`, `cImageMuditaLockScreen_map` | meink's fb notifier, on every panel power-down | the default: `assets/sleep-default.jpg` via `apply-boot-logo.sh`, vendor image. The user's own: the Kompakt app, through `/sys/einkinfo/sleep_image` ([E-inkdriver.md](E-inkdriver.md)) |
| Power-off screen | `meink.ko`, `cImageMuditaPowerOffScreen_map` | `power_off` and the notifier, at shutdown | `assets/power-off.png` via `apply-boot-logo.sh`, vendor image |
| Flat-battery screen | `meink.ko`, `cImageMuditaBatteryFullyDischargedScreen_map` | the same, when the shutdown is for a flat battery | `sleepimg.py --battery`, vendor image |
| Low battery outline | `logo` partition, slot 2 | the bootloader, too flat to boot | `logoimg.py` |
| Charging screens | `logo` partition, 25-30 and 37 (battery levels), 4-14 and 49-59 (digits, percent) | Mudita's `kpoc_charger` through `libshowlogo.so`, when a switched-off phone is plugged in. Both live in the system image; KompaktOS ships them in `vendor/kompakt/charger` | `logoimg.py` |
| Unused | `logo` partition, 1, 3, 31-34, 39-48 (one placeholder), 15-24 and 36 (white) | nothing | ignore |
| Android boot animation | system image, `vendor/kompakt/bootanimation/bootanimation.zip` in KompaktOS | `bootanimation`, from surfaceflinger's start to the lock screen. Mudita's vendor sets `debug.sf.nobootanimation=1`; the system image sets it back to 0 | `make-frames.py` beside the zip, system image |
| Recovery menu | LineageOS recovery in the boot ramdisk | recovery, drawn in black and white only; the kernel inverts every frame in recovery and fastbootd (`kernel/patches/0023`) | the recovery patches in `patches/bootable_recovery`, boot image |
| Boot mode menu, fastboot text | the bootloader, drawn as text | the bootloader | out of scope |

## Formats

**meink.ko arrays:** 480 × 800, 4 bytes a pixel, R = G = B with 0xff last,
stored rotated 180° (the panel's scan order). 1,536,000 bytes; the lock
symbol runs one row past that and nothing writes those bytes.

**logo partition:** MediaTek image. A 512-byte header (magic `0x58881688`,
body length, name `logo`, 0xff padding), then the body: count, body length,
one offset per picture, then that many zlib streams. Full screens decompress
to 480 × 800 BGRA, upright. After the body, 16-byte aligned, two more
MediaTek images, `cert1` and `cert2`: X.509 certificates from the image
signing, which `logoimg.py` keeps verbatim. An unlocked phone boots with a
modified body. The rest of the 11,010,048-byte partition is zero. `logo` is a
plain partition, not A/B, and Mudita's updates do not write it, so keep a copy
of the original: it is the only way back to Mudita's boot screen.

## Order at boot

Bootloader logo (slot 0) → kernel → meink loads and paints its own logo →
Android boot animation → lock screen. On MuditaOS and other system images the
animation is switched off and the meink logo stays until the lock screen.
Both logos carry the same art in Mudita's build, which is why replacing one
still shows theirs. A picture that should replace the Mudita logo everywhere
goes into slot 0, slot 38 and both copies of `meink.ko` (vendor and the boot
ramdisk).
