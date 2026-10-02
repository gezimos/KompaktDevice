#!/usr/bin/env python3
"""Replace the sleep, power-off, logo and low-battery pictures inside meink.ko.

The pictures are 480x800 arrays, 4 bytes a pixel (R = G = B, 0xff last),
stored rotated 180 degrees; this script rotates both ways. See tools/README.md.

    sleepimg.py extract meink.ko -o previews/
    sleepimg.py patch   meink.ko --lock photo.jpg -o meink-patched.ko
"""

import argparse
import os
import struct
import sys

WIDTH, HEIGHT = 480, 800
FRAME = WIDTH * HEIGHT * 4

# The four pictures the driver can paint, by the symbol that holds each one.
TARGETS = {
    "lock":     ("cImageMuditaLockScreen_map",
                 "sleep screen, shown whenever the screen goes off"),
    "poweroff": ("cImageMuditaPowerOffScreen_map",
                 "shown after the phone powers down"),
    "logo":     ("cImageMuditaLogo_map",
                 "logo the driver can paint"),
    "battery":  ("cImageMuditaBatteryFullyDischargedScreen_map",
                 "shown when the battery is flat"),
}


# --------------------------------------------------------------------- ELF

def _sections(blob):
    """Section headers of an ELF64 little-endian object."""
    if blob[:4] != b"\x7fELF":
        raise SystemExit("not an ELF file")
    (e_shoff,) = struct.unpack_from("<Q", blob, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", blob, 0x3A)
    secs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        name, typ, _fl, _ad, sh_off, size, link, _in, _al, entsize = \
            struct.unpack_from("<IIQQQQIIQQ", blob, off)
        secs.append(dict(name=name, type=typ, off=sh_off, size=size,
                         link=link, entsize=entsize))
    strtab = secs[e_shstrndx]
    for s in secs:
        end = blob.index(b"\0", strtab["off"] + s["name"])
        s["sname"] = blob[strtab["off"] + s["name"]:end].decode()
    return secs


def find_symbol(blob, want):
    """File offset and size of a symbol in a .ko (st_value is section-relative)."""
    secs = _sections(blob)
    for sec in secs:
        if sec["type"] not in (2, 11) or not sec["entsize"]:
            continue
        strs = secs[sec["link"]]
        for i in range(sec["size"] // sec["entsize"]):
            off = sec["off"] + i * sec["entsize"]
            name, _info, _other, shndx, value, size = \
                struct.unpack_from("<IBBHQQ", blob, off)
            end = blob.index(b"\0", strs["off"] + name)
            if blob[strs["off"] + name:end].decode(errors="replace") == want:
                return secs[shndx]["off"] + value, size
    raise SystemExit("symbol not found in this module: %s" % want)


# ------------------------------------------------------------------- images

def to_frame(path, dither=True, fill=False):
    """Any image to the 1,536,000-byte frame: fitted on white, 16 greys, dithered unless --no-dither."""
    from PIL import Image, ImageOps

    im = Image.open(path)
    # Flatten transparency onto white, or it turns black.
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        im = Image.alpha_composite(bg, im)
    im = im.convert("L")

    if fill:
        im = ImageOps.fit(im, (WIDTH, HEIGHT), method=Image.LANCZOS)
    else:
        im = ImageOps.contain(im, (WIDTH, HEIGHT), method=Image.LANCZOS)
        canvas = Image.new("L", (WIDTH, HEIGHT), 255)
        canvas.paste(im, ((WIDTH - im.width) // 2, (HEIGHT - im.height) // 2))
        im = canvas

    if dither:
        # Dither to a palette of 16 evenly spaced greys, then back to L.
        pal = Image.new("P", (1, 1))
        levels = [round(i * 255 / 15) for i in range(16)]
        pal.putpalette([v for lv in levels for v in (lv, lv, lv)] + [0] * (256 - 16) * 3)
        im = im.quantize(palette=pal, dither=Image.FLOYDSTEINBERG).convert("L")

    im = im.rotate(180)                      # the panel's scan order
    grey = im.tobytes()
    out = bytearray(FRAME)
    out[0::4] = grey
    out[1::4] = grey
    out[2::4] = grey
    out[3::4] = b"\xff" * (WIDTH * HEIGHT)
    return bytes(out)


def from_frame(data):
    """The driver's bytes back to an upright PIL image."""
    from PIL import Image
    return Image.frombytes("RGBA", (WIDTH, HEIGHT), data[:FRAME]) \
                .convert("L").rotate(180)


# ------------------------------------------------------------------ actions

def cmd_extract(args):
    blob = open(args.module, "rb").read()
    os.makedirs(args.out, exist_ok=True)
    for key, (sym, what) in TARGETS.items():
        try:
            off, size = find_symbol(blob, sym)
        except SystemExit:
            print("  %-9s not in this module" % key)
            continue
        dest = os.path.join(args.out, "%s.png" % key)
        from_frame(blob[off:off + FRAME]).save(dest)
        print("  %-9s %7d bytes at 0x%-8x -> %s   (%s)" % (key, size, off, dest, what))


def cmd_patch(args):
    blob = bytearray(open(args.module, "rb").read())
    original = bytes(blob)

    wanted = {k: getattr(args, k) for k in TARGETS if getattr(args, k)}
    if not wanted:
        raise SystemExit("nothing to do: pass at least one of --lock --poweroff "
                         "--logo --battery")

    for key, src in wanted.items():
        sym, _what = TARGETS[key]
        off, size = find_symbol(bytes(blob), sym)
        if size < FRAME:
            raise SystemExit("%s is %d bytes, expected at least %d -- this does "
                             "not look like a 480x800 frame" % (sym, size, FRAME))
        frame = to_frame(src, dither=not args.no_dither, fill=args.fill)
        # Write only the frame: LockScreen's symbol is 1,920 bytes longer.
        blob[off:off + FRAME] = frame
        print("  %-9s <- %s  (%d bytes at 0x%x)" % (key, src, FRAME, off))
        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            dest = os.path.join(args.preview, "%s.png" % key)
            from_frame(frame).save(dest)
            print("  %-9s    preview %s" % ("", dest))

    # The module must be the same size and differ only where we said.
    if len(blob) != len(original):
        raise SystemExit("internal error: module size changed")
    changed = sum(1 for a, b in zip(original, blob) if a != b)
    print("\n  %d bytes differ from the input module (%.2f MB of image data written)"
          % (changed, len(wanted) * FRAME / 1e6))

    open(args.out, "wb").write(blob)
    print("  wrote %s (%d bytes)" % (args.out, len(blob)))
    print("\nvermagic and every symbol are untouched, so this loads exactly as the")
    print("original does. Install it at /vendor/lib/modules/meink.ko -- see README.")


def main():
    ap = argparse.ArgumentParser(
        description="Change the Kompakt's e-ink sleep and power-off screens.",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    e = sub.add_parser("extract", help="save the current pictures as PNGs")
    e.add_argument("module", help="path to meink.ko")
    e.add_argument("-o", "--out", default="sleepimg-extracted", help="output directory")
    e.set_defaults(func=cmd_extract)

    p = sub.add_parser("patch", help="write new pictures into a copy of the module")
    p.add_argument("module", help="path to the original meink.ko")
    for key, (_sym, what) in TARGETS.items():
        p.add_argument("--%s" % key, metavar="IMAGE", help=what)
    p.add_argument("-o", "--out", required=True, help="where to write the patched module")
    p.add_argument("--preview", metavar="DIR",
                   help="also save what each picture will look like on the phone")
    p.add_argument("--fill", action="store_true",
                   help="crop to fill 480x800 instead of fitting on white")
    p.add_argument("--no-dither", action="store_true",
                   help="skip Floyd-Steinberg; better for line art, worse for photos")
    p.set_defaults(func=cmd_patch)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
