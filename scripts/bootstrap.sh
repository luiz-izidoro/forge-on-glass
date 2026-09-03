#!/bin/sh
# bootstrap.sh — staged setup for a fresh Alpine/iSH checkout.
# Apple/Swift/glibc inputs are user-provided and remain outside Git.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SYSROOT=${ISB_SYSROOT:-/opt/isb/sysroot}
TOOLCHAIN=${ISB_TOOLCHAIN_ROOT:-/opt/ios-toolchain}
SWIFT_ROOT=${ISB_SWIFT_ROOT:-/opt/swift6.3.3}
STEP=0; CHECK=0
usage(){ echo "uso: $0 --check | --step N | --all"; exit 2; }
[ "$#" -gt 0 ] || usage
while [ "$#" -gt 0 ]; do case "$1" in --check) CHECK=1;; --step) shift; STEP=${1:?falta N};; --all) STEP=99;; *) usage;; esac; shift; done
check(){
  bad=0; echo '== forge-on-glass arm64e bootstrap check =='
  printf 'repo: '; [ -f "$ROOT/SKILL.md" ] && echo OK || { echo FAIL; bad=1; }
  printf 'Swift 6.3.3 frontend: '; [ -x "$SWIFT_ROOT/usr/bin/swift-frontend" ] && echo OK || { echo MISSING; bad=1; }
  printf 'iOS SDK 26.5: '; [ -f "$TOOLCHAIN/iPhoneOS26.5.sdk/usr/lib/libSystem.tbd" ] && echo OK || { echo MISSING; bad=1; }
  printf 'arm64e cache: '; if [ -d "$TOOLCHAIN/foundation-build633-arm64e" ] && python3 "$ROOT/scripts/check-module-cache.py" "$TOOLCHAIN/foundation-build633-arm64e" >/dev/null 2>&1; then echo OK; else echo MISSING/INVALID; bad=1; fi
  printf 'neutral sysroot: '; [ -e "$SYSROOT/iPhoneOS26.5.sdk" ] && echo OK || { echo MISSING; bad=1; }
  printf 'PAC linker: '; [ -x "$TOOLCHAIN/ld64.lld-arm64e" ] && echo OK || { echo MISSING; bad=1; }
  printf 'glibc loader: '; [ -e "${ISB_GLIBC_ROOT:-/opt/xtool-glibc/lib}/ld-linux-aarch64.so.1" ] && echo OK || { echo MISSING; bad=1; }
  [ "$bad" -eq 0 ] && return 0; echo 'Missing inputs are expected until bootstrap stages are completed.'; return 1
}
[ "$CHECK" -eq 1 ] && { check; exit $?; }
[ "$STEP" -ge 1 ] && [ "$STEP" -le 99 ] && apk add clang19 lld zip xz zstd binutils patchelf git python3 wget patch
if [ "$STEP" -ge 2 ] && [ "$STEP" -le 99 ]; then
  : "${ISB_SWIFT_URL:?Set ISB_SWIFT_URL to the Swift 6.3.3 Ubuntu aarch64 tarball}"
  : "${ISB_SWIFT_SHA256:?Set ISB_SWIFT_SHA256 before downloading}"
  mkdir -p /tmp/isb-bootstrap; archive=/tmp/isb-bootstrap/swift.tar.gz
  wget -O "$archive" "$ISB_SWIFT_URL"; echo "$ISB_SWIFT_SHA256  $archive" | sha256sum -c -
  tar xzf "$archive" -C /tmp/isb-bootstrap
  src=$(find /tmp/isb-bootstrap -maxdepth 1 -type d -name 'swift-6.3.3-RELEASE*' | head -1)
  [ -n "$src" ] || { echo 'Swift archive layout not recognized' >&2; exit 1; }
  rm -rf "$SWIFT_ROOT"; mv "$src" "$SWIFT_ROOT"; echo "Swift 6.3.3 extracted to $SWIFT_ROOT"
fi
if [ "$STEP" -ge 3 ] && [ "$STEP" -le 99 ]; then
  : "${ISB_SDK_ARCHIVE:?Set ISB_SDK_ARCHIVE to a user-provided iOS 26.5 SDK archive}"
  : "${ISB_SDK_SHA256:?Set ISB_SDK_SHA256 before extracting the SDK}"
  echo "$ISB_SDK_SHA256  $ISB_SDK_ARCHIVE" | sha256sum -c -; mkdir -p "$TOOLCHAIN"; tar xf "$ISB_SDK_ARCHIVE" -C "$TOOLCHAIN"
fi
if [ "$STEP" -ge 4 ] && [ "$STEP" -le 99 ]; then sh "$ROOT/scripts/compile-stdlib.sh"; fi
if [ "$STEP" -ge 5 ] && [ "$STEP" -le 99 ]; then
  echo 'Stage 5 requires real Linux/VM/Docker: build foundation-build633-arm64e.'
  echo 'Use references/linux-vm/orchestrator_vm633.py and copy the validated cache.'
fi
[ "$STEP" -ge 6 ] && [ "$STEP" -le 99 ] && sh "$ROOT/scripts/bootstrap-glibc.sh" --packages "${ISB_GLIBC_PACKAGES:?Set ISB_GLIBC_PACKAGES}" --sha256 "${ISB_GLIBC_SHA256:?Set ISB_GLIBC_SHA256}" --out "${ISB_GLIBC_ROOT:-/opt/xtool-glibc/lib}"
[ "$STEP" -eq 99 ] && check
