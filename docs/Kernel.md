# The Kompakt kernel

KompaktOS runs its own kernel: Linux 4.19.191 built from Mudita's published
1.5.0 source with our patches on top. It boots, loads Mudita's prebuilt modules
unchanged, runs the e-ink panel, and lets the SoC sleep between AOD clock
updates. The same `boot.img` carries the LineageOS recovery.

This page covers the source, the toolchain, the build, what our patches change,
the module gate that freezes the config, the boot image layout, and how to flash
and recover. Related pages: [E-inkdriver.md](E-inkdriver.md) for the panel
driver, [Battery.md](Battery.md), [Device-tree.md](Device-tree.md),
[Images.md](Images.md) and [Vendor.md](Vendor.md). The patch list and how to
apply it are in [kernel/README.md](../kernel/README.md); the dtbo is in
[dtbo/README.md](../dtbo/README.md).

---

## Source and toolchain

| | |
|---|---|
| Source | <https://github.com/mudita/MuditaOS-K-Kernel-opensource>, release 1.5.0 (`c41ded21e`) |
| Kernel | 4.19.191, MediaTek ALPS BSP, `Kompakt_defconfig` |
| SoC | MT6761 (Helio A22, 4x Cortex-A53, ARMv8.0) |
| Compiler | AOSP `clang-r383902` (clang 11.0.1, LLD 11.0.1) |
| Where to get it | `platform/prebuilts/clang/host/linux-x86`, tag `android-11.0.0_r48` |
| Target triple | `CROSS_COMPILE=aarch64-linux-gnu-` |

This is the toolchain Mudita used; `/proc/version` on a stock phone names it.
With it the tree builds with no warning suppressions and no source changes, and
the resulting `.config` matches the phone's `/proc/config.gz` line for line.
`/proc/config.gz` is world-readable, so the shipped config can always be pulled
and compared.

**The triple matters.** The top-level `Makefile` derives clang's `--target` from
`CROSS_COMPILE`, and this tree has no `CLANG_TRIPLE` override. With
`aarch64-linux-android-` clang generates different code for a large part of the
kernel; the image builds, packs and flashes, and never prints a byte. Use
`aarch64-linux-gnu-`.

**The source does not configure as published.** Mudita's
`drivers/misc/mudita/Kconfig` sources `drivers/misc/mudita/eink/Kconfig`, and the
`eink/` directory is excluded from the release by their `.gitignore`. Our
`kernel/stub/` supplies a Kconfig declaring the six symbols the defconfig needs
(`PANEL_EINK_ED043WC5`, `PANEL_EINK_WAVESHARE75BV2`, `PANEL_EINK_WAVESHARE27BV2`,
`PANEL_EINK_TCON`, `MUDITA_EINK_DEBUG`, `MUDITA_EINK_TCORR`) and an empty
Makefile. Nothing in the withheld directory is needed: `meink.ko` ships
prebuilt on the vendor partition, and everything it links against is published.

The tree also carries `Compact_defconfig` (`CONFIG_PANEL_EINK_TCON`), for a
different Mudita device. It is not ours.

---

## Building

```sh
git clone --depth 1 https://github.com/mudita/MuditaOS-K-Kernel-opensource.git \
    kernel/mudita/kompakt
K=kernel/mudita/kompakt
cp -r kernel/stub/* "$K"/
git -C "$K" apply kernel/patches/0020-kompakt-eink-complete.patch
git -C "$K" apply kernel/patches/0023-kompakt-recovery-black-on-white.patch
git -C "$K" apply kernel/patches/0024-kompakt-usb-serial-null-tty.patch
git -C "$K" apply kernel/patches/0025-kompakt-gpu-sync-lockup-recovery.patch
KOMPAKT_BUILD=<n> kernel/build-kernel.sh "$K" <out dir>
```

`build-kernel.sh` needs `TOOLCHAIN` (the clang-r383902 directory) and `LINEAGE`
(a LineageOS tree, for its prebuilt binutils) in the environment. It:

