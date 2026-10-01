# prebuilt/

Binaries the device build takes as given. None are committed: the kernel and
device tree are rebuilt per release, and `meink.ko` is Mudita's and
proprietary.

```
Image.gz                          kernel, built as in kernel/README.md
dtb/mt6761.dtb                    base device tree, make mediatek/mt6761.dtb
dtbo.img                          overlay, dtbo/mkdtbo.py (identical to stock)
recovery-modules/meink_hal.ko     \
recovery-modules/meink.ko          } from the stock boot ramdisk's lib/modules/
recovery-modules/meink_loader.ko  /
adb_keys                          public adb key(s) recovery trusts, e.g. ~/.android/adbkey.pub
```

The recovery modules are Mudita's stock ones on purpose: recovery drives the
panel the way stock recovery does and does not depend on our driver changes.
