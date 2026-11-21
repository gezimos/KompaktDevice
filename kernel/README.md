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
| `0038-kompakt-a-rejected-upload-gives-the-buffer-mutex-back.patch` | meink's `uploadImageToDisplay` and `writeDisplayPattern` return from a failed first SPI write with the buffer mutex held, and the next taker blocks on it forever under the display mutex. Through `writeImage`: the frozen AOD after a wake right after locking (build 424). Through `clear`: the lock's clear leaked it on its first clear and blocked on its second, and the next AOD tick's `EinkDisplayOpen` hung the hardware composer, a black screen while the phone kept working (build 459). The loader's display vtable copy is installed at probe and wraps `writeImage`, `writePartialImage`, `open` and `clear`; a buffer mutex still held when one returns is released and logged (`kompakt-eink: <call> left it locked`). Modules only |
| `0050-kompakt-the-kompakt-app-decides-whether-the-camera-is-cut.patch` | Mudita's kernel cut the camera's analog supply (GPIO168) and every sensor power pin whenever the Offline+ switch was engaged: the switch interrupt set `hwswitch_camera_is_permitted` to 0 and `imgsensor_hw_power_sequence` forced it to 0 at every open, so nothing in the app could change it. The switch no longer touches the camera flags. They are set only through `cameragpio_state` (`camera_gpio_ctl`), which the Kompakt app writes: 0 while Offline+ is on and Camera access is blocked, 1 otherwise. Permitted at boot, so the camera is still recognized then. Needs the vendor label for `cameragpio_state` and KompaktOS 1.3. Kernel image (boot) |
| `0049-kompakt-panel-writes-wait-out-a-system-suspend.patch` | meink's event thread is not freezable and keeps painting while the phone suspends; once the SPI controller is suspended, `spi_write` returns `-ESHUTDOWN`, the failure that leaks meink's buffer mutex (0038). Every HAL write goes through `eink_spi_write`, which retries every 20 ms until the controller is back (up to 30 s awake) and logs a write that needed it (`einkspi: write`). Modules only |
| `0039-kompakt-meink-event-thread-no-longer-spins-on-a-stale-queue-counter.patch` | meink's `[meink]event consumer` thread takes work from a queue with no lock and tests the queue's counter before it pops the list. A push from the display driver (the unblank and AOD entry hooks of 0035, overlapping the thread's pops after 0036) can leave the counter above the list; the pop then fails, nothing counts it down and the thread spins at 100% of a core until reboot. The loader changes the one instruction at `event_consumer_thrd+0x64` that reads the counter to read the list head, after checking the three instructions around it. A lost event from the same race is not recovered. Modules only |

| `0040-kompakt-binder-freezer.patch` | the binder half of Android's cached-app freezer: the `BINDER_FREEZE` and `BINDER_GET_FROZEN_INFO` ioctls, `BR_FROZEN_REPLY`, and the freeze race and async space fixes, as the Android common kernel carries them on 5.4. Without them system_server logs `Freezer disabled` at boot, cached apps keep running and are never compressed into zram. `struct binder_proc` lives in binder.c on 4.19, so its new fields are there |
| `0041-kompakt-frontlight-square-law-pwm.patch` | the front light's PWM duty from Android's 255 levels by a square law over a 12-bit period: the period goes from 1023 to 4095 with the clock divider down by the same factor (div 3 to 0), so the PWM frequency is unchanged, and the duty is 2040 × (level ÷ 255)² of 4096: the same top as stock's linear map, with twenty distinct duties below the old fifth step, so the dim light an e-ink front light runs at has steps for the auto-brightness ramp to walk. The period is written and read back the first time the light is set; if it does not take, the old period stays and the light runs on 510 × (level ÷ 255)² of 1023. A `kompakt-pwm:` kernel line says which, a one-time `kompakt-frontlight:` line names the map, and `backlight_debug_log`'s `map:` is the fine duty, 0 to 2040. The Kompakt app and the overlay curve carry their levels in these steps |
| `0043-kompakt-mode-writes-wait-for-the-wake.patch` | from the AOD's entry or the sleep screen's power-down until the next unblank, writes to `waveform_mode`, `pixelbits`, the dither nodes and the waveform table dials are kept and applied at the unblank (table dials from a work item after it): a waveform table upload to the panel in DOZE_SUSPEND never returned and hung every wake (build 453, app 402). Modules only |
| `0044-kompakt-gyro-bias-learned-and-subtracted.patch` | the gyro reads about 3 °/s lying still and nothing calibrates it: no `gyro_cali.json` or `gyro_bias.json` was ever saved in `nvcfg`, the SCP firmware refuses the factory calibration ("detect shake" lying flat), never sends a bias and ignores one written to `gyrocali`. `gyro_recv_data` now learns the bias from the raw samples (2 s with every axis within 1 °/s peak to peak and a mean under 10 °/s) and subtracts it before the HAL; a change over 0.1 °/s, at most once a minute, goes out through `gyro_bias_report`, which the sensor HAL saves as `gyro_bias.json` and writes back to `gyrocali` at start-up. A `kompakt-gyro: bias` kernel line shows each save. The factory node still reads the raw rate. Stops MediaTek's video stabilization drifting (KompaktOS 1.3 still turns stabilization off: EIS drops frames on this SoC) |
| `0045-kompakt-meink-redraws-follow-its-dither.patch` | meink's own redraws (AOD-entry clear, full refresh every N, deep refresh, operational clear) called `hsmThreadedGetNewestFrameBuffer` with 0 and drew the undithered frame; a new frame takes the dithered copy when the render's dithering type (+0x34) is set. With Normal dither the AOD wallpaper came out thresholded after locking and Fast + dither apps kept grey patches after a full refresh. The loader patches the four call sites at probe to pass the dithering type, checking each instruction and call target first. `kompakt-eink: N of 4 redraws follow meink's dither` at boot. Modules only |
| `0046-kompakt-a-wake-that-draws-nothing-is-logged.patch` | a wake within seconds of locking left meink taking frames and drawing none (kprobes, build 459: MeinkWriteImage returns 0, the state machine drops the event). Two seconds after each unblank the loader compares the HAL refresh count with the one at the unblank; frames sent and none drawn is logged (`kompakt-eink: wake drew nothing`). Log only: a forced clear (in 460 to 462) never recovered a freeze and fired on healthy wakes whose one frame matched the glass, redrawing the screen in GL16: a black flash after unlock. Modules only |
| `0047-kompakt-the-lock-clears-the-panel-before-the-aod.patch` | locking with AOD on showed the AOD, a black flash, then the AOD again: the AOD-entry clear (0035) runs at the switch to DOZE, after Android has drawn the AOD. SystemUI (KompaktOS frameworks_base 0139) writes 1 to `/sys/einkinfo/kompakt_wf_lockclear` as the lock starts; the loader runs the same GL16 to A2 flash then and stays on A2, so the DOZE entry has nothing to clear. 0 at the wake gives a lock that never reached DOZE the user's mode back. `einkwake: lock, meink clears the awake screen before the AOD`, then `AOD entry, cleared at the lock`. Modules only; the node needs the vendor chmod (`apply-eink-access.sh`) |
| `0048-kompakt-fast-speed-is-the-count-asked-for.patch` | `kompakt_wf_a2frames` shortened only for 7 and below and lengthened only for 8 and 9, written for an A2 band of 7 frames. The panel reports about 8 °C in a 20 °C room (SPI `40` reads `08`/`09`, battery 24 °C), so at Mudita's +11 the band is 6 and has 11 frames: 8 and 9 did nothing and the app's "7" was 11. It now takes 2 to 11 and sets exactly that count on every band; 0 leaves the band's own. A2 frames are all the same push, so any count is a valid record. Modules only |

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
