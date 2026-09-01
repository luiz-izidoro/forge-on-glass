#!/bin/sh
# bootstrap.sh — staged, idempotent setup for a fresh Alpine/iSH checkout.
# It never downloads Apple SDK material implicitly. User-provided artifacts are
# verified with SHA-256 before extraction; the Linux module cache still requires
# a real Linux VM/Docker and the user's licensed SDK.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SYSROOT=${ISB_SYSROOT:-/opt/isb/sysroot}
TOOLCHAIN=${ISB_TOOLCHAIN_ROOT:-/opt/ios-toolchain}
SWIFT_ROOT=${ISB_SWIFT_ROOT:-/opt/swift6.3}
STEP=0
CHECK=0
usage(){ echo "uso: $0 --check | --step N | --all"; exit 2; }
[ "$#" -gt 0 ] || usage
while [ "$#" -gt 0 ]; do case "$1" in --check) CHECK=1;; --step) shift; STEP=${1:?falta N};; --all) STEP=99;; *) usage;; esac; shift; done
have(){ [ -e "$1" ]; }
check(){
  echo "== forge-on-glass bootstrap check =="
  printf 'repo: '; [ -f "$ROOT/scripts/check-env.sh" ] && echo OK || echo FAIL
  printf 'Swift 6.3.2 frontend: '; [ -x "$SWIFT_ROOT/usr/bin/swift-frontend" ] && echo OK || echo MISSING
  printf 'iOS SDK: '; [ -f "$TOOLCHAIN/iPhoneOS26.5.sdk/usr/lib/libSystem.tbd" ] && echo OK || echo MISSING
  printf 'stdlib cache: '; [ -s "$TOOLCHAIN/exp63/SwiftShims.pcm" ] && echo OK || echo MISSING
  printf 'pure Swift arm64 cache: '; [ -s "$TOOLCHAIN/foundation-build633/swift_SwiftUI.swiftmodule" ] && echo OK || echo MISSING
  printf 'neutral sysroot: '; [ -e "$SYSROOT/iPhoneOS26.5.sdk" ] && echo OK || echo MISSING
  echo "Missing caches are expected until steps 1-5 are completed."
}
if [ "$CHECK" -eq 1 ]; then check; exit 0; fi
if [ "$STEP" -ge 1 ] && [ "$STEP" -le 99 ]; then
  echo "[1] Installing Alpine host tools"
  apk add clang19 lld zip xz zstd binutils patchelf git python3 wget patch
fi
if [ "$STEP" -ge 2 ] && [ "$STEP" -le 99 ]; then
  : "${ISB_SWIFT_URL:?Set ISB_SWIFT_URL to the Swift 6.3.2 Ubuntu aarch64 tarball}"
  : "${ISB_SWIFT_SHA256:?Set ISB_SWIFT_SHA256 before downloading}"
  mkdir -p /tmp/isb-bootstrap "$SWIFT_ROOT"
  archive=/tmp/isb-bootstrap/swift.tar.gz
  wget -O "$archive" "$ISB_SWIFT_URL"
  echo "$ISB_SWIFT_SHA256  $archive" | sha256sum -c -
  tar xzf "$archive" -C /tmp/isb-bootstrap
  src=$(find /tmp/isb-bootstrap -maxdepth 1 -type d -name 'swift-6.3.2-RELEASE*' | head -1)
  [ -n "$src" ] || { echo 'Swift archive layout not recognized' >&2; exit 1; }
  rm -rf "$SWIFT_ROOT"; mv "$src" "$SWIFT_ROOT"
  echo "Swift extracted to $SWIFT_ROOT"
  echo "Next: install an aarch64 glibc loader in /opt/xtool-glibc/lib and patchelf swift-frontend as documented in references/BOOTSTRAP.md."
fi
if [ "$STEP" -ge 3 ] && [ "$STEP" -le 99 ]; then
  : "${ISB_SDK_ARCHIVE:?Set ISB_SDK_ARCHIVE to an SDK archive obtained under your license}"
  : "${ISB_SDK_SHA256:?Set ISB_SDK_SHA256 before extracting the SDK}"
  echo "$ISB_SDK_SHA256  $ISB_SDK_ARCHIVE" | sha256sum -c -
  mkdir -p "$TOOLCHAIN"
  tar xf "$ISB_SDK_ARCHIVE" -C "$TOOLCHAIN"
  [ -f "$TOOLCHAIN/iPhoneOS26.5.sdk/usr/lib/libSystem.tbd" ] || { echo 'iPhoneOS26.5.sdk not found after extraction' >&2; exit 1; }
  echo "SDK installed; patches must be generated/applied locally with make/apply-patchset.sh."
fi
if [ "$STEP" -ge 4 ] && [ "$STEP" -le 99 ]; then
  [ -x "$ROOT/scripts/compile-stdlib.sh" ] || exit 1
  sh "$ROOT/scripts/compile-stdlib.sh"
fi
if [ "$STEP" -ge 5 ] && [ "$STEP" -le 99 ]; then
  echo "Step 5 requires real Linux/VM/Docker: build foundation-build633 from the user's SDK and copy it to $TOOLCHAIN/."
  echo "Read references/linux-vm/orchestrator_vm633.py and references/DISPATCH-VIA-LINUX.md."
  echo "No Apple SDK, PCM, swiftmodule, or generated binary is downloaded by this script."
fi
if [ "$STEP" -eq 99 ]; then check; fi
