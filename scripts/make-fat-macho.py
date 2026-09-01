#!/usr/bin/env python3
"""Build a big-endian FAT Mach-O from arm64 and arm64e slices."""
import struct, sys
if len(sys.argv) != 4:
    print('usage: make-fat-macho.py ARM64 ARM64E OUTPUT', file=sys.stderr); raise SystemExit(2)
a,b,out=sys.argv[1:]
sa=open(a,'rb').read(); se=bytearray(open(b,'rb').read())
def header(x):
    if len(x)<32: raise SystemExit('short Mach-O')
    return struct.unpack_from('<8I',x,0)
ha=header(sa); he=header(se)
if ha[0]!=0xfeedfacf or ha[1]!=0x0100000c or (ha[2]&0xffffff)!=0: raise SystemExit('first input is not arm64')
if he[0]!=0xfeedfacf or he[1]!=0x0100000c or (he[2]&0xffffff)!=2: raise SystemExit('second input is not arm64e')
# FAT table and inner header use the platform's versioned arm64e ABI.
# Do not emit subtype 2: iOS 26 reports that as arm64e.old.
struct.pack_into('<I',se,8,0x81000002)
align=14; header_size=8+2*20; off_a=(header_size + (1<<align)-1)&~((1<<align)-1); off_e=(off_a+len(sa)+(1<<align)-1)&~((1<<align)-1)
outb=bytearray(off_e+len(se)); struct.pack_into('>II',outb,0,0xcafebabe,2)
struct.pack_into('>iiIII',outb,8,0x0100000c,0,off_a,len(sa),align)
struct.pack_into('>IiIII',outb,28,0x0100000c,-2130706430,off_e,len(se),align)
outb[off_a:off_a+len(sa)]=sa; outb[off_e:off_e+len(se)]=se
open(out,'wb').write(outb)
print('FAT Mach-O: arm64 off=%d size=%d; arm64e off=%d size=%d; total=%d' % (off_a,len(sa),off_e,len(se),len(outb)))
