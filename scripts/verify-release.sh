#!/bin/sh
# verify-release.sh — governance, privacy and release-content audit.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
sh scripts/verify-docs.sh
python3 scripts/check-repo-clean.py
git diff --check
if [ "${VERIFY_RELEASE_CLEAN:-0}" = 1 ] && [ -n "$(git status --porcelain)" ]; then
  echo 'RELEASE: FAIL — working tree is dirty'; exit 1
fi
for f in LICENSE NOTICE.md SECURITY.md CONTRIBUTING.md CHANGELOG.md \
  REPRODUCE-FROM-ZERO.md references/BEST-PRACTICES.md references/HANDOFF.md \
  references/PROJECT-GOVERNANCE.md references/PROJECT-GUIDE.md \
  references/PUBLISHING.md references/PORTING-TERCEROS.md references/VERSION-MATRIX.md; do
  [ -s "$f" ] || { echo "RELEASE: missing $f"; exit 1; }
done
# Reject dangling Git commits before publication; they can retain removed secrets.
DANGLING=$(git fsck --full --no-reflogs 2>/dev/null | awk '$2 == "commit" {print $3}')
[ -z "$DANGLING" ] || { echo "RELEASE: dangling commit objects present"; echo "$DANGLING"; exit 1; }
for commit in $(git rev-list --all); do
  if [ -n "$(git grep -I -nE '/home/[A-Za-z0-9_.-]+' "$commit" -- . ':(exclude)scripts/verify-release.sh' 2>/dev/null)" ]; then
    echo "RELEASE: forbidden personal path in history"; exit 1
  fi
  if [ -n "$(git grep -I -nE -- '-----BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY-----' "$commit" -- . ':(exclude)scripts/verify-release.sh' 2>/dev/null)" ]; then
    echo "RELEASE: private key in history"; exit 1
  fi
done
# No `grep`: in this shell GNU grep may not terminate (see verify-docs.sh).
contains_file(){ while IFS= read -r _l; do case "$_l" in *"$2"*) return 0 ;; esac; done < "$1"; return 1; }
contains_file scripts/profile.sh arm64e
contains_file scripts/acceptance-suite.sh acceptance-suite-arm64e.sh
contains_file references/PROJECT-GOVERNANCE.md PROJECT-GUIDE.md
echo 'RELEASE: PASS — governance, privacy, copyright and docs'
