# Edit one file inside a newc cpio (the boot ramdisk) without unpacking it, so
# every other entry keeps its bytes, order, modes and inode numbers.
#   cpioedit.py in.cpio out.cpio [name newcontent-file]
import sys

def parse(b):
    ents, off = [], 0
    while True:
        h = b[off:off + 110]
        assert h[:6] in (b'070701', b'070702'), (off, h[:6])
        f = [int(h[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        nsz, fsz = f[11], f[6]
        name = b[off + 110:off + 110 + nsz - 1].decode()
        doff = (off + 110 + nsz + 3) & ~3
        data = b[doff:doff + fsz]
        end = (doff + fsz + 3) & ~3
        ents.append((h, name, data))
        off = end
        if name == 'TRAILER!!!':
            return ents, b[off:]

def build(ents, tail):
    out = bytearray()
    for h, name, data in ents:
        h = bytearray(h)
        h[54:62] = b'%08x' % len(data)          # c_filesize, lowercase as mkbootfs writes it
        out += h + name.encode() + b'\0'
        out += b'\0' * ((-len(out)) % 4)
        out += data
        out += b'\0' * ((-len(out)) % 4)
    return bytes(out) + tail

src = open(sys.argv[1], 'rb').read()
ents, tail = parse(src)
if len(sys.argv) == 3:
    print('ROUNDTRIP_IDENTICAL=%s entries=%d' % (build(ents, tail) == src, len(ents)))
    sys.exit(0)
name, new = sys.argv[3], open(sys.argv[4], 'rb').read()
hits = [i for i, e in enumerate(ents) if e[1] == name]
assert len(hits) == 1
i = hits[0]; ents[i] = (ents[i][0], name, new)
open(sys.argv[2], 'wb').write(build(ents, tail))
print('EDITED', name, len(new))
