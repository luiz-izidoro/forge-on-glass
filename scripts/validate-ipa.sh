#!/bin/sh
# validate-ipa.sh — inspect a built IPA and confirm it is a valid Swift iOS app.
# Usage: validate-ipa.sh /path/to/App.ipa
set -e
IPA="$1"
[ -f "$IPA" ] || { echo "usage: validate-ipa.sh <App.ipa>"; exit 2; }

OBJ=$(command -v llvm-objdump || echo "/usr/bin/llvm-objdump")
TMP=/tmp/ipaval_$$; rm -rf "$TMP"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
unzip -q "$IPA" -d "$TMP"
BIN=$(find "$TMP/Payload" -maxdepth 2 -type f ! -name '*.plist' | head -1)
[ -n "$BIN" ] || { echo "no executable found in Payload"; exit 1; }

echo "=== $IPA ==="
echo "-- executable --"; file "$BIN" | sed 's/^[^:]*: //'
echo "-- platform / SDK --"
"$OBJ" --macho --all-headers "$BIN" 2>/dev/null | grep -iE "platform ios|sdk |minos" | head -3
echo "-- linked dylibs --"
"$OBJ" --macho --dylibs-used "$BIN" 2>/dev/null | sed 's/^[[:space:]]*//' | grep -v '^$'
echo "-- Swift embedded? (mangled symbol / metadata section) --"
strings "$BIN" 2>/dev/null | grep -m1 -E '\$s|[0-9]+swift' && echo "  → Swift symbols present" || echo "  (no visible swift symbol — may be fully stripped)"
"$OBJ" --macho --section-headers "$BIN" 2>/dev/null | grep -i "swift5" | head -2
echo "-- code signature --"
ldid -h "$BIN" 2>/dev/null | grep -iE "CDHash=" | head -1 || echo "  (no signature — run ldid -S)"
echo "-- bundle contents --"
find "$TMP/Payload" -type f | sed "s|$TMP/Payload/||"
echo "=== OK ==="
