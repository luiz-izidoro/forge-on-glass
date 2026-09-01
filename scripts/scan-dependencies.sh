#!/bin/sh
# scan-dependencies.sh — generate a target-specific graph on real Linux.
# Run from a machine containing the user's SDK and Swift 6.3.3.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SW=${ISB_VM_SW:?set ISB_VM_SW to Swift 6.3.3}
SDK=${ISB_VM_SDK:?set ISB_VM_SDK to the user iOS SDK}
VFS=${ISB_VM_VFS:?set ISB_VM_VFS to the matching overlay.yaml}
SEED=${1:?usage: scan-dependencies.sh seed.swift [output.json]}
OUT=${2:-fscan.json}
TARGET=${ISB_TARGET:-arm64e-apple-ios26.5}
CACHE=${ISB_VM_MODULE_CACHE:-$PWD/module-cache}
mkdir -p "$CACHE" "$(dirname "$OUT")"
"$SW/usr/bin/swift-frontend" -scan-dependencies \
  -target "$TARGET" -sdk "$SDK" -resource-dir "$SW/usr/lib/swift" \
  -module-cache-path "$CACHE" -Xcc -ivfsoverlay -Xcc "$VFS" \
  "$SEED" -o "$OUT"
python3 - "$OUT" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); print("scan OK: modules=%d"%(len(d["modules"])//2))
PY
