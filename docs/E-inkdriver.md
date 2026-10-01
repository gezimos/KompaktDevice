# The Kompakt e-ink driver stack

How the panel is driven on KompaktOS, what each piece does, and how to tune it.
See also [Kernel.md](Kernel.md) for the kernel as a whole, [Vendor.md](Vendor.md)
for the vendor partition and its SELinux policy, and [Images.md](Images.md) for
every picture the phone shows outside Android.

## 1. Hardware

| | |
|---|---|
| panel | ED043WC5, 480×800 at 213 dpi, 16 grey levels |
| attachment | SPI, `/sys/bus/spi/drivers/eink_spi/spi1.0` |
| SoC, kernel | MediaTek MT6761, Linux 4.19.191 |
| kernel config | `CONFIG_MUDITA_EINK=m`, `CONFIG_PANEL_EINK_ED043WC5=y`, `CONFIG_EINK_MTKFB_SUPPORT=y`, `CONFIG_MUDITA_EINK_TCORR=11` |

The panel is mounted as 800×480 landscape, so one panel row is one screen
column. A refresh is one waveform pass of roughly 200 ms, whatever the size of
the area. The controller ignores SPI writes that arrive during a pass, so every
write first waits for the panel to report ready.

## 2. The pieces

| piece | licence | source | ships in | job |
|---|---|---|---|---|
| `meink.ko` | proprietary, Mudita | binary only | vendor, `/vendor/lib/modules/` | the render engine: converts frames to the panel format, holds the waveform tables and four built-in pictures, runs the panel state machine |
| `meink_hal.ko` | GPL | Mudita's `eink_spi_hal.c` + our `kernel/patches/0020` | vendor | SPI transport and panel power. Every byte meink sends passes through it, so partial updates and Auto live here |
| `meink_loader.ko` | GPL | Mudita's `loader.c` + 0020 | vendor | the SPI driver: probes the panel, calls meink's `EinkInit()`, creates `/sys/einkinfo/` |
| `mtkfb` | GPL | `drivers/misc/mediatek/video/mt6765/videox/mtkfb.c` + 0020, 0023 | kernel image, `boot.img` | the framebuffer: hands each new frame to meink, drives the AOD transitions, inverts recovery |

The two GPL modules come from `drivers/misc/mudita/eink_loader/` in Mudita's
published kernel; [kernel/README.md](../kernel/README.md) has the build. Our
vendor image ships Mudita's `meink.ko` with its code untouched and only its
pictures replaced ([tools/README.md](../tools/README.md)).

Our `meink_hal` and `meink_loader` import functions only our kernel exports, so
**our vendor image needs our boot image**. The system image depends on neither
and runs on stock boot and vendor; features that need our images are simply not
offered there.

`init.project.rc` loads the modules explicitly, in the order `meink_hal`,
`meink`, `meink_loader`; `modules.load` is ignored on this device. The LineageOS
recovery in our boot image carries its own copy of the modules in the ramdisk,
so recovery and fastbootd drive the panel themselves (§12).
`kernel/drivers/misc/kompakt/kompakt_eink.c` is a tracing shim; no shipping
image loads it.

**How a frame reaches the panel.** Android composes into the framebuffer.
mtkfb copies each frame, compares it with the previous one, and if it changed
(or a repaint was requested) calls meink's update hook. meink renders it at the
current waveform, bit depth, gamma, contrast, brightness and dithering, and
sends a window, the pixels and a refresh command through `meink_hal`, which
decides what actually goes over SPI (§7).

## 3. What replaces MuditaService

On MuditaOS, `com.mudita.service` (uid system) writes `/sys/einkinfo` once at
start, with A2 at 1 bpp as its baseline, and afterwards changes only contrast
and dithering per app. KompaktOS has no MuditaService. The Kompakt app
(`KompaktService` in the KompaktOS repository) takes its place: it also runs as
uid system, and applies a refresh mode device-wide or per app (§5).

## 4. `/sys/einkinfo`

Owned `system:system`. Values are text with a trailing newline.

