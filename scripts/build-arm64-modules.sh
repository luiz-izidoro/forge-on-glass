#!/bin/sh
# build-arm64-modules.sh — generate the reproducible arm64 Swift module cache.
# Requires the user's licensed SDK and Swift 6.3.3 under the neutral sysroot.
# It never overwrites an existing output directory.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
MODE=full
case "${1:-}" in
  "") ;;
  --full) MODE=full ;;
  --pcm-only) MODE=pcm-only ;;
  *) echo "uso: $0 [--full|--pcm-only]" >&2; exit 2 ;;
esac
VM_ROOT=${ISB_VM_ROOT:-/opt/isb/sysroot}
SW=${ISB_VM_SW:-$VM_ROOT/swift-6.3.3}
SDK=${ISB_VM_SDK:-$VM_ROOT/iPhoneOS26.5.sdk}
VFS=${ISB_VM_VFS:-$VM_ROOT/vfs/overlay.yaml}
OUT=${ISB_VM_OUT:-/opt/ios-toolchain/foundation-build633-neutral}
TARGET=${ISB_TARGET:-arm64-apple-ios26.0}
SCAN_CACHE=${ISB_SCAN_CACHE:-$VM_ROOT/module-cache-arm64}
FSCAN_GIVEN=0
SCAN_OK=0
[ -n "${FSCAN:-}" ] && FSCAN_GIVEN=1
FSCAN=${FSCAN:-$SCAN_CACHE/fscan.json}
SCAN_LOG=${ISB_SCAN_LOG:-$SCAN_CACHE/scan-dependencies.log}
SF="$SW/usr/bin/swift-frontend"
ORCH=${ISB_ORCHESTRATOR:-$ROOT/references/linux-vm/orchestrator_vm633.py}

[ -x "$SF" ] || { echo "swift-frontend ausente: $SF" >&2; exit 1; }
[ -d "$SDK" ] || { echo "SDK ausente: $SDK" >&2; exit 1; }
[ -f "$VFS" ] || { echo "VFS ausente: $VFS" >&2; exit 1; }
[ -f "$ORCH" ] || { echo "orquestrador ausente: $ORCH" >&2; exit 1; }
if [ "$MODE" = full ]; then
  n=$(find "$SDK" -name 'arm64-apple-ios*.swiftinterface' | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || {
    echo "SDK sem interfaces arm64 ($n encontradas): apenas PCMs podem ser regenerados. Use --pcm-only." >&2
    exit 3
  }
fi
[ ! -e "$OUT" ] || { echo "saida ja existe; recusando sobrescrever: $OUT" >&2; exit 2; }
mkdir -p "$OUT" "$SCAN_CACHE"
SEED="$SCAN_CACHE/seed-arm64.swift"
cat > "$SEED" <<'EOF'
import Foundation
import UIKit
import SwiftUI
import SwiftOnoneSupport
EOF
if [ "$FSCAN_GIVEN" -eq 1 ]; then
  [ -s "$FSCAN" ] || { echo "FSCAN fornecido ausente ou vazio: $FSCAN" >&2; exit 1; }
  SCAN_OK=1
else
  rm -f "$FSCAN" "$SCAN_LOG"
  for attempt in 1 2 3 4 5 6; do
    rm -f "$FSCAN"
    scan_rc=0
    "$SF" -scan-dependencies -target "$TARGET" -sdk "$SDK" \
        -resource-dir "$SW/usr/lib/swift" -module-cache-path "$SCAN_CACHE" \
        -Xcc -ivfsoverlay -Xcc "$VFS" "$SEED" -o "$FSCAN" \
        >>"$SCAN_LOG" 2>&1 || scan_rc=$?
    if [ "$scan_rc" -eq 0 ] && [ -s "$FSCAN" ]; then
      SCAN_OK=1
      break
    fi
    if [ "$scan_rc" -eq 0 ] && [ ! -s "$FSCAN" ] && [ ! -s "$SCAN_LOG" ]; then
      echo "scan-dependencies silent-exit race on attempt $attempt; retrying" >&2
    else
      echo "scan-dependencies retry $attempt (rc=$scan_rc; see $SCAN_LOG)" >&2
    fi
  done
fi
[ "$SCAN_OK" -eq 1 ] || { echo "scan-dependencies falhou; log: $SCAN_LOG" >&2; exit 1; }
python3 - "$FSCAN" <<'PY'
import json, sys
p=sys.argv[1]
d=json.load(open(p))
print("scan OK: modules=%d" % (len(d["modules"]) // 2))
PY

# The orchestrator is resumable, but its generated artifacts remain private.
# Retry the complete pass for the known iSH startup race, then fail closed via
# the explicit module and neutral-path checks below.
ORCH_OK=0
for attempt in 1 2 3; do
  if ISB_VM_ROOT="$VM_ROOT" ISB_VM_SW="$SW" ISB_VM_SDK="$SDK" \
      ISB_VM_VFS="$VFS" ISB_VM_OUT="$OUT" ISB_VM_MODULE_CACHE="$SCAN_CACHE" \
      ISB_TARGET="$TARGET" FSCAN="$FSCAN" ISB_PCM_ONLY="$([ "$MODE" = pcm-only ] && echo 1 || echo 0)" python3 "$ORCH"; then
    ORCH_OK=1
    break
  fi
  echo "orchestrator retry $attempt" >&2
done
[ "$ORCH_OK" -eq 1 ] || { echo "orquestrador falhou" >&2; exit 1; }

# In full mode these modules are required by the pure Swift UI profile. In
# pcm-only mode, Swift interfaces are intentionally not regenerated; only the
# Clang PCM set is required and validated.
if [ "$MODE" = full ]; then
  for m in Swift Foundation UIKit SwiftUI SwiftUICore Dispatch os; do
    [ -s "$OUT/swift_${m}.swiftmodule" ] || {
      echo "modulo swift ausente: $m" >&2
      exit 1
    }
  done
fi
for m in SwiftShims _SwiftConcurrencyShims _AvailabilityInternal Foundation UIKit SwiftUI SwiftUICore Dispatch os; do
  [ -s "$OUT/clang_${m}.pcm" ] || {
    echo "modulo clang ausente: $m" >&2
    exit 1
  }
done
python3 "$ROOT/scripts/check-module-cache.py" "$OUT" \
  || { echo "cache arm64 gerado nao e neutro" >&2; exit 1; }
count=$(find "$OUT" -maxdepth 1 -name 'swift_*.swiftmodule' -type f | wc -l)
pcms=$(find "$OUT" -maxdepth 1 -name '*.pcm' -type f | wc -l)
echo "arm64 module profile READY: $OUT ($count swiftmodule, $pcms PCM)"
