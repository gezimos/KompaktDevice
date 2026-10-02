#!/usr/bin/env python3
"""Pack an overlay FDT into a dtbo.img shaped like stock. Usage: mkdtbo.py Kompakt.dtb stock-dtbo.img out-dtbo.img"""
import hashlib
import struct
import sys

MAGIC, HDR, ENT, PAGE = 0xD7B7AB1E, 32, 32, 2048

fdt = open(sys.argv[1], 'rb').read()
ref = open(sys.argv[2], 'rb').read()

assert fdt[:4] == b'\xd0\x0d\xfe\xed', 'input is not an FDT'
r_magic, r_total = struct.unpack_from('>II', ref, 0)
assert r_magic == MAGIC, 'reference is not an Android DT table'

off = HDR + ENT
total = off + len(fdt)
table = struct.pack('>8I', MAGIC, total, HDR, ENT, 1, HDR, PAGE, 0)
table += struct.pack('>8I', len(fdt), off, 0, 0, 0, 0, 0, 0)
table += fdt

tail = ref[r_total:]
img = table + tail
img += b'\0' * max(0, len(ref) - len(img))

open(sys.argv[3], 'wb').write(img)

r_fdt = ref[64:r_total]
print(f'fdt      {hashlib.md5(fdt).hexdigest()}  {len(fdt)} bytes')
print(f'stock    {hashlib.md5(r_fdt).hexdigest()}  {len(r_fdt)} bytes')
print(f'image    {hashlib.md5(img).hexdigest()}  {len(img)} bytes')
print(f'ref img  {hashlib.md5(ref).hexdigest()}  {len(ref)} bytes')
print('IDENTICAL_TO_STOCK' if img == ref else 'DIFFERS_FROM_STOCK')
