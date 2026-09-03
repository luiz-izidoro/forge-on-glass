#!/usr/bin/env python3
"""Validate Mach-O invariants required by LiveContainer's patcher."""
import os, struct, sys
if len(sys.argv) != 2:
    print('usage: check-livecontainer.py executable'); raise SystemExit(2)
p=sys.argv[1]; b=open(p,'rb').read()
if len(b)<32: raise SystemExit('short Mach-O')
magic,cpu,sub,ft,ncmd,sz,flags,res=struct.unpack_from('<IiiIIIII',b,0)
if magic != 0xfeedfacf or cpu != 0x0100000c: raise SystemExit('not thin 64-bit ARM Mach-O')
base=sub & 0x00ffffff
if base not in (0,1,2): raise SystemExit('unsupported ARM64 subtype 0x%08x'%(sub&0xffffffff))
p=32; segments=0; fix=None; main=None; cs=None
for i in range(ncmd):
    if p+8>len(b): raise SystemExit('truncated load command')
    cmd,cmdsize=struct.unpack_from('<II',b,p)
    if cmdsize<8 or p+cmdsize>len(b): raise SystemExit('invalid load command')
    if cmd==0x19: segments+=1
    elif cmd==0x80000034: fix=struct.unpack_from('<II',b,p+8)
    elif cmd==0x80000028: main=struct.unpack_from('<QQ',b,p+8)
    elif cmd==0x1d: cs=struct.unpack_from('<II',b,p+8)
    p+=cmdsize
if not main or main[0]==0: raise SystemExit('missing LC_MAIN entryoff')
if not fix: raise SystemExit('missing LC_DYLD_CHAINED_FIXUPS')
off,size=fix
if size == 0 or off+size>len(b): raise SystemExit('invalid fixup payload')
if off+28 > len(b): raise SystemExit('short fixup header')
h=struct.unpack_from('<7I',b,off)
if h[0] != 0x00000000: raise SystemExit('unsupported chained fixups version')
if h[1] < 28 or off+h[1] > len(b): raise SystemExit('invalid fixup starts')
segcount=struct.unpack_from('<I',b,off+h[1])[0]
if segcount != segments: raise SystemExit('fixup seg_count=%d != Mach-O segments=%d'%(segcount,segments))
if os.environ.get('ISB_REQUIRE_SIGNATURE','0') == '1' and not cs: raise SystemExit('missing LC_CODE_SIGNATURE')
print('LiveContainer invariants OK: subtype=0x%08x segments=%d fixups=yes entryoff=%d signature=%s'%(
    sub&0xffffffff,segments,main[0], 'yes' if cs else 'no'))