| node | read | write |
|---|---|---|
| `waveform_mode` | current waveform | `A2`, `DU2`, `DU4`, `GL16`, `GC16`, `AUTO`; `KAUTO` for Auto mode (§9) |
| `pixelbits` | bits per pixel | `1`, `2` or `4` |
| `gamma` | gamma level | `-1` = 1.00, `0` = 0.25, `1` = 0.50, `2` = 0.75, `3` = 1.25, `4` = 1.50, `5` = 2.00, `6` = 2.20 |
| `contrast` | contrast | 0 to 255; `10` is neutral |
| `brightness` | brightness | 0 to 255; `100` is neutral |
| `dither_type` | algorithm | `0` off, `4` Floyd-Steinberg (the only one KompaktOS uses) |
| `dither_param` | amount | 0 to 255 |
| `dither_colors` | same as `dither_param` | MuditaSDK compatibility: non-zero also forces `dither_type 4`, `0` turns dithering off |
| `timings_mode` | controller timing set | `clean`, `text` (high contrast), `fast` |
| `refresh_mode` | meink's refresh mode, `deep` by default | a name meink knows; KompaktOS leaves it alone |
| `manual_mode` | `1` | `1`: use the waveform in `waveform_mode`. `0`: meink chooses, with full, flashing refreshes |
| `fps_limit` | meink's frame rate cap | a number; stock is 62 |
| `clear` | – | `0` or `1`: flash white or black, then repaint the current frame |
| `power` | panel power | `1` on, `0` off |
| `eink_temperature` | panel temperature, °C | a temperature offset (§10) |
| `temperature_offset` | current offset | a temperature offset |
| `log_level` | `meink_hal` debug level | a number |
| `refresh_time` | last, min, avg, max refresh in µs, count, last mode | anything: resets the counters |
| `sleep_image` | the sleep screen frame | a new frame (§8) |
| `sleep_image_stock` | the frame built into `meink.ko` | read only |

`refresh_time` and both `sleep_image` nodes exist only with our `meink_loader`,
and `eink_temperature` is writable only with it.

```
A2     1 bpp   fastest, no flash, never fully settles, so ghosting builds up
DU4    2 bpp   medium fidelity, suited to text
GL16   4 bpp   high fidelity, no flash
GC16   4 bpp   high fidelity, flashes
```

A2 ghosting stays until something drives the whole panel: a GL16 mode, a
periodic full frame (§7), the screen-off flash, or `clear`.

**Access.** The Kompakt app reaches every node: it runs as uid system and the
vendor policy grants `system_app` each e-ink type. Mudita's policy gives most
nodes their own SELinux type but leaves `refresh_mode`, `manual_mode`,
`temperature_offset` and `log_level` as generic `sysfs`, which no app may be
granted. Our vendor labels `refresh_mode`, `manual_mode`, `log_level` and
`sleep_image*` as `sysfs_eink_misc`, granted to `system_app` and `shell`.
Mudita's own types are granted to apps, not to `adb shell`, so set modes from
the app. Mudita's `init.project.rc` chmods `dithering_*` names that do not
exist; ours adds `chmod 0666` for the real `dither_*` nodes and each node we
use. `vendor/scripts/apply-eink-access.sh` applies all of this; see
[Vendor.md](Vendor.md) §2 and §7.

## 5. Refresh modes

A mode is a preset of the nodes above, applied by the Kompakt app for the whole
device or per app. An app with no mode of its own gets **Fast + dither**.

| mode | waveform, bpp | gamma, contrast | dithering | for |
|---|---|---|---|---|
| Fast | A2, 1 | 0.50, 10 | off | no flash, very high contrast; dark colours go black |
| Fast, soft | A2, 1 | 1.25, 8 | off | no flash, less contrast, dark colours keep some detail |
| Fast + dither | A2, 1 | 0.50, 12 | Floyd-Steinberg, 96 | no flash, greys as dots; the most detail at speed |
| Text | GL16, 4 | 0.50, 12 | off | sharp greys for reading; slower |
| Quality | GL16, 4 | 0.75, 10 | off | the cleanest picture; slowest |
| Auto | `KAUTO` | as Quality | switched by the kernel | fast while moving, Quality once still (§9) |

