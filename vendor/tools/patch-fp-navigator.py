#!/usr/bin/env python3
"""Turn on the navigation loop in Chipone's fingerprint HAL by giving it an ini path.

Usage: patch-fp-navigator.py <stock .so> <out .so>. Refuses anything but the stock bytes.
"""

import struct
import sys

PATH = b"/vendor/etc/fpsensor_nav.ini"

GETTER = 0x14d94                       # customer_get_ini_file_full_name
MOV_X0_0, RET = 0xd2800000, 0xd65f03c0
PATHSTR = 0x47c30
PATHSTR_OLD = b"fp_hal.cpp interrupt_test test invoked\0"


def segments(b):
    phoff = struct.unpack_from("<Q", b, 0x20)[0]
    phnum = struct.unpack_from("<H", b, 0x38)[0]
    return [struct.unpack_from("<IIQQQQQQ", b, phoff + i * 56) for i in range(phnum)]


def off(b, va):
    for typ, _fl, o, sva, _pa, fs, _ms, _al in segments(b):
        if typ == 1 and sva <= va < sva + fs:
            return o + va - sva
    raise SystemExit("0x%x is not file-backed" % va)


def adr(rd, pc, target):
    imm = target - pc
    if not -(1 << 20) <= imm < (1 << 20):
        raise SystemExit("adr out of range")
    imm &= (1 << 21) - 1
    return 0x10000000 | ((imm & 3) << 29) | ((imm >> 2) << 5) | rd


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: patch-fp-navigator.py <stock .so> <out .so>")
    src = open(sys.argv[1], "rb").read()
    b = bytearray(src)

    g = off(b, GETTER)
    if struct.unpack_from("<2I", b, g) != (MOV_X0_0, RET):
        raise SystemExit("customer_get_ini_file_full_name is not stock")
    p = off(b, PATHSTR)
    if bytes(b[p:p + len(PATHSTR_OLD)]) != PATHSTR_OLD:
        raise SystemExit("the path's log string is not stock")

    b[p:p + len(PATHSTR_OLD)] = PATH.ljust(len(PATHSTR_OLD), b"\0")
    struct.pack_into("<I", b, g, adr(0, GETTER, PATHSTR))

    assert len(b) == len(src)
    changed = sum(1 for i in range(len(b)) if b[i] != src[i])
    open(sys.argv[2], "wb").write(b)
    print("patched %d bytes: getter at 0x%x, path at 0x%x" % (changed, g, p))


if __name__ == "__main__":
    main()
