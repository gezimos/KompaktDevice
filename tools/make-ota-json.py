#!/usr/bin/env python3
# Writes the update list the LineageOS Updater reads for one update package.
#
#   tools/make-ota-json.py <ota.zip> <system.img> <download url> > <type>-<region>.json
#
# The system image gives the build date the phone compares against; the
# package's own date is the packaging time and would offer a phone its own
# build again. Needs debugfs.
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import zipfile


def system_props(image):
    props = {}
    with tempfile.TemporaryDirectory() as d:
        for i, path in enumerate(["/system/build.prop", "/system/product/etc/build.prop"]):
            out = os.path.join(d, f"{i}.prop")
            subprocess.run(["debugfs", "-R", f"dump {path} {out}", image],
                           check=True, capture_output=True)
            with open(out) as f:
                props.update(line.rstrip("\n").split("=", 1) for line in f
                             if "=" in line and not line.startswith("#"))
    return props


def ota_metadata(package):
    with zipfile.ZipFile(package) as z:
        text = z.read("META-INF/com/android/metadata").decode()
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: make-ota-json.py <ota.zip> <system.img> <download url>")
    package, image, url = sys.argv[1:]
    props = system_props(image)
    meta = ota_metadata(package)
    if meta.get("ota-type") != "AB":
        sys.exit(f"{package} is not an A/B package")
    update = {
        "datetime": int(props["ro.build.date.utc"]),
        "type": props["ro.lineage.releasetype"].lower(),
        "version": props["ro.lineage.build.version"],
        "files": [{
            "filename": os.path.basename(url),
            "sha256": sha256(package),
            "size": os.path.getsize(package),
            "url": url,
            "os_patch_level": meta["post-security-patch-level"],
            "os_sdk_level": int(meta["post-sdk-level"]),
            "ota_property_files": meta["ota-property-files"].strip(),
        }],
    }
    json.dump([update], sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
