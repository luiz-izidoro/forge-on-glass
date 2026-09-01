#!/usr/bin/env python3
"""Experimental compatibility shim for old ld64.lld.

Converts ARM64_RELOC_AUTHENTICATED_POINTER (type 11) records in a copied
Mach-O object to ARM64_RELOC_UNSIGNED (type 0). This deliberately drops PAC
metadata and is only a diagnostic/fallback path; never mutate originals.
"""
import struct, sys

MH = struct.Struct('<IiiIIIII')
LC_SEG64 = 0x19
SEG = struct.Struct('<II16sQQQQiiII')
SEC = struct.Struct('<16s16sQQIIIIIIII')
REL = struct.Struct('<II')
AUTH = 11

def patch(src, dst):
    b = bytearray(open(src, 'rb').read())
    magic, cput, sub, ft, ncmd, sizeof, flags, r = MH.unpack_from(b, 0)
    p = MH.size; changed = 0
    for _ in range(ncmd):
        cmd, cmdsize = struct.unpack_from('<II', b, p)
        if cmd == LC_SEG64:
            nsects = struct.unpack_from('<I', b, p + 64)[0]
            q = p + SEG.size
            for _ in range(nsects):
                vals = SEC.unpack_from(b, q)
                reloff, nreloc = vals[6], vals[7]
                for j in range(nreloc):
                    off = reloff + j * REL.size
                    addr, info = REL.unpack_from(b, off)
                    typ = (info >> 28) & 0xf
                    if typ == AUTH:
                        info = (info & ~(0xf << 28))
                        REL.pack_into(b, off, addr, info)
                        changed += 1
                q += SEC.size
        p += cmdsize
    open(dst, 'wb').write(b)
    print(f'{src}: converted {changed} authenticated relocations -> unsigned')
    return changed

if len(sys.argv) != 3:
    print('usage: strip-arm64e-auth-relocs.py INPUT.o OUTPUT.o'); raise SystemExit(2)
if patch(sys.argv[1], sys.argv[2]) == 0:
    raise SystemExit('no authenticated relocations found')
