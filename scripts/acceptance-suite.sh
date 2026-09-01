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
python3 scripts/check-livecontainer.py "$BIN" || fail "LiveContainer invariants"
python3 scripts/check-slice.py "$BIN" arm64 || fail "exact arm64 slice"
if python3 scripts/check-slice.py "$BIN" arm64e >/dev/null 2>&1; then
  fail "arm64 guard accepted an arm64 binary as arm64e"
fi
pass "fresh local arm64 IPA and exact slice guards"

# The quick suite retains the minimal reproducer for the cross-file bug.
sh scripts/regression-suite.sh --quick || fail "quick regression suite"
pass "primary-file regression and known whole-module reproducer"

echo "ACCEPTANCE: PASS"
echo "log: $LOG"
