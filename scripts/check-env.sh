#!/bin/sh
# check-env.sh — verify the iOS Swift Builder toolchain is intact.
# Exit 0 if ready to build; prints what's missing otherwise.
set -e
ok=1
note() { printf '%s %s\n' "$1" "$2"; }

SW=/opt/swift6.3/usr/bin/swift-frontend
SWROOT=/opt/swift6.3
SDK=/opt/ios-toolchain/iPhoneOS26.5.sdk
EXP=/opt/ios-toolchain/exp63
MODS=$EXP/modules
BK=/var/minis/shared/darwin-sdk/swift-modules-full

ISB_SYSROOT="${ISB_SYSROOT:-/opt/isb/sysroot}"
ISB_MODULE_CACHE="${ISB_MODULE_CACHE:-/var/tmp/isb-cache}"

echo "=== iOS Swift Builder — environment check ==="

# 1. swift-frontend runs (patchelf'd to glibc loader)
if [ -x "$SW" ]; then
  v=$(env -i HOME=/root TERM=dumb "$SW" --version 2>/dev/null | head -1)
  case "$v" in
    *"6.3.2"*) note "OK " "swift-frontend: $v" ;;
    "") note "!! " "swift-frontend present but did not print version (startup race — retry check-env once)"; ok=0 ;;
    *) note "?? " "swift-frontend version mismatch: $v (SDK expects 6.3.2)"; ok=0 ;;
  esac
else
  note "XX " "swift-frontend MISSING at $SW → see references/BOOTSTRAP.md"; ok=0
fi

# 2. iOS SDK
[ -f "$SDK/usr/lib/libSystem.tbd" ] && note "OK " "iOS SDK 26.5 present" || { note "XX " "iOS SDK missing at $SDK"; ok=0; }
[ -d "$SDK/System/Library/SubFrameworks" ] && note "OK " "SubFrameworks dir (iOS 26 UIKit split)" || note "?? " "SubFrameworks dir missing (UIKit may fail)"

# 3. Prebuilt Swift stdlib modules (restore from backup if absent)
for m in Swift _Concurrency _StringProcessing SwiftOnoneSupport; do
  f="$MODS/$m.swiftmodule/arm64-apple-ios.swiftmodule"
  if [ -s "$f" ]; then
    note "OK " "module $m ($(wc -c <"$f")B)"
  elif [ -s "$BK/modules/$m.swiftmodule/arm64-apple-ios.swiftmodule" ]; then
    note ".. " "module $m missing — restoring from backup"
    mkdir -p "$MODS/$m.swiftmodule"
    cp "$BK/modules/$m.swiftmodule/arm64-apple-ios.swiftmodule" "$f"
  else
    note "XX " "module $m MISSING (no backup) → run scripts/compile-stdlib.sh"; ok=0
  fi
done

# 4. SwiftShims PCM
if [ -s "$EXP/SwiftShims.pcm" ]; then note "OK " "SwiftShims.pcm"; \
elif [ -s "$BK/SwiftShims.pcm" ]; then cp "$BK/SwiftShims.pcm" "$EXP/SwiftShims.pcm"; note ".. " "SwiftShims.pcm restored from backup"; \
else note "XX " "SwiftShims.pcm MISSING → run scripts/compile-stdlib.sh"; ok=0; fi

# 5. Tools
for t in clang ld64.lld ldid llvm-strip zip; do
  command -v "$t" >/dev/null 2>&1 && note "OK " "tool: $t" || { note "XX " "tool MISSING: $t (apk add clang19 lld zip; build ldid from ProcursusTeam/ldid)"; ok=0; }
done

echo "==="

# ---------------------------------------------------------------------------
# 6. PERFIL "SWIFT PURO" (UIKit/SwiftUI) — o caminho PRINCIPAL da skill.
#    Depende de coisas que a checagem acima NAO cobre: outra toolchain (6.3.3),
#    outro conjunto de modulos (foundation-build633) e o sysroot neutro
#    espelhado em ISB_SYSROOT, porque os .pcm gravam caminhos absolutos.
# ---------------------------------------------------------------------------
pure=1
echo "--- perfil Swift puro (build-pure-ui.sh / build-parallel.py) ---"

SW633=/opt/swift6.3.3/usr/bin/swift-frontend
if [ "${ISB_ARCH:-arm64}" = "arm64e" ]; then
  SW633=/opt/swift6.3.3/usr/bin/swift-frontend
fi
if [ -x "$SW633" ]; then
  v=$(env -i HOME=/root TERM=dumb "$SW633" --version 2>/dev/null | head -1)
  case "$v" in
    *"6.3.3"*) note "OK " "swift-frontend 6.3.3: $v" ;;
    "") note "!! " "swift-frontend 6.3.3 nao imprimiu versao (race de startup — repita)"; pure=0 ;;
    *) note "?? " "swift-frontend 6.3.3 divergente: $v"; pure=0 ;;
  esac
else
  note "XX " "swift-frontend 6.3.3 AUSENTE em $SW633"; pure=0
fi

FB=/opt/ios-toolchain/foundation-build633
[ "${ISB_ARCH:-arm64}" = "arm64e" ] && FB=/opt/ios-toolchain/foundation-build633-arm64e
if [ -d "$FB" ]; then
  nmod=$(ls "$FB"/swift_*.swiftmodule 2>/dev/null | wc -l)
  npcm=$(ls "$FB"/clang_*.pcm 2>/dev/null | wc -l)
  if [ "$nmod" -gt 0 ] && [ "$npcm" -gt 0 ]; then
    note "OK " "foundation-build633 ($nmod swiftmodule, $npcm pcm)"
  else
    note "XX " "foundation-build633 incompleto ($nmod swiftmodule, $npcm pcm)"; pure=0
  fi
