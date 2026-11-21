# Changelog

The boot image (kernel and LineageOS recovery) and the vendor images. Each
KompaktOS release ships these inside its full update package; the recovery
image is also released here on its own.

## 1.3 (2026-11-21)

Boot 284 (released on its own as recovery 1.3), vendor 331 for Global and USA.

### Front light

- **Dim light has steps.** Android sends the front light 255 levels, and the
  kernel mapped them to the PWM in steps of 4 of 1023, so the bottom few
  percent the light runs at on e-ink had five levels, each a visible jump. The
  map is now a square law over a 4096-step PWM period at the same PWM
  frequency: the same light at the top, sixteen times the steps at the dim
  end, so the automatic brightness can fade a change of room through steps
  too small to see. Needs KompaktOS 1.3 for the fade and the curve.
  `kernel/patches/0041`.

### Offline+

- **Camera access is a real block, and only the app's choice.** The kernel cut
  the camera's power whenever the switch was engaged, so the camera could not
  open in Offline+ even with Camera access left alone in the Offline page, and
  turning it on only asked Android to block the camera, which a tap on the
  "unblock" prompt undid. The switch no longer touches the camera. With Camera
  access on, the Offline page now cuts the camera's power as well while the
  switch is on, and nothing on the phone can turn it back on until you flip
  the switch or turn the row off. Needs KompaktOS 1.3.
  `kernel/patches/0050`, `vendor/scripts/apply-camera-switch-access.sh`.

- **Started with Offline+ on, the modem no longer resets every 14 seconds.**
  With the switch engaged the modem fails its radio self-check as it boots, and
  MediaTek's init daemon restarted it without end, with the phone process dying
  and restarting alongside, for as long as the switch stayed on. The modem is
  now only started once the switch is off, at boot or when you flip it, and
  comes up within seconds of the flip. Needs KompaktOS 1.3 for the phone
  process half. `vendor/scripts/apply-offline-modem-gate.sh`.

### Memory

- **Apps you leave are frozen.** Android freezes an app a few seconds after
  you leave it, so it uses no processor until you come back. Two things kept
  it off at every boot ("Freezer disabled"): the kernel lacked the binder half
  of it, and Mudita's vendor pointed Android's freezer profile at a cgroup v1
  file this phone does not have. `kernel/patches/0040`,
  `vendor/scripts/apply-freezer-profiles.sh`.

### Flashlight

- **The warm light stays on when the white one goes off.** With both on,
  switching the white flashlight off turned the warm one off too, while its
  tile still showed it on. `kernel/patches/0037`.

### E-ink

meink draws, as in 1.2; these add to the tables and dithers it uses
(`kernel/patches/0035`).

- **No frozen screen after a wake right after locking.** With the always-on
  display coming straight from an awake screen, a wake within a second or two
  could meet a frame still being uploaded; a failed SPI write inside meink then
  left its buffer lock held, the next upload waited on it forever, and the wake
  behind that. The screen kept the clock until a forced restart. The loader
  now gives the lock back when an upload is rejected. `kernel/patches/0038`.
- **No black screen that never changes after locking.** The panel's clear as
  the phone locks could still be running when the phone went into deep
  sleep; its SPI write failed, meink kept its buffer lock, and the next
  always-on display update waited on it forever. The phone kept working
  (calls, unlock) behind a screen that never changed until a forced restart.
  Panel writes now wait for the phone to wake, and the loader gives the lock
  back after a clear or an open as well. `kernel/patches/0038`, `0049`.
- **No frozen screen when a mode changes as the phone locks.** A mode or
  waveform change that reached the panel after the always-on display had put
  it to sleep sent a waveform table to an unpowered panel; it never returned,
  and every wake after it hung until a forced restart. Changes made while the
  screen is off now wait for the wake. `kernel/patches/0043`.
- **Normal dither stays dithered when the driver redraws by itself.** meink
  redraws its last frame on its own when the always-on display comes on, on
  the full refresh every few updates and when clearing ghosts, and it took
  that frame undithered. With Normal dither the always-on wallpaper came out
  as hard black shapes after locking, and apps in Fast + dither could pick up
  grey patches that only a mode change cleared. Those redraws now use the
  dithered frame. `kernel/patches/0045`.
- **A wake that draws nothing is logged.** A wake within a few seconds of
  locking could leave the screen on an old picture while the phone ran
  normally. Two seconds after each wake the loader checks that something
  was drawn and logs it if not (`kompakt-eink: wake drew nothing`). It does
  not clear the screen: that never brought a frozen screen back, and it
  flashed healthy wakes. `kernel/patches/0046`.
- **No ghost of the previous screen after a slide-in.** A partial refresh
  could leave one changed area out (two separated areas, the first in two
  parts, such as the app drawer sliding over the home screen); that area kept
  the old picture until something redrew it. Every changed area now gets
  refreshed, or the whole screen is. The HAL.
- **Fast speed is the count asked for.** `kompakt_wf_a2frames` takes 2 to 11
  and gives the fast waveform exactly that many frames; 0 leaves Mudita's.
  The panel reports about 8 °C in a 20 °C room, so at Mudita's +11 offset the
  fast waveform has 11 frames, not 7. `kernel/patches/0048`.
- **Blue noise dithering** (`kompakt_wf_dither 4`): dots that stay put like
  Pattern, without its grid.
