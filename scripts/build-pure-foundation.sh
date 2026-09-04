#!/bin/sh
# build-pure-foundation.sh — compile+link a pure-Swift Foundation/Dispatch app.
# Uses the same configurable neutral profile as build-pure-ui.sh.
# Usage: build-pure-foundation.sh <AppName> <main.swift>
set -eu
APP="${1:?uso: $0 <AppName> <main.swift>}"
SRC="${2:?falta main.swift}"
. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/profile.sh"
[ -f "$SRC" ] || { echo "fonte ausente: $SRC" >&2; exit 1; }
[ -d "$OUT" ] || { echo "cache ausente: $OUT" >&2; exit 1; }
OBJ="/tmp/${APP}-foundation-$$.o"
ERRF="/tmp/${APP}-foundation-$$.err"
BIN="${ISB_OUTPUT:-$PWD/$APP}"
mkdir -p "$ISB_MODULE_CACHE"

# Explicit modules are required: implicit module discovery is not reliable on
# iSH and can accidentally load a cache built with the wrong prefix.
MOD_ARGS=""
for f in "$OUT"/swift_*.swiftmodule; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .swiftmodule); n=${n#swift_}
  [ "$n" = XPC ] && continue
  MOD_ARGS="$MOD_ARGS -swift-module-file=$n=$f"
done
for f in "$OUT"/clang_*.pcm; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .pcm); n=${n#clang_}
  MOD_ARGS="$MOD_ARGS -Xcc -fmodule-file=$n=$f"
done

OK=0
for attempt in 1 2 3 4 5 6; do
  rm -f "$OBJ" "$ERRF"
  # shellcheck disable=SC2086
  "$SF" -frontend -c -target "$ISB_TARGET" $ISB_CPU_ARGS -sdk "$SDK" \
    -resource-dir "$SW/usr/lib/swift" -module-name "$APP" \
    -disable-implicit-swift-modules -Xcc -fno-implicit-modules \
    -Xcc -fno-implicit-module-maps -Xcc -ivfsoverlay -Xcc "$VFS" \
    -Xcc "-fmodules-cache-path=$BIG" $MOD_ARGS "$SRC" -o "$OBJ" \
    2>"$ERRF" || true
  if [ -s "$OBJ" ]; then OK=1; break; fi
  if grep -q 'error:' "$ERRF" 2>/dev/null; then
    echo "swift compile failed:" >&2; grep 'error:' "$ERRF" | head -10 >&2; exit 1
  fi
  echo "swift frontend retry $attempt" >&2
done
[ "$OK" -eq 1 ] || { echo "swift compile failed after retries" >&2; tail -10 "$ERRF" >&2; exit 1; }
echo "[1/2] Swift OK ($(wc -c <"$OBJ")B)"

# arm64e/PAC objects use the canonical linker selected by profile.sh.
ARCH="$ISB_ARCH"
PLATFORM_MIN=26.5
"$ISB_LINKER" -arch "$ARCH" -platform_version ios "$PLATFORM_MIN" 26.5 \
  -syslibroot "$SDK" -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" \
  -dead_strip -lSystem -lobjc \
  -framework Foundation -framework CoreFoundation \
  -lswiftCore -lswiftFoundation -lswiftDispatch -lswift_Concurrency \
  -lswift_StringProcessing -lswiftSwiftOnoneSupport -lswiftCoreFoundation \
  -rpath /usr/lib/swift -e _main "$OBJ" -o "$BIN" \
  2>"$ERRF" || { echo "link failed:" >&2; cat "$ERRF" >&2; exit 1; }
echo "[2/2] Linked: $BIN ($(wc -c <"$BIN")B)"
rm -f "$OBJ" "$ERRF"
