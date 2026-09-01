#!/bin/sh
# check-newcomer.sh — smoke-test the fresh-clone onboarding diagnostics.
# It never changes /opt; all bootstrap roots point at an empty temp tree.
set -eu
SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
W=$(mktemp -d /tmp/isb-newcomer.XXXXXX)
trap 'rm -rf "$W"' EXIT
OUT="$W/bootstrap.log"
set +e
ISB_TOOLCHAIN_ROOT="$W/toolchain" ISB_SWIFT_ROOT="$W/swift" \
  ISB_SYSROOT="$W/sysroot" ISB_GLIBC_ROOT="$W/glibc/lib" \
  sh "$SKILL/scripts/bootstrap.sh" --check >"$OUT" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || { cat "$OUT"; echo "newcomer check unexpectedly passed" >&2; exit 1; }
for label in 'Swift 6.3.2 frontend: MISSING' 'iOS SDK: MISSING' \
    'stdlib cache: MISSING' 'pure Swift arm64 cache: MISSING' \
    'pure Swift arm64e cache: MISSING' 'neutral sysroot: MISSING' \
    'glibc loader: MISSING'; do
  grep -F "$label" "$OUT" >/dev/null || { cat "$OUT"; echo "missing diagnostic: $label" >&2; exit 1; }
done
# Ensure the documented next-step recipe mentions every missing class.
grep -q 'bootstrap.sh --step' "$SKILL/REPRODUCE-FROM-ZERO.md"
grep -q 'compile-stdlib.sh' "$SKILL/REPRODUCE-FROM-ZERO.md"
grep -q 'orchestrator_vm633.py' "$SKILL/REPRODUCE-FROM-ZERO.md"
grep -q 'BOOTSTRAP.md' "$SKILL/REPRODUCE-FROM-ZERO.md"
# No traceback is an acceptable onboarding diagnostic.
! grep -qi 'traceback' "$OUT"
echo 'NEWCOMER: PASS — empty roots report actionable MISSING diagnostics'
