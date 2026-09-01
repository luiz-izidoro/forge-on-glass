#!/bin/sh
# arm64e-module-profile.sh — build the complete Swift module cache for the
# arm64e iOS 26.5 slice. Run on a real Linux host with the same Swift 6.3.3
# toolchain and SDK used by the arm64 profile.
set -e
ROOT="${ISB_VM_ROOT:-$HOME/swift-ios-build}"
SW="${ISB_VM_SW:-$ROOT/swift-6.3.3}"
SDK="${ISB_VM_SDK:-$ROOT/iPhoneOS26.5.sdk}"
OUT="${ISB_VM_OUT:-$ROOT/foundation-build633-arm64e}"
TARGET="${ISB_TARGET:-arm64e-apple-ios26.5}"
SCAN_CACHE="${ISB_SCAN_CACHE:-$ROOT/bigtmp/scan-arm64e}"
SF="$SW/usr/bin/swift-frontend"
ORCH="${ISB_ORCHESTRATOR:-$ROOT/orchestrator_vm633-arm64e.py}"

[ -x "$SF" ] || { echo "swift-frontend ausente: $SF" >&2; exit 1; }
[ -d "$SDK" ] || { echo "SDK ausente: $SDK" >&2; exit 1; }
[ -f "$SDK/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface" ] || {
  echo "FoundationModels arm64e interface ausente no SDK 26.5" >&2; exit 1;
}
mkdir -p "$SCAN_CACHE" "$OUT"

# Include both native language embeddings and the on-device Foundation Models
# API in the dependency graph. The scanner then discovers Foundation,
# Observation, _Concurrency, and _StringProcessing transitively.
cat > "$SCAN_CACHE/seed.swift" <<'EOF'
import Foundation
import NaturalLanguage
import FoundationModels
import SwiftOnoneSupport
EOF
rm -f "$SCAN_CACHE/fscan.json"
"$SF" -scan-dependencies -target "$TARGET" -sdk "$SDK" \
  -resource-dir "$SW/usr/lib/swift" -module-cache-path "$SCAN_CACHE" \
  "$SCAN_CACHE/seed.swift" -o "$SCAN_CACHE/fscan.json"
[ -s "$SCAN_CACHE/fscan.json" ] || { echo "scan-dependencies falhou" >&2; exit 1; }
cp "$SCAN_CACHE/fscan.json" /tmp/fscan.json

# The orchestrator is shared with the arm64 VM recipe but all outputs and
# target triples are isolated by these variables.
ISB_VM_SW="$SW" ISB_VM_SDK="$SDK" ISB_VM_OUT="$OUT" ISB_TARGET="$TARGET" \
  FSCAN="$SCAN_CACHE/fscan.json" python3 "$ORCH"

# Hard fail if the IA modules were silently skipped.
for m in Swift Foundation NaturalLanguage FoundationModels SwiftUICore UIKit SwiftUI; do
  [ -s "$OUT/swift_${m}.swiftmodule" ] || { echo "modulo ausente: $m" >&2; exit 1; }
done
for fw in Foundation NaturalLanguage FoundationModels; do
  [ -s "$SDK/System/Library/Frameworks/$fw.framework/$fw.tbd" ] || { echo "framework ausente: $fw" >&2; exit 1; }
done
echo "arm64e module profile READY: $OUT"
