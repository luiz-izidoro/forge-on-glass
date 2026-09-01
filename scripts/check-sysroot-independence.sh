#!/bin/sh
# check-sysroot-independence.sh — prove arm64 does not depend on /home.
# The legacy mirror is moved, never deleted, and restored by trap on every exit.
set -eu
SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BACKUP=${ISB_HOME_SHADOW:-/tmp/isb-home-shadow-$$}

# If the legacy mirror was already removed, a normal fresh build is the
# positive proof. When it exists, the destructive move-and-restore test below
# remains available and is used during migration.
if ! find /home -maxdepth 2 -type d -name swift-ios-build 2>/dev/null | grep -q .; then
  OUTPUT="${ISB_OUTPUT:-/tmp/isb-sysroot-independent-$$.ipa}"
  cd "$SKILL"
  ISB_OUTPUT="$OUTPUT" sh scripts/build-livecontainer.sh \
    P0SysrootIndependent com.example.p0.independent \
    assets/PureSwiftDemo.swift
  [ -s "$OUTPUT" ] || { echo "build produced no IPA" >&2; exit 1; }
  echo "sysroot independence: PASS (no legacy mirror present)"
  exit 0
fi

restore(){
  failed=0
  for dest in "$BACKUP"/*/swift-ios-build; do
    [ -e "$dest" ] || continue
    user=${dest#"$BACKUP"/}
    user=${user%/swift-ios-build}
    src="/home/$user/swift-ios-build"
    if [ -e "$src" ]; then
      echo "cannot restore: destination exists: $src" >&2
      failed=1
      continue
    fi
    mkdir -p "/home/$user"
    mv "$dest" "$src" || failed=1
    [ -e "$src" ] || { echo "restore verification failed: $src" >&2; failed=1; }
  done
  for dest in "$BACKUP"/*/swift-ios-build; do
    [ ! -e "$dest" ] || failed=1
  done
  [ "$failed" -eq 0 ] || return 1
  rm -rf "$BACKUP"
  [ ! -e "$BACKUP" ] || { echo "backup cleanup failed: $BACKUP" >&2; return 1; }
}
finish(){
  rc=$?
  trap - EXIT INT TERM
  restore || rc=1
  exit "$rc"
}

[ ! -e "$BACKUP" ] || {
  echo "backup destination already exists: $BACKUP" >&2
  exit 2
}
mkdir -p "$BACKUP"
# Install the restoration trap before moving the first legacy mirror. If a later
# collision, interruption, or build failure occurs, every completed move is
# restored by finish().
trap finish EXIT INT TERM
MOVED=0
for src in /home/*/swift-ios-build; do
  [ -e "$src" ] || continue
  user=${src#/home/}
  user=${user%/swift-ios-build}
  dest="$BACKUP/$user/swift-ios-build"
  [ ! -e "$dest" ] || {
    echo "backup destination already exists: $dest" >&2
    exit 2
  }
  mkdir -p "$(dirname "$dest")"
  mv "$src" "$dest"
  MOVED=$((MOVED + 1))
done
[ "$MOVED" -gt 0 ] || {
  echo "no /home/*/swift-ios-build found" >&2
  exit 2
}

OUTPUT="$BACKUP/independence.ipa"
echo "temporarily shadowed $MOVED legacy sysroot mirror(s)"
echo "building fresh arm64 IPA without /home mirror"
cd "$SKILL"
ISB_OUTPUT="$OUTPUT" sh scripts/build-livecontainer.sh \
  P0SysrootIndependent com.example.p0.independent \
  assets/PureSwiftDemo.swift
[ -s "$OUTPUT" ] || { echo "build produced no IPA" >&2; exit 1; }
echo "sysroot independence: PASS"
