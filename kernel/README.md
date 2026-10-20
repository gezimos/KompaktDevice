# kernel

Our changes to Mudita's published kernel, and the scripts that build it. The
kernel tree itself is Mudita's and is not committed here.

```
patches/             our kernel patches
build-kernel.sh      builds Image.gz and the modules
stub/                stands in for the eink/ directory Mudita's release leaves out
patch-aod-boot.sh    older route: patches Mudita's stock kernel instead of building one
trace-eink-spi.py    adds an SPI trace to the e-ink transport
drivers/misc/kompakt/  an old e-ink shim; nothing loads it any more
```

## Get the source

```sh
git clone --depth 1 https://github.com/mudita/MuditaOS-K-Kernel-opensource.git \
    kernel/mudita/kompakt          # Release 1.5.0, Linux 4.19.191
K=kernel/mudita/kompakt
cp -r kernel/stub/* "$K"/
```

The stub is needed: Mudita's Kconfig and Makefile refer to
`drivers/misc/mudita/eink/`, which their `.gitignore` leaves out of the
release, and without it the tree does not configure. The stub declares the
config symbols and builds nothing. The panel driver `meink.ko` is proprietary
and comes from the vendor partition.

## Patches

| patch | what |
|---|---|
| `0020-kompakt-eink-complete.patch` | the kernel: partial e-ink updates, the always-on display that lets the phone sleep, the LED timer trigger, a writable panel temperature |
| `0021-kompakt-dtbo-from-source.patch` | builds the dtbo (`make mediatek/Kompakt.dtb`); changes nothing in `Image.gz`. See [dtbo/README.md](../dtbo/README.md) |
| `0023-kompakt-recovery-black-on-white.patch` | recovery and fastbootd in black on white |
| `0024-kompakt-usb-serial-null-tty.patch` | fixes a panic at USB plug-in when the serial port closes as the host opens it |
| `0025-kompakt-gpu-sync-lockup-recovery.patch` | keeps the GPU's sync lockup recovery on, so a dead fence cannot freeze the always-on display |
| `0026-kompakt-battery-capacity.patch` | full charge, charge counter and design capacity are the 3037 mAh this phone charges the cell to, so battery health reads 100% and the mAh figures add up |
| `0027-kompakt-notification-led.patch` | the notification LED takes brightness levels and the timed nodes LineageOS's lights HAL breathes it through |
| `0028-kompakt-led-level-log.patch` | one kernel line (`kompakt-led:`, visible in logcat) per light change: the level set, and for a timed light the duty peak it came from |
| `0029-kompakt-led-pwm-dimming.patch` | a steady notification light dims by the chip's 1 kHz PWM duty in 32 steps at full current; a breathing one by its peak current; the log line reads the DIM and ISINK registers back |
| `0030-kompakt-wf-dials.patch` | the waveform switches become dials: `kompakt_wf_a2frames` (2 to 6, every band) and `kompakt_wf_gl16trim` (frames dropped from the end of GL16, never below 4); `a2short` stays as the alias for 5. Experiments, off by default |
| `0031-kompakt-a2grey-bpp.patch` | `kompakt_wf_a2grey` works: after an A2 upload that carries the grey record, the loader's set-waveform hook lifts meink's bit depth to 4 (meink's own `pixelbits` setter is a no-op and A2 is 1 bpp by its table). Experiment, off by default |
| `0032-kompakt-auto-no-burst-flash.patch` | Auto's moving phase sets meink's one-shot skip-clear flag (render `+0x244`) before its GL16 to A2 switch, so a scroll burst no longer starts with a black and white flash |
| `0033-kompakt-bayer-dither.patch` | `kompakt_wf_dither`: `1` or `2` replaces meink's Floyd-Steinberg with an ordered Bayer pass (8x8 or 4x4) done in the loader, on exactly the frames the app or Auto asked to dither; the pattern stands still between frames. `kompakt_wf_dither_cut` (default `48 208`) leaves greys outside that range pure black or white, so light backgrounds and text edges get no dots. `3` is ordered error diffusion: Atkinson rounding against a Bayer threshold near the middle, spread by `kompakt_wf_dither_step`. `0` (default) is stock |
| `0034-kompakt-wf-du4.patch` | `kompakt_wf_du4`: the DU2 slot (2 bpp, unused by any mode) drives every grey straight to every other in one push of the GL16 family's charge difference, a balanced 4-grey fast mode at about half of Quality's time. Use with `waveform_mode DU2`. Off by default |
| `withdrawn/0022-kompakt-spi-write-clock.patch` | not applied: a faster SPI clock, after which the panel stopped refreshing. Kept as a record |

Applying 0020, 0021, 0023, 0024, 0025 and 0026 reproduces the shipping kernel tree exactly.

## Build

A shipping kernel is 0020, 0023, 0024 and 0025:

```sh
KOMPAKT_BUILD=<n> kernel/build-kernel.sh "$K" out \
    kernel/patches/0020-kompakt-eink-complete.patch \
    kernel/patches/0023-kompakt-recovery-black-on-white.patch \
    kernel/patches/0024-kompakt-usb-serial-null-tty.patch \
    kernel/patches/0025-kompakt-gpu-sync-lockup-recovery.patch
```

`KOMPAKT_BUILD` sets the build number in the kernel version, which the Kompakt
app shows under Installed images. The script needs AOSP clang-r383902
(`TOOLCHAIN=`) and a LineageOS tree (`LINEAGE=`). It builds with
`CROSS_COMPILE=aarch64-linux-gnu-`; with `aarch64-linux-android-` the kernel
builds and never boots. Full recipe in [docs/Kernel.md](../docs/Kernel.md).

## Verify before flashing

The kernel must keep loading Mudita's prebuilt `meink.ko`:

```
vermagic  4.19.191-00095-g83b1ab1a9a4b-dirty SMP preempt mod_unload modversions aarch64
CRCs      all 45 symbols meink.ko imports must match Module.symvers
```

`build-kernel.sh` pins the vermagic by writing `.scmversion` at the tree root.
With `VENDOR_MODULES=<folder of the stock .ko files>` it also checks all eight
prebuilt modules (meink, meink_hal, Wi-Fi, Bluetooth, GPS, FM, headset) with
`check-module-crcs.py` and stops on any mismatch. Any config change that shifts
those CRCs makes them refuse to load, so the kernel config is effectively fixed.

## patch-aod-boot.sh

The route before we built our own kernel: it patches 8 bytes of Mudita's stock
kernel so the always-on display lets the phone sleep, and repacks the boot
image.

```sh
kernel/patch-aod-boot.sh stock-boot.img boot-aod.img
```

## trace-eink-spi.py

Adds a trace of every SPI transfer between `meink.ko` and the panel to
`eink_spi_hal.c`. It edits the file in place (set the path at the top of the
script). The trace is off unless enabled with `einktrace.trace=1`; read it with
`dmesg | grep einkspi`.
