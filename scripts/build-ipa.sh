#!/bin/sh
# build-ipa.sh — build a native iOS .ipa inside iSH (no Mac).
#
# Usage:
#   build-ipa.sh <AppName> <BundleID> <AppLogic.swift> <AppShell.m> [--debug]
#   build-ipa.sh --pure <AppName> <BundleID> <main.swift> [--debug]
#
# Hybrid mode: Swift logic (@_cdecl exports) + ObjC UIKit shell → real UI app.
# Pure mode:   a single Swift file (console-style, top-level or @main) → app.
#
# Output: /var/minis/workspace/<AppName>.ipa
set -e

# arm64e is canonical; arm64 remains a local rollback profile.
ARCH="${ISB_ARCH:-arm64e}"
CLANG=/usr/bin/clang
if [ "$ARCH" = arm64e ]; then
  . "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/profile.sh"
  SW="$ISB_SW"
  SF="$ISB_SW/usr/bin/swift-frontend"
  SDK="$ISB_SDK"
  CACHE="$ISB_FOUNDATION_BUILD"
  MODS="$CACHE"
  DEPLOY=26.5
  SDKVER=26.5
  TARGET="$ISB_TARGET"
  LINKER="$ISB_LINKER"
  PROFILE_MODS=""
  for f in "$CACHE"/swift_*.swiftmodule; do
    [ -f "$f" ] || continue
    n=$(basename "$f" .swiftmodule); n=${n#swift_}
    [ "$n" = XPC ] && continue
    PROFILE_MODS="$PROFILE_MODS -swift-module-file=$n=$f"
  done
  for f in "$CACHE"/clang_*.pcm; do
    [ -f "$f" ] || continue
    n=$(basename "$f" .pcm); n=${n#clang_}
    PROFILE_MODS="$PROFILE_MODS -Xcc -fmodule-file=$n=$f"
  done
else
  SW=/opt/swift6.3
  SF="$SW/usr/bin/swift-frontend"
  SDK=/opt/ios-toolchain/iPhoneOS26.5.sdk
  CACHE=/opt/ios-toolchain/exp63
  MODS="$CACHE/modules"
  DEPLOY=26.0
  SDKVER=26.5
  TARGET="arm64-apple-ios26.0"
  LINKER=ld64.lld
  PROFILE_MODS=""
fi
OUT="${ISB_WORKSPACE:-/var/minis/workspace}"

# ---- parse args ----
PURE=0
if [ "$1" = "--pure" ]; then PURE=1; shift; fi
APP="$1"; BUNDLE_ID="$2"
if [ $PURE -eq 1 ]; then SWIFT_SRC="$3"; shift 3; else LOGIC_SRC="$3"; SHELL_SRC="$4"; shift 4; fi
DEBUG=0
for arg in "$@"; do [ "$arg" = "--debug" ] && DEBUG=1; done
if [ "$DEBUG" -eq 1 ] && [ "$PURE" -eq 1 ]; then
  echo "--debug requer build-pure-ui.sh para apps com UIKit; build-ipa --pure e' Foundation-only"
  exit 2
fi
DEBUG_ASSET=/var/minis/skills/ios-swift-builder/assets/DebugSupport.swift
if [ "$DEBUG" -eq 1 ] && [ ! -f "$DEBUG_ASSET" ]; then echo "DebugSupport.swift ausente"; exit 1; fi

WORK=/tmp/ipabuild_$$
rm -rf "$WORK"; mkdir -p "$WORK/Payload/$APP.app"
APPDIR="$WORK/Payload/$APP.app"
trap 'rm -rf "$WORK"' EXIT

# ---- retry wrapper for the iSH startup race ----
swiftc_retry() {  # $1=output file, rest=args
  out="$1"; shift
  i=0
  while [ $i -lt 10 ]; do
    rm -f "$out"
    timeout 120 env -i HOME=/root TERM=dumb "$SF" "$@" -o "$out" 2>/tmp/sf_err.$$ || true
    [ -s "$out" ] && return 0
    # real error (non-empty stderr with 'error:') → stop; else it's the race → retry
    if grep -q 'error:' /tmp/sf_err.$$ 2>/dev/null; then
      echo "--- swift-frontend error ---"; grep -v 'core dumps' /tmp/sf_err.$$ | head -12; return 1
    fi
    i=$((i+1))
  done
  echo "gave up after retries (persistent startup race)"; return 1
}

echo "[1] Compiling Swift..."
if [ $PURE -eq 1 ]; then
  if [ "$DEBUG" -eq 1 ]; then
    SWIFT_INPUT="$SWIFT_SRC $DEBUG_ASSET"
  else
    SWIFT_INPUT="$SWIFT_SRC"
  fi
  # shellcheck disable=SC2086
  swiftc_retry "$WORK/app.o" -c -target "$TARGET" -sdk "$SDK" \
    -resource-dir "$SW/usr/lib/swift" -I "$MODS" -O \
    -Xcc -fmodule-file=SwiftShims="$CACHE/clang_SwiftShims.pcm" \
    $PROFILE_MODS \
    $SWIFT_INPUT
  SWIFT_OBJ="$WORK/app.o"
else
  # O builder hibrido compila a logica Swift separadamente do shell ObjC.
  # Nao injeta o runtime UIKit aqui: use build-pure-ui.sh para o overlay DBG.
  LOGIC_INPUT="$LOGIC_SRC"
  swiftc_retry "$WORK/logic.o" -c -target "$TARGET" -sdk "$SDK" \
    -resource-dir "$SW/usr/lib/swift" -I "$MODS" -parse-as-library -O \
    -Xcc -fmodule-file=SwiftShims="$CACHE/clang_SwiftShims.pcm" \
    $PROFILE_MODS \
    "$LOGIC_INPUT"
  SWIFT_OBJ="$WORK/logic.o"
fi
echo "    Swift OK ($(wc -c <"$SWIFT_OBJ")B)"

OBJS="$SWIFT_OBJ"
if [ $PURE -eq 0 ]; then
  echo "[2] Compiling ObjC UIKit shell..."
  "$CLANG" -c -target "$TARGET" -isysroot "$SDK" \
    -fobjc-arc -O2 -fvisibility=hidden \
    -F "$SDK/System/Library/SubFrameworks" \
    "$SHELL_SRC" -o "$WORK/shell.o"
  echo "    ObjC OK ($(wc -c <"$WORK/shell.o")B)"
  OBJS="$OBJS $WORK/shell.o"
fi

echo "[3] Linking..."
FRAMEWORKS="-framework Foundation"
[ $PURE -eq 0 ] && FRAMEWORKS="-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -lobjc"
if [ "$ARCH" = arm64e ]; then
  # UIKitCore exports generic UIKit Swift symbols. It permits UIKit as client.
  "$LINKER" -arch arm64e -platform_version ios 26.5 26.5 \
    -syslibroot "$SDK" -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" \
    -F/opt/ios-toolchain/extrafw -framework UIKitCore -client_name UIKit \
    -lSystem -lobjc -framework UIKit -framework Foundation \
    -framework CoreGraphics -framework QuartzCore \
    -lswiftCore -lswiftFoundation -lswiftUIKit -lswiftDarwin \
    -lswiftObjectiveC -lswiftCoreGraphics -lswiftDispatch -lswiftCoreFoundation \
    -lswiftQuartzCore -rpath /usr/lib/swift -e _main \
    $OBJS -o "$APPDIR/$APP"
else
  # shellcheck disable=SC2086
  "$CLANG" -target "$TARGET" -isysroot "$SDK" -fuse-ld=lld \
    -F "$SDK/System/Library/SubFrameworks" -L "$SDK/usr/lib/swift" \
    -Wl,-platform_version,ios,$DEPLOY,$SDKVER -Wl,-dead_strip \
    $FRAMEWORKS $OBJS -o "$APPDIR/$APP"
fi
llvm-strip "$APPDIR/$APP" 2>/dev/null || true
echo "    Link OK ($(wc -c <"$APPDIR/$APP")B)"

echo "[4] Info.plist + ad-hoc signature..."
SCENE=""
[ $PURE -eq 0 ] && SCENE='
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key><false/>
        <key>UISceneConfigurations</key><dict>
            <key>UIWindowSceneSessionRoleApplication</key><array><dict>
                <key>UISceneConfigurationName</key><string>Default Configuration</string>
                <key>UISceneDelegateClassName</key><string>SceneDelegate</string>
            </dict></array>
        </dict>
    </dict>'
cat > "$APPDIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
    <key>MinimumOSVersion</key><string>$DEPLOY</string>
    <key>DTPlatformName</key><string>iphoneos</string>
    <key>DTPlatformVersion</key><string>$SDKVER</string>
    <key>DTSDKName</key><string>iphoneos$SDKVER</string>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>UILaunchScreen</key><dict/>
    <key>LSApplicationQueriesSchemes</key><array><string>stikdebug</string></array>
    <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
    <key>UISupportedInterfaceOrientations</key><array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>$SCENE
</dict></plist>
EOF
cat > "$WORK/ent.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>application-identifier</key><string>$BUNDLE_ID</string>
    $( [ "$DEBUG" -eq 1 ] && printf '<key>get-task-allow</key><true/>\n' )
</dict></plist>
EOF
ldid -S"$WORK/ent.plist" "$APPDIR/$APP"

echo "[5] Packaging IPA..."
mkdir -p "$OUT"; rm -f "$OUT/$APP.ipa"
( cd "$WORK" && zip -qr "$OUT/$APP.ipa" Payload )
echo "IPA: $OUT/$APP.ipa ($(wc -c <"$OUT/$APP.ipa")B)"
