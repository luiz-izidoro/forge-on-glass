#!/usr/bin/env python3
"""Prepare a thin arm64e Mach-O for LiveContainer and iOS 26.

The iOS 26 dyld requires the versioned pointer-auth ABI. A thin arm64e
executable must use CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_PTRAUTH_ABI (0x81000002),
which `file` reports as arm64e.v1. Do not strip the ABI bit to 0x2: that is
arm64e.old and dyld rejects it. Run on a copied executable before packaging.
"""
import struct, sys
if len(sys.argv) != 2:
    print('usage: prepare-livecontainer-arm64e.py MACH-O', file=sys.stderr)
    raise SystemExit(2)
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
if len(b) < 32: raise SystemExit('short Mach-O')
magic,cput,sub=struct.unpack_from('<Iii',b,0)
if magic != 0xfeedfacf or cput != 0x0100000c:
    raise SystemExit('expected thin 64-bit ARM Mach-O')
base=sub & 0x00ffffff
if base != 2: raise SystemExit('expected arm64e, got cpusubtype=0x%08x' % (sub & 0xffffffff))
new=0x81000002
struct.pack_into('<I', b, 8, new)
open(p,'wb').write(b)
print('LiveContainer arm64e.v1 header: 0x%08x -> 0x%08x' % (sub & 0xffffffff,new))
