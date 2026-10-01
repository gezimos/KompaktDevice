#!/bin/bash
# Enable real display doze by patching the stock kernel: makes
# primary_is_aod_supported() return 1. See docs/Kernel.md.
#
# Usage:  ./patch-aod-boot.sh <stock boot.img> <output boot.img>
# Needs:  a Linux host, the lineage tree (mkbootimg + avbtool), and
#         vmlinux-to-elf in a venv:  python3 -m venv ~/v2e && ~/v2e/bin/pip install vmlinux-to-elf

set -euo pipefail

IN=${1:?usage: patch-aod-boot.sh <stock boot.img> <out boot.img>}
OUT=${2:?usage: patch-aod-boot.sh <stock boot.img> <out boot.img>}
L=${LINEAGE:?set LINEAGE to a LineageOS tree}
V2E=${V2E:?set V2E to the venv bin folder with vmlinux-to-elf}
AVB=$L/out/host/linux-x86/bin/avbtool
MKB=$L/system/tools/mkbootimg
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "== unpacking $IN"
python3 "$MKB/unpack_bootimg.py" --boot_img "$IN" --out "$W/u" > "$W/hdr.txt"
grep -E "ramdisk load address|kernel load address|page size|header version|command line" "$W/hdr.txt"

# ramdisk_addr must be 0x51b00000 or the kernel does not boot.
RA=$(grep -m1 "ramdisk load address" "$W/hdr.txt" | grep -oE "0x[0-9a-f]+")
[ "$RA" = "0x51b00000" ] || { echo "!! unexpected ramdisk address $RA"; exit 1; }

echo "== decompressing kernel"
gunzip -c "$W/u/kernel" > "$W/Image"

echo "== recovering symbols"
"$V2E/kallsyms-finder" "$W/Image" 2>/dev/null > "$W/ks.txt"
TEXT=$(awk '$3=="_text"{print $1; exit}' "$W/ks.txt")
FN=$(awk '$3=="primary_is_aod_supported"{print $1; exit}' "$W/ks.txt")
[ -n "$TEXT" ] && [ -n "$FN" ] || { echo "!! symbols not found"; exit 1; }
echo "   _text=$TEXT  primary_is_aod_supported=$FN"

python3 - "$W/Image" "$TEXT" "$FN" <<'PY'
import struct, sys
img, text, fn = sys.argv[1], int(sys.argv[2],16), int(sys.argv[3],16)
off = fn - text
d = bytearray(open(img,'rb').read())
# Refuse to patch if the function prologue is not the expected one.
prologue = bytes(d[off:off+8])
if prologue != bytes.fromhex("fd7bbea9f30b00f9"):
    sys.exit("!! unexpected prologue at 0x%x: %s" % (off, prologue.hex()))
d[off:off+8] = struct.pack("<II", 0x52800020, 0xd65f03c0)   # mov w0,#1 ; ret
open(img,'wb').write(bytes(d))
print("   patched 8 bytes at file offset 0x%x" % off)
PY

echo "== repacking"
gzip -n -9 -c "$W/Image" > "$W/kernel.gz"
python3 "$MKB/mkbootimg.py" \
  --kernel "$W/kernel.gz" --ramdisk "$W/u/ramdisk" --dtb "$W/u/dtb" \
  --header_version 2 --base 0x40000000 --pagesize 2048 \
  --kernel_offset 0x00080000 --ramdisk_offset 0x11b00000 \
  --tags_offset 0x07880000 --dtb_offset 0x07880000 \
  --os_version 12.0.0 --os_patch_level 2026-07 \
  --cmdline "bootopt=64S3,32N2,64N2 buildvariant=user" -o "$OUT"
$AVB add_hash_footer --image "$OUT" --partition_name boot \
  --partition_size 33554432 --algorithm NONE

echo "== result"
ls -l "$OUT"; md5sum "$OUT"
echo "   ramdisk_addr in output: $(xxd -s 20 -l 4 -p "$OUT")   (must be 0000b051)"
echo
echo "Flash with the phone's own recovery path known first:"
echo "  fastboot flash boot $OUT"
echo "Back out with:  mtk.py w boot_a <stock boot.img>   (boot carries recovery here)"
