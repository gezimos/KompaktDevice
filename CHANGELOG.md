# Changelog

The boot image (kernel and LineageOS recovery) and the vendor images. Each
KompaktOS release ships these inside its full update package; the recovery
image is also released here on its own.

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
