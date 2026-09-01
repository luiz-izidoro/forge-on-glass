#!/usr/bin/env python3
"""Set the versioned arm64e pointer-auth ABI in a thin Mach-O executable.

Must run before code signing. iOS 26.x requires a versioned arm64e subtype;
ABI 1 is selected for iOS 26.6. The operation changes only mach_header_64.
"""
import struct, sys
if len(sys.argv) != 2:
    print('usage: set-arm64e-ptrauth-abi.py MACH-O', file=sys.stderr)
    raise SystemExit(2)
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
magic, cputype, subtype = struct.unpack_from('<Iii', b, 0)
if magic != 0xFEEDFACF or cputype != 0x0100000C:
    raise SystemExit('not a 64-bit ARM Mach-O')
base = subtype & 0x00FFFFFF
if base != 2:
    raise SystemExit('not arm64e: cpusubtype=0x%x' % (subtype & 0xffffffff))
new = 0x81000002
struct.pack_into('<I', b, 8, new)
open(p, 'wb').write(b)
print('arm64e ptrauth ABI: 0x%08x -> 0x%08x' % (subtype & 0xffffffff, new))
