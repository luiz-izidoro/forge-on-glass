#!/bin/sh
# regression-suite.sh — bateria de regressao da skill ios-swift-builder.
#
# Compila os assets de referencia nos DOIS modos (primary-file e whole-module)
# e reporta uma tabela. Serve para (a) detectar regressao ao mexer nos scripts,
# (b) sustentar com medida a escolha do modo padrao.
#
# Uso: sh scripts/regression-suite.sh [--quick]
set -e

SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
A=$SKILL/assets
W=/tmp/regression-suite
rm -rf "$W" && mkdir -p "$W"
RESULT="$W/result.txt"
: > "$RESULT"

QUICK=0
[ "$1" = "--quick" ] && QUICK=1

run_case() {
  name=$1; mode=$2; shift 2
  d="$W/$name-$mode"
  mkdir -p "$d"
  # os fontes ja foram preparados em $W/src-$name
  cp "$W/src-$name"/*.swift "$d"/ 2>/dev/null || true
  files=$(cd "$d" && ls *.swift | tr '\n' ' ')
  # nome de MODULO Swift nao aceita hifen
  tag=$(echo "$mode" | tr -d '-')
  start=$(date +%s)
  if (cd "$d" && sh "$SKILL/scripts/build-pure-ui.sh" "RS$name$tag" \
        "ro.izido.rs.$name.$tag" $files "--$mode" > build.log 2>&1); then
    rc=OK
  else
    rc=FALHA
  fi
  end=$(date +%s)
  printf '%-22s %-14s %-6s %ss\n' "$name" "$mode" "$rc" "$((end - start))" >> "$RESULT"
  if [ "$rc" = "FALHA" ]; then
    printf '    %s\n' "$(grep 'error:' "$d/build.log" | head -2 | tr '\n' ' ')" >> "$RESULT"
  fi
}

prep() {
  name=$1; shift
  mkdir -p "$W/src-$name"
  for f in "$@"; do cat "$f" > "$W/src-$name/$(basename "$f")"; done
}

echo "=== preparando casos ==="

# 1. UIKit puro, arquivo unico
prep uikit "$A/PureSwiftDemo.swift"
mv "$W/src-uikit/PureSwiftDemo.swift" "$W/src-uikit/main.swift"

# 2. SwiftUI puro, arquivo unico
prep swiftui "$A/SwiftUIDemo.swift"
mv "$W/src-swiftui/SwiftUIDemo.swift" "$W/src-swiftui/main.swift"

# 3. Multi-arquivo com o kit (caso classico de 2+ arquivos)
prep kit "$A/PureSwiftDemo.swift" "$A/PureSwiftKit.swift"
mv "$W/src-kit/PureSwiftDemo.swift" "$W/src-kit/main.swift"

# 4. REGRESSAO DO BUG 2026-08-23: CoreGraphics num arquivo faz o Foundation
#    sumir de OUTRO arquivo (whole-module). Deve passar em primary-file.
mkdir -p "$W/src-cgfoundation"
cat "$A/PureSwiftDemo.swift" > "$W/src-cgfoundation/main.swift"
cat > "$W/src-cgfoundation/Helper.swift" <<'EOF'
import Foundation
import UIKit
public enum RegressionHelper {
    public static func bundleID() -> String {
        return Bundle.main.bundleIdentifier ?? "?"
    }
}
EOF

# 5. Modo debug (DebugSupport.swift entra automaticamente)
prep debugmode "$A/PureSwiftDemo.swift"
mv "$W/src-debugmode/PureSwiftDemo.swift" "$W/src-debugmode/main.swift"

CASES="uikit swiftui kit cgfoundation"
[ "$QUICK" -eq 1 ] && CASES="uikit cgfoundation"

for c in $CASES; do
  echo "--- $c ---"
  run_case "$c" primary-file
  run_case "$c" whole-module
done

# caso debug: so faz sentido no modo padrao
echo "--- debugmode ---"
d="$W/debugmode-debug"; mkdir -p "$d"
cp "$W/src-debugmode/main.swift" "$d"/
start=$(date +%s)
if (cd "$d" && sh "$SKILL/scripts/build-pure-ui.sh" RSdebug ro.izido.rs.debug \
      main.swift --debug > build.log 2>&1); then
  rc=OK
  python3 "$SKILL/scripts/check-debug-ipa.py" /var/minis/workspace/RSdebug.ipa > "$d/guard.log" 2>&1 || rc="FALHA(guarda)"
else
  rc=FALHA
fi
end=$(date +%s)
printf '%-22s %-14s %-6s %ss\n' "debugmode" "--debug" "$rc" "$((end - start))" >> "$RESULT"

MATRIX_FAIL=0
if [ -s /var/minis/workspace/RSuikitprimaryfile.ipa ]; then
  ipa=/var/minis/workspace/RSuikitprimaryfile.ipa
  sd="$W/guard-stripped"; mkdir -p "$sd"
  unzip -q "$ipa" -d "$sd"
  appdir=$(find "$sd/Payload" -mindepth 1 -maxdepth 1 -type d | head -1)
  sb="$appdir/$(basename "$appdir" .app)"
  llvm-strip -x "$sb"
  if python3 "$SKILL/scripts/check-entry.py" "$sb" > "$sd/result.log" 2>&1; then
    printf '%-22s %-14s %-6s\n' "guard-stripped-swift" "llvm-strip -x" "OK" >> "$RESULT"
  else
    printf '%-22s %-14s %-6s\n' "guard-stripped-swift" "llvm-strip -x" "FALHA" >> "$RESULT"
    MATRIX_FAIL=1
  fi

  # Negative binary case: corrupt only the registered launch selector after
  # stripping. The Swift section remains, so a downgrade to ObjC would be a
  # false positive; the strict Swift branch must reject it.
  bad="$W/guard-invalid-stripped"; mkdir -p "$bad"
  cp "$sb" "$bad/invalid"
  python3 - "$bad/invalid" <<'PY'
import sys
p=sys.argv[1]; b=open(p,'rb').read()
old=b'applicationDidFinishLaunching:'
new=b'applicationXidFinishLaunching:'
if old not in b: raise SystemExit('selector not found')
open(p,'wb').write(b.replace(old,new,1))
PY
  if python3 "$SKILL/scripts/check-entry.py" "$bad/invalid" > "$bad/result.log" 2>&1; then
    printf '%-22s %-14s %-6s\n' "invalid-stripped" "entry guard" "FALHA" >> "$RESULT"
    MATRIX_FAIL=1
  else
    printf '%-22s %-14s %-6s\n' "invalid-stripped" "entry guard" "OK" >> "$RESULT"
  fi
else
  printf '%-22s %-14s %-6s\n' "guard-stripped-swift" "llvm-strip -x" "SKIP" >> "$RESULT"
  MATRIX_FAIL=1
fi
mkdir -p "$W/src-invalid"
sed 's/func applicationDidFinishLaunching(_ application: UIApplication) {/func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: NSDictionary?) {/' \
  "$A/PureSwiftDemo.swift" > "$W/src-invalid/main.swift"
if (cd "$W/src-invalid" && sh "$SKILL/scripts/build-pure-ui.sh" RSinvalid ro.izido.rs.invalid main.swift > build.log 2>&1); then
  printf '%-22s %-14s %-6s\n' "invalid-delegate" "warning guard" "FALHA" >> "$RESULT"
else
  if grep -q 'nearly matches\|didFinishLaunchingWithOptions' "$W/src-invalid/build.log"; then
    printf '%-22s %-14s %-6s\n' "invalid-delegate" "warning guard" "OK" >> "$RESULT"
  else
    printf '%-22s %-14s %-6s\n' "invalid-delegate" "warning guard" "FALHA" >> "$RESULT"
    MATRIX_FAIL=1
  fi
fi

echo ""
cat "$RESULT"
echo "============================================="
echo "logs: $W/<caso>-<modo>/build.log"

# falha o script se algum caso do modo PADRAO quebrou
if grep -q 'primary-file *FALHA' "$RESULT" || grep -q 'debug *FALHA' "$RESULT" || [ "${MATRIX_FAIL:-0}" -ne 0 ]; then
  echo ""
  echo "REGRESSAO no modo padrao."
  exit 1
fi
echo ""
echo "modo padrao (primary-file) sem regressao."