- **Text stays sharp with the Pattern, Hybrid and Noise dithers.** A pixel at a
  sharp edge (text, lines, icons) is cut to black or white instead of dotted;
  photos and gradients are still dithered. `kompakt_wf_dither_edge` sets how
  sharp, 0 turns it off.
- **Text in the Pattern, Hybrid and Noise dithers is as bold as in Normal.**
  They follow the mode's tone curve, as meink's own dither does, and cut text
  edges at the same grey; before, they saw lighter greys and drew thinner
  strokes.
- **Dither brightness** (`kompakt_wf_dither_light`, 0 to 3): lifts the dark
  greys of Pattern, Hybrid and Noise so photos keep their shadows; text keeps
  its weight.
- **Waking keeps your e-ink mode.** meink switched to Fast on every wake, so
  a Quality or Text phone drew the lock screen in Fast. The loader sets your
  mode again right after.
- **Locking goes straight to the always-on display.** No panel power-down
  and no sleep picture before it: the panel clears once as you lock, then
  draws the always-on display, whose clock and notification updates draw in
  Fast, whatever mode is chosen. The sleep picture still shows when the
  always-on display is off. `kernel/patches/0036`, `0047`.

## 1.2 (2026-10-20)

Boot 275 (released on its own as recovery 1.1), vendor 297 for Global and USA.

### Speed

- **Swiping and scrolling are smoother.** Each touch holds the CPU at
  1.075 GHz or more for a second, as MuditaOS does while scrolling.
  `vendor/scripts/apply-power-hints.sh`.

### Battery

- **Battery health reads 100%.** Full charge, the charge counter and the
  design capacity read 3037 mAh, what this phone charges the cell to.
  `kernel/patches/0026`.

### Sound

- **Quieter lowest ring and notification steps** on the speaker.
  `vendor/scripts/apply-volume-curves.sh`.
  - Android's default speaker curve instead of Mudita's.
  - Step 1 goes from -25.8 dB to -45.7 dB. Full volume is unchanged.
- **In-call earpiece volume goes much lower.** `vendor/scripts/apply-speech-volume.sh`.
  - The six call steps are -28, -21, -15, -8, -2 and +5 dB (Mudita's: -10 to
    +5 dB), on normal, VoLTE and Wi-Fi calls.
  - The loudest step is unchanged.
  - Needs KompaktOS 1.2, which drops MtkInCallService (device_phh_treble 0014).

### Notification light

- **The LED runs through LineageOS's lights HAL.** `kernel/patches/0027`,
  `0028`, `0029`, `vendor/scripts/apply-lights-hal.sh`.
  - Colours mix on the red, green and blue LEDs.
  - A steady light dims in 32 steps.
  - A pulsing light runs at full brightness: the PMIC's breath mode cannot be
    dimmed on this LED.
  - The driver logs each level it sets (`kompakt-led:` in logcat).

### E-ink

- **The last app no longer shows through the sleep screen.** `meink_loader`
  waits for a frame still on its way before the sleep picture.
  `kernel/patches/0020`, `loader.c`.
- **Waveform switches**, off by default. `kernel/patches/0020`,
  `vendor/scripts/apply-eink-access.sh`.
- **Waveform dials for experiments**, off by default: `kompakt_wf_a2frames`
  (Fast at 2 to 6 frames, every band) and `kompakt_wf_gl16trim` (frames
  dropped from the end of Quality). `kernel/patches/0030`, in the vendor's
  `meink_loader`; `apply-eink-access.sh` makes the two nodes writable like
  the switches.
- **`kompakt_wf_a2grey` works**: Fast with real greys. meink's `pixelbits`
  setter is a no-op and A2 is 1 bpp by its table, so the grey record never
  had grey input; the loader now lifts the depth to 4 after an A2 upload that
  carries it. Experiment, off by default. `kernel/patches/0031`.
- **Auto no longer flashes at the start of a scroll.** Its switch to the fast
  waveform went through meink's manual path, which clears black and white
  first; the loader now sets meink's own skip-once flag before that switch.
  `kernel/patches/0032`.
- **Bayer dithering as an option.** `kompakt_wf_dither` 1 or 2 replaces
  meink's Floyd-Steinberg with an ordered pattern (8x8 or 4x4) computed in the
  loader, so dithered pictures stop boiling while they move. Greys lighter
  than 208 or darker than 48 (`kompakt_wf_dither_cut`) stay pure white or
  black, so light backgrounds and text get no dots. Mode 3 is ordered error
  diffusion: Atkinson's diffusion rounding against a Bayer threshold
  (`kompakt_wf_dither_step`). Off by default, for testing over adb; the
  Kompakt app has no switch for it. `kernel/patches/0033`,
  `apply-eink-access.sh` makes the node writable.
- **A 4-grey fast mode for testing**: `kompakt_wf_du4` rebuilds the DU2
  table so every grey goes straight to every other in one push, balanced with
  Quality. About half of Quality's time. `kernel/patches/0034`.

## 1.1 (2026-10-03)

Boot 269, unchanged: the recovery stays `KompaktOS-Kernel-LineageOS-Recovery-1.0.img`.

- **Vendor 264** (Global) and **264-usa** (USA): `ipsec_mon` may read
  privileged route details (`nlmsg_readpriv`), which Android 16 asks for on the
  Wi-Fi calling tunnel's interface lookups.
  `vendor/scripts/apply-wifi-calling-access.sh`. The USA image is built from
  the same stage with `vendor/scripts/make-usa-vendor.sh`.

## 1.0

Boot 269, vendor 263 (Global) and 263-usa (USA).

- First release.
