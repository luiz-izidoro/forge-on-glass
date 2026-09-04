#!/bin/sh
# bootstrap.sh — staged setup for a fresh Alpine/iSH checkout.
# Apple SDK, Swift, glibc and module-cache inputs are user-provided and remain
# outside Git. This script never downloads Apple material implicitly.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SYSROOT=${ISB_SYSROOT:-/opt/isb/sysroot}
TOOLCHAIN=${ISB_TOOLCHAIN_ROOT:-/opt/ios-toolchain}
SWIFT_ROOT=${ISB_SWIFT_ROOT:-/opt/swift6.3.3}
SDK="${ISB_SDK:-$SYSROOT/iPhoneOS26.5.sdk}"
CACHE="${ISB_FOUNDATION_BUILD:-$TOOLCHAIN/foundation-build633-arm64e}"
LINKER="${ISB_LINKER:-$TOOLCHAIN/ld64.lld-arm64e}"
VFS="${ISB_VFS:-$SYSROOT/vfs/overlay.yaml}"
STEP=0; CHECK=0
usage(){ echo "usage: $0 --check | --step N | --all"; exit 2; }
[ "$#" -gt 0 ] || usage
while [ "$#" -gt 0 ]; do case "$1" in
  --check) CHECK=1;; --step) shift; STEP=${1:?missing step};; --all) STEP=99;; *) usage;;
esac; shift; done
check(){
  bad=0; echo '== forge-on-glass arm64e bootstrap check =='
  printf 'repo: '; [ -f "$ROOT/SKILL.md" ] && echo OK || { echo MISSING; bad=1; }
  printf 'Swift 6.3.3 frontend: '; [ -x "$SWIFT_ROOT/usr/bin/swift-frontend" ] && echo OK || { echo MISSING; bad=1; }
  printf 'iOS SDK 26.5: '; [ -f "$SDK/usr/lib/libSystem.tbd" ] && echo OK || { echo MISSING; bad=1; }
  printf 'arm64e cache: '; if [ -d "$CACHE" ] && python3 "$ROOT/scripts/check-module-cache.py" "$CACHE" "$SYSROOT" >/dev/null 2>&1; then echo OK; else echo MISSING/INVALID; bad=1; fi
  printf 'neutral sysroot: '; [ -e "$SYSROOT/iPhoneOS26.5.sdk" ] && echo OK || { echo MISSING; bad=1; }
  printf 'VFS overlay: '; [ -f "$VFS" ] && echo OK || { echo MISSING; bad=1; }
  printf 'PAC linker: '; [ -x "$LINKER" ] && echo OK || { echo MISSING; bad=1; }
  printf 'glibc loader: '; [ -e "${ISB_GLIBC_ROOT:-/opt/xtool-glibc/lib}/ld-linux-aarch64.so.1" ] && echo OK || { echo MISSING; bad=1; }
  [ "$bad" -eq 0 ] && return 0
  echo 'Missing inputs are expected until bootstrap stages are completed.'
  return 1
}
[ "$CHECK" -eq 1 ] && { check; exit $?; }
if [ "$STEP" -ge 1 ] && [ "$STEP" -le 99 ]; then
  apk add clang19 lld zip xz zstd binutils patchelf git python3 wget patch
fi
if [ "$STEP" -ge 2 ] && [ "$STEP" -le 99 ]; then
  : "${ISB_SWIFT_URL:?Set ISB_SWIFT_URL to the Swift 6.3.3 Ubuntu aarch64 tarball}"
  : "${ISB_SWIFT_SHA256:?Set ISB_SWIFT_SHA256 before downloading}"
  mkdir -p /tmp/isb-bootstrap; archive=/tmp/isb-bootstrap/swift.tar.gz
  wget -O "$archive" "$ISB_SWIFT_URL"
  echo "$ISB_SWIFT_SHA256  $archive" | sha256sum -c -
  tar xzf "$archive" -C /tmp/isb-bootstrap
  src=$(find /tmp/isb-bootstrap -maxdepth 1 -type d -name 'swift-6.3.3-RELEASE*' | head -1)
  [ -n "$src" ] || { echo 'Swift archive layout not recognized' >&2; exit 1; }
  rm -rf "$SWIFT_ROOT"; mv "$src" "$SWIFT_ROOT"
fi
if [ "$STEP" -ge 3 ] && [ "$STEP" -le 99 ]; then
  : "${ISB_SDK_ARCHIVE:?Set ISB_SDK_ARCHIVE to a user-provided iOS 26.5 SDK archive}"
  : "${ISB_SDK_SHA256:?Set ISB_SDK_SHA256 before extracting the SDK}"
  echo "$ISB_SDK_SHA256  $ISB_SDK_ARCHIVE" | sha256sum -c -
  mkdir -p "$TOOLCHAIN" "$SYSROOT"
  tar xf "$ISB_SDK_ARCHIVE" -C "$SYSROOT"
  [ -d "$SDK" ] || {
    echo "SDK extraído mas não encontrado em $SDK" >&2; exit 1;
  }
fi
if [ "$STEP" -ge 4 ] && [ "$STEP" -le 99 ]; then
  echo 'Stage 4: stdlib and framework modules are produced with the matching Linux VM orchestrator.'
# The canonical module cache is generated with arm64e; no compatibility cache
# is produced by this script.
fi
if [ "$STEP" -ge 5 ] && [ "$STEP" -le 99 ]; then
  echo 'Stage 5 requires real Linux/VM/Docker: build foundation-build633-arm64e.'
  echo 'Use references/linux-vm/orchestrator_vm633.py and copy the validated cache.'
fi
if [ "$STEP" -ge 6 ] && [ "$STEP" -le 99 ]; then
  sh "$ROOT/scripts/bootstrap-glibc.sh" \
    --packages "${ISB_GLIBC_PACKAGES:?Set ISB_GLIBC_PACKAGES}" \
    --sha256 "${ISB_GLIBC_SHA256:?Set ISB_GLIBC_SHA256}" \
    --out "${ISB_GLIBC_ROOT:-/opt/xtool-glibc/lib}"
fi
[ "$STEP" -eq 99 ] && check
