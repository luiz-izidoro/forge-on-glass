#!/bin/sh
# verify-docs.sh — cheap checks for claims that can be verified locally.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fail=0
# Pure-shell matching. Do not use `grep` here: in this shell (iSH) GNU
# grep may not terminate, and these gates are exactly the ones that must run
# reliably. `case` is POSIX and creates no process.
contains_file(){ while IFS= read -r _l; do case "$_l" in *"$2"*) return 0 ;; esac; done < "$1"; return 1; }
for f in scripts/*.sh; do sh -n "$f" || fail=1; done
# Syntax check without writing bytecode: `py_compile` leaves `__pycache__/`
# after every run, an artifact that kept coming back and serves no purpose here.
for _py in "$ROOT"/scripts/*.py; do
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$_py" || fail=1
done
python3 "$ROOT/scripts/check-repo-clean.py" || fail=1
[ -x "$ROOT/scripts/bootstrap.sh" ] || { echo 'bootstrap.sh missing/executable'; fail=1; }
[ -x "$ROOT/scripts/bootstrap-glibc.sh" ] || { echo 'bootstrap-glibc.sh missing/executable'; fail=1; }
[ -x "$ROOT/scripts/benchmark-build.sh" ] || { echo 'benchmark-build.sh missing/executable'; fail=1; }
[ -x "$ROOT/scripts/check-newcomer.sh" ] || { echo 'check-newcomer.sh missing/executable'; fail=1; }
contains_file "$ROOT/.github/workflows/static.yml" 'check-newcomer.sh' || { echo 'CI missing newcomer smoke test'; fail=1; }
contains_file "$ROOT/scripts/acceptance-suite-arm64e.sh" 'check-weak-link.py' || { echo 'arm64e acceptance missing weak-link guard'; fail=1; }
contains_file "$ROOT/scripts/build-parallel.py" 'OPT_FLAGS' || { echo 'optimization matrix missing'; fail=1; }
contains_file "$ROOT/REPRODUCE-FROM-ZERO.md" 'FoundationModelsRuntimeMain.swift' || { echo 'AI diagnostic instructions missing'; fail=1; }
contains_file "$ROOT/.github/workflows/static.yml" 'check-repo-clean.py' || { echo 'CI missing repository guard'; fail=1; }
contains_file "$ROOT/.github/workflows/static.yml" 'verify-docs.sh' || { echo 'CI missing documentation guard'; fail=1; }
if [ -f "$ROOT/Dockerfile" ]; then
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    case "$src" in
      --*) continue ;;
    esac
    [ -f "$ROOT/$src" ] || { echo "Dockerfile COPY missing: $src"; fail=1; continue; }
    git -C "$ROOT" ls-files --error-unmatch -- "$src" >/dev/null 2>&1 || {
      echo "Dockerfile COPY is not tracked: $src"; fail=1;
    }
  done <<EOF
$(awk '$1 == "COPY" { print $2 }' "$ROOT/Dockerfile")
EOF
fi
if find "$ROOT/docs" -type f -name '*.md' -print 2>/dev/null | while read -r f; do
  b=$(basename "$f")
  [ ! -e "$ROOT/references/$b" ] || { echo "duplicate documentation basename: $b"; exit 1; }
done; then
  :
else
  fail=1
fi
# Recursive scan without `grep`: walks the .md files and flags the lines that
# contradict the recorded evidence.
for _md in "$ROOT"/references/*.md; do
  [ -f "$_md" ] || continue
  while IFS= read -r _l; do
    case "$_l" in
      *'still requires'*|*'S3 pending'*) echo "evidence contradiction: $_md"; fail=1;;
    esac
  done < "$_md"
done
[ "$fail" -eq 0 ] && echo 'DOCS: PASS' || { echo 'DOCS: FAIL'; exit 1; }