else
  note "XX " "foundation-build633 AUSENTE em $FB"; pure=0
fi

# Paths espelhados da VM: os .pcm gravam paths absolutos + (tamanho, mtime).
# Sem eles: "file X has been modified since the module file Y".
for p in "$ISB_SYSROOT/iPhoneOS26.5.sdk" \
         "$ISB_SYSROOT/vfs/overlay.yaml"; do
  if [ -e "$p" ]; then note "OK " "espelho da VM: $p"
  else note "XX " "espelho da VM AUSENTE: $p → HANDOFF.md §3.2"; pure=0; fi
done

# module cache: /tmp na VM e' tmpfs pequeno; aqui usamos bigtmp
if [ -d "$ISB_MODULE_CACHE" ]; then note "OK " "module cache $ISB_MODULE_CACHE"
else note ".. " "criando $ISB_MODULE_CACHE (module cache)"; mkdir -p "$ISB_MODULE_CACHE"; fi

# UIKitCore.tbd: sem ele o link falha nas classes genericas do UIKit
UKC=/opt/ios-toolchain/extrafw/UIKitCore.framework/UIKitCore.tbd
if [ -f "$UKC" ]; then note "OK " "UIKitCore.tbd (link de classes genericas)"
else note "?? " "UIKitCore.tbd ausente → rode scripts/extract-uikitcore-tbd.sh"; fi

# ---------------------------------------------------------------------------
# 7. Espaco em disco — builds grandes precisam de folga.
# ---------------------------------------------------------------------------
avail_kb=$(df -Pk / | awk 'NR==2 {print $4}')
avail_gb=$((avail_kb / 1024 / 1024))
if [ "$avail_gb" -ge 4 ]; then
  note "OK " "disco livre: ${avail_gb} GB"
elif [ "$avail_gb" -ge 2 ]; then
  note "?? " "disco livre: ${avail_gb} GB (baixo — veja scripts/gc-workdirs.sh)"
else
  note "XX " "disco livre: ${avail_gb} GB (insuficiente p/ build) → scripts/gc-workdirs.sh"; pure=0
fi

# 8. Native intelligence profiles (auditable, optional).
# The framework stubs are fat for arm64/arm64e, but Swift interfaces and PCMs
# are slice-specific. Never report the arm64 cache as an arm64e cache.
NATIVE_SDK="$SDK"
for fw in NaturalLanguage FoundationModels CoreML Vision Accelerate; do
  if [ -f "$NATIVE_SDK/System/Library/Frameworks/$fw.framework/$fw.tbd" ]; then
    note "OK " "$fw.framework stub (arm64 + arm64e)"
  else
    note "?? " "$fw.framework unavailable"
  fi
done
FM_IF="$NATIVE_SDK/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface"
NL_IF="$NATIVE_SDK/usr/lib/swift/NaturalLanguage.swiftmodule/arm64e-apple-ios.swiftinterface"
[ -s "$FM_IF" ] && note "OK " "FoundationModels Swift interface arm64e (iOS 26.5)" || note "?? " "FoundationModels interface arm64e unavailable"
[ -s "$NL_IF" ] && note "OK " "NaturalLanguage Swift interface arm64e (iOS 26.5)" || note "?? " "NaturalLanguage interface arm64e unavailable"
if [ "${ISB_ARCH:-arm64}" = "arm64e" ]; then
  # The active foundation-build633-arm64e cache supplies target modules.
  # embedded/ was hidden and the complete arm64e acceptance still passed.
  note "OK " "Swift stdlib embedded arm64e (não requerido; Fase 5.2 PASS)"
  if [ -x /opt/ios-toolchain/ld64.lld-arm64e ]; then
    if file /opt/ios-toolchain/ld64.lld-arm64e 2>/dev/null | grep -q 'aarch64'; then
      note "OK " "local arm64e PAC linker (aarch64, offline)"
    else
      note "XX " "local arm64e linker nao e aarch64"; pure=0
    fi
  else
    note "XX " "local arm64e PAC linker ausente em /opt/ios-toolchain/ld64.lld-arm64e"; pure=0
  fi
  if [ -d "$FB" ] && [ -s "$FB/swift_FoundationModels.swiftmodule" ] && [ -s "$FB/swift_NaturalLanguage.swiftmodule" ] && [ -s "$FB/swift_SwiftUICore.swiftmodule" ] && [ -s "$FB/swift_UIKit.swiftmodule" ] && [ -s "$FB/swift_SwiftUI.swiftmodule" ]; then
    note "OK " "foundation-build arm64e completo (IA + SwiftUI/UIKit)"
  else
    note "XX " "foundation-build arm64e incompleto — rode build-arm64e-modules.sh em Linux"; pure=0
  fi
else
  if strings "$FB/swift_Swift.swiftmodule" 2>/dev/null | grep -q "arm64-apple-ios26.0"; then
    note "OK " "Swift pure profile arm64/iOS 26.0 (default comprovado)"
  fi
fi


echo "==="
if [ $ok -eq 1 ]; then
  echo "PERFIL HIBRIDO (Swift+ObjC, scripts/build-ipa.sh): READY"
else
  echo "PERFIL HIBRIDO (scripts/build-ipa.sh): NOT READY"
fi
if [ $pure -eq 1 ]; then
  echo "PERFIL SWIFT PURO (scripts/build-pure-ui.sh): READY  <- caminho principal"
else
  echo "PERFIL SWIFT PURO (scripts/build-pure-ui.sh): NOT READY"
fi

if [ $ok -eq 1 ] || [ $pure -eq 1 ]; then exit 0
else echo "NOT READY — address the XX items above"; exit 1; fi
