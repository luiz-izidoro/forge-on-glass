#!/bin/sh
# gc-workdirs.sh — conservative cleanup for orphaned temporary build workdirs.
# Dry-run is the default; deletion requires --apply explicitly.
set -eu
MODE=dry-run
OLDER=1
usage(){ echo "uso: $0 [--dry-run|--apply] [--older-than N]" >&2; exit 2; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=dry-run ;;
    --apply) MODE=apply ;;
    --older-than) shift; OLDER=${1:?falta N} ;;
    *) usage ;;
  esac
  shift
done
case "$OLDER" in ''|*[!0-9]*) echo '--older-than exige inteiro >= 0' >&2; exit 2;; esac
MINUTES=$((OLDER * 1440))
# A worker can have an open file without its path appearing in argv. Be
# conservative: while any known builder worker exists, skip every target.
active=0
if pgrep -af 'swift-frontend|orchestrator_vm|build-pure-ui|build-parallel|link-ipa|acceptance-suite|regression-suite' 2>/dev/null | grep -v 'gc-workdirs' | grep -q .; then
  active=1
  echo 'active build worker detected; all targets will be skipped'
fi
found=0
for pattern in /tmp/build-* /tmp/link-* /tmp/regression-suite /tmp/isb-*; do
  [ -d "$pattern" ] || continue
  found=1
  if [ "$active" -eq 1 ]; then
    echo "skip active-worker guard: $pattern"
    continue
  fi
  if [ "$MINUTES" -gt 0 ] && [ "$pattern" -nt "/tmp" ]; then
    :
  fi
  # BusyBox find supplies the portable age check used on iSH.
  if ! find "$pattern" -prune -mmin "+$MINUTES" 2>/dev/null | grep -q .; then
    echo "skip newer than ${OLDER}d: $pattern"
    continue
  fi
  size=$(du -sh "$pattern" 2>/dev/null | cut -f1)
  if [ "$MODE" = apply ]; then
    rm -rf -- "$pattern"
    echo "removed: $pattern ($size)"
  else
    echo "would remove: $pattern ($size)"
  fi
done
[ "$found" -eq 1 ] || echo 'no matching workdirs'
if [ "$MODE" = dry-run ]; then echo 'dry-run: nothing removed; use --apply explicitly'; fi