Every mode also writes `timings_mode clean` and brightness 100. Auto needs our
vendor and boot images; elsewhere the app sees the kernel did not take `KAUTO`
and applies Quality.

## 6. `meink_hal` module parameters

`/sys/module/meink_hal/parameters/`. A change applies to the next frame; a
reboot restores the defaults.

| parameter | default | what it does |
|---|---|---|
| `partial` | 1 | send only changed rectangles (§7); `0` is stock behaviour |
| `partial_max_pct` | 25 | above this share of screen rows changed, send the full frame |
| `partial_full_every` | 24 | after this many partial updates, send one full frame to clear residue |
| `semi_partial` | 1 | when a full frame goes out, refresh only the band that changed (§7) |
| `semi_window` | 1 | narrow the controller's window to that band too. Leave at 1 |
| `deghost_every` | 8 | run meink's screen-off de-ghost flash on every Nth sleep; `1` = always |
| `auto_busy_pct` | 25 | share of screen rows changed that counts as movement (§9) |
| `auto_busy_frames` | 1 | moving frames in a row before Auto switches to fast |
| `auto_idle_ms` | 2000 | quiet time before Auto settles back to quality |
| `auto_calm_pct` | 5 | below this share changed, the screen counts as still |
| `trace` | 1 | log every SPI transfer (`einkspi`). Noisy; `0` silences it |
| `measure` | 1 | log each refresh's duration (`einktime`) and waveform table uploads |

```sh
adb shell cat /sys/module/meink_hal/parameters/auto_idle_ms
adb shell 'echo 1200 > /sys/module/meink_hal/parameters/auto_idle_ms'
adb shell 'echo 0 > /sys/module/meink_hal/parameters/trace'
```

The directory is labelled `sysfs_eink_param` and granted to `shell` and
`system_app`. The label is a path prefix and covers new parameters
automatically; the file mode does not, so each parameter needs its own chmod
(§13). `auto_calm_pct` has none yet: readable over adb, not writable.

Kernel log lines appear in logcat. `einkpart` reports partial and semi-partial
updates, `einkauto` Auto switches, `einktime` refresh durations, `kompakt-aod`
AOD transitions, `kompakt-sleepimg` the sleep screen:

```sh
adb logcat -c && adb logcat | grep -E 'einkpart|einkauto|einktime|kompakt-'
adb shell cat /sys/einkinfo/refresh_time
```

## 7. Partial updates

meink always sends whole frames. `meink_hal` keeps a copy of what the panel
shows, compares each new frame with it, and sends:

- **nothing**, when nothing changed: the frame and its refresh are dropped;
- **the changed rectangles**, each with its own refresh, at most two per frame.
  A band with unchanged rows in the middle is split, so a seekbar's time label
  and playhead get one small rectangle each. A rectangle that fails to send is
  retried with the next frame;
- **the full frame**, when more than `partial_max_pct` changed, when the change
  needs more than two rectangles, and every `partial_full_every`th update.

A full frame is also forced after a panel power-up, a bit depth change, a new
waveform, an AOD transition, and for the first frame after boot: in each case
the glass content is unknown, so a diff would be wrong. Each rectangle costs a
full waveform pass, which is why the limit is two. The gain is less flashing and
less SPI traffic, not a faster pass.

**Semi-partial.** The panel is bistable: an area the waveform does not drive
keeps its ink. So when a full frame goes out, `meink_hal` narrows its refresh to
the band of screen rows that changed. All the pixels still reach the controller,
but only that band is driven, and the status bar stops flashing on every page
turn. It is not applied to the forced full frames above or to the
`partial_full_every` pass, whose purpose is to drive what has not changed.

**Screen-off de-ghost.** On screen-off meink flashes the panel white, then
black. `meink_hal` lets that through only on every `deghost_every`th sleep.

