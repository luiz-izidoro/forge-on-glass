#!/bin/sh
# build-multimodule.sh — compila um app iOS 100% Swift em DOIS MODULOS
# (dependencias + app) e gera o IPA.
#
# ############################################################################
# ## 🔴 DEPRECADO — NAO USE (2026-08-23)                                    ##
# ############################################################################
#
# STATUS: quebrado E desnecessario. Mantido apenas como registro tecnico.
#
# 1. QUEBRADO: importar um modulo separado DEGRADA o bridging String<->NSString
#    no modulo do app. Medido em 2026-08-23 com um app de 19 linhas:
#
#      l.text = "literal direto"
#      -> error: cannot assign value of type 'String' to type 'NSString'
#
#    O MESMO arquivo, sem o `import <DepMod>`, compila e empacota sem tocar
#    numa linha (via build-pure-ui.sh). Ou seja: o defeito vem do modulo
#    separado, nao do codigo do app. Isso explica por que TODOS os apps
#    gerados por este script davam TELA PRETA e nenhum jamais abriu.
#
# 2. DESNECESSARIO: a premissa abaixo ("limite de ~15-25k linhas por
#    processo") foi REFUTADA em 2026-08-22. Nao existe limite de tamanho; o
#    que travava era o type-checker em modo whole-module. A solucao e'
#    `-primary-file` em MODULO UNICO — que ja roda 27k linhas (TCA + 6 deps)
#    e tem app validado no device.
#
# USE NO LUGAR:
#    python3 scripts/build-parallel.py --module <App> --src <dir> --out <obj>
#    sh      scripts/link-ipa.sh      <App> <BundleID> <obj>
#    (ou simplesmente build-pure-ui.sh, que ja faz os dois)
#
# Ver: references/TYPECHECKER-E-MULTIMODULO.md e references/HANDOFF.md
# ############################################################################
#
# Uso (historico):
#   ./build-multimodule.sh <AppName> <BundleID> <DepModuleName> <dep_dir> <app_dir>
#
#   <dep_dir>  diretorio com os .swift das DEPENDENCIAS (sem entry point)
#   <app_dir>  diretorio com os .swift do APP; o entry deve ser main.swift
#              ou *Main.swift (contendo a chamada UIApplicationMain)

if [ "$ISB_ALLOW_MULTIMODULE" != "1" ]; then
  echo "build-multimodule.sh esta DEPRECADO e produz apps quebrados."
  echo "  motivo: modulo separado degrada o bridging String<->NSString"
  echo "          (app compila com erro 'cannot assign String to NSString'"
  echo "           ou abre com TELA PRETA)."
  echo ""
  echo "  use:  python3 scripts/build-parallel.py --module <App> --src <dir> --out /tmp/obj"
  echo "        sh      scripts/link-ipa.sh <App> <BundleID> /tmp/obj"
  echo "        (ou scripts/build-pure-ui.sh, que faz os dois)"
  echo ""
  echo "  para rodar assim mesmo (diagnostico): ISB_ALLOW_MULTIMODULE=1 $0 ..."
  exit 1
fi

#
# Regras aprendidas (NAO remover):
#  1. O modulo de deps PRECISA de `-parse-as-library`, senao o swift-frontend
#     emite um `_main` fantasma e o link falha com "duplicate symbol: _main".
#  2. O PRIMEIRO arquivo de CADA modulo deve importar Foundation (e o que mais
#     o modulo usar). Sem isso os tipos ObjC do Foundation somem nos demais
#     arquivos (NSRecursiveLock/String.replacingOccurrences "nao existem").
#     Este script injeta um _00_Prelude.swift automaticamente.
#  3. Os fontes do app precisam de `import <DepModuleName>`.
#  4. `-swift-module-file=X=path` = SEMPRE 1 argumento.
#  5. main.swift PRIMEIRO na lista de arquivos do app.
#
# Saida: /var/minis/workspace/<AppName>.ipa
set -e

