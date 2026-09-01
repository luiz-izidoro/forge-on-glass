#!/bin/sh
# build-pure-ui.sh — compila e empacota um app iOS 100% Swift (UIKit/SwiftUI).
# ISB_ARCH=arm64e opt-in seleciona uma cache de módulos isolada.
# O perfil arm64e só fica READY depois de reconstruir foundation-build633-arm64e.
SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$SKILL/scripts/profile.sh"
#
# Uso: ./build-pure-ui.sh <AppName> <BundleID> <main.swift> [outro.swift ...]
#                         [--debug] [--primary-file | --whole-module]
# Saida: /var/minis/workspace/<AppName>.ipa
# --debug: preserva get-task-allow, inclui DebugSupport.swift e overlay DBG
# --extra-objc FILE.m: compila uma ponte Objective-C contra o SDK e a linka
# --resources DIR: copia pesos/modelos para o bundle (use com CoreML/Vision)
#
# MODO DE COMPILACAO (2026-08-23):
#   --primary-file  (PADRAO com 2+ arquivos) compila arquivo-a-arquivo via
#                   build-parallel.py e linka com link-ipa.sh.
#   --whole-module  modo antigo (um unico swift-frontend com todos os fontes).
#
#   Por que o padrao mudou: em whole-module, um arquivo que usa CoreGraphics
#   faz os tipos do Foundation (Bundle/NotificationCenter/OperationQueue)
#   DESAPARECEREM de OUTROS arquivos do mesmo modulo:
#       error: cannot find 'Bundle' in scope
#   Determinstico e reproduzido com 2 arquivos. Com -primary-file o MESMO
#   codigo compila em segundos, sem alteracao alguma.
#   Ver references/WARNINGS-FATAIS.md -> "CoreGraphics degrada Foundation".
set -e

APP="${1:?uso: $0 <AppName> <BundleID> <main.swift> [outro.swift ...] [--debug]}"
BUNDLE="${2:?falta o bundle id}"
shift 2
DEBUG=0
UNSIGNED=0
[ "${ISB_ARCH:-arm64}" = "arm64e" ] && UNSIGNED="${ISB_UNSIGNED:-1}"
MODE=""
SRC_ARGS=""
OBJC_ARGS=""
FRAMEWORK_ARGS=""
OPT_MODE="${ISB_OPT:-O}"
case "$OPT_MODE" in
  none) OPT_FLAGS=-Onone ;;
  O) OPT_FLAGS=-O ;;
  Osize) OPT_FLAGS=-Osize ;;
  *) echo "ISB_OPT inválido: $OPT_MODE (use none, O ou Osize)" >&2; exit 2 ;;
esac
SWIFT_DEFINES="${ISB_SWIFT_DEFINES:-}"
WEAK_FRAMEWORK_ARGS=""
RESOURCES=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --debug) DEBUG=1 ;;
    --unsigned) UNSIGNED=1 ;;
    --primary-file) MODE=primary ;;
    --whole-module) MODE=whole ;;
    --extra-objc) OBJC_ARGS="$OBJC_ARGS $2"; shift ;;
    --extra-framework) FRAMEWORK_ARGS="$FRAMEWORK_ARGS $2"; shift ;;
    --weak-framework) WEAK_FRAMEWORK_ARGS="$WEAK_FRAMEWORK_ARGS $2"; shift ;;
    --resources) RESOURCES="$2"; shift ;;
    --plist-extra) PLIST_EXTRA="$PLIST_EXTRA $2"; shift ;;
    --define) SWIFT_DEFINES="$SWIFT_DEFINES -D$2"; shift ;;
    *) SRC_ARGS="$SRC_ARGS $1" ;;
  esac
  shift
done
if [ "$ISB_ARCH" = "arm64e" ]; then
  echo "    (perfil arm64e ativo; IA nativa somente quando declarada pelo projeto)"
