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
  sh "$SKILL/scripts/bootstrap.sh" --check >"$OUT" 2>&1 </dev/null
rc=$?
set -e
[ "$rc" -ne 0 ] || { cat "$OUT"; echo "newcomer check unexpectedly passed" >&2; exit 1; }

# Matching is done in-shell rather than with `grep` on a pipe: some restricted
# shells (notably iSH on device) can hang when grep is spawned inside a
# pipeline, which made this smoke test flaky. `case` is POSIX and cannot hang.
contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}
LOG=$(cat "$OUT")
for label in 'Swift 6.3.3 frontend: MISSING' 'iOS SDK 26.5: MISSING' \
    'arm64e cache: MISSING/INVALID' 'neutral sysroot: MISSING' \
    'VFS overlay: MISSING' 'PAC linker: MISSING' 'glibc loader: MISSING'; do
  contains "$LOG" "$label" || { cat "$OUT"; echo "missing diagnostic: $label" >&2; exit 1; }
done
# No traceback is an acceptable onboarding diagnostic.
contains "$(echo "$LOG" | tr 'A-Z' 'a-z')" 'traceback' && {
  cat "$OUT"; echo "traceback in onboarding diagnostic" >&2; exit 1;
}

# Ensure the documented next-step recipe mentions every missing class.
DOC=$(cat "$SKILL/REPRODUCE-FROM-ZERO.md")
contains "$DOC" 'bootstrap.sh --step' || { echo 'doc missing bootstrap --step' >&2; exit 1; }
contains "$DOC" 'orchestrator_vm633.py' || { echo 'doc missing orchestrator' >&2; exit 1; }
contains "$DOC" 'BOOTSTRAP.md' || { echo 'doc missing BOOTSTRAP.md' >&2; exit 1; }
echo 'NEWCOMER: PASS — empty roots report actionable MISSING diagnostics'
