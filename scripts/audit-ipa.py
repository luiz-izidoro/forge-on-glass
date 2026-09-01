#!/usr/bin/env python3
"""Audit one Radar IPA without confusing FAT payloads or stale outputs."""
import hashlib, plistlib, struct, sys, zipfile
from pathlib import Path
if len(sys.argv)!=3: raise SystemExit('usage: audit-ipa.py IPA fat|arm64|arm64e')
ipa=Path(sys.argv[1]); expected=sys.argv[2]
with zipfile.ZipFile(ipa) as z:
    dirs=sorted({n.rsplit('/',1)[0]+'/' for n in z.namelist() if n.startswith('Payload/') and '.app/' in n})
    if not dirs: raise SystemExit('Payload app missing')
    root=dirs[0]; app=Path(root.rstrip('/')).name.removesuffix('.app'); data=z.read(root+app); info=plistlib.loads(z.read(root+'Info.plist'))
print('IPA=%s app=%s executable=%s sha256=%s'%(ipa.name,root,app,hashlib.sha256(data).hexdigest()))
magic=struct.unpack_from('>I',data,0)[0] if len(data)>=4 else 0
if magic==0xcafebabe:
    arch='fat'; nfat=struct.unpack_from('>I',data,4)[0]; print('architecture=fat slices=%d'%nfat)
    if expected!='fat': raise SystemExit('expected '+expected+', got FAT')
    for i in range(nfat):
        cpu,sub,off,size,align=struct.unpack_from('>IiIII',data,8+i*20); inner=struct.unpack_from('<I',data,off+8)[0]; print('slice[%d] table=0x%08x inner=0x%08x'%(i,sub&0xffffffff,inner))
elif data[:4]==b'\xcf\xfa\xed\xfe':
    sub=struct.unpack_from('<I',data,8)[0]; arch='arm64e' if sub&0xffffff==2 else 'arm64' if sub&0xffffff==0 else 'unknown'; print('architecture=%s subtype=0x%08x'%(arch,sub));
    if expected!=arch: raise SystemExit('expected '+expected+', got '+arch)
else: raise SystemExit('not Mach-O')
print('bundle=%s minOS=%s'%(info.get('CFBundleIdentifier'),info.get('MinimumOSVersion')))