fi
export ISB_SWIFT_DEFINES="$SWIFT_DEFINES"
SRCS="$SRC_ARGS"
[ -n "$SRCS" ] || { echo "falta pelo menos um .swift"; exit 1; }

# O modo debug e' deliberadamente opt-in. Ele nao altera o fonte do usuario:
# cria uma copia de trabalho, adiciona o runtime de logs/overlay e abre o
# pedido oficial stikdebug://enable-jit com bundle-id + PID + universal.js.
DEBUG_ASSET="$SKILL/assets/DebugSupport.swift"
STIK_QUERY=""
if [ "$DEBUG" -eq 1 ]; then
  STIK_QUERY='<key>LSApplicationQueriesSchemes</key><array><string>stikdebug</string></array>'
  [ -f "$DEBUG_ASSET" ] || { echo "DebugSupport.swift ausente"; exit 1; }
  SRCS="$SRCS $DEBUG_ASSET"
  echo "    (debug StikDebug: runtime + get-task-allow + overlay DBG)"
fi

# Use the neutral prefix for newly generated PCMs. Existing caches may override it
# with ISB_SYSROOT for compatibility during migration.
# Os .pcm gravam os paths absolutos dos headers de entrada; usar /opt/... faz o
# Clang reclamar "file has been modified since the module file".
ROOT="${ISB_SYSROOT:-/opt/isb/sysroot}"
if [ ! -e "$ROOT/iPhoneOS26.5.sdk" ]; then
  legacy=$(find /home -maxdepth 2 -type d -name swift-ios-build 2>/dev/null | head -1 || true)
  [ -n "$legacy" ] && ROOT="$legacy"
fi
SW="$ISB_SW"
SF="$SW/usr/bin/swift-frontend"
SDK="$ISB_SDK"
OUT="$ISB_FOUNDATION_BUILD"
VFS="$ISB_VFS"
WORK=/tmp/build-$APP-$ISB_ARCH-$$
BIG="$WORK/objc-cache"
OUTPUT="${ISB_OUTPUT:-/var/minis/workspace/$APP.ipa}"
if [ ! -d "$OUT" ] || ! find "$OUT" -maxdepth 1 -name 'swift_*.swiftmodule' -type f | grep -q .; then
  echo "PERFIL $ISB_ARCH sem cache Swift: $OUT" >&2
  [ "$ISB_ARCH" = "arm64e" ] && echo "Rode scripts/build-arm64e-modules.sh em Linux e copie o resultado para esse caminho." >&2
  exit 1
fi
rm -rf "$WORK" && mkdir -p "$WORK" "$BIG"

