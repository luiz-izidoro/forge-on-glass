#!/bin/sh
# link-ipa.sh — linka, assina e empacota objetos Swift.
# ISB_ARCH=arm64e seleciona o slice arm64e; default arm64.
. "$(dirname "$0")/profile.sh"
#
# POR QUE ISSO EXISTE:
#   build-parallel.py compila arquivo-a-arquivo (-primary-file) e entrega .o,
#   mas nao linkava nada: a documentacao mandava montar o ld64.lld a mao.
#   Este script fecha esse caminho e e' usado por build-pure-ui.sh --primary-file.
#
# Uso:
#   ./link-ipa.sh <AppName> <BundleID> <objdir> [--debug]
#                 [--resources DIR] [--main-obj NAME] [--plist-extra XML]
#
# Saida: /var/minis/workspace/<AppName>.ipa
set -e

APP="${1:?uso: $0 <AppName> <BundleID> <objdir> [--debug] [--resources DIR]}"
BUNDLE="${2:?falta o bundle id}"
OBJDIR="${3:?falta o diretorio com os .o}"
shift 3

DEBUG=0
UNSIGNED=0
[ "$ISB_ARCH" = "arm64e" ] && UNSIGNED="${ISB_UNSIGNED:-1}"
RESDIR=""
MAINOBJ="main"
PLIST_EXTRA=""
EXTRA_OBJ_LIST=""
EXTRA_FRAMEWORK_LIST=""
WEAK_FRAMEWORK_LIST=""
EXTRA_MODE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --debug) DEBUG=1; EXTRA_MODE="" ;;
    --unsigned) UNSIGNED=1; EXTRA_MODE="" ;;
    --resources) RESDIR="$2"; shift; EXTRA_MODE="" ;;
    --main-obj) MAINOBJ="$2"; shift; EXTRA_MODE="" ;;
    --plist-extra) PLIST_EXTRA="$2"; shift; EXTRA_MODE="" ;;
    --extra-obj-list) EXTRA_MODE="obj" ;;
    --extra-framework-list) EXTRA_MODE="framework" ;;
    --weak-framework-list) EXTRA_MODE="weakframework" ;;
    --extra-obj) EXTRA_OBJ_LIST="$EXTRA_OBJ_LIST $2"; shift ;;
    *)
      if [ "$EXTRA_MODE" = "obj" ]; then EXTRA_OBJ_LIST="$EXTRA_OBJ_LIST $1"
      elif [ "$EXTRA_MODE" = "framework" ]; then EXTRA_FRAMEWORK_LIST="$EXTRA_FRAMEWORK_LIST $1"
      elif [ "$EXTRA_MODE" = "weakframework" ]; then WEAK_FRAMEWORK_LIST="$WEAK_FRAMEWORK_LIST $1"
      else echo "argumento desconhecido: $1"; exit 1
      fi
      ;;
  esac
  shift
done

# Add -framework names and their Swift runtime stubs when present. FoundationModels
# intentionally has no libswiftFoundationModels.tbd: its ABI is provided by the
# framework itself and the SDK 26.5 stub is the authoritative link input.
EXTRA_FRAMEWORK_FLAGS=""
for fw in $EXTRA_FRAMEWORK_LIST; do
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
for fw in $WEAK_FRAMEWORK_LIST; do WEAK_FRAMEWORK_FLAGS="$WEAK_FRAMEWORK_FLAGS -weak_framework $fw"; done

ROOT=/opt/isb/sysroot
SDK="$ISB_SDK"
WORK=/tmp/link-$APP-$ISB_ARCH-$$
OUTPUT="${ISB_OUTPUT:-/var/minis/workspace/$APP.ipa}"
rm -rf "$WORK" && mkdir -p "$WORK"

