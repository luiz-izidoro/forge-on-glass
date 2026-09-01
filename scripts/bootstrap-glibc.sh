#!/bin/sh
# bootstrap-glibc.sh — assemble a private aarch64 glibc runtime from user
# supplied Ubuntu .deb packages. Nothing is downloaded or redistributed.
set -eu
PACKAGES=""
CHECKSUMS=""
OUT=${ISB_GLIBC_ROOT:-/opt/xtool-glibc/lib}
usage() {
  echo "usage: $0 --packages DIR --sha256 FILE [--out DIR]"
  echo "  DIR must contain user-provided Ubuntu arm64 .deb files."
  exit 2
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --packages) shift; PACKAGES=${1:?missing package directory} ;;
    --sha256) shift; CHECKSUMS=${1:?missing checksum file} ;;
    --out) shift; OUT=${1:?missing output directory} ;;
    *) usage ;;
  esac
  shift
done
[ -n "$PACKAGES" ] && [ -d "$PACKAGES" ] || usage
[ -f "$CHECKSUMS" ] || { echo "checksum file missing: $CHECKSUMS" >&2; exit 1; }
command -v ar >/dev/null 2>&1 || { echo "ar is required (apk add binutils)" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }
set -- "$PACKAGES"/*.deb
[ -f "$1" ] || { echo "no .deb files in $PACKAGES" >&2; exit 1; }
(
  cd "$PACKAGES"
  sha256sum -c "$CHECKSUMS"
)
TMP=$(mktemp -d /tmp/isb-glibc.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"
mkdir -p "$STAGE" "$OUT"
for pkg in "$PACKAGES"/*.deb; do
  [ -f "$pkg" ] || continue
  member=$(ar t "$pkg" | awk '/^data\.tar\./ {print; exit}')
  [ -n "$member" ] || { echo "data archive missing: $pkg" >&2; exit 1; }
  archive="$TMP/$(basename "$pkg").data"
  ar p "$pkg" "$member" > "$archive"
  mkdir -p "$STAGE/$(basename "$pkg")"
  tar -xf "$archive" -C "$STAGE/$(basename "$pkg")"
done
# Copy only runtime libraries needed by the Swift frontend. Preserve symlinks;
# the real files and their ABI sonames are selected from the same package tree.
find "$STAGE" \( -type f -o -type l \) -print | while IFS= read -r file; do
  base=${file##*/}
  case "$base" in
    ld-linux-aarch64.so.1|libc.so.6|libc-*.so*|libm.so.6|libm-*.so*|libpthread.so*|libdl.so*|librt.so*|libutil.so*|libanl.so*|libresolv.so*|libnss_*.so*|libstdc++.so*|libgcc_s.so*|libz.so*|libncurses.so*|libtinfo.so*|libuuid.so*|libcom_err.so*)
      cp -a "$file" "$OUT/$base"
      ;;
  esac
done
for lib in ld-linux-aarch64.so.1 libc.so.6 libstdc++.so.6 libgcc_s.so.1; do
  find "$STAGE" \( -type f -o -type l \) -name "$lib" -print -quit | grep -q . || {
    echo "required runtime absent from supplied packages: $lib" >&2
    exit 1
  }
  [ -e "$OUT/$lib" ] || [ -L "$OUT/$lib" ] || {
    echo "required runtime was not installed: $lib" >&2
    exit 1
  }
done
echo "glibc runtime assembled: $OUT"
ls -l "$OUT" | sed -n '1,80p'