**Panel power.** If meink paints while the panel rail is off, `meink_hal` powers
the panel on and resends its last configuration first.

## 8. The sleep screen

The sleep screen is a picture inside `meink.ko`, painted by meink itself on
every panel power-down. With AOD off it is what the phone shows asleep; with AOD
on it shows briefly on lock, until the AOD clock is painted over it.

| node | mode | |
|---|---|---|
| `/sys/einkinfo/sleep_image` | 0666 after init | read: the frame meink will paint. Write: a new one |
| `/sys/einkinfo/sleep_image_stock` | 0444 | the frame built into `meink.ko` |

A frame is 480×800, 4 bytes a pixel with R = G = B and `0xff` last, stored
rotated 180°: 1,536,000 bytes. A write takes effect only once all of it has
arrived in order from offset 0; a short or interrupted write changes nothing.
The first write of a boot keeps the original aside for `sleep_image_stock`.

`meink_loader` finds the picture by name in meink's symbol table and writes it
through a temporary writable mapping; `meink.ko` on disk never changes. So the
picture resets at every boot, and the Kompakt app writes the user's picture
again at start-up. On our vendor the built-in picture is
`assets/sleep-default.jpg`; to change that default, use `tools/sleepimg.py`
([Images.md](Images.md)).

```sh
adb exec-out cat /sys/einkinfo/sleep_image > sleep.raw                       # save it
adb shell 'cat /sys/einkinfo/sleep_image_stock > /sys/einkinfo/sleep_image'  # built-in, until reboot
```

**Keeping Android's last frame off it.** meink paints the picture from its
framebuffer blank notifier while Android's display pipeline is still running,
and Android's last frame before sleep (an opaque black scrim) could land after
it. `meink_loader` wraps meink's frame hook and registers one notifier just
before meink's and one just after; Android frames that arrive in between are
dropped, and marked so the next identical frame is still sent.

## 9. Auto mode

Fast while the screen moves, quality once it settles. `meink_hal` already diffs
every frame (§7), so it knows how much changed:

- A frame with at least `auto_busy_pct` of screen rows changed is movement.
  After `auto_busy_frames` of them in a row, Auto switches to fast.
- Any frame at or above `auto_calm_pct` restarts the settle timer. When
  `auto_idle_ms` passes with only quieter frames, Auto switches to quality and
  repaints, so the clean version appears without a touch.
- Between the two thresholds the state is held, so a blinking cursor or a clock
  cannot keep the screen in fast.

| state | waveform | bpp | dithering |
|---|---|---|---|
| moving | A2 | 1 | Floyd-Steinberg |
| settled | GL16 | 4 | off |

Gamma, contrast and brightness stay as the mode set them. Switches run on a
kernel workqueue, never on meink's thread, which would re-enter meink mid-SPI.

Auto is switched on by writing `KAUTO` to `waveform_mode`, and off by writing
any other waveform; while on, `waveform_mode` reads `KAUTO`. Using an existing,
already-labelled node avoids a new SELinux type, and makes Auto self-detecting:
meink does not know the name, so on a kernel without Auto the write is ignored,
`waveform_mode` keeps the old value, and the app falls back to Quality.

## 10. Temperature offset

meink picks its waveform tables by panel temperature, in bands of about 3 °C. A
positive offset tells it the panel is warmer than it is, so it drives shorter
waveforms: faster, but less clean. The Kompakt app offers 0, 5, 10, 20, 30 and
40 °C.

Mudita's vendor gives `temperature_offset` no label and no chmod, so our
`meink_loader` also takes the offset on `eink_temperature`, which has both.
Reading `eink_temperature` still returns the measured temperature.

```sh
adb shell cat /sys/einkinfo/eink_temperature     # measured, °C
adb shell cat /sys/einkinfo/temperature_offset   # current offset
```

## 11. AOD

Android's doze moves the display to DOZE (AOD showing) or DOZE_SUSPEND (AOD
showing, SoC allowed to sleep) through mtkfb, which tells meink to enter or
leave its AOD mode. Our kernel changes that path in four places:

