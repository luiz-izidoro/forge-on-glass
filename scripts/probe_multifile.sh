#!/bin/sh
# probe_multifile.sh — compara resolucao de nomes em UM arquivo vs MULTI arquivo.
# Descoberta 2026-08-19: compilar varios .swift juntos MUDA a visibilidade de
# alguns simbolos do Foundation (NotificationCenter, NSAttributedString.Key).
set -e
SW=/opt/swift6.3.3
SF=$SW/usr/bin/swift-frontend
ROOT=/opt/isb/sysroot
SDK=$ROOT/iPhoneOS26.5.sdk
OUT=/opt/ios-toolchain/foundation-build633
VFS=$ROOT/vfs/overlay.yaml
W=/tmp/probe-multi
rm -rf $W && mkdir -p $W /var/tmp/isb-cache/pm

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

CODE="${1:-_ = NotificationCenter.default}"

cat > $W/a.swift <<EOF
import Foundation
import UIKit
import Dispatch
public func probe() { $CODE }
EOF
cat > $W/b.swift <<EOF
import Foundation
import UIKit
import Dispatch
public func helper() -> Int { return 1 }
EOF

run() {
  $SF -frontend -typecheck -target arm64-apple-ios26.0 -sdk "$SDK" \
    -enable-objc-interop -swift-version 5 \
    -disable-implicit-swift-modules -Xcc -fno-implicit-modules \
    -Xcc -fno-implicit-module-maps -Xcc -ivfsoverlay -Xcc "$VFS" \
    -module-name Probe "$@" $MODS \
    -Xcc -fmodules-cache-path=/var/tmp/isb-cache/pm -Xcc -DCF_SWIFT_SENDABLE= 2>&1
}

echo "== 1 arquivo =="
if run $W/a.swift > $W/one.err 2>&1; then echo "  OK"; else grep -m1 "error:" $W/one.err | sed 's/^/  /'; fi
echo "== 2 arquivos =="
if run $W/a.swift $W/b.swift > $W/two.err 2>&1; then echo "  OK"; else grep -m1 "error:" $W/two.err | sed 's/^/  /'; fi