# REGRA DO SWIFT: com VARIOS arquivos, codigo top-level (UIApplicationMain) so e'
# permitido num arquivo literalmente chamado `main.swift`. Copiamos os fontes
# para o dir de trabalho e renomeamos o arquivo de entrada para main.swift.
SRCLIST=""
nfiles=$(echo $SRCS | wc -w)
if [ "$nfiles" -gt 1 ]; then
  mainsrc=""
  for f in $SRCS; do
    case "$(basename "$f")" in
      main.swift) [ -z "$mainsrc" ] && mainsrc="$f" ;;
      *Main.swift) [ -z "$mainsrc" ] && mainsrc="$f" ;;
    esac
  done
  [ -n "$mainsrc" ] || mainsrc=$(echo $SRCS | awk '{for(i=1;i<=NF;i++) if ($i !~ /DebugSupport\.swift$/) {print $i; exit}}')
  mkdir -p "$WORK/src"
  for f in $SRCS; do
    if [ "$f" = "$mainsrc" ]; then
      cat "$f" > "$WORK/src/main.swift"
    else
      cat "$f" > "$WORK/src/$(basename "$f")"
    fi
  done
  SRCLIST=$(ls "$WORK"/src/*.swift)
  # main.swift PRIMEIRO na lista: a ordem dos arquivos afeta a resolucao de
  # tipos ObjC do Foundation (FileManager/UUID/Locale somem se o primeiro
  # arquivo que importa UIKit nao for o main — medido em 2026-08-19).
  SRCLIST="$WORK/src/main.swift $(echo "$SRCLIST" | tr ' ' '\n' | grep -v '/main\.swift$' | tr '\n' ' ')"
  echo "    (entry point: $(basename "$mainsrc") -> main.swift)"
  # Garante que o runtime de debug seja inicializado antes do run loop.
  if [ "$DEBUG" -eq 1 ] && grep -q "UIApplicationMain(" "$WORK/src/main.swift"; then
    sed -i '/UIApplicationMain(/i ISBDebugRuntime.bootstrap()' "$WORK/src/main.swift"
  fi
else
  SRCLIST="$SRCS"
fi

# --- MODO PRIMARY-FILE --------------------------------------------------------
# Padrao quando ha 2+ arquivos. Delega a compilacao ao build-parallel.py
# (-primary-file, arquivo-a-arquivo) e o link ao link-ipa.sh. Isso evita a
# degradacao cross-file do whole-module (Foundation some de outros arquivos
# quando algum arquivo usa CoreGraphics).
if [ -z "$MODE" ]; then
  if [ "$nfiles" -gt 1 ]; then MODE=primary; else MODE=whole; fi
fi

if [ "$MODE" = "primary" ]; then
  BP="$SKILL/scripts/build-parallel.py"
  LI="$SKILL/scripts/link-ipa.sh"
  [ -f "$BP" ] || { echo "build-parallel.py ausente"; exit 1; }
  [ -f "$LI" ] || { echo "link-ipa.sh ausente"; exit 1; }

  # build-parallel.py compila um DIRETORIO. Com 1 arquivo so, monta o dir.
  if [ "$nfiles" -le 1 ]; then
    mkdir -p "$WORK/src"
    cat $SRCS > "$WORK/src/main.swift"
  fi

  echo "==> compilando (modo primary-file)"
  mkdir -p "$WORK/obj"
  python3 "$BP" --module "$APP" --src "$WORK/src" --out "$WORK/obj" --jobs 3 || {
    echo ""
    echo "BUILD ABORTADO na compilacao arquivo-a-arquivo."
    exit 1
  }

  # Bridges Objective-C são compiladas separadamente contra o SDK 26.5.
  EXTRA_OBJS=""
  for f in $OBJC_ARGS; do
    [ -f "$f" ] || { echo "bridge ObjC ausente: $f"; exit 1; }
    base=$(basename "$f" .m)
    mkdir -p "$WORK/extra-obj"
    LD="$ROOT/xtool-glibc/lib/ld-linux-aarch64.so.1"
    [ -x "$LD" ] || LD="/opt/xtool-glibc/lib/ld-linux-aarch64.so.1"
    CLANG_LIB="$SW/usr/bin/clang-21"
    [ -x "$CLANG_LIB" ] || CLANG_LIB="/opt/swift6.3.3/usr/bin/clang-21"
    CLANG_RES="$SW/usr/lib/clang/21"
    [ -d "$CLANG_RES" ] || CLANG_RES="/opt/swift6.3.3/usr/lib/clang/21"
    BRIDGE_OK=0
    for attempt in 1 2 3; do
      rm -f "$WORK/extra-obj/$base.o" "$WORK/extra-obj/$base.o.tmp"
      if LD_LIBRARY_PATH="/opt/xtool-glibc/lib" "$LD" --library-path /opt/xtool-glibc/lib "$CLANG_LIB" -target "$ISB_TARGET" -isysroot "$SDK" -resource-dir "$CLANG_RES" -fmodules -fobjc-arc -c "$f" -o "$WORK/extra-obj/$base.o" \
        -F"$SDK/System/Library/Frameworks" -F"$SDK/System/Library/SubFrameworks" -I"$SDK/usr/include" \
        -fmodules-cache-path="$WORK/objc-cache" -Xclang -fmodule-feature -Xclang found_incompatible_headers__check_search_paths 2>"$WORK/extra-obj/$base.err" && [ -s "$WORK/extra-obj/$base.o" ]; then
        BRIDGE_OK=1; break
      fi
      echo "   (bridge Clang retry $attempt: $base)"
    done
    [ "$BRIDGE_OK" -eq 1 ] || { cat "$WORK/extra-obj/$base.err"; exit 1; }
    EXTRA_OBJS="$EXTRA_OBJS $WORK/extra-obj/$base.o"
  done

  LINK_ARGS=""
  [ "$DEBUG" -eq 1 ] && LINK_ARGS="--debug"
  [ -n "$EXTRA_OBJS" ] && LINK_ARGS="$LINK_ARGS --extra-obj-list $EXTRA_OBJS"
  [ -n "$FRAMEWORK_ARGS" ] && LINK_ARGS="$LINK_ARGS --extra-framework-list $FRAMEWORK_ARGS"
  [ -n "$WEAK_FRAMEWORK_ARGS" ] && LINK_ARGS="$LINK_ARGS --weak-framework-list $WEAK_FRAMEWORK_ARGS"
  [ -n "$PLIST_EXTRA" ] && LINK_ARGS="$LINK_ARGS --plist-extra $PLIST_EXTRA"
  [ -n "$RESOURCES" ] && LINK_ARGS="$LINK_ARGS --resources $RESOURCES"
  [ "$UNSIGNED" -eq 1 ] && LINK_ARGS="$LINK_ARGS --unsigned"
  sh "$LI" "$APP" "$BUNDLE" "$WORK/obj" $LINK_ARGS
  exit 0
fi

echo "    (modo whole-module)"

# Frameworks extras sao opt-in tambem neste caminho.
EXTRA_FRAMEWORK_FLAGS=""
for fw in $FRAMEWORK_ARGS; do
  EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -framework $fw"
  case "$fw" in
    NaturalLanguage) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftNaturalLanguage" ;;
    CoreML) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftCoreML" ;;
    Vision) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftVision" ;;
    Accelerate) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftAccelerate" ;;
    *) : ;;
  esac
done
WEAK_FRAMEWORK_FLAGS=""
for fw in $WEAK_FRAMEWORK_ARGS; do WEAK_FRAMEWORK_FLAGS="$WEAK_FRAMEWORK_FLAGS -weak_framework $fw"; done
FM_LINK=""
if echo "$FRAMEWORK_ARGS" | grep -qw FoundationModels; then FM_LINK="-framework FoundationModels"; fi
if echo "$WEAK_FRAMEWORK_ARGS" | grep -qw FoundationModels; then FM_LINK="-weak_framework FoundationModels"; fi

# --- monta as flags de modulos explicitos -------------------------------------
MODS=""
for f in "$OUT"/swift_*.swiftmodule; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .swiftmodule); n=${n#swift_}
  # o overlay Swift do XPC cria ciclo os<->XPC (ver PURE-SWIFT-UI-STATUS.md)
  [ "$n" = "XPC" ] && continue
  # NOTA (2026-08-19): usar DOIS args (-swift-module-file X=path). O formato
  # de um arg so (-swift-module-file=X=path) faz os modulos carregarem de forma
  # corrompida com muitos arquivos (tipos do Foundation/Dispatch somem).
  MODS="$MODS -swift-module-file=$n=$f"
done
for f in "$OUT"/clang_*.pcm; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .pcm); n=${n#clang_}
  MODS="$MODS -Xcc -fmodule-file=$n=$f"
done

echo "==> compilando Swift (pode levar alguns minutos)"
n=0
until [ $n -ge 3 ]; do
  # o iSH tem uma race de startup no swift-frontend (~15-25%): sempre retry
  if $SF -frontend -c -target "$ISB_TARGET" $ISB_CPU_ARGS -sdk "$SDK" \
      -enable-objc-interop -swift-version 5 $OPT_FLAGS \
      -disable-implicit-swift-modules -Xcc -fno-implicit-modules \
      -Xcc -fno-implicit-module-maps \
      -Xcc -ivfsoverlay -Xcc "$VFS" \
      -module-name "$APP" $SRCLIST \
      $MODS \
      -Xcc -fmodules-cache-path="$BIG" -Xcc -DCF_SWIFT_SENDABLE= \
      -o "$WORK/app.o" 2> "$WORK/swift.err"; then
    break
  fi
  if grep -q "error:" "$WORK/swift.err"; then
    echo "ERRO de compilacao:"; grep "error:" "$WORK/swift.err" | head -20; exit 1
  fi
  n=$((n + 1)); echo "   (race de startup, tentativa $n)"
done
[ -s "$WORK/app.o" ] || { echo "falhou"; cat "$WORK/swift.err" | head -20; exit 1; }
echo "    objeto: $(stat -c %s "$WORK/app.o") bytes"

# GUARDA OBRIGATORIA: warnings que significam "o app abre e nao funciona".
# O caso classico e' uma assinatura de delegate que nao casa com o
# .swiftinterface patchado: o Swift so AVISA e o framework nunca chama o
# metodo -> app vivo com TELA PRETA. Ver references/WARNINGS-FATAIS.md
CW=/var/minis/skills/ios-swift-builder/scripts/check-warnings.py
if [ -f "$CW" ]; then
  python3 "$CW" "$WORK/swift.err" || {
    echo ""
    echo "BUILD ABORTADO: o binario compilaria, mas o app nao funcionaria."
    exit 1
  }
fi

# Bridges Objective-C também precisam entrar no modo whole-module.
WHOLE_EXTRA_OBJS=""
for f in $OBJC_ARGS; do
  [ -f "$f" ] || { echo "bridge ObjC ausente: $f"; exit 1; }
  base=$(basename "$f" .m)
  mkdir -p "$WORK/extra-obj"
  LD="/opt/xtool-glibc/lib/ld-linux-aarch64.so.1"
  [ -x "$LD" ] || LD="$ROOT/xtool-glibc/lib/ld-linux-aarch64.so.1"
  CLANG_LIB="$SW/usr/bin/clang-21"
  [ -x "$CLANG_LIB" ] || CLANG_LIB="/opt/swift6.3.3/usr/bin/clang-21"
  CLANG_RES="$SW/usr/lib/clang/21"
  [ -d "$CLANG_RES" ] || CLANG_RES="/opt/swift6.3.3/usr/lib/clang/21"
  LD_LIBRARY_PATH="/opt/xtool-glibc/lib" "$LD" --library-path /opt/xtool-glibc/lib "$CLANG_LIB" -target "$ISB_TARGET" -isysroot "$SDK" -resource-dir "$CLANG_RES" -fmodules -fobjc-arc -c "$f" -o "$WORK/extra-obj/$base.o" \
    -F"$SDK/System/Library/Frameworks" -F"$SDK/System/Library/SubFrameworks" -I"$SDK/usr/include" \
    -fmodules-cache-path="$WORK/objc-cache" -Xclang -fmodule-feature -Xclang found_incompatible_headers__check_search_paths 2>"$WORK/extra-obj/$base.err" || { cat "$WORK/extra-obj/$base.err"; exit 1; }
  WHOLE_EXTRA_OBJS="$WHOLE_EXTRA_OBJS $WORK/extra-obj/$base.o"
done

# UIKitCore generic stub is used only by the regular linker; the local PAC
# linker rejects direct clients of this private framework.
EXTRAFW=/opt/ios-toolchain/extrafw
EXTRAFLAGS=""
if [ "$ISB_ARCH" != "arm64e" ] && [ -f "$EXTRAFW/UIKitCore.framework/UIKitCore.tbd" ]; then
  EXTRAFLAGS="-F$EXTRAFW -framework UIKitCore"
fi
if [ "$ISB_ARCH" = "arm64e" ]; then
  "$ISB_LINKER" -arch arm64e -platform_version ios 26.5 26.5 \
    -syslibroot "$SDK" -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" \
    -lSystem -lobjc \
    -framework UIKit -framework Foundation $FM_LINK \
    -framework CoreGraphics \
    -framework QuartzCore -framework SwiftUI -framework CoreText -framework Combine \
    $EXTRA_FRAMEWORK_FLAGS $WEAK_FRAMEWORK_FLAGS -lswiftCore -lswiftFoundation -lswiftUIKit \
    -lswiftDarwin -lswiftObjectiveC -lswiftCoreGraphics -lswiftDispatch \
    -lswiftCoreFoundation -lswiftQuartzCore -rpath /usr/lib/swift -e _main \
    "$WORK/app.o" $WHOLE_EXTRA_OBJS -o "$WORK/$APP"
else
  ld64.lld -arch arm64 -platform_version ios 26.0 26.5 \
    -syslibroot "$SDK" -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" \
    -lSystem -lobjc $EXTRAFLAGS \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -framework QuartzCore -framework SwiftUI -framework CoreText -framework Combine \
    $EXTRA_FRAMEWORK_FLAGS $WEAK_FRAMEWORK_FLAGS -lswiftCore -lswiftFoundation -lswiftUIKit \
    -lswiftDarwin -lswiftObjectiveC -lswiftCoreGraphics -lswiftDispatch \
    -lswiftCoreFoundation -lswiftQuartzCore -rpath /usr/lib/swift -e _main \
    "$WORK/app.o" $WHOLE_EXTRA_OBJS -o "$WORK/$APP"
fi

echo "==> empacotando"
PAY="$WORK/Payload/$APP.app"
mkdir -p "$PAY"
cp "$WORK/$APP" "$PAY/$APP"
APP_VERSION="${ISB_APP_VERSION:-1.0}"
APP_BUILD="${ISB_APP_BUILD:-1}"
DISPLAY_NAME="${ISB_DISPLAY_NAME:-$APP}"

cat > "$PAY/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE</string>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>MinimumOSVersion</key><string>$([ "$ISB_ARCH" = "arm64e" ] && echo 26.5 || echo 26.0)</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
  $PLIST_EXTRA
  $STIK_QUERY
</dict></plist>
EOF
# get-task-allow e' necessario para o StikDebug anexar ao processo. A assinatura
# normal permanece ad-hoc; o entitlement so e' preservado em --debug.
if [ "$UNSIGNED" -eq 1 ]; then
  echo "    (unsigned: LiveContainer/SideStore fara a assinatura)"
elif [ "$DEBUG" -eq 1 ]; then
  cat > "$WORK/debug-entitlements.plist" <<EOT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$BUNDLE</string>
  <key>get-task-allow</key><true/>
</dict></plist>
EOT
  ldid -S"$WORK/debug-entitlements.plist" "$PAY/$APP"
else
  ldid -S "$PAY/$APP"
fi
mkdir -p /var/minis/workspace

# GUARDA FINAL: invariantes usadas pelo patcher LiveContainer.
LCG=/var/minis/skills/ios-swift-builder/scripts/check-livecontainer.py
if [ -f "$LCG" ]; then
  python3 "$LCG" "$PAY/$APP" || { echo "BUILD ABORTADO: Mach-O incompatível com LiveContainer"; exit 1; }
fi

# GUARDA FINAL: o binario realmente inicia?
# Isto NAO depende do warning do compilador, que e' inconstante — olha o que
# ficou no binario. Ver references/WARNINGS-FATAIS.md
CE=/var/minis/skills/ios-swift-builder/scripts/check-entry.py
if [ -f "$CE" ]; then
  python3 "$CE" "$PAY/$APP" || {
    echo ""
    echo "BUILD ABORTADO: o IPA seria gerado, mas o app nao iniciaria."
    exit 1
  }
fi

(cd "$WORK" && zip -qr "$OUTPUT" Payload)
echo "==> pronto: $OUTPUT"
ls -lh "$OUTPUT"
