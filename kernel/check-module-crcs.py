#!/usr/bin/env python3
"""Check a prebuilt module's symbol CRCs against a kernel's Module.symvers.

    check-module-crcs.py <Module.symvers> <module.ko>

Prints MISMATCH=0 when the module will load on that kernel.
"""
import sys,struct
def sect(path,want):
    f=open(path,"rb"); d=f.read()
    assert d[:4]==b"\x7fELF"
    is64=d[4]==2; end="<" if d[5]==1 else ">"
    shoff,=struct.unpack_from(end+"Q",d,0x28)
    shentsize,shnum,shstrndx=struct.unpack_from(end+"HHH",d,0x3a)
    def sh(i):
        o=shoff+i*shentsize
        name,typ,flags,addr,off,size=struct.unpack_from(end+"IIQQQQ",d,o)
        return name,off,size
    _,stroff,_=sh(shstrndx)
    for i in range(shnum):
        n,off,size=sh(i)
        nm=d[stroff+n:d.index(b"\x00",stroff+n)].decode()
        if nm==want: return d[off:off+size]
    return b""
sym,ko=sys.argv[1],sys.argv[2]
ours={}
for l in open(sym):
    p=l.split()
    if len(p)>=2: ours[p[1]]=int(p[0],16)&0xffffffff
d=sect(ko,"__versions")
ENT=64; match=miss=absent=0; bad=[]
for i in range(0,len(d)-ENT+1,ENT):
    e=d[i:i+ENT]
    crc=struct.unpack("<Q",e[:8])[0]&0xffffffff
    name=e[8:].split(b"\x00")[0].decode(errors="replace")
    if not name: continue
    if name not in ours: absent+=1; continue
    if ours[name]==crc: match+=1
    else: miss+=1; bad.append((name,hex(crc),hex(ours[name])))
print(f"{ko.split(chr(47))[-1]:28} match={match:4} MISMATCH={miss:3} not-in-kernel={absent}")
for b in bad[:6]: print("      ",b)