- **AOD is reported as supported.** The display driver's nominal LCM is a
  placeholder that is never driven, so the stock check always said no and
  DOZE_SUSPEND never suspended. The placeholder also gets an empty `aod`
  callback, without which DOZE entry falls back to a full resume.
- **Wake from AOD.** The stock resume never takes meink out of AOD. mtkfb does
  it on unblank, holding off the panel power-off meink would send during that
  call, then asks meink through `meink_loader` to wake and power the panel on.
- **Power-down from AOD.** mtkfb takes meink out of AOD before suspending.
- **Every AOD transition forces a full frame.** meink paints the AOD clock
  through the same write path, so `meink_hal`'s copy of the glass holds the
  clock afterwards. Without the reset, the first frame after a wake could be
  diffed against it and dropped, leaving a blank panel on an awake phone.

## 12. Recovery and power-off

**Recovery, black on white.** Recovery and fastbootd draw white on black, which
on e-ink is a large area of ink on every repaint. mtkfb inverts each frame it
hands meink in a recovery boot (`kernel/patches/0023`): one whose kernel command
line carries Android boot flags but not `androidboot.force_normal_boot=1`.
Normal boots are never inverted. The inversion goes to a separate buffer, so
mtkfb's comparison copy is untouched. mtkfb's `kompakt_invert` parameter forces
it on in any boot.

**Power-off picture.** A reboot notifier in `meink_loader` paints meink's
power-off picture last, waits for it to reach the panel, and drops every Android
frame after it, so the phone never switches off showing the last app. A
shutdown for a flat battery shows the flat-battery picture instead.
[Images.md](Images.md) covers both pictures.

## 13. Rules for maintainers

- **Wrap meink's hooks after `EinkInit()`.** meink registers its frame hook
  inside `EinkInit()`, which `meink_loader` calls from its SPI probe. Anything
  registered at module init is overwritten a moment later. Wrap in the probe,
  after `EinkInit()` returns.
- **Each module parameter needs a chmod.** `module_param` rejects the
  world-write bit at compile time, so `init.project.rc` carries a
  `chmod 0666` per parameter: add the name to `PARAMS` in
  `vendor/scripts/apply-eink-access.sh`. For those chmods to work `init` needs
  `setattr` on the e-ink types, which `vendor/scripts/fix-orphaned-vendor-types.sh`
  adds ([Battery.md](Battery.md)).
- **A new sysfs node needs vendor policy.** It gets the generic `sysfs` label
  and stays unreachable until the vendor CIL declares a type, labels the node
  and grants it ([Vendor.md](Vendor.md) §7). Prefer a path an existing
  `genfscon` prefix covers, as `sleep_image_stock` does, or an existing node, as
  Auto does.
- **A module needs its own `init.project.rc` line.** Anything of ours that talks
  to meink loads between `meink.ko` and `meink_loader.ko`.
- **The kernel must keep loading `meink.ko`.** `CONFIG_MODVERSIONS` is on, so
  every symbol meink imports must keep its CRC, and the vermagic must stay
  `4.19.191-00095-g83b1ab1a9a4b-dirty`. `kernel/build-kernel.sh` checks both
  ([Kernel.md](Kernel.md)).
- **Build the vendor modules and the boot image from the same tree**, since our
  `meink_hal` and `meink_loader` import our kernel's exports.
- **Do not invent waveforms.** The tables come from the panel maker and are
  compiled into `meink.ko`. Wrong waveforms usually only ghost, but sustained
  wrong drive voltages can mark e-ink permanently.

## 14. Tried and reverted

- A dirty-rectangle diff in mtkfb stopped AOD repainting; reverted.
- Raising the SPI clock to 18.2 MHz stopped the panel refreshing; withdrawn
  (`kernel/patches/withdrawn/`).
- A whole-panel invert mode also inverted the lock screen and AOD, so it could
  not be per app; removed.
- Free-form per-app dials could leave the panel black with no way back; replaced
  by the fixed modes in §5.
