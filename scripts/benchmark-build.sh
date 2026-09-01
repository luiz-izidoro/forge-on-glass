#!/bin/sh
# benchmark-build.sh — reproducible local compile/size benchmark.
# This measures build time and artifact size, not device runtime performance.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${ISB_BENCH_OUT:-/tmp/isb-benchmark}
mkdir -p "$OUT"
for mode in none O Osize; do
  ipa="$OUT/Bench-$mode.ipa"; log="$OUT/Bench-$mode.log"
  start=$(date +%s)
  ISB_OPT="$mode" ISB_OUTPUT="$ipa" sh "$ROOT/scripts/build-pure-ui.sh" Bench-$mode com.forge.bench "$ROOT/assets/PureSwiftDemo.swift" --whole-module --unsigned >"$log" 2>&1
  elapsed=$(( $(date +%s) - start ))
  bin="$OUT/Bench-$mode.bin"; unzip -p "$ipa" "Payload/Bench-$mode.app/Bench-$mode" >"$bin"
  printf '%s\t%s\t%s\t%s\n' "$mode" "$elapsed" "$(wc -c <"$bin")" "$(wc -c <"$ipa")"
done
