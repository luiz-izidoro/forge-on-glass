#!/bin/sh
# validate-ipa.sh — strict structural validation for a single-app IPA.
set -eu
IPA="${1:-}"
[ -f "$IPA" ] || { echo "usage: validate-ipa.sh <App.ipa>"; exit 2; }
command -v unzip >/dev/null || { echo 'unzip is required' >&2; exit 2; }
command -v llvm-objdump >/dev/null || { echo 'llvm-objdump is required' >&2; exit 2; }
TMP=$(mktemp -d /tmp/ipaval_XXXXXX); trap 'rm -rf "$TMP"' EXIT
unzip -q "$IPA" -d "$TMP"
APPS=$(find "$TMP/Payload" -maxdepth 1 -type d -name '*.app' 2>/dev/null | wc -l | tr -d ' ')
[ "$APPS" = 1 ] || { echo "expected exactly one Payload/*.app, got $APPS" >&2; exit 1; }
APPDIR=$(find "$TMP/Payload" -maxdepth 1 -type d -name '*.app' | head -1)
BIN="$APPDIR/$(basename "$APPDIR" .app)"
[ -s "$BIN" ] || { echo "bundle executable missing: $BIN" >&2; exit 1; }
python3 - "$BIN" "${ISB_REQUIRE_SIGNATURE:-1}" <<'PY'
import struct,sys
p=sys.argv[1]; require_sig=sys.argv[2] == '1'; b=open(p,'rb').read()
if len(b)<32: raise SystemExit('short Mach-O')
magic,cpu,sub,ft,ncmd,sz,flags,res=struct.unpack_from('<IiiIIIII',b,0)
if magic != 0xfeedfacf or cpu != 0x0100000c: raise SystemExit('not thin ARM64 Mach-O')
cmds=[]; pos=32
for _ in range(ncmd):
 if pos+8>len(b): raise SystemExit('truncated load commands')
 c,s=struct.unpack_from('<II',b,pos)
 if s<8 or pos+s>len(b): raise SystemExit('invalid load command')
 cmds.append(c); pos+=s
if 0x80000028 not in cmds: raise SystemExit('missing LC_MAIN')
if 0x80000034 not in cmds: raise SystemExit('missing LC_DYLD_CHAINED_FIXUPS')
if 0x1d not in cmds and require_sig: raise SystemExit('missing LC_CODE_SIGNATURE (required)')
print('strict Mach-O: chained fixups present; code signature=%s' % ('present' if 0x1d in cmds else 'absent/explicitly allowed'))
PY
OBJ=llvm-objdump
printf '%s\n' "=== $IPA ==="
printf '%s\n' '-- executable --'; file "$BIN" | sed 's/^[^:]*: //'
printf '%s\n' '-- platform / SDK --'; "$OBJ" --macho --all-headers "$BIN" 2>/dev/null | grep -iE 'platform ios|sdk |minos' | head -3
printf '%s\n' '-- linked dylibs --'; "$OBJ" --macho --dylibs-used "$BIN" 2>/dev/null | sed 's/^[[:space:]]*//' | grep -v '^$'
printf '%s\n' '-- code signature --'; ldid -h "$BIN" 2>/dev/null | grep -iE 'CDHash=' | head -1
printf '%s\n' '-- bundle contents --'; find "$TMP/Payload" -type f | sed "s|$TMP/Payload/||"
printf '%s\n' '=== OK ==='
