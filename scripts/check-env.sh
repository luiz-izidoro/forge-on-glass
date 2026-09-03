#!/bin/sh
# check-env.sh — verify the canonical native arm64e/PAC profile.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SYSROOT=${ISB_SYSROOT:-/opt/isb/sysroot}
SWROOT=${ISB_SW_ROOT:-/opt/swift6.3.3}
TOOLCHAIN=${ISB_TOOLCHAIN_ROOT:-/opt/ios-toolchain}
SDK=${ISB_SDK:-$SYSROOT/iPhoneOS26.5.sdk}
CACHE=${ISB_FOUNDATION_BUILD:-$TOOLCHAIN/foundation-build633-arm64e}
LINKER=${ISB_LINKER:-$TOOLCHAIN/ld64.lld-arm64e}
VFS=${ISB_VFS:-$SYSROOT/vfs/overlay.yaml}
APP_CACHE=${ISB_MODULE_CACHE:-/var/tmp/isb-cache}
ok=1
note(){ printf '%s %s\n' "$1" "$2"; }
fail(){ ok=0; note 'XX' "$1"; }

printf '%s\n' '=== forge-on-glass arm64e environment ==='
[ -x "$SWROOT/usr/bin/swift-frontend" ] || fail "Swift 6.3.3 frontend missing: $SWROOT/usr/bin/swift-frontend"
if [ -x "$SWROOT/usr/bin/swift-frontend" ]; then
  version=$(env -i HOME=/root TERM=dumb "$SWROOT/usr/bin/swift-frontend" --version 2>/dev/null | head -1 || true)
  case "$version" in *6.3.3*) note 'OK' "swift-frontend: $version";; *) fail "Swift frontend is not 6.3.3: ${version:-no output}";; esac
fi
[ -f "$SDK/usr/lib/libSystem.tbd" ] || fail "iOS SDK 26.5 missing: $SDK"
[ -d "$SDK/System/Library/SubFrameworks" ] || fail 'SDK SubFrameworks missing'
[ -f "$VFS" ] || fail "neutral VFS overlay missing: $VFS"
[ -x "$LINKER" ] || fail "arm64e PAC linker missing: $LINKER"
if [ -x "$LINKER" ]; then file "$LINKER" | grep -q aarch64 && note 'OK' 'local arm64e PAC linker' || fail 'PAC linker is not native aarch64'; fi
[ -d "$CACHE" ] || fail "arm64e module cache missing: $CACHE"
if [ -d "$CACHE" ]; then
  swift_count=$(find "$CACHE" -maxdepth 1 -name 'swift_*.swiftmodule' -type f | wc -l | tr -d ' ')
  pcm_count=$(find "$CACHE" -maxdepth 1 -name 'clang_*.pcm' -type f | wc -l | tr -d ' ')
  [ "$swift_count" -gt 0 ] && [ "$pcm_count" -gt 0 ] || fail "arm64e cache incomplete (${swift_count} swiftmodule, ${pcm_count} PCM)"
  note 'OK' "arm64e cache (${swift_count} swiftmodule, ${pcm_count} PCM)"
  cache_log=$(mktemp /tmp/isb-cache-check.XXXXXX)
  if python3 "$ROOT/scripts/check-module-cache.py" "$CACHE" >"$cache_log" 2>&1; then :; else cat "$cache_log"; fail 'arm64e cache is not neutral'; fi
  rm -f "$cache_log"
fi
for tool in clang ldid llvm-strip zip; do command -v "$tool" >/dev/null 2>&1 && note 'OK' "tool: $tool" || fail "tool missing: $tool"; done
mkdir -p "$APP_CACHE"
for framework in NaturalLanguage FoundationModels CoreML Vision Accelerate; do
  [ -f "$SDK/System/Library/Frameworks/$framework.framework/$framework.tbd" ] && note 'OK' "$framework framework stub" || fail "$framework framework stub missing";
done
[ -f "$TOOLCHAIN/extrafw/UIKitCore.framework/UIKitCore.tbd" ] && note 'OK' 'UIKitCore generic stub' || fail 'UIKitCore generic stub missing'
free_kb=$(df -Pk / | awk 'NR==2 {print $4}')
free_gb=$((free_kb / 1024 / 1024))
[ "$free_gb" -ge 2 ] && note 'OK' "free disk: ${free_gb} GB" || fail "free disk: ${free_gb} GB"
printf '%s\n' '==='
[ "$ok" -eq 1 ] && { echo 'ARM64E: READY'; exit 0; }
echo 'ARM64E: NOT READY'; exit 1