- writes `-00095-g83b1ab1a9a4b-dirty` to `.scmversion`, which pins the vermagic
  (see [The module gate](#the-module-gate-vermagic-and-crcs));
- sets `KBUILD_BUILD_USER` and `KBUILD_BUILD_HOST` to Mudita's strings, or, with
  `KOMPAKT_BUILD=<n>`, puts our build number into `/proc/version`. The Kompakt
  app shows it under Installed images. It is not part of the vermagic;
- runs `Kompakt_defconfig`, then `make Image.gz modules` with
  `ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-`;
- prints the `Linux version` banner and the path of the display driver object
  that was actually compiled.

The equivalent by hand:

```sh
export PATH=$TOOLCHAIN/bin:$PATH
export KBUILD_BUILD_USER=nobody KBUILD_BUILD_HOST=android-build
echo "-00095-g83b1ab1a9a4b-dirty" > .scmversion
M="ARCH=arm64 O=$OUT LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-"
make $M Kompakt_defconfig
make -j"$(nproc)" $M Image.gz modules
```

Patch 0021 is not part of the kernel. It adds `arch/arm64/boot/dts/Kompakt/cust.dtsi`
so `make mediatek/Kompakt.dtb` builds the dtbo; it touches nothing in
`Image.gz`. See [dtbo/README.md](../dtbo/README.md). The base dtb inside
`boot.img` builds from the unmodified `mediatek/mt6761.dts`.

### mt6761 builds the mt6765 display driver

`drivers/misc/mediatek/video/Makefile` maps `CONFIG_MTK_PLATFORM="mt6761"` to
`MTK_PLATFORM := mt6765`. The tree carries near-identical `videox/` directories
for mt6739, mt6765, mt6768 and others. An edit to any directory but **mt6765**
compiles to nothing, and the kernel comes out identical to stock. The mt6765
copy is also different code: only its `mtkfb.c` has the e-ink AOD hook
(`register_eink_aod_func`) that `meink.ko` uses.

### Check the binary, not the source

After any change to kernel code:

```sh
# which object was really built
find $OUT/drivers/misc/mediatek/video -name primary_display.o

# the function you changed, in the finished image
kallsyms-finder Image > ks.txt                      # from vmlinux-to-elf
dd if=Image bs=1 skip=$((addr - _text)) count=16 | objdump -D -b binary -m aarch64
```

A patch that landed in the wrong file builds cleanly and flashes cleanly; only
the disassembly shows it did nothing.

---

## What our patches change

A shipping kernel is Mudita's 1.5.0 source plus **0020**, **0023**, **0024** and **0025**.

### 0020: e-ink, AOD, battery, LED

| File | Change |
|---|---|
| `Kompakt_defconfig` | `CONFIG_LEDS_TRIGGER_TIMER=y`. Without the `timer` trigger the lights HAL's write fails and `setFlashing` throws in system_server. |
| `mt6765/videox/primary_display.c` | `primary_is_aod_supported()` returns 1. The nominal LCM is a video-mode nt35521 that is never driven, so the stock check is always false and DOZE_SUSPEND never powers dispsys down. Also leaves low power correctly on a resume from DOZE. |
| `lcm/nt35521_.../nt35521_hd_dsi_vdo_truly_rt5081.c` | A no-op `.aod` callback. Without it `disp_lcm_aod()` fails and DOZE entry falls back to a full resume. |
| `mt6765/videox/mtkfb.c` | A wake out of DOZE detours through DOZE_SUSPEND (the driver cannot resume out of DOZE) and takes meink out of AOD with its power-off held off; `FB_BLANK_POWERDOWN` from DOZE tells meink to leave AOD; new hooks `register_eink_force_full_func`, `register_eink_aod_exit_funcs`, `register_eink_repower_func`; `kompakt_request_repaint()`. |
| `mudita/eink_loader/eink_spi_hal.c` | Partial updates: each frame is diffed against the last and only the changed rectangles are sent. `force_full` on both AOD transitions, so the first frame after a wake is not diffed against the AOD clock and dropped. Auto waveform mode (fast while the screen moves, quality once it settles). Refresh timing, optional SPI trace. A mutex serialises partial-update state against `eink_force_full()`. |
| `mudita/eink_loader/loader.c` | `sleep_image` and `sleep_image_stock` in `/sys/einkinfo` (the sleep screen, see [Images.md](Images.md)); `refresh_time`; a store handler on `eink_temperature`; the repower request after a DOZE wake; dropping Android's last frame from the sleep screen. |
| `mudita/eink_loader/eink_hal.h` | Declarations for the above. |
| `drivers/misc/kompakt/kompakt_eink.c` | New module: a shim that takes over meink's callback table, forwards every call and can trace it. |
| `mudita/battery_monitor/battery_monitor.c`, `power/supply/mtk_battery.c` | Real cycle count instead of a constant 1; design capacity 3000 mAh. See [Battery.md](Battery.md). |

The e-ink work is described in [E-inkdriver.md](E-inkdriver.md).
`eink_spi_hal.c` builds into `meink_hal.ko`, so its tunables (`partial`,
`semi_partial`, `auto_*`, `trace`, `measure`, ...) are under
`/sys/module/meink_hal/parameters/`.

**AOD needs both halves.** The ioctl in mt6765 `mtkfb.c` runs two things on
DOZE_SUSPEND: `primary_display_suspend()` when `primary_is_aod_supported()`, and
`eink_aod_func(0)` when meink has registered it. With
`ro.vendor.mtk_aod_support=1` but the kernel gate unpatched, only the panel half
runs: the frontlight stays on, dispsys stays powered, and the kernel logs
`AOD check error: fail to set FB power mode`. Ship the property only with a
kernel that has the gate.

**Change the gate only.** Leave `DISP_OPT_AOD` at 0 in the option table and in
`disp_helper_option_init()`. Setting it arms the display idle manager and SODI
paths, and on this board that wedges the panel after lock.

With both in place the display parks in DOZE_SUSPEND, the display blocker is
released, `pri_disp_wakelock` is never taken, and the phone spends most of an
AOD period asleep.

### 0023: recovery in black on white

`mtkfb.c` inverts the frame it hands meink when the command line has
`androidboot.slot_suffix=` but not `androidboot.force_normal_boot=1`, which is
a recovery or fastbootd boot. It inverts into its own buffer and keeps alpha.
Normal boots are never inverted.

### 0024: USB serial at plug-in

`gs_start_io()` in `u_serial.c` woke the serial port's tty without checking it.
If the Kompakt app closed `ttyGS0` at the moment the computer set up the ACM
port, the tty was already gone and the kernel panicked. It now checks, as
upstream Linux does.

### 0025: GPU sync lockup recovery

The PowerVR userspace driver asks for Sync Lockup Recovery (SLR) to be disabled
on every GPU context. When a fence never signals, the driver's stalled-CCB check
then only logs `SLR disabled for FWCtx` every 200 ms, and SystemUI's renderer
stays blocked, with its main thread, until the next wake. On the always-on
display that is a clock frozen for minutes. `rgxccb.c` now ignores the request,
so the check force-signals the dead fences (`Forced update command issued`) and
the renderer carries on. The stalled-CCB action is compiled in on this device
(`PVRSRV_STALLED_CCB_ACTION` in `config_kernel_user_mt6761.h`).

### Stock kernel alternative

`kernel/patch-aod-boot.sh` enables the AOD gate on Mudita's own kernel instead:
it unpacks a stock `boot.img`, finds `primary_is_aod_supported` with
`kallsyms-finder`, checks the prologue, overwrites 8 bytes with
`mov w0,#1 ; ret`, recompresses with `gzip -n -9` and repacks with the stock
header. It does only the gate; the rest of 0020 needs our kernel.

---

## The module gate (vermagic and CRCs)

The vendor partition and the boot ramdisk carry Mudita's prebuilt modules:
`meink.ko` (the closed panel driver), and wlan, bt, gps, fm, accdet and others.
They load only if the kernel matches them.

```
CONFIG_MODVERSIONS=y          per-symbol CRC check
# CONFIG_MODULE_SIG is not set    modules are unsigned
```

**vermagic, byte for byte:**

```
4.19.191-00095-g83b1ab1a9a4b-dirty SMP preempt mod_unload modversions aarch64
```

`-00095-g83b1ab1a9a4b-dirty` comes from `scripts/setlocalversion`, which is why
the build writes it into `.scmversion`; otherwise it asks git and gets something
else. `SMP preempt mod_unload modversions` are config options that stay as they
are. Build host and timestamp are only in the banner.

`modversions` is part of the string, so turning `CONFIG_MODVERSIONS` off does
not get around a CRC mismatch: the vermagic changes and every module is refused
on that instead.

**CRCs.** `meink.ko` imports 45 symbols, and each one's CRC in its `__versions`
section (64-byte entries: 8-byte CRC, 56-byte name) must match the kernel's
`Module.symvers`:

| Count | Symbols | Source |
|---|---|---|
| 36 | `__kmalloc`, `printk`, `mutex_lock`, `memcpy`, `jiffies`, `fb_register_client`, `module_layout`, ... | core kernel |
| 6 | `eink_initHal`, `eink_deinitHal`, `eink_read`, `eink_write`, `eink_waitForReady`, `eink_registerCallbackTable` | `mudita/eink_loader/eink_spi_hal.c` (GPL) |
| 2 | `eink_powerDownSequence`, `eink_get_battery_capacity` | `eink_loader`, `battery_monitor` (GPL) |
| 3 | `register_eink_refresh_func`, `unregister_eink_refresh_func`, `register_eink_aod_func` | `mt6765/videox/mtkfb.c` |

A build is good when all eight prebuilt modules checked show `MISMATCH=0`, with
`meink.ko` at 45 of 45, and the vermagic above. Check this before a boot image
is written; it needs no phone.

**The config is frozen by this.** Anything that changes a struct layout or a
calling convention changes CRCs, and then the prebuilt modules refuse to load.
That rules out, for as long as the Mudita modules are used:

- `NR_CPUS` (sizes every cpumask), and anything touching `task_struct`,
  `struct module` (`module_layout`'s CRC) or other types the imports reference
- `CONFIG_LTO_CLANG`, `CONFIG_CFI_CLANG`
- `CONFIG_SHADOW_CALL_STACK` (reserves x18)

Only additions that leave every imported type alone are safe, like
`LEDS_TRIGGER_TIMER`. Test any change against the gate before flashing.

**Keep the e-ink transport a module.** First-stage init loads `meink_hal.ko`,
`meink.ko` and `meink_loader.ko` from the boot ramdisk, before `/vendor` is
mounted. Building the transport into `vmlinux` (`CONFIG_MUDITA_EINK=y` plus
`obj-y`) makes that `insmod` fail, and a module load failure in first-stage init
stops the boot with no panic.

### The shipped config, for reference

What `/proc/config.gz` holds, and why it stays:

| Setting | Value | Note |
|---|---|---|
| Filesystems | ext4 only | no F2FS, EROFS or SquashFS; `/data` and `/vendor` are ext4 |
| `CONFIG_NR_CPUS` | 32 | on a 4-core SoC; frozen by the gate |
| `CONFIG_HZ` | 250 | |
| `CONFIG_STATIC_USERMODEHELPER_PATH` | `/system_ext/bin/aee_core_forwarder` | absent on a GSI, so usermode helper calls fail silently |
| Debug | `DEBUG_LIST`, `DEBUG_DEVRES`, `MTK_*_DEBUG`, `PROFILING`, `SCHEDSTATS`, `DEBUG_INFO` on | no KASAN, lockdep, SLUB debug or function tracer |
| Memory | `ZRAM=y` (lz4, zstd), no `KSM`, no `ZRAM_WRITEBACK`, no THP | 2.8 GB RAM |
| Hardening | KASLR, `STACKPROTECTOR_STRONG`, `HARDENED_USERCOPY`, `STRICT_KERNEL_RWX` | no PAC, BTI or MTE on ARMv8.0 |
| Scheduler | `PREEMPT`, `PSI`, `MEMCG`, `UCLAMP_TASK`, schedutil, `ENERGY_MODEL` | |

4.19 is past upstream end of life (December 2024). The MediaTek BSP
(`drivers/misc/mediatek/`, about 4.5 million lines) is written against 4.19 and
does not port forward, so the base stays 4.19.191.

---

## Boot image

The device is A/B with no recovery partition: `boot` holds the kernel, the dtb
and a ramdisk that is both first-stage init and recovery. Our `boot.img` carries
the LineageOS recovery, packed by `tools/pack-recovery-boot.sh` with our
kernel and dtb (see [Device-tree.md](Device-tree.md) for the recovery build).

| Field | Value |
|---|---|
| Header version | 2 |
| Page size | 2048 |
| Base | `0x40000000` |
| Kernel offset | `0x00080000` (load `0x40080000`) |
| Ramdisk offset | `0x11b00000` (load `0x51b00000`) |
| Tags / dtb offset | `0x07880000` (load `0x47880000`) |
| Command line | `bootopt=64S3,32N2,64N2 buildvariant=user` |
| OS version / patch level | `12.0.0` / `2026-07` |
| Kernel | `Image.gz`, gzip `-n -9` (reproduces Mudita's compression exactly) |
| Ramdisk | gzip; the kernel unpacks gzip only. LK reserves 64 MiB for it |
| Partition size | 33,554,432 bytes |
| AVB | hash footer, `--algorithm NONE` |

```sh
python3 system/tools/mkbootimg/mkbootimg.py \
  --kernel Image.gz --ramdisk ramdisk --dtb dtb \
  --header_version 2 --base 0x40000000 --pagesize 2048 \
  --kernel_offset 0x00080000 --ramdisk_offset 0x11b00000 \
  --tags_offset 0x07880000 --dtb_offset 0x07880000 \
  --os_version 12.0.0 --os_patch_level 2026-07 \
  --cmdline "bootopt=64S3,32N2,64N2 buildvariant=user" -o boot.img
avbtool add_hash_footer --image boot.img --partition_name boot \
  --partition_size 33554432 --algorithm NONE
```

A wrong ramdisk offset builds a normal-looking image that resets before the
kernel prints anything. Before trusting a packing command, run it on the
**stock** kernel, ramdisk and dtb and compare the first 1664 bytes (the header)
with the stock `boot.img`; they must be identical. The ramdisk also carries the
three e-ink modules and `modules.load.recovery`, which is what lets recovery
drive the panel.

---

## Flashing and the way back

`boot` is written from the **bootloader**, not fastbootd:

```sh
adb reboot bootloader
fastboot flash boot boot.img
fastboot reboot
```

`fastboot boot` does not work on this bootloader: LK crashes and the image
never runs. The only way to test a boot image is to flash it. Flashing `boot`
also replaces recovery, since recovery lives in it.

**The way back** is a known-good `boot.img` (ours or stock) flashed the same
way. If the bootloader's fastboot is out of reach, use MediaTek BROM mode with
[mtkclient](https://github.com/bkerler/mtkclient). It addresses raw GPT
partitions, which are slot-suffixed:

```sh
python3 mtk.py w boot_a boot.img
```

For a boot that dies early, `expdb` holds the preloader, LK and kernel console
of the most recent boot only (`python3 mtk.py r expdb expdb.bin`). A boot that
reached the kernel shows `Linux version` there; one that ends at
`< Kernel Enter Normal Boot >` never ran the kernel.

### The bootloader can never be relocked

LK is a stock AVB 2.0 implementation with no `avb_custom_key` support and no
such partition. It trusts only the key burned in at the factory. Locked, it
verifies `boot` and `vbmeta` against Mudita's key, refuses our images, and then
refuses to flash anything back. This applies with the stock kernel too, since
KompaktOS runs its own `system`. The Orange State warning at boot is the cost of
an unlocked bootloader and is cosmetic.

---

## Do not retry

- `CROSS_COMPILE=aarch64-linux-android-`: builds a kernel that never boots.
- A newer clang: it needs dozens of warning classes disabled and gains nothing
  over Mudita's clang-r383902.
- Trimming the config: `NR_CPUS` and anything else that changes a struct
  changes module CRCs and bricks the modules. Turning the debug options off
  gains nothing either: the compressed kernel comes out larger.
- `CONFIG_MODVERSIONS=n`: changes the vermagic, so every module is refused.
- An EROFS system: needs a newer kernel; the tree only has the 2018 staging
  driver.
- `DISP_OPT_AOD=1`: wedges the panel after lock. Patch the gate only.
- Editing `video/mt6768/`: not compiled for mt6761.
- `CONFIG_MUDITA_EINK=y` with the transport built in: first-stage init fails
  loading the ramdisk's `meink_hal.ko`.
- `fastboot boot`: crashes LK.
- A newer kernel base or a mainline port: the MediaTek BSP does not port forward.
