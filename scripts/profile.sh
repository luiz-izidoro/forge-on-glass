#!/bin/sh
# profile.sh — target/profile selection shared by the pure Swift pipeline.
# Default remains the proven arm64 profile. arm64e is opt-in and isolated
# because Swift modules/PCMs are target- and compiler-tag specific.
ISB_ARCH="${ISB_ARCH:-arm64}"
ISB_SYSROOT="${ISB_SYSROOT:-/opt/isb/sysroot}"
# Compatibility with a pre-existing local cache. New installs should use the
# neutral prefix and regenerate their PCMs there.
if [ ! -e "$ISB_SYSROOT/iPhoneOS26.5.sdk" ]; then
  legacy=$(find /home -maxdepth 2 -type d -name swift-ios-build 2>/dev/null | head -1 || true)
  [ -n "$legacy" ] && ISB_SYSROOT="$legacy"
fi
ISB_MODULE_CACHE="${ISB_MODULE_CACHE:-/var/tmp/isb-cache}"
case "$ISB_ARCH" in
  arm64)
    ISB_TARGET="${ISB_TARGET:-arm64-apple-ios26.0}"
    ISB_CPU="${ISB_CPU:-}"
    ISB_SW="${ISB_SW:-/opt/swift6.3.3}"
    ISB_SDK="${ISB_SDK:-$ISB_SYSROOT/iPhoneOS26.5.sdk}"
    ISB_FOUNDATION_BUILD="${ISB_FOUNDATION_BUILD:-/opt/ios-toolchain/foundation-build633}"
    ISB_CPU=""
    ISB_LINKER="${ISB_LINKER:-ld64.lld}"
    ;;
  arm64e)
    ISB_TARGET="${ISB_TARGET:-arm64e-apple-ios26.5}"
    ISB_CPU="${ISB_CPU:-apple-a12}"
    ISB_LINKER="${ISB_LINKER:-/opt/ios-toolchain/ld64.lld-arm64e}"
    ISB_SW="${ISB_SW:-/opt/swift6.3.3}"
    ISB_SDK="${ISB_SDK:-$ISB_SYSROOT/iPhoneOS26.5.sdk}"
    ISB_FOUNDATION_BUILD="${ISB_FOUNDATION_BUILD:-/opt/ios-toolchain/foundation-build633-arm64e}"
    ;;
  *) echo "ISB_ARCH invalido: $ISB_ARCH (use arm64 ou arm64e)" >&2; exit 2 ;;
esac

# The SDK itself is the same 26.5 tree for both slices. The framework stubs
# expose arm64 and arm64e; the Swift module cache must match the selected slice.
ROOT="$ISB_SYSROOT"
SDK="$ISB_SDK"
SW="$ISB_SW"
SF="$SW/usr/bin/swift-frontend"
OUT="$ISB_FOUNDATION_BUILD"
VFS="$ROOT/vfs/overlay.yaml"
BIG="${ISB_MODULE_CACHE}/app-$ISB_ARCH"
ISB_VFS="$VFS"
ISB_MODULE_CACHE="$BIG"
if [ -n "$ISB_CPU" ]; then
  ISB_CPU_ARGS="-target-cpu $ISB_CPU"
else
  ISB_CPU_ARGS=""
fi
if [ "$ISB_ARCH" = "arm64e" ]; then
  # arm64e/PAC is a local production profile. The linker is built once for
  # Linux/aarch64 from the upstream LLD ARM64e implementation and then kept
  # on-device. No build step may depend on SSH or a VM.
  ISB_LINKER="${ISB_LINKER:-/opt/ios-toolchain/ld64.lld-arm64e}"
  [ -x "$ISB_LINKER" ] || {
    echo "linker arm64e local ausente: $ISB_LINKER" >&2
    echo "Instale o artefato LLD PAC aarch64; o build nao usa fallback remoto." >&2
    exit 1
  }
fi

export ISB_ARCH ISB_TARGET ISB_CPU ISB_CPU_ARGS ISB_LINKER ISB_SDK ISB_SW ISB_FOUNDATION_BUILD ISB_MODULE_CACHE ISB_VFS ROOT SDK SW SF OUT VFS BIG
