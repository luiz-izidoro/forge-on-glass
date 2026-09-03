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
# Scan historical trees for actual personal home paths or private-key headers.
for commit in $(git rev-list --all); do
  if git grep -I -nE '/home/[A-Za-z0-9_.-]+' "$commit" -- . ':(exclude)scripts/verify-release.sh' | grep -q .; then
    echo "RELEASE: forbidden personal path in history"; exit 1
  fi
  if git grep -I -nE -- '-----BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY-----' "$commit" -- . ':(exclude)scripts/verify-release.sh' | grep -q .; then
    echo "RELEASE: private key in history"; exit 1
  fi
done
grep -q arm64e scripts/profile.sh
grep -q acceptance-suite-arm64e.sh scripts/acceptance-suite.sh
grep -q PROJECT-GUIDE.md references/PROJECT-GOVERNANCE.md
echo 'RELEASE: PASS — governance, privacy, copyright and docs'
