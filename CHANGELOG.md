# Changelog

The boot image (kernel and LineageOS recovery) and the vendor images. Each
KompaktOS release ships these inside its full update package; the recovery
image is also released here on its own.

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
