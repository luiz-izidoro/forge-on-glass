#!/bin/sh
# benchmark-device-build.sh — build the two device benchmark variants.
# Install both IPAs in LiveContainer, tap the button, and record the on-screen
# milliseconds. This script itself proves only S2 packaging.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${ISB_BENCH_DEVICE_OUT:-${ISB_WORKSPACE:-/var/minis/workspace}}
mkdir -p "$OUT"
for mode in none O; do
  ISB_OPT="$mode" ISB_OUTPUT="$OUT/BenchDevice-$mode.ipa" \
    sh "$ROOT/scripts/build-pure-ui.sh" BenchDevice-$mode com.forge.benchdevice \
    "$ROOT/assets/BenchApp.swift" --whole-module --unsigned
  echo "S2 IPA: $OUT/BenchDevice-$mode.ipa"
done
