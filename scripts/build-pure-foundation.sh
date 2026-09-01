#!/bin/sh
# build-pure-foundation.sh — compile+link a PURE-SWIFT iOS app that uses
# Foundation/Dispatch/Combine/etc. on iSH, using the VM-built modules.
#
# Usage: build-pure-foundation.sh <AppName> <main.swift>
# Output: <AppName> (Mach-O arm64 iOS 26.0)
#
# Requires (all present after the 2026-08-18 breakthrough):
#   /opt/ios-toolchain/foundation-build/  (VM-built pcm + swiftmodule set)
#   /opt/isb/sysroot/{iPhoneOS26.5.sdk,swift-6.3.2} symlinks
#   /opt/swift6.3/usr/lib/swift/{dispatch,os,CoreFoundation} -> SDK symlinks
set -e
APP="$1"; SRC="$2"
OBJ="/tmp/$(basename "$APP").o"
ERRF="/tmp/$(basename "$APP").swift.err"
SW=/opt/swift6.3
SF="$SW/usr/bin/swift-frontend"
SDK=/opt/ios-toolchain/iPhoneOS26.5.sdk
OUT=/opt/ios-toolchain/foundation-build

# --- compile (retry for the ~15-25% startup race) ---
CMD="$SF -c -target arm64-apple-ios26.0 -sdk $SDK -resource-dir $SW/usr/lib/swift -I $OUT"
for f in $OUT/swift_*.swiftmodule; do
  nm=$(basename "$f" .swiftmodule | sed 's/^swift_//')
  CMD="$CMD -swift-module-file=$nm=$f"
done
for f in $OUT/clang_*.pcm; do
  nm=$(basename "$f" .pcm | sed 's/^clang_//')
  CMD="$CMD -Xcc -fmodule-file=$nm=$f"
done
CMD="$CMD -Xcc -ivfsoverlay -Xcc /opt/ios-toolchain/vfs/overlay.yaml"

i=0
while [ $i -lt 6 ]; do
  timeout 900 env -i HOME=/root TERM=dumb sh -c "$CMD '$SRC' -o $OBJ" 2>"$ERRF" || true
  [ -s "$OBJ" ] && break
  i=$((i+1)); sleep 1
done
[ -s "$OBJ" ] || { echo "swift compile failed"; tail -5 "$ERRF"; exit 1; }
echo "[1/2] Swift OK ($(wc -c <"$OBJ")B)"

# --- link ---
/usr/bin/clang -target arm64-apple-ios26.0 -isysroot "$SDK" -fuse-ld=lld \
  -L "$SDK/usr/lib/swift" -L "$SDK/usr/lib" \
  "$OBJ" \
  -framework Foundation -framework CoreFoundation -lobjc \
  -lswiftCore -lswiftFoundation -lswiftDispatch -lswift_Concurrency \
  -lswift_StringProcessing -lswiftSwiftOnoneSupport -lswiftCoreFoundation \
  -Wl,-platform_version,ios,26.0,26.5 \
  -o "$APP" 2>"/tmp/$(basename "$APP").link.err" || { echo "link failed"; cat "/tmp/$(basename "$APP").link.err"; exit 1; }
echo "[2/2] Linked: $APP ($(wc -c <"$APP")B)"
