#!/bin/sh
# verify-docs.sh — cheap checks for claims that can be verified locally.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fail=0
for f in scripts/*.sh; do sh -n "$f" || fail=1; done
python3 -m py_compile "$ROOT"/scripts/*.py || fail=1
python3 "$ROOT/scripts/check-repo-clean.py" || fail=1
[ -x "$ROOT/scripts/bootstrap.sh" ] || { echo 'bootstrap.sh missing/executable'; fail=1; }
[ -x "$ROOT/scripts/benchmark-build.sh" ] || { echo 'benchmark-build.sh missing/executable'; fail=1; }
grep -q 'OPT_FLAGS' "$ROOT/scripts/build-parallel.py" || { echo 'optimization matrix missing'; fail=1; }
grep -q 'FoundationModelsRuntimeMain.swift' "$ROOT/REPRODUCE-FROM-ZERO.md" || { echo 'AI diagnostic instructions missing'; fail=1; }
if grep -RInE 'libera ~1 GB por toolchain|13G livres|65\.109\.165\.106|/home/[a-zA-Z]' "$ROOT/SKILL.md" "$ROOT/README.md" "$ROOT/references" "$ROOT/scripts" --exclude='verify-docs.sh' >/tmp/isb-doc-fail 2>&1; then
  cat /tmp/isb-doc-fail; fail=1
fi
rm -f /tmp/isb-doc-fail
[ "$fail" -eq 0 ] && echo 'DOCS: PASS' || { echo 'DOCS: FAIL'; exit 1; }
