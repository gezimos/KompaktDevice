#!/usr/bin/env python3
"""Read and rewrite the Kompakt's logo partition: the bootloader's 60 pictures.

The boot screen is slot 0, copied at slot 38. Pictures are 480x800 BGRA,
upright. See tools/README.md and docs/Images.md.

    logoimg.py extract logo.bin -o pictures/
    logoimg.py patch   logo.bin --slot 0 boot.png --slot 38 boot.png -o logo-new.bin
    logoimg.py verify  logo.bin
    fastboot flash logo logo-new.bin        # from the bootloader
"""

import argparse
import os
import struct
import sys
import zlib

MAGIC = 0x58881688
HEADER = 512
ALIGN = 16
WIDTH, HEIGHT = 480, 800
FRAME = WIDTH * HEIGHT * 4

# Pixel sizes of the small pictures, by decompressed length (labels only).
DIMS = {
    FRAME: (WIDTH, HEIGHT),
    2852: (23, 31),      # digits 0-9 for the small percentage
    3844: (31, 31),      # percent sign
    12960: (54, 60),     # blank
    540: (15, 9),        # blank
    28080: (54, 130),    # large digits
    15360: (48, 80),     # large digit 1
}


# --------------------------------------------------------------- container

def _images(blob):
    """Every MediaTek image in the partition: (offset, name, body bytes)."""
    out = []
    pos = 0
    while pos + HEADER <= len(blob):
        magic, size = struct.unpack_from("<II", blob, pos)
        if magic != MAGIC:
            break
        name = blob[pos + 8:pos + 40].split(b"\0")[0].decode()
        out.append((pos, name, blob[pos + HEADER:pos + HEADER + size]))
        pos = -(-(pos + HEADER + size) // ALIGN) * ALIGN
    return out


def parse(blob):
    images = _images(blob)
    if not images or images[0][1] != "logo":
        raise SystemExit("not a logo partition: no MediaTek 'logo' image at offset 0")
    body = images[0][2]
    count, total = struct.unpack_from("<II", body, 0)
    if total != len(body):
        raise SystemExit("body length %d does not match the header's %d" % (total, len(body)))
    offsets = list(struct.unpack_from("<%dI" % count, body, 8)) + [total]
    slots = [zlib.decompress(body[offsets[i]:offsets[i + 1]]) for i in range(count)]
    return slots, images


def build(slots, template, images, level):
    """A partition from the pictures, keeping everything else from the template."""
    streams = [zlib.compress(s, level) for s in slots]
    head = 8 + 4 * len(streams)
    offsets, pos = [], head
    for s in streams:
        offsets.append(pos)
        pos += len(s)
    body = struct.pack("<II", len(streams), pos) + struct.pack("<%dI" % len(streams), *offsets) + b"".join(streams)

    out = bytearray(len(template))
    header = bytearray(template[:HEADER])
    struct.pack_into("<I", header, 4, len(body))
    out[:HEADER] = header
    out[HEADER:HEADER + len(body)] = body
    pos = -(-(HEADER + len(body)) // ALIGN) * ALIGN
    for src, name, cert in images[1:]:
        if pos + HEADER + len(cert) > len(out):
            raise SystemExit("pictures too large: the trailing '%s' image no longer fits" % name)
        out[pos:pos + HEADER] = template[src:src + HEADER]
        out[pos + HEADER:pos + HEADER + len(cert)] = cert
        pos = -(-(pos + HEADER + len(cert)) // ALIGN) * ALIGN
    return bytes(out)


def exact_level(slots, blob):
    """The zlib level that reproduces the partition's own streams, or None."""
    images = _images(blob)
    body = images[0][2]
    count = struct.unpack_from("<I", body, 0)[0]
    offsets = list(struct.unpack_from("<%dI" % count, body, 8)) + [len(body)]
    for level in range(10):
        if all(zlib.compress(slots[i], level) == body[offsets[i]:offsets[i + 1]] for i in range(count)):
            return level
    return None


# ------------------------------------------------------------------ images

def to_bgra(path, dither, fill):
    from PIL import Image, ImageOps

    im = Image.open(path)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        im = Image.alpha_composite(bg, im)
    im = im.convert("L")
    if im.size != (WIDTH, HEIGHT):
        if fill:
            im = ImageOps.fit(im, (WIDTH, HEIGHT), method=Image.LANCZOS)
        else:
            im = ImageOps.contain(im, (WIDTH, HEIGHT), method=Image.LANCZOS)
            canvas = Image.new("L", (WIDTH, HEIGHT), 255)
            canvas.paste(im, ((WIDTH - im.width) // 2, (HEIGHT - im.height) // 2))
            im = canvas
    if dither:
        pal = Image.new("P", (1, 1))
        levels = [round(i * 255 / 15) for i in range(16)]
        pal.putpalette([v for lv in levels for v in (lv, lv, lv)] + [0] * (256 - 16) * 3)
        im = im.quantize(palette=pal, dither=Image.FLOYDSTEINBERG).convert("L")
    grey = im.tobytes()
    out = bytearray(FRAME)
    out[0::4] = grey
    out[1::4] = grey
    out[2::4] = grey
    out[3::4] = b"\xff" * (WIDTH * HEIGHT)
    return bytes(out)


def to_image(raw):
    from PIL import Image
    dims = DIMS.get(len(raw))
    if not dims:
        return None
    return Image.frombytes("RGBA", dims, raw).convert("L")


# ----------------------------------------------------------------- actions

def cmd_verify(args):
    blob = open(args.partition, "rb").read()
    slots, images = parse(blob)
    print("  partition %d bytes, %d pictures, trailing images: %s"
          % (len(blob), len(slots), ", ".join(n for _, n, _ in images[1:]) or "none"))
    for i, s in enumerate(slots):
        dims = DIMS.get(len(s))
        print("  slot %2d  %8d bytes  %s" % (i, len(s), "%dx%d" % dims if dims else "?"))
    level = exact_level(slots, blob)
    if level is None:
        print("  no zlib level reproduces the original streams; a repack differs in compression only")
        return
    again = build(slots, blob, images, level)
    print("  round trip at zlib level %d: %s" % (level, "byte-identical" if again == blob else "DIFFERS"))
    if again != blob:
        sys.exit(1)


def cmd_extract(args):
    blob = open(args.partition, "rb").read()
    slots, _ = parse(blob)
    os.makedirs(args.out, exist_ok=True)
    for i, s in enumerate(slots):
        im = to_image(s)
        if im is None:
            dest = os.path.join(args.out, "slot%02d.bgra" % i)
            open(dest, "wb").write(s)
        else:
            dest = os.path.join(args.out, "slot%02d.png" % i)
            im.save(dest)
        print("  slot %2d -> %s" % (i, dest))


def cmd_patch(args):
    blob = open(args.partition, "rb").read()
    slots, images = parse(blob)
    if not args.slot:
        raise SystemExit("nothing to do: pass --slot N IMAGE at least once")
    for n, path in args.slot:
        n = int(n)
        if not 0 <= n < len(slots):
            raise SystemExit("slot %d: the partition has %d" % (n, len(slots)))
        if len(slots[n]) != FRAME:
            raise SystemExit("slot %d is %d bytes, not a full screen; only those are replaced"
                             % (n, len(slots[n])))
        slots[n] = to_bgra(path, args.dither, args.fill)
        print("  slot %2d <- %s" % (n, path))
        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            dest = os.path.join(args.preview, "slot%02d.png" % n)
            to_image(slots[n]).save(dest)
            print("          preview %s" % dest)
    level = exact_level(parse(blob)[0], blob)
    out = build(slots, blob, images, 9 if level is None else level)
    if len(out) != len(blob):
        raise SystemExit("internal error: size changed")
    open(args.out, "wb").write(out)
    print("  wrote %s (%d bytes, same as the input)" % (args.out, len(out)))
    print("\nFlash from the bootloader: fastboot flash logo %s" % os.path.abspath(args.out))


def main():
    ap = argparse.ArgumentParser(description="The Kompakt's logo partition.",
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("verify", help="parse the partition and prove the repack is exact")
    v.add_argument("partition")
    v.set_defaults(func=cmd_verify)

    e = sub.add_parser("extract", help="save every picture")
    e.add_argument("partition")
    e.add_argument("-o", "--out", default="logo-extracted")
    e.set_defaults(func=cmd_extract)

    p = sub.add_parser("patch", help="replace full-screen pictures")
    p.add_argument("partition", help="the partition to start from")
    p.add_argument("--slot", nargs=2, action="append", metavar=("N", "IMAGE"),
                   help="replace slot N; 0 and 38 are the boot screen")
    p.add_argument("-o", "--out", required=True)
    p.add_argument("--preview", metavar="DIR", help="save what each slot will show")
    p.add_argument("--dither", action="store_true", help="16 grey levels with Floyd-Steinberg, for photos")
    p.add_argument("--fill", action="store_true", help="crop to fill instead of fitting on white")
    p.set_defaults(func=cmd_patch)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