# ORDEM DOS OBJETOS: o que contem o codigo top-level (UIApplicationMain) precisa
# vir primeiro, senao o _main resultante pode ficar vazio.
MAINO="$OBJDIR/$MAINOBJ.o"
[ -f "$MAINO" ] || { echo "objeto de entrada ausente: $MAINO"; exit 1; }
OBJS="$MAINO"
for f in "$OBJDIR"/*.o; do
  [ "$f" = "$MAINO" ] && continue
  OBJS="$OBJS $f"
done
for f in $EXTRA_OBJ_LIST; do OBJS="$OBJS $f"; done
nobj=$(echo $OBJS | wc -w)
echo "==> linkando ($nobj objeto(s), entrada: $(basename "$MAINO"))"

# UIKitCore: os simbolos Swift das classes GENERICAS do UIKit sao exportados
# pelo documento do UIKitCore dentro do UIKit.tbd, que o lld nao percorre.
EXTRAFW=/opt/ios-toolchain/extrafw
EXTRAFLAGS=""
if [ "$ISB_ARCH" != "arm64e" ] && [ "${ISB_USE_UIKITCORE:-1}" = "1" ] && [ -f "$EXTRAFW/UIKitCore.framework/UIKitCore.tbd" ]; then
  EXTRAFLAGS="-F$EXTRAFW -framework UIKitCore"
fi
if [ "$ISB_ARCH" = "arm64e" ]; then
  LINKER="/opt/ios-toolchain/darwin-toolset/bin/ld64.lld"
  PLATFORM_MIN=26.5
else
  LINKER="ld64.lld"
  PLATFORM_MIN=26.0
fi

# arm64e uses the local authenticated LLD installed by the bootstrap step.
# The production profile is deliberately offline: no SSH/SCP/VM fallback.
if [ "$ISB_ARCH" = "arm64e" ]; then
  "$ISB_LINKER" -arch arm64e -platform_version ios 26.5 26.5 \
    -syslibroot "$SDK" -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" \
    -dead_strip \
    -lSystem -lobjc $EXTRAFLAGS \
    -framework UIKit -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore -framework SwiftUI -framework CoreText \
    -framework Combine \
    $EXTRA_FRAMEWORK_FLAGS $WEAK_FRAMEWORK_FLAGS \
    -lswiftCore -lswiftFoundation -lswiftUIKit \
    -lswiftDarwin -lswiftObjectiveC -lswiftCoreGraphics -lswiftDispatch \
    -lswiftCoreFoundation -lswiftQuartzCore \
    -rpath /usr/lib/swift \
    -e _main \
    $OBJS -o "$WORK/$APP"
else
  ld64.lld -arch arm64 -platform_version ios 26.0 26.5 \
    -syslibroot "$SDK" \
    -dead_strip \
    -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" \
    -lSystem -lobjc \
    $EXTRAFLAGS \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -framework QuartzCore -framework SwiftUI -framework CoreText \
    -framework Combine \
    $EXTRA_FRAMEWORK_FLAGS $WEAK_FRAMEWORK_FLAGS \
    -lswiftCore -lswiftFoundation -lswiftUIKit \
    -lswiftDarwin -lswiftObjectiveC -lswiftCoreGraphics -lswiftDispatch \
    -lswiftCoreFoundation -lswiftQuartzCore \
    -rpath /usr/lib/swift \
    -e _main \
    $OBJS -o "$WORK/$APP"
fi

echo "==> empacotando"
PAY="$WORK/Payload/$APP.app"
mkdir -p "$PAY"
cp "$WORK/$APP" "$PAY/$APP"

if [ -n "$RESDIR" ] && [ -d "$RESDIR" ]; then
  # BusyBox cp -R can report "replaced while being copied" for generated PNGs
  # on this filesystem. Copy files atomically one by one instead.
  for resource in "$RESDIR"/*; do
    [ -f "$resource" ] || continue
    cat "$resource" > "$PAY/$(basename "$resource")"
  done
  echo "    recursos copiados de $RESDIR"
fi

STIK_QUERY=""
[ "$DEBUG" -eq 1 ] && STIK_QUERY='<key>LSApplicationQueriesSchemes</key><array><string>stikdebug</string></array>'

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
  $STIK_QUERY
  $PLIST_EXTRA
</dict></plist>
EOF

# Optional post-link symbol stripping. It runs before signing and guards.
if [ "${ISB_STRIP:-0}" = "1" ]; then
  llvm-strip -x "$PAY/$APP"
  echo "    llvm-strip -x aplicado"
elif [ "${ISB_STRIP:-0}" != "0" ]; then
  echo "ISB_STRIP inválido: use 0 ou 1" >&2; exit 2
fi

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

# GUARDA FINAL: o binario realmente inicia? (thunk ObjC do delegate + _main)
CE="$SKILL/scripts/check-entry.py"
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
