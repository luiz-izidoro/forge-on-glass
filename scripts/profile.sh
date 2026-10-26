#!/bin/sh
# Arm64e/PAC is canonical; the former arm64 path is discontinued.
# arm64e.v1/PAC is the only supported profile.
set -eu
ISB_ARCH="${ISB_ARCH:-arm64e}"
[ "$ISB_ARCH" = arm64e ] || { echo "ISB_ARCH unsupported: only arm64e.v1/PAC is supported" >&2; exit 2; }
ISB_SYSROOT="${ISB_SYSROOT:-/opt/isb/sysroot}"
ISB_MODULE_CACHE_ROOT="${ISB_MODULE_CACHE_ROOT:-/var/tmp/isb-cache}"
ISB_SW="${ISB_SW:-/opt/swift6.3.3}"
ISB_TOOLCHAIN_ROOT="${ISB_TOOLCHAIN_ROOT:-/opt/ios-toolchain}"
ISB_GLIBC_ROOT="${ISB_GLIBC_ROOT:-/opt/xtool-glibc/lib}"
ISB_TARGET="${ISB_TARGET:-arm64e-apple-ios26.5}"
ISB_CPU="${ISB_CPU:-apple-a12}"
ISB_SDK="${ISB_SDK:-$ISB_SYSROOT/iPhoneOS26.5.sdk}"
ISB_FOUNDATION_BUILD="${ISB_FOUNDATION_BUILD:-$ISB_TOOLCHAIN_ROOT/foundation-build633-arm64e}"
ISB_LINKER="${ISB_LINKER:-$ISB_TOOLCHAIN_ROOT/ld64.lld-arm64e}"
ROOT="$ISB_SYSROOT"; SDK="$ISB_SDK"; SW="$ISB_SW"; SF="$SW/usr/bin/swift-frontend"
ISB_VFS="${ISB_VFS:-$ROOT/vfs/overlay.yaml}"
OUT="$ISB_FOUNDATION_BUILD"; VFS="$ISB_VFS"
BIG="$ISB_MODULE_CACHE_ROOT/app-arm64e"; ISB_MODULE_CACHE="$BIG"
ISB_CPU_ARGS="-target-cpu $ISB_CPU"
[ -e "$SDK" ] || { echo "SDK missing: $SDK" >&2; exit 2; }
[ -f "$VFS" ] || { echo "VFS missing: $VFS" >&2; exit 2; }
[ -x "$SF" ] || { echo "Swift frontend missing: $SF" >&2; exit 2; }
[ -d "$OUT" ] || { echo "arm64e module cache missing: $OUT" >&2; exit 2; }
[ -x "$ISB_LINKER" ] || { echo "PAC linker missing: $ISB_LINKER" >&2; exit 2; }
export ISB_ARCH ISB_SYSROOT ISB_MODULE_CACHE_ROOT ISB_TARGET ISB_CPU ISB_SW ISB_SDK ISB_VFS ISB_TOOLCHAIN_ROOT ISB_FOUNDATION_BUILD ISB_LINKER ISB_GLIBC_ROOT ROOT SDK SW SF OUT VFS BIG ISB_MODULE_CACHE ISB_CPU_ARGS
