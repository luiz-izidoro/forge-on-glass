#!/bin/sh
# regression-suite.sh — regression suite for the forge-on-glass skill.
#
# Compiles the reference assets in BOTH modes (primary-file and whole-module)
# and reports a table. It serves to (a) detect regressions when changing scripts,
# (b) support the choice of default mode with measurements.
#
# Usage: sh scripts/regression-suite.sh [--quick]
set -e

SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
A=$SKILL/assets
W=/tmp/regression-suite
rm -rf "$W" && mkdir -p "$W"
RESULT="$W/result.txt"
: > "$RESULT"

# Pure-shell matching: `grep` may not terminate in this shell (iSH),
# and the suite needs its results to be useful as a commit gate.
contains_file(){ while IFS= read -r _l; do case "$_l" in *"$2"*) return 0 ;; esac; done < "$1"; return 1; }
contains_line2(){ while IFS= read -r _l; do case "$_l" in *"$2"*"$3"*) return 0 ;; esac; done < "$1"; return 1; }
first_errors(){ _n=${2:-2}; while IFS= read -r _l; do case "$_l" in *error:*) printf '%s ' "$_l"; _n=$((_n-1)); [ "$_n" -le 0 ] && break ;; esac; done < "$1"; }

QUICK=0
[ "$1" = "--quick" ] && QUICK=1

