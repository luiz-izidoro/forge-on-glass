#!/usr/bin/env python3
"""Check that a framework is weak-linked in a thin 64-bit Mach-O."""
import struct
import sys

LC_LOAD_DYLIB = 0x0000000C
LC_LOAD_WEAK_DYLIB = 0x80000018
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE


def framework_name(path):
    return path.rsplit('/', 1)[-1].removesuffix('.framework')


def main():
    if len(sys.argv) != 3:
        print('usage: check-weak-link.py executable Framework', file=sys.stderr)
        return 2
    path, wanted = sys.argv[1:]
    wanted = framework_name(wanted)
    data = open(path, 'rb').read()
    if len(data) < 32:
        raise SystemExit('short Mach-O')
    magic = struct.unpack_from('<I', data)[0]
    if magic == MH_MAGIC_64:
        endian = '<'
    elif magic == MH_CIGAM_64:
        endian = '>'
    else:
        raise SystemExit('not a thin 64-bit Mach-O')
    _, _, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from(
        endian + 'IiiIIIII', data, 0)
    pos = 32
    found = []
    for _ in range(ncmds):
        if pos + 8 > len(data):
            raise SystemExit('truncated load command')
        cmd, cmdsize = struct.unpack_from(endian + 'II', data, pos)
        if cmdsize < 8 or pos + cmdsize > len(data):
            raise SystemExit('invalid load command')
        if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
            if cmdsize < 24:
                raise SystemExit('invalid dylib load command')
            nameoff = struct.unpack_from(endian + 'I', data, pos + 8)[0]
            if nameoff >= cmdsize - 8:
                raise SystemExit('invalid dylib name offset')
            end = data.find(b'\0', pos + nameoff, pos + cmdsize)
            if end < 0:
                raise SystemExit('unterminated dylib name')
            name = data[pos + nameoff:end].decode('utf-8', 'replace')
            if framework_name(name) == wanted:
                found.append((cmd, name))
        pos += cmdsize
    if not found:
        raise SystemExit('%s framework load command not found' % wanted)
    strong = [name for cmd, name in found if cmd == LC_LOAD_DYLIB]
    if strong:
        raise SystemExit('%s is strong-linked: %s' % (wanted, ', '.join(strong)))
    print('%s weak-linked: %s' % (wanted, ', '.join(name for _, name in found)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
