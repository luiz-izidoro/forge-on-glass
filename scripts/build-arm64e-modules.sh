#!/bin/sh
# arm64e-module-profile.sh — build the complete Swift module cache for the
# arm64e iOS 26.5 slice. Run on a real Linux host with the same Swift 6.3.3
# toolchain and SDK used by the local arm64e profile.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT="${ISB_VM_ROOT:-$HOME/swift-ios-build}"
SW="${ISB_VM_SW:-$ROOT/swift-6.3.3}"
SDK="${ISB_VM_SDK:-$ROOT/iPhoneOS26.5.sdk}"
OUT="${ISB_VM_OUT:-$ROOT/foundation-build633-arm64e}"
TARGET="${ISB_TARGET:-arm64e-apple-ios26.5}"
SCAN_CACHE="${ISB_SCAN_CACHE:-$ROOT/bigtmp/scan-arm64e}"
SF="$SW/usr/bin/swift-frontend"
VFS="${ISB_VM_VFS:-$ROOT/vfs/overlay.yaml}"
ORCH="${ISB_ORCHESTRATOR:-$REPO_ROOT/references/linux-vm/orchestrator_vm633.py}"

[ -x "$SF" ] || { echo "swift-frontend ausente: $SF" >&2; exit 1; }
[ -d "$SDK" ] || { echo "SDK ausente: $SDK" >&2; exit 1; }
[ -f "$SDK/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface" ] || {
  echo "FoundationModels arm64e interface ausente no SDK 26.5" >&2; exit 1;
}
mkdir -p "$SCAN_CACHE" "$OUT"
[ -f "$ORCH" ] || { echo "orchestrator ausente: $ORCH" >&2; exit 1; }
[ "$TARGET" = "arm64e-apple-ios26.5" ] || { echo "target must be arm64e-apple-ios26.5" >&2; exit 1; }
[ -f "$VFS" ] || { echo "VFS ausente: $VFS" >&2; exit 1; }
# Include both native language embeddings and the on-device Foundation Models
# API in the dependency graph. The scanner then discovers Foundation,
# Observation, _Concurrency, and _StringProcessing transitively.
cat > "$SCAN_CACHE/seed.swift" <<'EOF'
import Foundation
import NaturalLanguage
import FoundationModels
import SwiftOnoneSupport
EOF
rm -f "$SCAN_CACHE/fscan.json" "$SCAN_CACHE/scan.err"
scan_ok=0
for attempt in 1 2 3 4 5 6; do
  if "$SF" -scan-dependencies -target "$TARGET" -sdk "$SDK" \
  -resource-dir "$SW/usr/lib/swift" -module-cache-path "$SCAN_CACHE" \
  -Xcc -ivfsoverlay -Xcc "$VFS" \
  "$SCAN_CACHE/seed.swift" -o "$SCAN_CACHE/fscan.json" \
      2>"$SCAN_CACHE/scan.err" && [ -s "$SCAN_CACHE/fscan.json" ]; then
    scan_ok=1
    break
  fi
  rm -f "$SCAN_CACHE/fscan.json"
  echo "scan-dependencies retry $attempt/6" >&2
done
[ "$scan_ok" -eq 1 ] || {
  echo "scan-dependencies falhou após 6 tentativas; log: $SCAN_CACHE/scan.err" >&2
  exit 1
}

# The canonical generator runs on a Linux/VM host; its outputs and target are
# isolated to arm64e/PAC.
ISB_VM_SW="$SW" ISB_VM_SDK="$SDK" ISB_VM_OUT="$OUT" ISB_VM_VFS="${ISB_VM_VFS:-$ROOT/vfs/overlay.yaml}" ISB_TARGET="$TARGET" \
  FSCAN="$SCAN_CACHE/fscan.json" python3 "$ORCH"

# Hard fail if the IA modules were silently skipped.
for m in Swift Foundation NaturalLanguage FoundationModels SwiftUICore UIKit SwiftUI; do
  [ -s "$OUT/swift_${m}.swiftmodule" ] || { echo "modulo ausente: $m" >&2; exit 1; }
done
for fw in Foundation NaturalLanguage FoundationModels; do
  [ -s "$SDK/System/Library/Frameworks/$fw.framework/$fw.tbd" ] || { echo "framework ausente: $fw" >&2; exit 1; }
done
echo "arm64e module profile READY: $OUT"
