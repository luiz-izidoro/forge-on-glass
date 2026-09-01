#!/bin/sh
# verify-docs.sh — cheap checks for claims that can be verified locally.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fail=0
for f in scripts/*.sh; do sh -n "$f" || fail=1; done
python3 -m py_compile "$ROOT"/scripts/*.py || fail=1
python3 "$ROOT/scripts/check-repo-clean.py" || fail=1
[ -x "$ROOT/scripts/bootstrap.sh" ] || { echo 'bootstrap.sh missing/executable'; fail=1; }
[ -x "$ROOT/scripts/bootstrap-glibc.sh" ] || { echo 'bootstrap-glibc.sh missing/executable'; fail=1; }
[ -x "$ROOT/scripts/benchmark-build.sh" ] || { echo 'benchmark-build.sh missing/executable'; fail=1; }
grep -q 'OPT_FLAGS' "$ROOT/scripts/build-parallel.py" || { echo 'optimization matrix missing'; fail=1; }
grep -q 'FoundationModelsRuntimeMain.swift' "$ROOT/REPRODUCE-FROM-ZERO.md" || { echo 'AI diagnostic instructions missing'; fail=1; }
grep -q 'check-repo-clean.py' "$ROOT/.github/workflows/static.yml" || { echo 'CI missing repository guard'; fail=1; }
grep -q 'verify-docs.sh' "$ROOT/.github/workflows/static.yml" || { echo 'CI missing documentation guard'; fail=1; }
if find "$ROOT/docs" -type f -name '*.md' -print 2>/dev/null | while read -r f; do
  b=$(basename "$f")
  [ ! -e "$ROOT/references/$b" ] || { echo "duplicate documentation basename: $b"; exit 1; }
done; then
  :
else
  fail=1
fi
if grep -RInE '\*\*S3\*\*.*|ainda requer|S3 pendente' "$ROOT/references" --include='*.md' >/tmp/isb-evidence-lines 2>&1; then
  while IFS= read -r f; do
    case "$f" in
      *'ainda requer'*|*'S3 pendente'*) echo "evidence contradiction: $f"; fail=1;;
    esac
  done < /tmp/isb-evidence-lines
fi
rm -f /tmp/isb-evidence-lines
[ "$fail" -eq 0 ] && echo 'DOCS: PASS' || { echo 'DOCS: FAIL'; exit 1; }
