#!/usr/bin/env python3
"""Validate the FAT shape expected by LiveContainer's arm64e repair path."""
import struct, sys
if len(sys.argv) != 2:
    print('usage: check-fat-livecontainer.py FAT-MACH-O', file=sys.stderr); raise SystemExit(2)
p=sys.argv[1]; b=open(p,'rb').read()
if len(b)<8 or struct.unpack_from('>I',b,0)[0] != 0xcafebabe: raise SystemExit('expected big-endian FAT Mach-O')
n=struct.unpack_from('>I',b,4)[0]
if n != 2: raise SystemExit('expected exactly arm64 + arm64e slices')
seen={}
for i in range(n):
    cpu,sub,off,size,align=struct.unpack_from('>iiIII',b,8+i*20)
    if off+size > len(b): raise SystemExit('slice outside FAT file')
    magic,cput,inner,ft,ncmd,sz,flags,res=struct.unpack_from('<8I',b,off)
    if magic != 0xfeedfacf or cput != 0x0100000c or ft != 2: raise SystemExit('invalid inner executable slice')
    base=sub & 0xffffff
    if base == 0:
        if sub != 0: raise SystemExit('arm64 table subtype must be 0')
    elif base == 2:
        if (sub & 0xffffffff) != 0x81000002: raise SystemExit('arm64e FAT table must be versioned v1 (0x81000002)')
        if (inner & 0xffffff) != 2 or (inner & 0xff000000) != 0x81000000: raise SystemExit('arm64e inner slice must be arm64e.v1')
    else: raise SystemExit('unexpected FAT subtype 0x%08x' % (sub & 0xffffffff))
    if base == 0 and inner != 0: raise SystemExit('arm64 table/inner subtype mismatch')
    seen[base]=(sub,off,size)
if set(seen) != {0,2}: raise SystemExit('missing arm64 or arm64e slice')
print('FAT LiveContainer shape OK: arm64 subtype=0x%08x; arm64e table=0x%08x inner=0x%08x' % (seen[0][0] & 0xffffffff, seen[2][0] & 0xffffffff, inner))
