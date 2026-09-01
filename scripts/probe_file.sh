#!/bin/sh
# probe_file.sh — compila um SNIPPET EM ESCOPO DE ARQUIVO (extensions, classes,
# top-level decls), ao contrario do probe_api.py que embrulha tudo numa func.
#
# Uso: probe_file.sh <arquivo.swift> [outro.swift ...]
set -e
SW=/opt/swift6.3.3
SF=$SW/usr/bin/swift-frontend
ROOT=/opt/isb/sysroot
SDK=$ROOT/iPhoneOS26.5.sdk
OUT=/opt/ios-toolchain/foundation-build633
VFS=$ROOT/vfs/overlay.yaml
BIG=/var/tmp/isb-cache/probefile
mkdir -p "$BIG"

MODS=""
for f in "$OUT"/swift_*.swiftmodule; do
  n=$(basename "$f" .swiftmodule); n=${n#swift_}
  [ "$n" = "XPC" ] && continue
  MODS="$MODS -swift-module-file=$n=$f"
done
for f in "$OUT"/clang_*.pcm; do
  n=$(basename "$f" .pcm); n=${n#clang_}
  MODS="$MODS -Xcc -fmodule-file=$n=$f"
done

$SF -frontend -typecheck -target arm64-apple-ios26.0 -sdk "$SDK" \
  -enable-objc-interop -swift-version 5 \
  -disable-implicit-swift-modules -Xcc -fno-implicit-modules \
  -Xcc -fno-implicit-module-maps -Xcc -ivfsoverlay -Xcc "$VFS" \
  -module-name ProbeFile "$@" $MODS \
  -Xcc -fmodules-cache-path="$BIG" -Xcc -DCF_SWIFT_SENDABLE= 2>&1 | grep -E "error:" | head -8
exit 0
