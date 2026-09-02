#!/bin/sh
# acceptance-suite.sh — acceptance tests for the local iOS Swift Builder.
# Usage: sh scripts/acceptance-suite.sh [--quick]
# The default performs the quick regression plus a fresh local LiveContainer IPA.
set -eu
SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=/tmp/isb-acceptance
LOG="$WORK/acceptance.log"
rm -rf "$WORK"; mkdir -p "$WORK"
# Keep the complete transcript in the log while mirroring it to the terminal.
# A POSIX tail avoids relying on Bash process substitution: this script is
# intentionally runnable with /bin/sh on Alpine.
echo "acceptance log: $LOG"
exec 3>&1
(tail -f "$LOG" >&3 2>&3) & TAIL_PID=$!
trap 'kill "$TAIL_PID" 2>/dev/null || true' EXIT
exec >"$LOG" 2>&1

fail() { echo "ACCEPTANCE: FAIL: $*"; exit 1; }
pass() { echo "ACCEPTANCE: OK: $*"; }

[ "${ISB_ARCH:-arm64}" = arm64 ] || fail "run the local acceptance suite with ISB_ARCH=arm64"
for f in "$SKILL"/scripts/*.sh; do sh -n "$f" || fail "shell syntax: $f"; done
python3 -m py_compile "$SKILL"/scripts/*.py || fail "Python syntax"
pass "script syntax"

ISB_ARCH=arm64 sh "$SKILL/scripts/check-env.sh" || fail "arm64 environment"
pass "arm64 environment"

# Foundation/Dispatch pure-Swift smoke: this used to select the obsolete
# 6.3.2 cache and personal /home paths. Keep it as an active S2 test.
cat > "$WORK/foundation-probe.swift" <<'EOF'
import Foundation
import Dispatch
let q = DispatchQueue(label: "acceptance")
let g = DispatchGroup(); g.enter()
q.async { _ = FileManager.default.fileExists(atPath: NSTemporaryDirectory()); g.leave() }
g.wait()
print("foundation-dispatch-ok")
EOF
ISB_OUTPUT="$WORK/FoundationDispatch" sh "$SKILL/scripts/build-pure-foundation.sh" \
  FoundationDispatch "$WORK/foundation-probe.swift" || fail "Foundation/Dispatch pure build"
python3 scripts/check-undefined.py "$WORK/FoundationDispatch" \
  "${ISB_SYSROOT:-/opt/isb/sysroot}/iPhoneOS26.5.sdk" || fail "Foundation/Dispatch undefined symbols"
pass "Foundation/Dispatch neutral 6.3.3 S2 smoke"
sh "$SKILL/scripts/verify-pureswiftkit.sh" >/dev/null || fail "PureSwiftKit coverage"
pass "PureSwiftKit workaround coverage"

# Build a fresh unsigned IPA through the exact path recommended for LiveContainer.
cd "$SKILL"
sh scripts/build-livecontainer.sh AcceptanceApp com.example.acceptance \
  assets/PureSwiftDemo.swift || fail "local LiveContainer build"
IPA=/var/minis/workspace/AcceptanceApp.ipa
[ -s "$IPA" ] || fail "missing $IPA"
sh scripts/validate-ipa.sh "$IPA" || fail "IPA validation"
TMP="$WORK/ipa"; mkdir -p "$TMP"; unzip -q "$IPA" -d "$TMP"
BIN="$TMP/Payload/AcceptanceApp.app/AcceptanceApp"
[ -s "$BIN" ] || fail "missing executable"
# Check a fresh executable against every SDK stub. This is a structural
# undefined-symbol guard, not device/runtime proof.
python3 scripts/check-undefined.py "$BIN" \
  "${ISB_SYSROOT:-/opt/isb/sysroot}/iPhoneOS26.5.sdk" || fail "undefined symbols"

if python3 scripts/check-slice.py "$BIN" arm64e >/dev/null 2>&1; then
  fail "arm64 guard accepted an arm64 binary as arm64e"
fi
pass "fresh local arm64 IPA and exact slice guards"

# Prove the production path does not depend on the old /home mirror.
ISB_SYSROOT="${ISB_SYSROOT:-/opt/isb/sysroot}" \
  sh "$SKILL/scripts/check-sysroot-independence.sh" || fail "sysroot independence"
pass "sysroot-independent arm64 build"

# The quick suite retains the minimal reproducer for the cross-file bug.
sh scripts/regression-suite.sh --quick || fail "quick regression suite"
pass "primary-file regression and known whole-module reproducer"

echo "ACCEPTANCE: PASS"
echo "log: $LOG"
