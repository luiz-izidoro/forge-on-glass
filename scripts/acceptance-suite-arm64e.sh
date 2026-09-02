#!/bin/sh
# acceptance-suite-arm64e.sh — fully local arm64e/PAC acceptance.
# The one-time linker/module bootstrap may use a VM; this suite never does.
set -eu
SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORKSPACE="${ISB_WORKSPACE:-/var/minis/workspace}"
WORK="${ISB_ACCEPTANCE_WORK:-/tmp/isb-acceptance-arm64e}"
rm -rf "$WORK"; mkdir -p "$WORK"
fail() { echo "ACCEPTANCE arm64e: FAIL: $*"; exit 1; }
ok() { echo "ACCEPTANCE arm64e: OK: $*"; }
[ "${ISB_ARCH:-arm64e}" = arm64e ] || fail "run with ISB_ARCH=arm64e"
for f in "$SKILL"/scripts/*.sh; do sh -n "$f" || fail "shell syntax: $f"; done
python3 -m py_compile "$SKILL"/scripts/*.py || fail "Python syntax"
[ -x /opt/ios-toolchain/ld64.lld-arm64e ] || fail "local PAC linker missing"
file /opt/ios-toolchain/ld64.lld-arm64e | grep -q 'aarch64' || fail "linker is not native aarch64"
/opt/ios-toolchain/ld64.lld-arm64e --version >/dev/null || fail "local linker does not execute"
for f in "$SKILL"/scripts/build-pure-ui.sh "$SKILL"/scripts/link-ipa.sh; do
  ! grep -qE '(^|[[:space:]])(ssh|scp)([[:space:]]|$)|link-remote-arm64e' "$f" || fail "remote dependency in $f"
done
# Foundation/Dispatch pure-Swift S2 smoke in the same arm64e profile.
cat > "$WORK/foundation-probe.swift" <<'EOF'
import Foundation
import Dispatch
let q = DispatchQueue(label: "acceptance-arm64e")
let g = DispatchGroup(); g.enter()
q.async { _ = FileManager.default.fileExists(atPath: NSTemporaryDirectory()); g.leave() }
g.wait()
print("foundation-dispatch-ok")
EOF
ISB_ARCH=arm64e ISB_OUTPUT="$WORK/FoundationDispatch" sh scripts/build-pure-foundation.sh \
  FoundationDispatch "$WORK/foundation-probe.swift" || fail "Foundation/Dispatch arm64e build"
python3 scripts/check-slice.py "$WORK/FoundationDispatch" arm64e || fail "Foundation/Dispatch slice"
python3 scripts/check-livecontainer.py "$WORK/FoundationDispatch" || fail "Foundation/Dispatch Mach-O"
python3 scripts/check-undefined.py "$WORK/FoundationDispatch" \
  "${ISB_SYSROOT:-/opt/isb/sysroot}/iPhoneOS26.5.sdk" || fail "Foundation/Dispatch undefined symbols"
ok "Foundation/Dispatch neutral 6.3.3 arm64e S2 smoke"
ISB_WORKSPACE="$WORKSPACE" ISB_ARCH=arm64e sh scripts/build-pure-ui.sh LocalAcceptanceUI com.example.acceptanceui \
  assets/SwiftUIDemo.swift --primary-file --unsigned \
  >"$WORK/ui.log" 2>&1 || { cat "$WORK/ui.log"; fail "SwiftUI/UIKit arm64e build"; }
ISB_WORKSPACE="$WORKSPACE" ISB_ARCH=arm64e sh scripts/build-pure-ui.sh LocalAcceptanceFMFixed com.example.acceptancefmfixed \
  assets/FoundationModelsSafeMain.swift assets/FoundationModelsSafeProbe.swift --primary-file --unsigned \
  --weak-framework FoundationModels \
  >"$WORK/fm.log" 2>&1 || { cat "$WORK/fm.log"; fail "FoundationModels arm64e build"; }
ISB_WORKSPACE="$WORKSPACE" ISB_ARCH=arm64e sh scripts/build-pure-ui.sh LocalAcceptanceNL com.example.acceptancenl \
  assets/NaturalLanguageProbeMain.swift assets/NaturalLanguageProbe.swift \
  --primary-file --extra-framework NaturalLanguage \
  --unsigned >"$WORK/nl.log" 2>&1 || { cat "$WORK/nl.log"; fail "NaturalLanguage Swift build"; }
ISB_WORKSPACE="$WORKSPACE" ISB_ARCH=arm64e sh scripts/build-pure-ui.sh LocalAcceptanceEmb com.example.acceptanceemb \
  assets/EmbeddingsProbeMain.swift assets/NativeEmbeddings.swift --primary-file \
  --extra-objc assets/NativeNLBridge.m --extra-framework NaturalLanguage \
  --unsigned >"$WORK/emb.log" 2>&1 || { cat "$WORK/emb.log"; fail "embeddings bridge build"; }
ISB_WORKSPACE="$WORKSPACE" ISB_ARCH=arm64e sh scripts/build-pure-ui.sh LocalAcceptanceFMRuntime com.example.acceptancefmruntime \
    assets/FoundationModelsRuntimeMain.swift --primary-file --weak-framework FoundationModels --unsigned \
    >"$WORK/runtime.log" 2>&1 || { cat "$WORK/runtime.log"; fail "FoundationModels runtime diagnostic build"; }
for app in LocalAcceptanceUI LocalAcceptanceFMFixed LocalAcceptanceNL LocalAcceptanceEmb LocalAcceptanceFMRuntime; do
  IPA="$WORKSPACE/$app.ipa"; [ -s "$IPA" ] || fail "missing $IPA"
  D="$WORK/$app"; mkdir -p "$D"; unzip -q -o "$IPA" -d "$D"
  BIN="$D/Payload/$app.app/$app"
  python3 scripts/check-slice.py "$BIN" arm64e || fail "slice $app"
  python3 scripts/check-livecontainer.py "$BIN" || fail "Mach-O $app"
  python3 "$SKILL/scripts/check-entry.py" "$BIN" || fail "entry $app"
  if [ "$app" = LocalAcceptanceFMFixed ] || [ "$app" = LocalAcceptanceFMRuntime ]; then
    python3 scripts/check-weak-link.py "$BIN" FoundationModels || fail "FoundationModels weak-link $app"
  fi
  python3 scripts/check-undefined.py "$BIN" \
    "${ISB_SYSROOT:-/opt/isb/sysroot}/iPhoneOS26.5.sdk" || fail "undefined symbols $app"
  if [ "$app" = LocalAcceptanceUI ]; then
    STRIPBIN="$WORK/stripped-$app"; cp "$BIN" "$STRIPBIN"; llvm-strip -x "$STRIPBIN"
    python3 scripts/check-entry.py "$STRIPBIN" || fail "stripped entry $app"
  fi
  "$SKILL/scripts/validate-ipa.sh" "$IPA" || fail "IPA $app"
done

# Negative proof: a strong FoundationModels load command must be rejected.
ISB_WORKSPACE="$WORKSPACE" ISB_ARCH=arm64e sh scripts/build-pure-ui.sh LocalAcceptanceFMStrong com.example.acceptancefmstrong \
  assets/FoundationModelsSafeMain.swift assets/FoundationModelsSafeProbe.swift --primary-file \
  --extra-framework FoundationModels --unsigned >"$WORK/strong.log" 2>&1 \
  || { cat "$WORK/strong.log"; fail "strong-link negative fixture build"; }
STRONG="$WORKSPACE/LocalAcceptanceFMStrong.ipa"
[ -s "$STRONG" ] || fail "missing strong-link negative fixture"
SD="$WORK/strong"; mkdir -p "$SD"; unzip -q -o "$STRONG" -d "$SD"
SBIN="$SD/Payload/LocalAcceptanceFMStrong.app/LocalAcceptanceFMStrong"
if python3 scripts/check-weak-link.py "$SBIN" FoundationModels >"$WORK/strong-guard.log" 2>&1; then
  cat "$WORK/strong-guard.log"; fail "weak-link guard accepted strong link"
fi
ok "FoundationModels weak-link guard and negative test"

ok "offline linker + SwiftUI/UIKit + FoundationModels + NaturalLanguage + embeddings"
ok "acceptance arm64e PASS"
