# patches

Patches to LineageOS 23.2 that make its recovery work on the e-ink panel and
make its installer report progress. They go into our `boot.img`, not into the
KompaktOS system image, whose patches live in the KompaktOS repo.

Each directory is one project (`bootable_recovery` is `bootable/recovery`) and
holds a `git format-patch` series:

```sh
git -C bootable/recovery    am /path/to/KompaktDevice/patches/bootable_recovery/*.patch
git -C system/update_engine am /path/to/KompaktDevice/patches/system_update_engine/*.patch
```

Then build and pack the recovery boot image as in
[tools/README.md](../tools/README.md) (`pack-recovery-boot.sh`).

| project | patch | what |
|---|---|---|
| `bootable/recovery` | `0001` | the menu in two inks, black and white, instead of LineageOS colours that dither on the panel |
| `bootable/recovery` | `0002` | waits for USB are limited (5 s, 10 s for sideload), so recovery draws without adb |
| `bootable/recovery` | `0003` | the selected row is outlined instead of filled |
| `bootable/recovery` | `0004` | adbd runs as shell, not root, so recovery comes up on USB |
| `bootable/recovery` | `0005` | the panel is cleared before the first frame, so the boot logo does not ghost under the menu |
| `bootable/recovery` | `0006` | the log wraps at word boundaries |
| `bootable/recovery` | `0007` | a progress bar with a percentage while installing |
| `bootable/recovery` | `0008` | Advanced → Switch to the other slot: the way back when an update does not boot; it cancels the unfinished update first and refuses once a merge has started |
| `system/update_engine` | `0001` | the sideload installer reports its progress, not just 0 or 1 |
