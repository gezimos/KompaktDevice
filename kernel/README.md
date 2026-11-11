# kernel

Our changes to Mudita's published kernel, and the scripts that build it. The
kernel tree itself is Mudita's and is not committed here.

```
patches/             our kernel patches
build-kernel.sh      builds Image.gz and the modules
stub/                stands in for the eink/ directory Mudita's release leaves out
trace-eink-spi.py    adds an SPI trace to the e-ink transport
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
| `0035-kompakt-eink-waveform-additions.patch` | additions on meink's own drawing: Fast speeds 8 and 9, blue noise, edge cut, the mode's tone curve for our dithers, dither brightness, the partial refresh box fix, the chosen mode back after every wake, and meink's clear before the always-on display. Modules only |
| `0036-kompakt-aod-straight-from-an-awake-display.patch` | DOZE requested while the display is awake marks the LCM low power, so locking can go straight to the always-on display with no panel power-down and no sleep picture under it |
| `0037-kompakt-warm-flash-led-outlives-the-torch.patch` | While the warm flash LED is held on from its sysfs switch, the camera HAL's torch on/off and its device close switch only the white LED, so turning the flashlight tile off no longer darkens the warm LED behind its tile's back |
| `0038-kompakt-a-rejected-upload-gives-the-buffer-mutex-back.patch` | meink's `uploadImageToDisplay` returns from a failed first SPI write with the buffer mutex held, and the next upload then blocks on it forever under the display mutex (the frozen AOD after a wake right after locking, build 424). The loader's display vtable copy is installed at probe and wraps `writeImage`/`writePartialImage`: a rejected upload gets its buffer mutex released. Modules only |
| `0039-kompakt-meink-event-thread-no-longer-spins-on-a-stale-queue-counter.patch` | meink's `[meink]event consumer` thread takes work from a queue with no lock and tests the queue's counter before it pops the list. A push from the display driver (the unblank and AOD entry hooks of 0035, overlapping the thread's pops after 0036) can leave the counter above the list; the pop then fails, nothing counts it down and the thread spins at 100% of a core until reboot. The loader changes the one instruction at `event_consumer_thrd+0x64` that reads the counter to read the list head, after checking the three instructions around it. A lost event from the same race is not recovered. Modules only |

| `0040-kompakt-binder-freezer.patch` | the binder half of Android's cached-app freezer: the `BINDER_FREEZE` and `BINDER_GET_FROZEN_INFO` ioctls, `BR_FROZEN_REPLY`, and the freeze race and async space fixes, as the Android common kernel carries them on 5.4. Without them system_server logs `Freezer disabled` at boot, cached apps keep running and are never compressed into zram. `struct binder_proc` lives in binder.c on 4.19, so its new fields are there |
| `0041-kompakt-frontlight-square-law-pwm.patch` | the front light's PWM duty from Android's 255 levels by a square law, 510 × (level ÷ 255)² of 1023, the same top as stock's linear map but twenty distinct duties below the old fifth step, so the dim light an e-ink front light runs at has steps for the auto-brightness ramp to walk. `backlight_debug_log`'s `map:` is now that duty; a one-time `kompakt-frontlight:` kernel line names the map. The Kompakt app and the overlay curve carry their levels in these steps |
| `0042-kompakt-frontlight-12-bit-pwm-period.patch` | the front light's PWM period from 1023 to 4095 with the clock divider down by the same factor (div 3 to 0), so the PWM frequency is unchanged and 0041's map has four times the steps: 2040 × (level ÷ 255)² of 4096. The period is written and read back the first time the light is set; if it does not take, the old period stays and 0041's duty is written. A `kompakt-pwm:` kernel line says which, and `map:` is now the fine duty, 0 to 2040 |

Applying every patch above in order, after the stub, reproduces the shipping kernel tree exactly.

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

## trace-eink-spi.py

Adds a trace of every SPI transfer between `meink.ko` and the panel to
`eink_spi_hal.c`. It edits the file in place (set the path at the top of the
script). The trace is off unless enabled with `einktrace.trace=1`; read it with
`dmesg | grep einkspi`.