run_case() {
  name=$1; mode=$2; shift 2
  d="$W/$name-$mode"
  mkdir -p "$d"
  # the sources have already been prepared in $W/src-$name
  cp "$W/src-$name"/*.swift "$d"/ 2>/dev/null || true
  files=$(cd "$d" && ls *.swift | tr '\n' ' ')
  # a Swift MODULE name does not accept a hyphen
  tag=$(echo "$mode" | tr -d '-')
  start=$(date +%s)
  if (cd "$d" && sh "$SKILL/scripts/build-pure-ui.sh" "RS$name$tag" \
        "ro.izido.rs.$name.$tag" $files "--$mode" > build.log 2>&1); then
    rc=OK
  else
    rc=FAIL
  fi
  end=$(date +%s)
  printf '%-22s %-14s %-6s %ss\n' "$name" "$mode" "$rc" "$((end - start))" >> "$RESULT"
  if [ "$rc" = "FAIL" ]; then
    printf '    %s\n' "$(first_errors "$d/build.log" 2)" >> "$RESULT"
  fi
}

prep() {
  name=$1; shift
  mkdir -p "$W/src-$name"
  for f in "$@"; do cat "$f" > "$W/src-$name/$(basename "$f")"; done
}

echo "=== preparing cases ==="

# 1. Pure UIKit, single file
prep uikit "$A/PureSwiftDemo.swift"
mv "$W/src-uikit/PureSwiftDemo.swift" "$W/src-uikit/main.swift"

# 2. Pure SwiftUI, single file
prep swiftui "$A/SwiftUIDemo.swift"
mv "$W/src-swiftui/SwiftUIDemo.swift" "$W/src-swiftui/main.swift"

# 3. Multi-file with the kit (classic 2+ file case)
prep kit "$A/PureSwiftDemo.swift" "$A/PureSwiftKit.swift"
mv "$W/src-kit/PureSwiftDemo.swift" "$W/src-kit/main.swift"

# 4. REGRESSION OF BUG 2026-08-23: CoreGraphics in one file makes Foundation
#    disappear from ANOTHER file (whole-module). It must pass in primary-file.
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

# 5. Debug mode (DebugSupport.swift is added automatically)
prep debugmode "$A/PureSwiftDemo.swift"
mv "$W/src-debugmode/PureSwiftDemo.swift" "$W/src-debugmode/main.swift"

CASES="uikit swiftui kit cgfoundation"
[ "$QUICK" -eq 1 ] && CASES="uikit cgfoundation"

for c in $CASES; do
  echo "--- $c ---"
  run_case "$c" primary-file
  run_case "$c" whole-module
done

# debug case: only makes sense in the default mode
echo "--- debugmode ---"
d="$W/debugmode-debug"; mkdir -p "$d"
cp "$W/src-debugmode/main.swift" "$d"/
start=$(date +%s)
if (cd "$d" && ISB_UNSIGNED=0 sh "$SKILL/scripts/build-pure-ui.sh" RSdebug ro.izido.rs.debug \
      main.swift --debug > build.log 2>&1); then
  rc=OK
  python3 "$SKILL/scripts/check-debug-ipa.py" /var/minis/workspace/RSdebug.ipa > "$d/guard.log" 2>&1 || rc="FAIL(guard)"
else
  rc=FAIL
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
    printf '%-22s %-14s %-6s\n' "guard-stripped-swift" "llvm-strip -x" "FAIL" >> "$RESULT"
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
    printf '%-22s %-14s %-6s\n' "invalid-stripped" "entry guard" "FAIL" >> "$RESULT"
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
  printf '%-22s %-14s %-6s\n' "invalid-delegate" "warning guard" "FAIL" >> "$RESULT"
else
  if contains_file "$W/src-invalid/build.log" 'nearly matches' || \
     contains_file "$W/src-invalid/build.log" 'didFinishLaunchingWithOptions'; then
    printf '%-22s %-14s %-6s\n' "invalid-delegate" "warning guard" "OK" >> "$RESULT"
  else
    printf '%-22s %-14s %-6s\n' "invalid-delegate" "warning guard" "FAIL" >> "$RESULT"
    MATRIX_FAIL=1
  fi
fi

echo ""
cat "$RESULT"
echo "============================================="
echo "logs: $W/<case>-<mode>/build.log"

# Generator failure-path regression: a successful, silent frontend exit is the
# iSH startup race. The canonical arm64e wrapper must retry and then report the
# actionable scan diagnostic, never aborting on an unset status variable.
FAIL_W="$W/generator-failure"
mkdir -p "$FAIL_W/fake-sw/usr/bin" "$FAIL_W/cache" "$FAIL_W/root"
cat > "$FAIL_W/fake-sw/usr/bin/swift-frontend" <<'EOF'
#!/bin/sh
# Deliberately emulate rc=0 + no output from the iSH startup race.
exit 0
EOF
chmod +x "$FAIL_W/fake-sw/usr/bin/swift-frontend"
if ISB_VM_ROOT="$FAIL_W/root" ISB_VM_SW="$FAIL_W/fake-sw" \
    ISB_VM_SDK="/opt/isb/sysroot/iPhoneOS26.5.sdk" \
    ISB_VM_VFS="/opt/isb/sysroot/vfs/overlay.yaml" \
    ISB_VM_OUT="$FAIL_W/out" ISB_SCAN_CACHE="$FAIL_W/cache" \
    ISB_ORCHESTRATOR="$SKILL/references/linux-vm/orchestrator_vm633.py" \
    sh "$SKILL/scripts/build-arm64e-modules.sh" >"$FAIL_W/result.log" 2>&1; then
  printf '%-22s %-14s %-6s\n' "generator-failure" "silent scan" "FAIL" >> "$RESULT"
  MATRIX_FAIL=1
else
  if contains_file "$FAIL_W/result.log" 'scan-dependencies failed' && \
     ! contains_file "$FAIL_W/result.log" 'parameter not set'; then
    printf '%-22s %-14s %-6s\n' "generator-failure" "silent scan" "OK" >> "$RESULT"
  else
    printf '%-22s %-14s %-6s\n' "generator-failure" "silent scan" "FAIL" >> "$RESULT"
    MATRIX_FAIL=1
  fi
fi
rm -rf "$FAIL_W"

echo "logs: $W/<case>-<mode>/build.log"

# fail the script if any case in the DEFAULT mode broke
if contains_line2 "$RESULT" 'primary-file' 'FAIL' || \
   contains_line2 "$RESULT" 'debug' 'FAIL' || \
   [ "${MATRIX_FAIL:-0}" -ne 0 ]; then
  echo ""
  echo "REGRESSION in the default mode."
  exit 1
fi
echo ""
echo "default mode (primary-file) with no regression."