APP="${1:?uso: $0 <AppName> <BundleID> <DepModule> <dep_dir> <app_dir>}"
BUNDLE="${2:?falta bundle id}"
DEPMOD="${3:?falta nome do modulo de deps}"
DEPDIR="${4:?falta dir das deps}"
APPDIR="${5:?falta dir do app}"

ROOT=/opt/isb/sysroot
SW=/opt/swift6.3.3
SF=$SW/usr/bin/swift-frontend
SDK=$ROOT/iPhoneOS26.5.sdk
OUT=/opt/ios-toolchain/foundation-build633
VFS=$ROOT/vfs/overlay.yaml
BIG=/var/tmp/isb-cache/app
B=/tmp/mm-$APP
mkdir -p "$BIG" "$B"

MODS=""
for f in "$OUT"/swift_*.swiftmodule; do
  n=$(basename "$f" .swiftmodule); n=${n#swift_}
  [ "$n" = "XPC" ] && continue   # overlay Swift do XPC cria ciclo os<->XPC
  MODS="$MODS -swift-module-file=$n=$f"
done
for f in "$OUT"/clang_*.pcm; do
  n=$(basename "$f" .pcm); n=${n#clang_}
  MODS="$MODS -Xcc -fmodule-file=$n=$f"
done
COMMON="-frontend -target arm64-apple-ios26.0 -sdk $SDK -enable-objc-interop -swift-version 5 \
 -disable-implicit-swift-modules -Xcc -fno-implicit-modules -Xcc -fno-implicit-module-maps \
 -Xcc -ivfsoverlay -Xcc $VFS -Xcc -fmodules-cache-path=$BIG -Xcc -DCF_SWIFT_SENDABLE="

# --- prelude (regra 2) --------------------------------------------------------
mkprelude() {
  d="$1"; extra="$2"
  [ -f "$d/_00_Prelude.swift" ] && return
  { echo "// Prelude gerado por build-multimodule.sh — NAO REMOVER."
    echo "// O primeiro arquivo do modulo precisa importar Foundation, senao os"
    echo "// tipos ObjC do Foundation somem nos demais arquivos."
    echo "import Foundation"
    echo "import SwiftUI"
    echo "import UIKit"
    echo "import Combine"
    [ -n "$extra" ] && echo "import $extra"
  } > "$d/_00_Prelude.swift"
}

# retry: o iSH tem race de startup (~15-25%) e OOM (rc<0) em builds grandes
run_retry() {
  errf="$1"; outf="$2"; shift 2
  n=0
  until [ $n -ge 5 ]; do
    set +e; "$@" 2> "$errf"; rc=$?; set -e
    [ $rc -eq 0 ] && return 0
    if grep -q "error:" "$errf"; then
      echo "ERRO de compilacao ($(grep -c 'error:' "$errf") erros):"
      grep "error:" "$errf" | head -25
      echo "   (log completo: $errf)"
      return 1
    fi
    n=$((n+1)); echo "   (rc=$rc sem erro no log = race/OOM, tentativa $n)"
  done
  return 1
}

echo "==> [1/3] modulo $DEPMOD ($(cat "$DEPDIR"/*.swift | wc -l) linhas)"
mkprelude "$DEPDIR" ""
run_retry "$B/dep.err" "$B/dep.o" \
  $SF $COMMON -c -parse-as-library -module-name "$DEPMOD" \
  $(ls "$DEPDIR"/*.swift) $MODS \
  -emit-module -emit-module-path "$B/$DEPMOD.swiftmodule" -o "$B/dep.o"
[ -s "$B/dep.o" ] || { echo "dep falhou"; exit 1; }
echo "    dep.o $(stat -c %s "$B/dep.o") B | $DEPMOD.swiftmodule $(stat -c %s "$B/$DEPMOD.swiftmodule") B"

echo "==> [2/3] app $APP ($(cat "$APPDIR"/*.swift | wc -l) linhas)"
mkprelude "$APPDIR" "$DEPMOD"
MAIN=""
for f in "$APPDIR"/main.swift "$APPDIR"/*Main.swift; do
  [ -f "$f" ] && { MAIN="$f"; break; }
done
[ -n "$MAIN" ] || { echo "sem entry point (main.swift ou *Main.swift) em $APPDIR"; exit 1; }
if [ "$(basename "$MAIN")" != "main.swift" ]; then
  cp "$MAIN" "$APPDIR/main.swift"; rm -f "$MAIN"; MAIN="$APPDIR/main.swift"
fi
# O app usa `#available` (direto ou via SwiftUI) -> precisa do shim do
# ___isPlatformVersionAtLeast (libclang_rt.ios.a nao existe no toolchain Linux)
SHIM=$(CDPATH= cd -- "$(dirname "$0")/.." SHIM=/var/minis/skills/ios-swift-builder/assets/PlatformVersionShim.swiftSHIM=/var/minis/skills/ios-swift-builder/assets/PlatformVersionShim.swift pwd)/assets/PlatformVersionShim.swift
[ -f "$SHIM" ] && [ ! -f "$APPDIR/PlatformVersionShim.swift" ] && \
  cat "$SHIM" > "$APPDIR/PlatformVersionShim.swift"

# MODO PARALELO (padrao): -primary-file por arquivo, 3 jobs.
# Medido: whole-module TRAVA o type-checker (60+ min sem .o) no mesmo conjunto
# que compila em ~2 min arquivo-a-arquivo.
PAR=$(CDPATH= cd -- "$(dirname "$0")/.." PAR=/var/minis/skills/ios-swift-builder/scripts/build-parallel.pyPAR=/var/minis/skills/ios-swift-builder/scripts/build-parallel.py pwd)/scripts/build-parallel.py
rm -rf "$B/obj"; mkdir -p "$B/obj"
python3 "$PAR" --module "$APP" --src "$APPDIR" --out "$B/obj" \
  --dep-module "$DEPMOD=$B/$DEPMOD.swiftmodule" --jobs "${JOBS:-3}" --timeout 1500 || exit 1
APPOBJS="$B/obj/main.o $(ls "$B"/obj/*.o | grep -v '/main\.o$' | tr '\n' ' ')"
echo "    $(ls "$B"/obj/*.o | wc -l) objetos"

echo "==> [3/3] link + IPA"
EXTRAFW=/opt/ios-toolchain/extrafw
EXTRAFLAGS=""
[ -f "$EXTRAFW/UIKitCore.framework/UIKitCore.tbd" ] && EXTRAFLAGS="-F$EXTRAFW -framework UIKitCore"
ld64.lld -arch arm64 -platform_version ios 26.0 26.5 -syslibroot "$SDK" \
  -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" -lSystem -lobjc $EXTRAFLAGS \
  -framework UIKit -framework Foundation -framework CoreGraphics \
  -framework QuartzCore -framework SwiftUI -framework CoreText -framework Combine \
  -lswiftCore -lswiftFoundation -lswiftUIKit -lswiftDarwin -lswiftObjectiveC \
  -lswiftCoreGraphics -lswiftDispatch -lswiftCoreFoundation -lswiftQuartzCore \
  -rpath /usr/lib/swift -e _main $APPOBJS "$B/dep.o" -o "$B/$APP"

PAY="$B/Payload/$APP.app"
rm -rf "$B/Payload"; mkdir -p "$PAY"
cp "$B/$APP" "$PAY/$APP"
cat > "$PAY/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE</string>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>MinimumOSVersion</key><string>26.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
</dict></plist>
EOF
ldid -S "$PAY/$APP"
mkdir -p /var/minis/workspace
rm -f "/var/minis/workspace/$APP.ipa"
(cd "$B" && zip -qr "/var/minis/workspace/$APP.ipa" Payload)
echo "==> pronto: /var/minis/workspace/$APP.ipa"
ls -lh "/var/minis/workspace/$APP.ipa"
